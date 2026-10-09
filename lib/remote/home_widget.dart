// Home-screen widgets (Android AppWidgets, Kotlin `com.neovarch.agent.widget`):
//   * NvHomeWidget   "Neovarch · Aksi cepat" 4x2: Chat / Suara / + Tugas /
//                    Kantor tiles + the latest Kantor 3D snapshot.
//   * NvStatusWidget "Neovarch · Status" 2x2: PC, working / waiting counts,
//                    last activity.
//   * NvAgentsWidget "Neovarch · Agen" 4x4: the agents with their coat
//                    avatars, status and current task; "Kasih tugas".
// The widgets hold no logic of their own: Flutter pushes one summary over the
// `neovarch/device` channel (`updateWidget`) whenever it changes (throttled,
// see [HomeWidgetThrottle]); every provider redraws from it. Buttons open the
// app with `nv_route` = chat | voice | newtask | kantor | connect |
// agent:<id>, handled by RemoteShell.route. The Kantor snapshot is captured
// by the 3D WebView ([KantorSnapshotThrottle]) and saved natively
// (`saveWidgetSnapshot`).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/device_tools.dart';
import '../theme/neovarch_mobile_theme.dart';
import 'agent_identity.dart';
import 'office_models.dart';
import 'remote_controller.dart';
import 'remote_gateway.dart' show RemoteStatus;

/// One-shot action asked for from outside the app (a home-screen widget
/// button): 'voice' starts dictation in Chat, 'newtask' opens the Tugas baru
/// sheet, `agent:<id>` opens that agent's sheet in Kantor. The screen that
/// performs it sets it back to null.
final remoteLaunchAction = ValueNotifier<String?>(null);

/// Payload format version (the native side reads v1 maps too).
const homeWidgetPayloadVersion = 2;

/// Agents sent to the widgets at most (the 4x4 list shows ~5–7).
const homeWidgetMaxAgents = 12;

/// Lanes that are finished work, not counted as open tasks.
const _closedLanes = {'done', 'archived', 'selesai'};

int _statusRank(String s) => switch (s) {
      'working' => 0,
      'waiting-approval' || 'waiting' => 1,
      'error' => 2,
      _ => 3,
    };

/// One agent row for the widgets: identity per agent-identity-spec (coat =
/// hash(id), initial of the core's display name) so the widget matches the app.
Map<String, Object?> homeWidgetAgent(OfficeAgent a) => {
      'id': a.id,
      'name': a.name,
      'initial': agentInitial(a.name),
      'coat': agentCoat(a.id).toARGB32(),
      'status': a.status,
      'task': a.task ?? a.title,
    };

/// The summary every widget draws from. Pure: same controller state (and
/// accent), same map.
Map<String, Object?> homeWidgetPayload(RemoteController r, {int? accent}) {
  final agents = r.office?.agents ?? const <OfficeAgent>[];
  final working = agents.where((a) => a.working).toList();
  final waitingAgents = agents.where((a) => a.waiting).length;
  final waiting = r.approvals.length;
  int tasks;
  final b = r.board;
  if (b != null) {
    tasks = b.lanes.where((l) => !_closedLanes.contains(l.name)).fold(0, (n, l) => n + l.cards.length);
  } else {
    final k = r.office?.kanban ?? const <String, int>{};
    tasks = k.entries.where((e) => !_closedLanes.contains(e.key)).fold(0, (n, e) => n + e.value);
  }
  final paired = r.desktop != null;
  final status = switch (r.status) {
    RemoteStatus.connected => 'terhubung',
    RemoteStatus.connecting || RemoteStatus.reconnecting => 'menyambung…',
    _ => paired ? 'terputus' : 'belum dipasangkan',
  };
  final current = working.isNotEmpty ? working.first : null;
  // stable order: working, waiting, error, idle; then by name
  final sorted = [...agents]..sort((x, y) {
      final c = _statusRank(x.status).compareTo(_statusRank(y.status));
      return c != 0 ? c : x.name.toLowerCase().compareTo(y.name.toLowerCase());
    });
  OfficeAgent? last;
  for (final a in agents) {
    final t = a.lastActivity;
    if (t == null) continue;
    if (last == null || t.isAfter(last.lastActivity!)) last = a;
  }
  return {
    'v': homeWidgetPayloadVersion,
    'pc': r.desktop?.name ?? 'Neovarch',
    'paired': paired,
    'connected': r.connected,
    'status': status,
    'working': working.length,
    'waiting': waiting,
    'waitingAgents': waitingAgents,
    'agentCount': agents.length,
    'tasks': tasks,
    'task': current == null ? null : '${current.name}: ${current.task ?? current.title ?? 'bekerja'}',
    'accent': accent ?? NV.red.toARGB32(),
    'agents': [for (final a in sorted.take(homeWidgetMaxAgents)) homeWidgetAgent(a)],
    'lastName': last?.name,
    'lastText': last == null ? null : (last.lastActivityText ?? last.task ?? last.title),
    'lastAt': last?.lastActivity?.millisecondsSinceEpoch,
  };
}

/// Deep equality for payload maps (lists of maps inside).
bool homeWidgetPayloadEquals(Map<String, Object?>? a, Map<String, Object?>? b) {
  if (a == null || b == null) return a == b;
  return jsonEncode(a) == jsonEncode(b);
}

/// Rate limit for widget pushes: an unchanged payload is never sent; a
/// changed one goes out at once unless the last send was less than
/// [minInterval] ago, then the newest payload is sent when the interval ends
/// (trailing edge; intermediate ones are dropped). A change of pairing or
/// connection is sent at once, so the widget never shows a stale online dot.
class HomeWidgetThrottle {
  HomeWidgetThrottle({
    required this.send,
    this.minInterval = const Duration(seconds: 10),
    DateTime Function()? clock,
    Timer Function(Duration, void Function())? timer,
  })  : _clock = clock ?? DateTime.now,
        _timer = timer ?? Timer.new;

  final void Function(Map<String, Object?> payload) send;
  final Duration minInterval;
  final DateTime Function() _clock;
  final Timer Function(Duration, void Function()) _timer;

  Map<String, Object?>? _sent;
  DateTime? _sentAt;
  Map<String, Object?>? _pending;
  Timer? _t;

  /// Payload waiting for the trailing send (tests).
  Map<String, Object?>? get pending => _pending;

  bool _urgent(Map<String, Object?> p) {
    final s = _sent;
    return s == null || s['connected'] != p['connected'] || s['paired'] != p['paired'];
  }

  void push(Map<String, Object?> p) {
    if (homeWidgetPayloadEquals(_sent, p)) {
      // back to what the widget shows: drop a queued change
      _pending = null;
      _t?.cancel();
      _t = null;
      return;
    }
    final now = _clock();
    final since = _sentAt == null ? null : now.difference(_sentAt!);
    if (_urgent(p) || since == null || since >= minInterval) {
      _flush(p, now);
      return;
    }
    _pending = p;
    _t ??= _timer(minInterval - since, () {
      _t = null;
      final q = _pending;
      if (q != null) _flush(q, _clock());
    });
  }

  void _flush(Map<String, Object?> p, DateTime now) {
    _t?.cancel();
    _t = null;
    _pending = null;
    _sent = p;
    _sentAt = now;
    send(p);
  }

  void dispose() {
    _t?.cancel();
    _t = null;
  }
}

/// Pushes [homeWidgetPayload] to the widgets (every remote notify lands
/// here; unchanged summaries are not sent, changes are throttled).
class HomeWidgetSync {
  HomeWidgetSync({
    Future<void> Function(Map<String, Object?> payload)? send,
    Duration minInterval = const Duration(seconds: 10),
    DateTime Function()? clock,
    Timer Function(Duration, void Function())? timer,
  }) {
    final s = send ?? _platformSend;
    _throttle = HomeWidgetThrottle(send: (p) => s(p), minInterval: minInterval, clock: clock, timer: timer);
  }

  late final HomeWidgetThrottle _throttle;

  static Future<void> _platformSend(Map<String, Object?> p) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await deviceCall<bool>('updateWidget', Map<String, dynamic>.from(p));
    } catch (_) {
      // older native side / no widget: nothing to update
    }
  }

  void update(RemoteController r) => _throttle.push(homeWidgetPayload(r));

  void dispose() => _throttle.dispose();
}

/// When the Kantor 3D view may take a snapshot for the "Aksi cepat" widget:
/// only while the scene is ready and on screen, at most every [minInterval]
/// (a scene change shortens the wait to [changedInterval]), so the GPU and
/// storage are not hit on every frame.
class KantorSnapshotThrottle {
  KantorSnapshotThrottle({
    this.minInterval = const Duration(minutes: 2),
    this.changedInterval = const Duration(seconds: 20),
    this.firstDelay = const Duration(seconds: 4),
  });

  final Duration minInterval;
  final Duration changedInterval;
  final Duration firstDelay;

  DateTime? _readyAt;
  DateTime? _lastAt;
  bool _changed = false;

  void sceneReady(DateTime now) => _readyAt = now;
  void sceneChanged() => _changed = true;

  bool shouldCapture(DateTime now, {required bool visible}) {
    final ready = _readyAt;
    if (!visible || ready == null) return false;
    if (now.difference(ready) < firstDelay) return false;
    final last = _lastAt;
    if (last == null) return true;
    final wait = _changed ? changedInterval : minInterval;
    return now.difference(last) >= wait;
  }

  void captured(DateTime now) {
    _lastAt = now;
    _changed = false;
  }
}

/// Decodes the scene's `data:image/jpeg;base64,…` snapshot. Null when it is
/// not a JPEG/PNG data URL or is implausibly small/large.
Uint8List? decodeSnapshotDataUrl(String? url) {
  if (url == null) return null;
  final m = RegExp(r'^data:image/(jpeg|png);base64,').firstMatch(url);
  if (m == null) return null;
  try {
    final bytes = base64Decode(url.substring(m.end));
    if (bytes.length < 512 || bytes.length > 2 * 1024 * 1024) return null;
    return bytes;
  } catch (_) {
    return null;
  }
}

/// Saves a Kantor snapshot for the widget (native writes it to app files and
/// redraws the "Aksi cepat" widgets). Returns the saved path or null.
Future<String?> saveKantorSnapshot(Uint8List jpeg) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    return await deviceCall<String>('saveWidgetSnapshot', {'bytes': jpeg});
  } catch (_) {
    return null;
  }
}

/// Whether any "Aksi cepat" widget is on the home screen (no snapshot work
/// otherwise). False off Android / on an older native side.
Future<bool> kantorWidgetPlaced() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    return await deviceCall<bool>('widgetsPlaced', {'kind': 'quick'}) ?? false;
  } catch (_) {
    return false;
  }
}
