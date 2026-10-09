import 'models_api.dart';

// The PC's Office (`GET /api/office`, pushed as `office.update`): the agents
// as "pegawai" at their desks, with status, current task and an activity feed.
// Pure Dart.

double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
String? _str(Object? v) {
  final s = v == null ? '' : '$v'.trim();
  return s.isEmpty ? null : s;
}

DateTime? _ts(Object? v) {
  final d = _num(v);
  return d <= 0 ? null : DateTime.fromMillisecondsSinceEpoch((d * (d > 1e12 ? 1 : 1000)).round());
}

class OfficeAgent {
  final String id;
  final String kind; // session | kanban
  final String? sessionId;
  final String name;
  final String role;
  final String status; // working | waiting-approval | idle
  final String? task;
  final String? tool;
  final String? title;
  final String model;
  final DateTime? lastActivity;
  final String? lastActivityText;
  final int messageCount;
  final String? pendingCommand;
  const OfficeAgent({
    required this.id,
    required this.kind,
    this.sessionId,
    required this.name,
    required this.role,
    required this.status,
    this.task,
    this.tool,
    this.title,
    this.model = '',
    this.lastActivity,
    this.lastActivityText,
    this.messageCount = 0,
    this.pendingCommand,
    this.modelOverride,
    this.modelSource = 'global',
  });

  /// 9Router contract: the agent's own model (null = follows the PC default).
  final ModelRef? modelOverride;
  final String modelSource;

  bool get working => status == 'working';
  bool get waiting => status == 'waiting-approval';

  /// Indonesian label for [status].
  String get statusLabel => switch (status) {
        'working' => 'bekerja',
        'waiting-approval' => 'menunggu persetujuan',
        'idle' => 'santai',
        _ => status,
      };

  factory OfficeAgent.fromJson(Map<String, dynamic> j) {
    final pa = j['pending_approval'];
    return OfficeAgent(
      id: '${j['id'] ?? j['session_id'] ?? j['name']}',
      kind: '${j['kind'] ?? 'session'}',
      sessionId: _str(j['session_id']),
      name: _str(j['name']) ?? 'Agen',
      role: _str(j['role']) ?? 'Agen',
      status: _str(j['status']) ?? 'idle',
      task: _str(j['current_task']),
      tool: _str(j['current_tool']),
      title: _str(j['title']),
      model: '${j['model'] ?? ''}',
      lastActivity: _ts(j['last_activity']),
      lastActivityText: _str(j['last_activity_text']),
      messageCount: (j['message_count'] as num?)?.toInt() ?? 0,
      pendingCommand: pa is Map ? _str(pa['command']) ?? _str(pa['description']) : null,
      modelOverride: ModelRef.maybe(j['model_override']),
      modelSource: _str(j['model_source']) ?? 'global',
    );
  }
}

class OfficeActivity {
  final int id;
  final DateTime? at;
  final String kind; // tool, tool.done, message, message.user, approval, approval.done, task, error
  final String agent;
  final String? sessionId;
  final String text;
  const OfficeActivity({required this.id, this.at, required this.kind, required this.agent, this.sessionId, required this.text});
  factory OfficeActivity.fromJson(Map<String, dynamic> j) => OfficeActivity(
        id: (j['id'] as num?)?.toInt() ?? 0,
        at: _ts(j['ts']),
        kind: '${j['kind'] ?? ''}',
        agent: _str(j['agent']) ?? 'Agen',
        sessionId: _str(j['session_id']),
        text: '${j['text'] ?? ''}',
      );
}

class OfficeSnapshot {
  final String host;
  final String coreVersion;
  final int seq;
  final List<OfficeAgent> agents;
  final List<OfficeActivity> feed;
  final Map<String, int> counts;
  final Map<String, int> kanban;
  final Map<String, dynamic> vault;
  const OfficeSnapshot({
    this.host = '',
    this.coreVersion = '',
    this.seq = 0,
    this.agents = const [],
    this.feed = const [],
    this.counts = const {},
    this.kanban = const {},
    this.vault = const {},
    this.defaultModel,
  });
  final ModelRef? defaultModel;

  int get working => counts['working'] ?? agents.where((a) => a.working).length;
  int get waiting => counts['waiting-approval'] ?? agents.where((a) => a.waiting).length;
  bool get vaultConfigured => vault['configured'] == true;

  static Map<String, int> _ints(Object? m) =>
      m is Map ? {for (final e in m.entries) '${e.key}': (e.value as num?)?.toInt() ?? 0} : const {};

  factory OfficeSnapshot.fromJson(Map<String, dynamic> j) => OfficeSnapshot(
        host: '${j['host'] ?? ''}',
        coreVersion: '${j['core_version'] ?? ''}',
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        agents: [for (final a in (j['agents'] as List? ?? const []).whereType<Map>()) OfficeAgent.fromJson(Map<String, dynamic>.from(a))],
        feed: [for (final f in (j['feed'] as List? ?? const []).whereType<Map>()) OfficeActivity.fromJson(Map<String, dynamic>.from(f))],
        counts: _ints(j['counts']),
        kanban: _ints(j['kanban']),
        vault: j['vault'] is Map ? Map<String, dynamic>.from(j['vault'] as Map) : const {},
        defaultModel: ModelRef.maybe(j['default_model']),
      );
}
