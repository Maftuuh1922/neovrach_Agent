// The phone's link to the desktop: the Hermes `tui_gateway` JSON-RPC over
// WebSocket (`/api/ws`, via the app's existing GatewayClient) plus the few
// REST routes the remote needs (Kanban plugin, public status). Pure Dart so
// it is unit-tested against an in-process mock gateway.
//
// Gateway facts this relies on (hermes-agent tui_gateway, see
// docs/remote-protocol.md):
//   * auth: `?token=` on the WS URL; REST takes `X-Hermes-Session-Token`
//     or `Authorization: Bearer` with the same token;
//   * `client.capabilities {server_requests:true}` must be sent, otherwise
//     approvals are never sent to this connection;
//   * approvals arrive as a server→client JSON-RPC request `approval`
//     (string id `srq-…`), answered with `{choice}`; `request.cancel` and
//     `approval.cancelled` withdraw them; `approval.pending` / `.respond`
//     are the RPC fallbacks;
//   * `ping` keeps the socket alive (the desktop pings every 15 s).
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/gateway_client.dart';
import '../models/models.dart';
import 'remote_transcript.dart';

enum RemoteStatus { disconnected, connecting, connected, reconnecting, failed }

class RemoteApproval {
  /// Server request id (`srq-…`) when it came as a server→client request.
  final String? rid;
  final String sessionId; // runtime session id
  final String requestId;
  final String command;
  final String description;
  final String? toolName;
  final List<String> choices;
  final DateTime receivedAt;
  RemoteApproval({
    this.rid,
    required this.sessionId,
    required this.requestId,
    required this.command,
    required this.description,
    this.toolName,
    required this.choices,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  String get key => rid ?? '$sessionId/$requestId';

  static List<String> _choices(Object? raw) {
    final l = (raw is List ? raw : const ['once', 'session', 'deny'])
        .map((e) => e is Map ? '${e['id'] ?? e['value'] ?? e['choice'] ?? e}' : '$e')
        .where((e) => e.isNotEmpty)
        .toList();
    return l.isEmpty ? const ['once', 'deny'] : l;
  }

  factory RemoteApproval.fromParams(Map<String, dynamic> p, {String? rid, String? sessionId}) => RemoteApproval(
        rid: rid,
        sessionId: '${p['session_id'] ?? sessionId ?? ''}',
        requestId: '${p['request_id'] ?? ''}',
        command: '${p['command'] ?? ''}',
        description: '${p['description'] ?? ''}',
        toolName: p['tool_name'] as String?,
        choices: _choices(p['choices']),
      );
}

class KanbanCard {
  final String id;
  final String title;
  final String? body;
  final String status;
  final String? assignee;
  final int priority;
  final String? summary;
  final int comments;
  const KanbanCard(
      {required this.id, required this.title, this.body, required this.status, this.assignee, this.priority = 0, this.summary, this.comments = 0});
  factory KanbanCard.fromJson(Map<String, dynamic> j) => KanbanCard(
        id: '${j['id']}',
        title: '${j['title'] ?? '(tanpa judul)'}',
        body: j['body'] as String?,
        status: '${j['status'] ?? ''}',
        assignee: j['assignee'] as String?,
        priority: (j['priority'] as num?)?.toInt() ?? 0,
        summary: j['latest_summary'] as String?,
        comments: (j['comment_count'] as num?)?.toInt() ?? 0,
      );
}

class KanbanLane {
  final String name;
  final List<KanbanCard> cards;
  const KanbanLane(this.name, this.cards);
}

class KanbanSnapshot {
  final List<KanbanLane> lanes;
  final List<String> assignees;
  const KanbanSnapshot(this.lanes, this.assignees);
  factory KanbanSnapshot.fromJson(Map<String, dynamic> j) => KanbanSnapshot(
        [
          for (final c in (j['columns'] as List? ?? const []).whereType<Map>())
            KanbanLane('${c['name']}', [for (final t in (c['tasks'] as List? ?? const []).whereType<Map>()) KanbanCard.fromJson(Map<String, dynamic>.from(t))]),
        ],
        [for (final a in (j['assignees'] as List? ?? const [])) '$a'],
      );
}

/// A session opened on the phone: stored id (durable) + runtime id (live).
class OpenedSession {
  final String storedId;
  final String runtimeId;
  final String title;
  final List<ChatMsg> messages;
  final bool running;
  const OpenedSession({required this.storedId, required this.runtimeId, required this.title, required this.messages, this.running = false});
}

class ActiveSession {
  final String id; // runtime id
  final String title;
  final String status;
  final String model;
  final String preview;
  const ActiveSession({required this.id, required this.title, required this.status, required this.model, required this.preview});
}

class RemoteGateway {
  RemoteGateway({
    required this.baseUrl,
    required this.token,
    this.headers = const {},
    this.profile,
    http.Client? httpClient,
    this.heartbeat = const Duration(seconds: 15),
    this.autoReconnect = true,
  }) : _http = httpClient ?? http.Client() {
    client = GatewayClient(baseUrl: baseUrl, token: token, headers: headers);
  }

  final String baseUrl;
  final String token;
  final Map<String, String> headers;
  final String? profile;
  final Duration heartbeat;
  final bool autoReconnect;
  final http.Client _http;
  late GatewayClient client;

  RemoteStatus status = RemoteStatus.disconnected;
  String? lastError;
  final _status = StreamController<RemoteStatus>.broadcast();
  final _events = StreamController<GatewayEventFrame>.broadcast();
  final _approvalsChanged = StreamController<RemoteApproval?>.broadcast();
  final Map<String, RemoteApproval> _approvals = {};
  StreamSubscription<GatewayEventFrame>? _sub;
  Timer? _beat;
  Timer? _retry;
  int _attempt = 0;
  bool _closed = false;

  Stream<RemoteStatus> get statusStream => _status.stream;

  /// Gateway notifications (session-scoped events) after approval handling.
  Stream<GatewayEventFrame> get events => _events.stream;

  /// Fires with the new approval when one arrives, null when one goes away.
  Stream<RemoteApproval?> get approvalsChanged => _approvalsChanged.stream;
  List<RemoteApproval> get approvals => _approvals.values.toList()..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));

  Map<String, dynamic> get _p => {if (profile != null && profile!.isNotEmpty) 'profile': profile};

  Map<String, String> get _restHeaders => {
        ...headers,
        if (token.isNotEmpty) 'X-Hermes-Session-Token': token,
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  void _setStatus(RemoteStatus s) {
    status = s;
    if (!_status.isClosed) _status.add(s);
  }

  // ------------------------------------------------------------ connection --
  /// Open the socket, advertise server-request support, start the heartbeat.
  /// Throws (and sets [lastError]) when the gateway cannot be reached.
  Future<void> connect() async {
    _closed = false;
    _retry?.cancel();
    _setStatus(_attempt == 0 ? RemoteStatus.connecting : RemoteStatus.reconnecting);
    try {
      await client.ensureConnected();
      _sub ??= client.events.listen(_onFrame);
      await client.call('client.capabilities', {'server_requests': true}, const Duration(seconds: 15));
      _attempt = 0;
      lastError = null;
      _beat?.cancel();
      _beat = Timer.periodic(heartbeat, (_) => _ping());
      _setStatus(RemoteStatus.connected);
    } catch (e) {
      lastError = '$e';
      final retrying = autoReconnect && !_closed && _attempt > 0;
      _setStatus(retrying ? RemoteStatus.reconnecting : RemoteStatus.failed);
      if (retrying) _scheduleRetry();
      rethrow;
    }
  }

  Future<void> _ping() async {
    try {
      await client.call('ping', const {}, const Duration(seconds: 20));
    } catch (_) {
      // A half-open socket: force a reconnect.
      client.close();
      _onDisconnected();
    }
  }

  void _onDisconnected() {
    if (status == RemoteStatus.reconnecting && _retry != null) return;
    _beat?.cancel();
    _beat = null;
    if (_closed) {
      _setStatus(RemoteStatus.disconnected);
      return;
    }
    _setStatus(RemoteStatus.reconnecting);
    if (autoReconnect) _scheduleRetry();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    final secs = [1, 2, 4, 8, 15, 30][_attempt.clamp(0, 5)];
    _attempt++;
    _retry = Timer(Duration(seconds: secs), () async {
      _retry = null;
      if (_closed) return;
      try {
        await connect(); // a failure schedules the next attempt itself
      } catch (_) {}
    });
  }

  /// Reconnect now (pull-to-refresh / app resumed).
  Future<void> reconnect() async {
    _retry?.cancel();
    _retry = null;
    _attempt = 1;
    client.close();
    await connect();
  }

  void _onFrame(GatewayEventFrame f) {
    switch (f.type) {
      case 'gateway.disconnected':
        _onDisconnected();
        return;
      case 'server.approval':
        final rid = f.payload['_rid'];
        final a = RemoteApproval.fromParams(f.payload, rid: rid == null ? null : '$rid', sessionId: f.sessionId);
        // Same approval may already be known from approval.pending (no rid).
        _approvals.removeWhere((_, x) => x.requestId.isNotEmpty && x.requestId == a.requestId);
        _approvals[a.key] = a;
        _approvalsChanged.add(a);
      case 'approval.request':
        // Older gateways: a notification instead of a server request.
        final a = RemoteApproval.fromParams(f.payload, sessionId: f.sessionId);
        _approvals[a.key] = a;
        _approvalsChanged.add(a);
      case 'request.cancel':
        final id = '${f.payload['id'] ?? ''}';
        if (_approvals.remove(id) != null) _approvalsChanged.add(null);
      case 'approval.cancelled':
        final ids = ((f.payload['request_ids'] as List?) ?? const []).map((e) => '$e').toSet();
        final sid = f.sessionId ?? '${f.payload['session_id'] ?? ''}';
        final before = _approvals.length;
        _approvals.removeWhere((_, a) => ids.contains(a.requestId) || (ids.isEmpty && a.sessionId == sid));
        if (_approvals.length != before) _approvalsChanged.add(null);
    }
    if (!_events.isClosed) _events.add(f);
  }

  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    _beat?.cancel();
    await _sub?.cancel();
    _sub = null;
    client.close();
    _http.close();
    _setStatus(RemoteStatus.disconnected);
    await _status.close();
    await _events.close();
    await _approvalsChanged.close();
  }

  // --------------------------------------------------------------- sessions --
  Future<List<ChatSessionInfo>> listSessions({int limit = 60}) async {
    final r = await client.call('session.list', {..._p, 'limit': limit});
    final rows = (r is Map ? r['sessions'] : null) as List? ?? const [];
    return rows.whereType<Map>().map((row) {
      final started = row['last_active'] ?? row['started_at'];
      final ts = started is num
          ? DateTime.fromMillisecondsSinceEpoch((started * (started > 1e12 ? 1 : 1000)).toInt()).toIso8601String()
          : '${started ?? ''}';
      final preview = '${row['preview'] ?? ''}';
      final title = '${row['title'] ?? ''}'.trim();
      return ChatSessionInfo(
        id: '${row['id']}',
        title: title.isNotEmpty ? title : (preview.isNotEmpty ? preview : '${row['id']}'),
        profile: profile ?? 'default',
        updatedAt: ts,
        messageCount: (row['message_count'] as num?)?.toInt() ?? 0,
        preview: preview,
      );
    }).toList();
  }

  Future<List<ActiveSession>> activeSessions() async {
    final r = await client.call('session.active_list', {..._p});
    final rows = (r is Map ? r['sessions'] : null) as List? ?? const [];
    return [
      for (final s in rows.whereType<Map>())
        ActiveSession(
          id: '${s['id']}',
          title: '${s['title'] ?? ''}',
          status: '${s['status'] ?? ''}',
          model: '${s['model'] ?? ''}',
          preview: '${s['preview'] ?? ''}',
        ),
    ];
  }

  /// Attach to a stored session (also re-attaches after a reconnect): its
  /// transcript, whether a turn is running, and any approval it waits on.
  Future<OpenedSession> resume(String storedId) async {
    final r = Map<String, dynamic>.from(await client.call('session.resume', {..._p, 'session_id': storedId, 'source': 'mobile'}) as Map);
    final runtime = '${r['session_id']}';
    _absorbPending(r, runtime);
    final info = r['info'] is Map ? r['info'] as Map : const {};
    return OpenedSession(
      storedId: '${r['stored_session_id'] ?? info['stored_session_id'] ?? storedId}',
      runtimeId: runtime,
      title: '${info['title'] ?? ''}',
      messages: RemoteTranscript.fromGatewayMessages(r['messages'] as List? ?? const []),
      running: r['running'] == true || info['running'] == true,
    );
  }

  Future<OpenedSession> create() async {
    final r = Map<String, dynamic>.from(await client.call('session.create', {..._p, 'source': 'mobile'}) as Map);
    final runtime = '${r['session_id']}';
    return OpenedSession(
      storedId: '${r['stored_session_id'] ?? runtime}',
      runtimeId: runtime,
      title: '',
      messages: RemoteTranscript.fromGatewayMessages(r['messages'] as List? ?? const []),
    );
  }

  void _absorbPending(Map<String, dynamic> r, String runtimeId) {
    var changed = false;
    final open = r['open_requests'];
    if (open is List) {
      for (final o in open.whereType<Map>()) {
        if (o['method'] != 'approval') continue;
        final a = RemoteApproval.fromParams(Map<String, dynamic>.from(o['params'] as Map? ?? const {}), rid: '${o['id']}', sessionId: runtimeId);
        _approvals[a.key] = a;
        changed = true;
      }
    }
    final pa = r['pending_approval'];
    if (!changed && pa is Map && '${pa['request_id'] ?? ''}'.isNotEmpty) {
      final a = RemoteApproval.fromParams(Map<String, dynamic>.from(pa), sessionId: runtimeId);
      if (!_approvals.values.any((x) => x.requestId == a.requestId)) {
        _approvals[a.key] = a;
        changed = true;
      }
    }
    if (changed) _approvalsChanged.add(null);
  }

  Future<void> submit(String runtimeId, String text) =>
      client.call('prompt.submit', {..._p, 'session_id': runtimeId, 'text': text, 'surface': 'mobile'});

  Future<void> interrupt(String runtimeId) => client.call('session.interrupt', {..._p, 'session_id': runtimeId});

  /// Pending approvals of a live session via RPC (fallback / refresh).
  Future<List<RemoteApproval>> pendingApprovals(String runtimeId) async {
    final r = await client.call('approval.pending', {..._p, 'session_id': runtimeId});
    final list = (r is Map ? r['approvals'] : null) as List? ?? const [];
    final out = [for (final a in list.whereType<Map>()) RemoteApproval.fromParams(Map<String, dynamic>.from(a), sessionId: runtimeId)];
    for (final a in out) {
      if (!_approvals.values.any((x) => x.requestId == a.requestId && x.sessionId == runtimeId)) _approvals[a.key] = a;
    }
    _approvalsChanged.add(null);
    return out;
  }

  /// Answer an approval: the server request when we got one (exactly what the
  /// desktop does), else the `approval.respond` RPC.
  Future<void> respondApproval(RemoteApproval a, String choice) async {
    _approvals.remove(a.key);
    _approvalsChanged.add(null);
    if (a.rid != null && a.rid!.isNotEmpty) {
      client.respondServerRequest(a.rid, {'choice': choice});
      return;
    }
    await client.call('approval.respond', {
      ..._p,
      'session_id': a.sessionId,
      'choice': choice,
      if (a.requestId.isNotEmpty) 'request_id': a.requestId,
    }, const Duration(seconds: 300));
  }

  // ------------------------------------------------------------------- REST --
  Uri _rest(String path, [Map<String, String>? q]) {
    final b = Uri.parse(baseUrl);
    return b.replace(path: '${b.path.replaceAll(RegExp(r'/+$'), '')}$path', queryParameters: q == null || q.isEmpty ? null : q);
  }

  Future<dynamic> _json(String method, String path, {Map<String, dynamic>? body, Map<String, String>? query}) async {
    final req = http.Request(method, _rest(path, query))..headers.addAll(_restHeaders);
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await _http.send(req).timeout(const Duration(seconds: 20));
    final text = await res.stream.bytesToString();
    if (res.statusCode == 404) throw const RemoteRestError(404, 'fitur ini tidak tersedia di gateway PC (plugin Kanban mati?)');
    if (res.statusCode == 401 || res.statusCode == 403) throw RemoteRestError(res.statusCode, 'token ditolak oleh PC — pasangkan ulang');
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String msg = 'HTTP ${res.statusCode}';
      try {
        final j = jsonDecode(text);
        if (j is Map && j['detail'] != null) msg = '${j['detail']}';
      } catch (_) {}
      throw RemoteRestError(res.statusCode, msg);
    }
    return text.isEmpty ? null : jsonDecode(text);
  }

  /// Public `/api/status` (version, components); never throws.
  Future<Map<String, dynamic>> serverStatus() async {
    try {
      final j = await _json('GET', '/api/status');
      return j is Map ? Map<String, dynamic>.from(j) : const {};
    } catch (_) {
      return const {};
    }
  }

  /// `GET /api/update?platform=android` — the PC core checks GitHub Releases
  /// (cached there) so the phone never calls GitHub itself. Never throws.
  Future<Map<String, dynamic>> updateInfo() async {
    try {
      final j = await _json('GET', '/api/update', query: const {'platform': 'android'});
      return j is Map ? Map<String, dynamic>.from(j) : const {};
    } catch (_) {
      return const {};
    }
  }

  static const _kanban = '/api/plugins/kanban';

  Future<KanbanSnapshot> board() async => KanbanSnapshot.fromJson(Map<String, dynamic>.from(await _json('GET', '$_kanban/board') as Map));

  Future<void> moveTask(String id, String status) => _json('PATCH', '$_kanban/tasks/${Uri.encodeComponent(id)}', body: {'status': status});

  Future<void> commentTask(String id, String text) =>
      _json('POST', '$_kanban/tasks/${Uri.encodeComponent(id)}/comments', body: {'body': text});

  Future<void> createTask({required String title, String? body, String? assignee, int? priority}) => _json('POST', '$_kanban/tasks', body: {
        'title': title,
        if (body != null && body.isNotEmpty) 'body': body,
        if (assignee != null && assignee.isNotEmpty) 'assignee': assignee,
        'priority': ?priority,
      });
}

class RemoteRestError implements Exception {
  final int status;
  final String message;
  const RemoteRestError(this.status, this.message);
  @override
  String toString() => message;
}
