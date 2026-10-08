// Phone remote state: which desktop, the live gateway link, the open chat,
// approvals, the Office, the Kanban board and the desktop's status. One
// ChangeNotifier the remote screens watch. Everything after the first load is
// pushed by the PC over the WebSocket (no polling); a reconnect re-reads the
// snapshots and replays or resumes what was missed.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/device_tools.dart';
import '../data/gateway_client.dart';
import '../models/models.dart';
import 'office_models.dart';
import 'pairing.dart';
import 'remote_gateway.dart';
import 'update_check.dart';
import 'vault_models.dart';
import 'remote_transcript.dart';
import 'saved_desktops.dart';

class RemoteController extends ChangeNotifier {
  RemoteController(this.desktops);
  final SavedDesktops desktops;

  RemoteGateway? gateway;
  SavedDesktop? desktop;
  RemoteStatus status = RemoteStatus.disconnected;
  String? error;
  StreamSubscription? _statusSub, _eventSub, _approvalSub, _routeSub;

  /// The PC's appearance (`/api/appearance`, `appearance.changed`).
  void Function(Map<String, dynamic> appearance)? onAppearance;

  /// Checks GitHub Releases for a newer phone app (injectable for tests).
  UpdateChecker updateChecker = UpdateChecker();

  // office (pushed via `office.update`)
  OfficeSnapshot? office;
  String? officeError;
  DateTime? officeAt;

  /// Bumped on `vault.changed` so an open vault screen re-reads its note.
  int vaultRevision = 0;

  /// Widget-test harness only: vault data without a gateway.
  @visibleForTesting
  VaultApi? debugVault;
  VaultApi? get vault => debugVault ?? gateway;

  // chat
  List<ChatSessionInfo> sessions = [];
  bool sessionsLoading = false;
  String? storedId;
  String? runtimeId;
  String title = '';
  RemoteTranscript transcript = RemoteTranscript();
  bool opening = false;
  bool notifyApprovals = true;
  void setNotifyApprovals(bool v) {
    notifyApprovals = v;
    notifyListeners();
  }

  // board / status
  KanbanSnapshot? board;
  String? boardError;
  bool boardLoading = false;
  List<ActiveSession> active = [];
  Map<String, dynamic> serverInfo = const {};

  /// Newest release for this phone app: GitHub Releases API directly, the
  /// PC core's `/api/update` (cached GitHub check) as the fallback.
  Map<String, dynamic> update = const {};
  String? dismissedUpdate;
  bool get updateAvailable =>
      update['available'] == true && update['latest'] != null && update['latest'] != dismissedUpdate;

  Future<void> checkUpdate() async {
    final u = await updateChecker.check(fallback: gateway?.updateInfo);
    if (u != null) {
      update = u;
      notifyListeners();
    }
  }
  void dismissUpdate() {
    dismissedUpdate = update['latest'] as String?;
    notifyListeners();
  }

  bool get connected => status == RemoteStatus.connected;
  List<RemoteApproval> get approvals => debugApprovals ?? gateway?.approvals ?? const [];

  /// Screenshot / widget-test harness only: approvals to show without a gateway.
  @visibleForTesting
  List<RemoteApproval>? debugApprovals;
  bool get running => transcript.running;

  String get statusLabel => switch (status) {
        RemoteStatus.connected => 'terhubung',
        RemoteStatus.connecting => 'menghubungkan…',
        RemoteStatus.reconnecting => 'menyambung ulang…',
        RemoteStatus.failed => 'gagal terhubung',
        RemoteStatus.disconnected => 'terputus',
      };

  /// Called once at start: reconnect to the last desktop.
  Future<void> start() async {
    final d = desktops.active;
    if (d != null) await connectTo(d);
  }

  /// Validate a scanned/typed pairing against the gateway, then save it.
  /// Returns an error message, or null on success.
  Future<String?> pair(GatewayPairing p) async {
    final g = RemoteGateway(baseUrl: p.url, token: p.token, headers: p.headers, profile: p.profile, autoReconnect: false);
    try {
      await g.connect();
      await g.listSessions(limit: 1);
    } catch (e) {
      await g.close();
      return _friendly('$e');
    }
    await g.close();
    final d = await desktops.upsert(p);
    await connectTo(d);
    return null;
  }

  static String _friendly(String e) {
    final s = e.replaceFirst('Exception: ', '');
    if (s.contains('401') || s.contains('403') || s.contains('not upgraded')) {
      return 'PC menolak token. Buat ulang QR pemasangan di PC lalu pindai lagi.';
    }
    if (s.contains('timed out') || s.contains('waktu habis') || s.contains('TimeoutException')) {
      return 'PC tidak menjawab. Pastikan HP dan PC di Wi-Fi yang sama (atau Tailscale) dan gateway Neovarch di PC aktif.';
    }
    if (s.contains('Connection refused') || s.contains('SocketException') || s.contains('tidak bisa terhubung')) {
      return 'Tidak bisa menjangkau PC ($s). Cek alamat IP/port dan firewall PC.';
    }
    return s;
  }

  Future<void> connectTo(SavedDesktop d) async {
    await _teardown();
    desktop = d;
    desktops.touch(d);
    final token = await desktops.token(d.id);
    final g = gateway = RemoteGateway(baseUrl: d.url, alternates: d.alternates, token: token, headers: d.headers, profile: d.profile);
    _statusSub = g.statusStream.listen(_onStatus);
    _eventSub = g.events.listen(_onEvent);
    _approvalSub = g.approvalsChanged.listen(_onApproval);
    _routeSub = g.routesChanged.listen((urls) => desktops.updateRoutes(d, alternates: urls));
    error = null;
    notifyListeners();
    try {
      await g.connect();
      if (status != g.status) _onStatus(g.status); // the stream event lands a tick later
    } catch (e) {
      error = _friendly('$e');
      // keep retrying in the background
      unawaited(Future<void>.delayed(const Duration(seconds: 2), () {
        if (gateway == g && !connected) unawaited(g.reconnect().catchError((_) {}));
      }));
      notifyListeners();
    }
  }

  Future<void> _teardown() async {
    await _statusSub?.cancel();
    await _eventSub?.cancel();
    await _approvalSub?.cancel();
    await _routeSub?.cancel();
    final g = gateway;
    gateway = null;
    await g?.close();
    sessions = [];
    storedId = runtimeId = null;
    title = '';
    transcript = RemoteTranscript();
    board = null;
    boardError = null;
    active = [];
    serverInfo = const {};
    office = null;
    officeError = null;
    status = RemoteStatus.disconnected;
  }

  Future<void> disconnect() async {
    await _teardown();
    desktop = null;
    notifyListeners();
  }

  Future<void> forget(SavedDesktop d) async {
    if (desktop?.id == d.id) await disconnect();
    await desktops.remove(d.id);
    notifyListeners();
  }

  Future<void> reconnect() async {
    final g = gateway;
    if (g == null) {
      final d = desktop ?? desktops.active;
      if (d != null) await connectTo(d);
      return;
    }
    try {
      await g.reconnect();
    } catch (e) {
      error = _friendly('$e');
      notifyListeners();
    }
  }

  void _onStatus(RemoteStatus s) {
    if (s == status) return;
    final was = status;
    status = s;
    if (s == RemoteStatus.connected) {
      error = null;
      final d = desktop, g = gateway;
      if (d != null && g != null) desktops.updateRoutes(d, lastUrl: g.activeUrl);
      unawaited(refreshAll());
      // Re-attach to the open chat when the missed events could not be
      // replayed (older core, PC restarted, gap too old).
      if (was != RemoteStatus.connected && storedId != null && (g == null || g.resyncNeeded || runtimeId == null)) {
        unawaited(openSession(storedId!, quiet: true));
      }
    } else if (s == RemoteStatus.reconnecting || s == RemoteStatus.failed) {
      transcript.interrupted();
      if (s == RemoteStatus.failed) error ??= _friendly(gateway?.lastError ?? 'gagal terhubung');
    }
    notifyListeners();
  }

  void _onEvent(GatewayEventFrame f) {
    switch (f.type) {
      case 'office.update':
        _applyOffice(f.payload);
      case 'appearance.changed':
        onAppearance?.call(f.payload);
      case 'kanban.changed':
        unawaited(refreshBoard());
      case 'vault.changed':
        vaultRevision++;
        notifyListeners();
      case 'resync.required':
        unawaited(refreshAll());
        if (storedId != null) unawaited(openSession(storedId!, quiet: true));
    }
    if (f.type == 'sessions.changed' || f.type == 'session.title') unawaited(loadSessions());
    if (f.sessionId != null && f.sessionId == runtimeId) {
      if (transcript.apply(f)) {
        if (f.type == 'session.title') title = transcript.title ?? title;
        notifyListeners();
      }
    }
  }

  void _onApproval(RemoteApproval? a) {
    notifyListeners();
    if (a != null && notifyApprovals) unawaited(_notify(a));
  }

  Future<void> _notify(RemoteApproval a) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await ensurePermissions(['android.permission.POST_NOTIFICATIONS']);
      await deviceCall<String>('notify', {
        'title': 'Neovarch · perlu persetujuan',
        'body': '${a.toolName ?? 'Agen'} di ${desktop?.name ?? 'PC'}: ${a.description.isNotEmpty ? a.description : a.command}',
        'route': 'approvals', // tap → Chat + approvals sheet
      });
    } catch (_) {
      // No notification bridge: the in-app badge still shows it.
    }
  }

  /// Snapshots after (re)connecting; from here on the PC pushes changes.
  Future<void> refreshAll() async {
    await Future.wait([loadSessions(), refreshStatus(), refreshBoard(), refreshOffice(), _loadAppearance()]);
  }

  Future<void> _loadAppearance() async {
    final a = await gateway?.appearance();
    if (a != null) onAppearance?.call(a);
  }

  // --------------------------------------------------------------- office --
  Future<void> refreshOffice() async {
    final g = gateway;
    if (g == null || !connected) return;
    try {
      office = await g.office();
      officeAt = DateTime.now();
      officeError = null;
    } catch (e) {
      officeError = '$e';
    }
    notifyListeners();
  }

  void _applyOffice(Map<String, dynamic> payload) {
    final before = office;
    office = OfficeSnapshot.fromJson(payload);
    officeAt = DateTime.now();
    officeError = null;
    // The Kanban counts changed or a task moved: re-read the board (event
    // driven; cores without `kanban.changed`).
    final k = office!.kanban, kb = before?.kanban ?? const {};
    final moved = office!.feed.isNotEmpty && office!.feed.first.kind == 'task' && office!.feed.first.id != (before?.feed.firstOrNull?.id);
    if (before != null && (moved || k.entries.any((e) => kb[e.key] != e.value))) unawaited(refreshBoard());
    notifyListeners();
  }

  // ----------------------------------------------------------------- chat --
  Future<void> loadSessions() async {
    final g = gateway;
    if (g == null || !connected) return;
    sessionsLoading = true;
    notifyListeners();
    try {
      sessions = await g.listSessions();
    } catch (_) {}
    sessionsLoading = false;
    notifyListeners();
  }

  Future<void> openSession(String stored, {bool quiet = false}) async {
    final g = gateway;
    if (g == null) return;
    if (!quiet) {
      opening = true;
      storedId = stored;
      transcript = RemoteTranscript();
      notifyListeners();
    }
    try {
      final s = await g.resume(stored);
      storedId = s.storedId;
      runtimeId = s.runtimeId;
      title = s.title.isNotEmpty ? s.title : (sessions.where((x) => x.id == stored).firstOrNull?.title ?? '');
      transcript = RemoteTranscript(history: s.messages)..running = s.running;
    } catch (e) {
      error = _friendly('$e');
    }
    opening = false;
    notifyListeners();
  }

  /// Open a live session from `session.active_list`: resume accepts a stored
  /// id or an exact title.
  Future<void> openActive(ActiveSession a) async {
    final stored = sessions.where((s) => s.title == a.title).firstOrNull?.id ?? (a.title.isNotEmpty ? a.title : a.id);
    await openSession(stored);
  }

  /// Start a new chat (a new gateway session).
  Future<void> newChat() async {
    final g = gateway;
    if (g == null) return;
    opening = true;
    notifyListeners();
    try {
      final s = await g.create();
      storedId = s.storedId;
      runtimeId = s.runtimeId;
      title = '';
      transcript = RemoteTranscript(history: s.messages);
    } catch (e) {
      error = _friendly('$e');
    }
    opening = false;
    notifyListeners();
  }

  Future<String?> send(String text) async {
    final t = text.trim();
    final g = gateway;
    if (t.isEmpty || g == null) return null;
    if (!connected) return 'Belum terhubung ke PC.';
    if (runtimeId == null) await newChat();
    final rid = runtimeId;
    if (rid == null) return error ?? 'Gagal membuat sesi di PC.';
    transcript.addUser(t);
    notifyListeners();
    try {
      await g.submit(rid, t);
      return null;
    } catch (e) {
      transcript.interrupted();
      transcript.error = _friendly('$e');
      notifyListeners();
      return transcript.error;
    }
  }

  Future<void> stop() async {
    final rid = runtimeId;
    if (rid == null) return;
    try {
      await gateway?.interrupt(rid);
    } catch (_) {}
  }

  Future<String?> respond(RemoteApproval a, String choice) async {
    try {
      await gateway?.respondApproval(a, choice);
      notifyListeners();
      return null;
    } catch (e) {
      return _friendly('$e');
    }
  }

  String sessionTitle(String runtimeOrStored) {
    final s = sessions.where((x) => x.id == runtimeOrStored).firstOrNull;
    if (s != null) return s.title;
    final a = active.where((x) => x.id == runtimeOrStored).firstOrNull;
    if (a != null && a.title.isNotEmpty) return a.title;
    if (runtimeOrStored == runtimeId && title.isNotEmpty) return title;
    return 'sesi ${runtimeOrStored.length > 8 ? runtimeOrStored.substring(0, 8) : runtimeOrStored}';
  }

  // ---------------------------------------------------------------- board --
  Future<void> refreshBoard() async {
    final g = gateway;
    if (g == null || !connected) return;
    boardLoading = true;
    notifyListeners();
    try {
      board = await g.board();
      boardError = null;
    } catch (e) {
      boardError = '$e';
    }
    boardLoading = false;
    notifyListeners();
  }

  Future<String?> moveTask(String id, String status) => _boardAction(() => gateway!.moveTask(id, status));
  Future<String?> commentTask(String id, String text) => _boardAction(() => gateway!.commentTask(id, text));
  Future<String?> createTask({required String title, String? body, String? assignee}) =>
      _boardAction(() => gateway!.createTask(title: title, body: body, assignee: assignee));

  Future<String?> _boardAction(Future<void> Function() f) async {
    if (gateway == null || !connected) return 'Belum terhubung ke PC.';
    try {
      await f();
      unawaited(refreshBoard());
      return null;
    } catch (e) {
      return '$e';
    }
  }

  // --------------------------------------------------------------- status --
  Future<void> refreshStatus() async {
    final g = gateway;
    if (g == null || !connected) return;
    try {
      active = await g.activeSessions();
      // Approvals of sessions this phone has not opened (desktop chats,
      // background work): ask each live session.
      for (final a in active) {
        try {
          await g.pendingApprovals(a.id);
        } catch (_) {}
      }
    } catch (_) {}
    serverInfo = await g.serverStatus();
    notifyListeners();
    unawaited(checkUpdate());
  }

  @override
  void dispose() {
    unawaited(_teardown());
    super.dispose();
  }
}

final remoteProvider = ChangeNotifierProvider<RemoteController>((ref) => throw UnimplementedError());
