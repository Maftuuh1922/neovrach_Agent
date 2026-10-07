// Port of src/lib/store.ts: the board snapshot and the meeting state,
// polled every NEXT_PUBLIC_POLL_MS (default 4 s) like the web app.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/office_backend.dart';
import '../models/models.dart';
import 'app_controller.dart';

class OfficeNotice {
  final String title;
  final String body;
  const OfficeNotice(this.title, this.body);
}

class OfficeController extends ChangeNotifier {
  OfficeController(this.app);
  final AppController app;

  OfficeBackend get backend => app.office;

  List<Task> tasks = [];
  List<Agent> agents = [];
  Meeting? meeting;
  List<Meeting> liveMeetings = [];
  bool meetingConfigured = false;
  List<ArchivedMeeting> meetingHistory = [];
  bool loading = true;
  String? error;
  DateTime? lastUpdated;

  final _seen = <String, String>{};
  final _notices = StreamController<OfficeNotice>.broadcast();
  Stream<OfficeNotice> get notices => _notices.stream;

  Timer? _timer;
  bool _ticking = false;
  int _listeners = 0;

  /// Screens call [attach]/[detach]; polling runs while any is visible.
  void attach() {
    _listeners++;
    if (_timer == null) {
      unawaited(_tick());
      _timer = Timer.periodic(Duration(milliseconds: app.settings.pollMs.clamp(1500, 60000)), (_) => _tick());
    }
  }

  void detach() {
    _listeners = (_listeners - 1).clamp(0, 999);
    if (_listeners == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void reset() {
    tasks = [];
    agents = [];
    meeting = null;
    liveMeetings = [];
    meetingHistory = [];
    _seen.clear();
    loading = true;
    error = null;
    notifyListeners();
    unawaited(_tick());
  }

  Future<void> _tick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      await Future.wait([load(), refreshMeeting()]);
    } finally {
      _ticking = false;
    }
  }

  Future<void> refresh() => _tick();

  Future<void> load() async {
    final res = await backend.get('/api/hermes/tasks');
    if (!res.ok || res.data == null) {
      error = res.error ?? 'gagal memuat papan';
      loading = false;
      notifyListeners();
      return;
    }
    final next = res.list('tasks').map(Task.fromJson).toList();
    // Alert on review/blocked transitions, like the web app's Notification.
    for (final t in next) {
      final prev = _seen[t.id];
      if (prev != null && prev != t.status && (t.status == 'review' || t.status == 'blocked')) {
        _notices.add(OfficeNotice('Kanban · ${t.status == 'review' ? 'REVIEW' : 'TERHAMBAT'}', t.title));
      }
      _seen[t.id] = t.status;
    }
    tasks = next;
    agents = res.list('agents').map(Agent.fromJson).toList();
    error = null;
    loading = false;
    lastUpdated = DateTime.now();
    notifyListeners();
  }

  Future<void> refreshMeeting() async {
    // A blip must not clear the panel: keep the last known meeting quietly.
    final res = await backend.get('/api/hermes/meeting');
    if (!res.ok || res.data == null) return;
    final live = res.list('live').map(Meeting.fromJson).toList();
    final active = live.where((m) => m.live).firstOrNull;
    liveMeetings = live;
    meeting = active ?? live.firstOrNull;
    meetingConfigured = res.map['configured'] == true;
    meetingHistory = res.list('archived').map(ArchivedMeeting.fromJson).toList();
    notifyListeners();
  }

  // ----------------------------------------------------------- derived ---
  int get running => tasks.where((t) => t.status == 'running').length;
  int get done => tasks.where((t) => t.status == 'done').length;
  int get pct => tasks.isEmpty ? 0 : ((done / tasks.length) * 100).round();
  bool get online => !loading && error == null;

  Task? task(String? id) => id == null ? null : tasks.where((t) => t.id == id).firstOrNull;
  Agent? agent(String? name) => name == null ? null : agents.where((a) => a.name == name).firstOrNull;
  Agent? agentAtDesk(int desk) => agents.where((a) => a.deskIndex == desk).firstOrNull;

  // ----------------------------------------------------------- actions ---
  Future<String?> createTask({required String title, required String assignee, String body = '', int priority = 0}) async {
    final res = await backend.post('/api/hermes/tasks', {
      'title': title,
      'assignee': assignee.isEmpty ? (agents.firstOrNull?.name ?? '') : assignee,
      'body': body,
      'priority': priority,
    });
    if (!res.ok || res.data == null) return res.error ?? 'gagal membuat tugas';
    await load();
    return null;
  }

  Future<String?> taskAction(String id, Map<String, dynamic> body) async {
    final res = await backend.post('/api/hermes/tasks/${Uri.encodeComponent(id)}', body);
    if (!res.ok) return res.error ?? 'aksi gagal';
    unawaited(load());
    return null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _notices.close();
    super.dispose();
  }
}
