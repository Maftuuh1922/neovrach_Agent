// Perusahaan (company) on the PC, controlled from the phone: org chart, tickets,
// approvals and costs over the core's `company.*` JSON-RPC methods (the same
// ones the desktop Kantor uses). The PC pushes `company.changed`; the phone
// re-reads. See docs/company-flow-design.md in the core branch.

/// What the company screens need from the PC. [RemoteGateway] implements it;
/// widget tests pass a fake through `RemoteController.debugCompanyApi`.
abstract class CompanyApi {
  /// Calls `company.<method>` with [params]; throws on an RPC error.
  Future<dynamic> companyCall(String method, [Map<String, dynamic> params = const {}]);
}

int _i(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0);
int? _iq(Object? v) => v == null ? null : _i(v);
double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
String _s(Object? v) => v == null ? '' : '$v';
Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};
List<Map<String, dynamic>> _l(Object? v) => v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : const [];

const ticketStatusLabel = {
  'backlog': 'Backlog',
  'todo': 'Akan dikerjakan',
  'in_progress': 'Dikerjakan',
  'review': 'Ditinjau',
  'blocked': 'Terhambat',
  'done': 'Selesai',
  'cancelled': 'Dibatalkan',
};

/// Board order on the phone (cancelled tickets are not listed).
const ticketStatusOrder = ['in_progress', 'review', 'blocked', 'todo', 'backlog', 'done'];

/// Mirrors core/neovarch/company.py TRANSITIONS; the core re-checks every move.
const ticketTransitions = {
  'backlog': ['todo', 'cancelled'],
  'todo': ['in_progress', 'blocked', 'backlog', 'cancelled'],
  'in_progress': ['review', 'blocked', 'done', 'todo', 'cancelled'],
  'review': ['in_progress', 'done', 'cancelled'],
  'blocked': ['todo', 'in_progress', 'cancelled'],
  'done': ['todo'],
  'cancelled': ['todo'],
};

const agentStatusLabel = {
  'idle': 'siaga',
  'running': 'bekerja',
  'paused': 'dijeda',
  'error': 'galat',
  'pending_approval': 'menunggu persetujuan',
  'terminated': 'diberhentikan',
};

class BudgetState {
  const BudgetState({this.cents = 0, this.tokens = 0, this.pct, this.level = 'ok'});
  final double cents;
  final int tokens;
  final double? pct;
  final String level;
  factory BudgetState.fromJson(Map<String, dynamic> j) =>
      BudgetState(cents: _d(j['cents']), tokens: _i(j['tokens']), pct: j['pct'] == null ? null : _d(j['pct']), level: _s(j['level']).isEmpty ? 'ok' : _s(j['level']));
}

class CompanyAgent {
  const CompanyAgent({
    required this.id,
    required this.name,
    this.title = '',
    this.status = 'idle',
    this.reportsTo,
    this.pauseReason,
    this.ticketKey,
    this.ticketTitle,
    this.ticketStatus,
    this.budget = const BudgetState(),
    this.sessionId,
  });
  final int id;
  final String name;
  final String title;
  final String status;
  final int? reportsTo;
  final String? pauseReason;
  final String? ticketKey;
  final String? ticketTitle;
  final String? ticketStatus;
  final BudgetState budget;
  final String? sessionId;

  factory CompanyAgent.fromJson(Map<String, dynamic> j) {
    final cur = _m(j['current_ticket']);
    return CompanyAgent(
      id: _i(j['id']),
      name: _s(j['name']),
      title: _s(j['title']).isNotEmpty ? _s(j['title']) : _s(j['role']),
      status: _s(j['status']).isEmpty ? 'idle' : _s(j['status']),
      reportsTo: _iq(j['reports_to']),
      pauseReason: j['pause_reason'] == null ? null : _s(j['pause_reason']),
      ticketKey: cur.isEmpty ? null : _s(cur['key']),
      ticketTitle: cur.isEmpty ? null : _s(cur['title']),
      ticketStatus: cur.isEmpty ? null : _s(cur['status']),
      budget: BudgetState.fromJson(_m(j['budget'])),
      sessionId: j['session_id'] == null ? null : _s(j['session_id']),
    );
  }

  String get statusLabel => agentStatusLabel[status] ?? status;
  bool get paused => status == 'paused' || status == 'error';
}

class CompanySnapshot {
  const CompanySnapshot({
    required this.exists,
    this.name = '',
    this.mission = '',
    this.autorun = false,
    this.pendingApprovals = 0,
    this.agents = const [],
    this.ticketCounts = const {},
    this.budget = const BudgetState(),
    this.active = const {},
  });
  final bool exists;
  final String name;
  final String mission;
  final bool autorun;
  final int pendingApprovals;
  final List<CompanyAgent> agents;
  final Map<String, int> ticketCounts;
  final BudgetState budget;
  final Set<int> active;

  factory CompanySnapshot.fromJson(Map<String, dynamic> j) {
    if (j['exists'] != true) return const CompanySnapshot(exists: false);
    final c = _m(j['company']);
    return CompanySnapshot(
      exists: true,
      name: _s(c['name']),
      mission: _s(c['mission']),
      autorun: c['autorun'] == true,
      pendingApprovals: _i(j['pending_approvals']),
      agents: [for (final a in _l(j['agents'])) CompanyAgent.fromJson(a)],
      ticketCounts: {for (final e in _m(j['ticket_counts']).entries) e.key: _i(e.value)},
      budget: BudgetState.fromJson(_m(j['budget'])),
      active: {for (final a in (j['active_agents'] is List ? j['active_agents'] as List : const [])) _i(a)},
    );
  }

  /// Managers before their reports, with depth (strict tree in the core).
  List<(CompanyAgent, int)> get orgTree {
    final ids = {for (final a in agents) a.id};
    final out = <(CompanyAgent, int)>[];
    final seen = <int>{};
    void walk(int? manager, int depth) {
      for (final a in agents) {
        final key = a.reportsTo != null && ids.contains(a.reportsTo) ? a.reportsTo : null;
        if (key != manager || seen.contains(a.id)) continue;
        seen.add(a.id);
        out.add((a, depth));
        walk(a.id, depth + 1);
      }
    }

    walk(null, 0);
    return out;
  }

  bool isRunning(CompanyAgent a) => a.status == 'running' || active.contains(a.id);
}

class CompanyTicket {
  const CompanyTicket({
    required this.id,
    required this.key,
    required this.title,
    required this.status,
    this.description = '',
    this.assigneeId,
    this.assigneeName,
    this.locked = false,
    this.blockedBy = 0,
  });
  final int id;
  final String key;
  final String title;
  final String status;
  final String description;
  final int? assigneeId;
  final String? assigneeName;
  final bool locked;
  final int blockedBy;

  factory CompanyTicket.fromJson(Map<String, dynamic> j) => CompanyTicket(
        id: _i(j['id']),
        key: _s(j['key']),
        title: _s(j['title']),
        status: _s(j['status']),
        description: _s(j['description']),
        assigneeId: _iq(j['assignee_id']),
        assigneeName: j['assignee_name'] == null ? null : _s(j['assignee_name']),
        locked: j['locked'] == true,
        blockedBy: _i(j['blocked_by']),
      );
}

class TicketComment {
  const TicketComment({required this.author, required this.body, this.fromUser = false});
  final String author;
  final String body;
  final bool fromUser;
}

class TicketDetail {
  const TicketDetail({required this.ticket, this.ancestry = const [], this.comments = const []});
  final CompanyTicket ticket;
  final List<String> ancestry;
  final List<TicketComment> comments;

  factory TicketDetail.fromJson(Map<String, dynamic> j) => TicketDetail(
        ticket: CompanyTicket.fromJson(j),
        ancestry: [
          for (final a in _l(j['ancestry'])) a['key'] != null ? '${a['key']} ${a['title']}' : _s(a['title']),
        ],
        comments: [
          for (final c in _l(j['comments']))
            TicketComment(
              author: c['author_name'] != null ? _s(c['author_name']) : (c['author_type'] == 'user' ? 'Kamu' : 'Sistem'),
              body: _s(c['body']),
              fromUser: c['author_type'] == 'user',
            ),
        ],
      );
}

class CompanyApproval {
  const CompanyApproval({required this.id, required this.kind, required this.title, this.status = 'pending', this.detail = '', this.agentName});
  final int id;
  final String kind;
  final String title;
  final String status;
  final String detail;
  final String? agentName;

  factory CompanyApproval.fromJson(Map<String, dynamic> j) {
    final p = _m(j['payload']);
    return CompanyApproval(
      id: _i(j['id']),
      kind: _s(j['kind']),
      title: _s(j['title']),
      status: _s(j['status']),
      detail: _s(p['plan'] ?? p['summary'] ?? ''),
      agentName: j['agent_name'] == null ? null : _s(j['agent_name']),
    );
  }

  String get kindLabel => const {'hire': 'rekrut', 'plan': 'rencana', 'review': 'tinjau hasil', 'budget': 'anggaran'}[kind] ?? kind;
}

class CostRow {
  const CostRow({required this.name, this.cents = 0, this.tokens = 0, this.pct});
  final String name;
  final double cents;
  final int tokens;
  final double? pct;
  factory CostRow.fromJson(Map<String, dynamic> j) =>
      CostRow(name: _s(j['name']), cents: _d(j['cents']), tokens: _i(j['tokens']), pct: j['pct'] == null ? null : _d(j['pct']));
}

class CompanyCosts {
  const CompanyCosts({this.month = '', this.total = const BudgetState(), this.byAgent = const []});
  final String month;
  final BudgetState total;
  final List<CostRow> byAgent;
  factory CompanyCosts.fromJson(Map<String, dynamic> j) => CompanyCosts(
        month: _s(j['month']),
        total: BudgetState.fromJson(_m(j['total'])),
        byAgent: [for (final r in _l(j['by_agent'])) CostRow.fromJson(r)],
      );
}

String formatCents(double cents) => '\$${(cents / 100).toStringAsFixed(cents > 0 && cents < 1 ? 4 : 2)}';

String formatTokens(int t) => t >= 1000000
    ? '${(t / 1000000).toStringAsFixed(1)} jt token'
    : t >= 1000
        ? '${(t / 1000).toStringAsFixed(1)} rb token'
        : '$t token';

/// Thin typed layer over [CompanyApi] used by the screens.
class CompanyClient {
  const CompanyClient(this.api);
  final CompanyApi api;

  Future<CompanySnapshot> snapshot() async => CompanySnapshot.fromJson(_m(await api.companyCall('snapshot')));
  Future<List<CompanyTicket>> tickets() async =>
      [for (final t in _l(_m(await api.companyCall('ticket.list'))['tickets'])) CompanyTicket.fromJson(t)];
  Future<TicketDetail> ticket(int id) async => TicketDetail.fromJson(_m(await api.companyCall('ticket.get', {'id': id})));
  Future<List<CompanyApproval>> approvals() async =>
      [for (final a in _l(_m(await api.companyCall('approval.list', {'status': 'pending'}))['approvals'])) CompanyApproval.fromJson(a)];
  Future<CompanyCosts> costs() async => CompanyCosts.fromJson(_m(await api.companyCall('costs')));

  Future<void> seedDemo() => api.companyCall('seed_demo');
  Future<void> setAutorun(bool on) => api.companyCall('update', {'autorun': on});
  Future<void> wake(int id) => api.companyCall('agent.wake', {'id': id});
  Future<void> pause(int id) => api.companyCall('agent.pause', {'id': id});
  Future<void> resume(int id) => api.companyCall('agent.resume', {'id': id});
  Future<void> stop(int id) => api.companyCall('agent.stop', {'id': id});
  Future<void> move(int id, String status) => api.companyCall('ticket.move', {'id': id, 'status': status});
  Future<void> assign(int id, int? agentId) => api.companyCall('ticket.assign', {'id': id, 'agent_id': agentId});
  Future<void> comment(int id, String body) => api.companyCall('ticket.comment', {'id': id, 'body': body});
  Future<void> createTicket(String title, int? assigneeId) =>
      api.companyCall('ticket.save', {'title': title, 'assignee_id': ?assigneeId});
  Future<void> decide(int id, bool approve, {String note = ''}) =>
      api.companyCall('approval.decide', {'id': id, 'decision': approve ? 'approve' : 'reject', 'note': note});
}
