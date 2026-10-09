// Home-screen widget (Android AppWidget `NvHomeWidget`, Kotlin): a small
// card with the paired PC's state (connection, agents working, approvals
// waiting, open Kanban tasks, the current task) and three buttons: Chat,
// Suara (dictation) and Tugas baru. The widget holds no logic of its own:
// Flutter pushes a summary over the `neovarch/device` channel
// (`updateWidget`) whenever it changes, and the buttons open the app with
// `nv_route` = chat | voice | newtask, handled by RemoteShell.route.
import 'package:flutter/foundation.dart';

import '../data/device_tools.dart';
import 'remote_controller.dart';
import 'remote_gateway.dart' show RemoteStatus;

/// One-shot action asked for from outside the app (a home-screen widget
/// button): 'voice' starts dictation in Chat, 'newtask' opens the Tugas baru
/// sheet. The screen that performs it sets it back to null.
final remoteLaunchAction = ValueNotifier<String?>(null);

/// Lanes that are finished work, not counted as open tasks.
const _closedLanes = {'done', 'archived', 'selesai'};

/// The summary the widget shows. Pure: same controller state, same map.
Map<String, Object?> homeWidgetPayload(RemoteController r) {
  final agents = r.office?.agents ?? const [];
  final working = agents.where((a) => a.status == 'working').toList();
  final waiting = r.approvals.length;
  int tasks;
  final b = r.board;
  if (b != null) {
    tasks = b.lanes.where((l) => !_closedLanes.contains(l.name)).fold(0, (n, l) => n + l.cards.length);
  } else {
    final k = r.office?.kanban ?? const <String, int>{};
    tasks = k.entries.where((e) => !_closedLanes.contains(e.key)).fold(0, (n, e) => n + e.value);
  }
  final status = switch (r.status) {
    RemoteStatus.connected => 'terhubung',
    RemoteStatus.connecting || RemoteStatus.reconnecting => 'menyambung…',
    _ => r.desktop == null ? 'belum dipasangkan' : 'terputus',
  };
  final current = working.isNotEmpty ? working.first : null;
  return {
    'pc': r.desktop?.name ?? 'Neovarch',
    'connected': r.connected,
    'status': status,
    'working': working.length,
    'waiting': waiting,
    'tasks': tasks,
    'task': current == null ? null : '${current.name}: ${current.task ?? current.title ?? 'bekerja'}',
  };
}

/// Pushes [homeWidgetPayload] to the widget when it changed (every remote
/// notify lands here; unchanged summaries are not sent).
class HomeWidgetSync {
  HomeWidgetSync({Future<void> Function(Map<String, Object?> payload)? send}) : _send = send ?? _platformSend;

  final Future<void> Function(Map<String, Object?> payload) _send;
  Map<String, Object?>? _last;

  static Future<void> _platformSend(Map<String, Object?> p) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await deviceCall<bool>('updateWidget', Map<String, dynamic>.from(p));
    } catch (_) {
      // older native side / no widget: nothing to update
    }
  }

  void update(RemoteController r) {
    final p = homeWidgetPayload(r);
    if (_last != null && mapEquals(_last, p)) return;
    _last = p;
    _send(p);
  }
}
