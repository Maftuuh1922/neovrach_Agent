// Kantor → Perusahaan: the PC's company of agents, controlled from the phone.
// Org chart (wake / pause / resume / stop), tickets (move, assign, comment,
// new), approvals (approve / reject) and costs. Everything goes through the
// core's `company.*` RPCs; the PC pushes `company.changed` and this re-reads.
import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/neovarch_mobile_theme.dart';
import '../../ui/widgets/common.dart' show toast;
import '../company_models.dart';
import '../remote_controller.dart';
import 'nv_widgets.dart';

/// Sub-views of the Perusahaan screen.
const companySegOrg = 0, companySegTickets = 1, companySegApprovals = 2, companySegCosts = 3;

class RemoteCompanyScreen extends ConsumerStatefulWidget {
  const RemoteCompanyScreen({super.key, this.initialSegment = companySegOrg});
  final int initialSegment;
  @override
  ConsumerState<RemoteCompanyScreen> createState() => _RemoteCompanyScreenState();
}

class _RemoteCompanyScreenState extends ConsumerState<RemoteCompanyScreen> {
  late int seg = widget.initialSegment;
  CompanySnapshot? snap;
  List<CompanyTicket> tickets = const [];
  List<CompanyApproval> approvals = const [];
  CompanyCosts? costs;
  String? error;
  bool busy = false;
  int _rev = -1;

  CompanyClient? get _client {
    final api = ref.read(remoteProvider).companyApi;
    return api == null ? null : CompanyClient(api);
  }

  Future<void> load() async {
    final c = _client;
    if (c == null) return;
    try {
      final s = await c.snapshot();
      final results = s.exists ? await Future.wait([c.tickets(), c.approvals(), c.costs()]) : const [];
      if (!mounted) return;
      setState(() {
        snap = s;
        if (s.exists) {
          tickets = results[0] as List<CompanyTicket>;
          approvals = results[1] as List<CompanyApproval>;
          costs = results[2] as CompanyCosts;
        }
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = _msg(e));
    }
  }

  static String _msg(Object e) {
    final s = '$e';
    if (s.contains('-32601') || s.contains('not implemented')) return 'Core di PC belum punya fitur Perusahaan — perbarui Neovarch di PC.';
    return s.replaceFirst(RegExp(r'^(Exception|RpcError|GatewayError)[^:]*:\s*'), '');
  }

  /// Runs one action, toasts its error, then re-reads.
  Future<void> act(Future<void> Function(CompanyClient c) fn, {String? done}) async {
    final c = _client;
    if (c == null || busy) return;
    setState(() => busy = true);
    try {
      await fn(c);
      if (mounted && done != null) toast(context, done);
    } catch (e) {
      if (mounted) toast(context, _msg(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(remoteProvider);
    if (r.companyRevision != _rev) {
      _rev = r.companyRevision;
      scheduleMicrotask(load);
    }
    final s = snap;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          key: const ValueKey('company-list'),
          padding: EdgeInsets.only(bottom: 120 + MediaQuery.paddingOf(context).bottom),
          children: [
            NvHeader(
              kicker: 'perusahaan · ${r.desktop?.name ?? 'pc'}',
              title: s?.exists == true ? s!.name : 'Perusahaan',
              status: Text(
                s == null
                    ? 'memuat…'
                    : !s.exists
                        ? 'belum dibuat di PC'
                        : '${s.agents.length} pegawai · ${s.pendingApprovals} menunggu persetujuan',
                style: NV.monoLabel(size: 10).copyWith(letterSpacing: 0.4),
              ),
              actions: [NvIconButton(tooltip: 'Segarkan', icon: CupertinoIcons.arrow_clockwise, onPressed: r.connected ? load : null)],
            ),
            if (error != null)
              Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: NvNotice(error!)),
            if (s != null && !s.exists)
              NvEmpty(
                kicker: 'kantor',
                title: 'Belum ada perusahaan',
                body: 'Jadikan Kantor di PC sebuah perusahaan: misi, struktur organisasi, tiket, persetujuan, dan anggaran. '
                    'Tidak ada agen yang berjalan sendiri sampai kamu menyalakan “Jalan otomatis”.',
                action: FilledButton(
                  key: const ValueKey('company-seed'),
                  onPressed: busy || !r.connected ? null : () => act((c) => c.seedDemo(), done: 'Contoh perusahaan dibuat'),
                  child: const Text('Buat contoh perusahaan'),
                ),
              ),
            if (s != null && s.exists) ...[
              if (s.mission.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(s.mission, style: TextStyle(fontSize: 13, height: 1.4, color: NV.muted)),
                ),
              NvPanel(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: SwitchListTile(
                  key: const ValueKey('company-autorun'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Jalan otomatis'),
                  subtitle: Text('Agen bangun sendiri saat ada tiket, komentar, atau jadwal', style: TextStyle(fontSize: 12, color: NV.muted)),
                  value: s.autorun,
                  onChanged: busy ? null : (v) => act((c) => c.setAutorun(v)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: NvGlassSegmented(
                  key: const ValueKey('company-segments'),
                  labels: ['Organisasi', 'Tiket', 'Setujui${approvals.isEmpty ? '' : ' (${approvals.length})'}', 'Biaya'],
                  index: seg,
                  onChanged: (i) => setState(() => seg = i),
                ),
              ),
              ...switch (seg) {
                companySegTickets => _tickets(s),
                companySegApprovals => _approvals(),
                companySegCosts => _costs(),
                _ => _org(s),
              },
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ org --
  List<Widget> _org(CompanySnapshot s) => [
        NvSection('struktur organisasi', count: s.agents.length),
        for (final (a, depth) in s.orgTree)
          NvPanel(
            key: ValueKey('company-agent-${a.id}'),
            margin: EdgeInsets.fromLTRB(16.0 + depth * 18, 0, 16, 8),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                NvDot(s.isRunning(a) ? NV.red : (a.paused ? NV.muted : NV.faint)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: a.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    TextSpan(text: '  ${a.title}', style: TextStyle(fontSize: 12, color: NV.muted)),
                  ])),
                ),
                NvPill(s.isRunning(a) ? 'bekerja' : (a.pauseReason == 'budget' && a.status == 'paused' ? 'dijeda · anggaran' : a.statusLabel),
                    color: s.isRunning(a) ? NV.red : null),
              ]),
              const SizedBox(height: 6),
              Text(
                a.ticketKey != null ? '${a.ticketKey} · ${a.ticketTitle} (${ticketStatusLabel[a.ticketStatus] ?? a.ticketStatus})' : 'Tidak memegang tiket',
                style: TextStyle(fontSize: 12.5, color: NV.muted),
              ),
              if (a.budget.pct != null) ...[
                const SizedBox(height: 6),
                _Meter(pct: a.budget.pct!, level: a.budget.level),
              ],
              Wrap(spacing: 4, children: [
                if (!s.isRunning(a) && !a.paused && a.status != 'pending_approval')
                  TextButton(onPressed: busy ? null : () => act((c) => c.wake(a.id), done: '${a.name} dibangunkan'), child: const Text('Bangunkan')),
                if (s.isRunning(a))
                  TextButton(onPressed: busy ? null : () => act((c) => c.stop(a.id), done: '${a.name} dihentikan'), child: const Text('Hentikan')),
                if (a.paused)
                  TextButton(onPressed: busy ? null : () => act((c) => c.resume(a.id), done: '${a.name} lanjut'), child: const Text('Lanjutkan'))
                else if (a.status != 'pending_approval')
                  TextButton(onPressed: busy ? null : () => act((c) => c.pause(a.id), done: '${a.name} dijeda'), child: const Text('Jeda')),
              ]),
            ]),
          ),
        if (s.agents.isEmpty) const NvEmpty(title: 'Belum ada pegawai', body: 'Rekrut pegawai dari Kantor di PC.'),
      ];

  // -------------------------------------------------------------- tickets --
  List<Widget> _tickets(CompanySnapshot s) => [
        NvSection('tiket', count: tickets.where((t) => t.status != 'cancelled').length, trailing: TextButton.icon(
          key: const ValueKey('company-new-ticket'),
          onPressed: busy ? null : () => _newTicket(s),
          icon: const Icon(CupertinoIcons.add, size: 16),
          label: const Text('Baru'),
        )),
        for (final status in ticketStatusOrder)
          if (tickets.any((t) => t.status == status)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
              child: Text((ticketStatusLabel[status] ?? status).toUpperCase(), style: NV.monoLabel(color: NV.redInk)),
            ),
            for (final t in tickets.where((t) => t.status == status))
              NvPanel(
                key: ValueKey('company-ticket-${t.key}'),
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: const EdgeInsets.all(12),
                onTap: () => _openTicket(s, t),
                child: Row(children: [
                  Text(t.key, style: NV.code(size: 11, color: NV.redInk)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                      Text(
                        '${t.assigneeName ?? 'belum ditugaskan'}${t.locked ? ' · dikerjakan' : ''}${t.blockedBy > 0 ? ' · ${t.blockedBy} hambatan' : ''}',
                        style: TextStyle(fontSize: 11.5, color: NV.muted),
                      ),
                    ]),
                  ),
                  Icon(CupertinoIcons.chevron_right, size: 14, color: NV.faint),
                ]),
              ),
          ],
        if (tickets.isEmpty) const NvEmpty(title: 'Belum ada tiket', body: 'Buat tiket dan tugaskan ke pegawai.'),
      ];

  Future<void> _newTicket(CompanySnapshot s) async {
    final title = TextEditingController();
    int? assignee;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const NvSheetTitle(kicker: 'perusahaan', title: 'Tiket baru'),
            TextField(key: const ValueKey('company-ticket-title'), controller: title, autofocus: true, decoration: const InputDecoration(hintText: 'Judul tiket')),
            const SizedBox(height: 12),
            DropdownButton<int?>(
              key: const ValueKey('company-ticket-assignee'),
              isExpanded: true,
              value: assignee,
              hint: const Text('Penanggung jawab'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Tanpa penanggung jawab')),
                for (final a in s.agents.where((a) => a.status != 'pending_approval')) DropdownMenuItem<int?>(value: a.id, child: Text(a.name)),
              ],
              onChanged: (v) => setSheet(() => assignee = v),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(key: const ValueKey('company-ticket-create'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Buat')),
            ),
          ]),
        ),
      ),
    );
    if (ok == true && title.text.trim().isNotEmpty) {
      await act((c) => c.createTicket(title.text.trim(), assignee), done: 'Tiket dibuat');
    }
  }

  Future<void> _openTicket(CompanySnapshot s, CompanyTicket t) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (ctx) => _TicketSheet(client: _client!, ticket: t, snap: s, onChanged: load),
      );

  // ------------------------------------------------------------ approvals --
  List<Widget> _approvals() => [
        NvSection('persetujuan', count: approvals.length),
        if (approvals.isEmpty) const NvEmpty(kicker: 'aman', title: 'Tidak ada yang menunggu', body: 'Rekrutmen, rencana, dan hasil kerja yang perlu kamu tinjau muncul di sini.'),
        for (final ap in approvals)
          NvPanel(
            key: ValueKey('company-approval-${ap.id}'),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [NvPill(ap.kindLabel), const SizedBox(width: 8), if (ap.agentName != null) Text(ap.agentName!, style: TextStyle(fontSize: 12, color: NV.muted))]),
              const SizedBox(height: 8),
              Text(ap.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              if (ap.detail.isNotEmpty) ...[const SizedBox(height: 6), Text(ap.detail, style: TextStyle(fontSize: 13, height: 1.4, color: NV.muted))],
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: busy ? null : () => act((c) => c.decide(ap.id, false), done: 'Ditolak'), child: const Text('Tolak')),
                const SizedBox(width: 6),
                FilledButton(onPressed: busy ? null : () => act((c) => c.decide(ap.id, true), done: 'Disetujui'), child: const Text('Setujui')),
              ]),
            ]),
          ),
      ];

  // ---------------------------------------------------------------- costs --
  List<Widget> _costs() {
    final c = costs;
    if (c == null) return const [NvEmpty(title: 'Memuat biaya…')];
    return [
      NvSection('biaya · ${c.month}'),
      NvPanel(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${formatCents(c.total.cents)} · ${formatTokens(c.total.tokens)}', style: NV.display(size: 26)),
          const SizedBox(height: 6),
          if (c.total.pct != null) _Meter(pct: c.total.pct!, level: c.total.level) else Text('tanpa batas anggaran', style: TextStyle(fontSize: 12, color: NV.muted)),
        ]),
      ),
      for (final row in c.byAgent)
        NvPanel(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(row.name, style: const TextStyle(fontWeight: FontWeight.w600))),
              Text('${formatCents(row.cents)} · ${formatTokens(row.tokens)}', style: NV.code(size: 11, color: NV.muted)),
            ]),
            if (row.pct != null) ...[const SizedBox(height: 6), _Meter(pct: row.pct!, level: row.pct! >= 100 ? 'exceeded' : 'ok')],
          ]),
        ),
    ];
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.pct, required this.level});
  final double pct;
  final String level;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0, 1).toDouble(),
              minHeight: 6,
              backgroundColor: NV.border,
              color: level == 'ok' ? NV.text : NV.red,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('${pct.toStringAsFixed(pct.truncateToDouble() == pct ? 0 : 1)}%', style: NV.monoLabel(size: 10)),
      ]);
}

class _TicketSheet extends StatefulWidget {
  const _TicketSheet({required this.client, required this.ticket, required this.snap, required this.onChanged});
  final CompanyClient client;
  final CompanyTicket ticket;
  final CompanySnapshot snap;
  final Future<void> Function() onChanged;
  @override
  State<_TicketSheet> createState() => _TicketSheetState();
}

class _TicketSheetState extends State<_TicketSheet> {
  TicketDetail? d;
  final comment = TextEditingController();
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final x = await widget.client.ticket(widget.ticket.id);
      if (mounted) setState(() => d = x);
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> _act(Future<void> Function() fn) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await fn();
      await _load();
      await widget.onChanged();
    } catch (e) {
      if (mounted) toast(context, '$e'.replaceFirst(RegExp(r'^[A-Za-z]*Error[^:]*:\s*'), ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = d?.ticket ?? widget.ticket;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(key: ValueKey('company-ticket-sheet-${t.key}'), crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          NvSheetTitle(kicker: '${t.key} · ${ticketStatusLabel[t.status] ?? t.status}', title: t.title),
          if (t.description.isNotEmpty) Text(t.description, style: TextStyle(fontSize: 13, height: 1.4, color: NV.muted)),
          if (d != null && d!.ancestry.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Kenapa: ${d!.ancestry.join(' → ')}', style: TextStyle(fontSize: 12, color: NV.faint)),
          ],
          const SizedBox(height: 10),
          DropdownButton<int?>(
            isExpanded: true,
            value: widget.snap.agents.any((a) => a.id == t.assigneeId) ? t.assigneeId : null,
            hint: const Text('Penanggung jawab'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Tanpa penanggung jawab')),
              for (final a in widget.snap.agents) DropdownMenuItem<int?>(value: a.id, child: Text(a.name)),
            ],
            onChanged: busy || t.locked ? null : (v) => _act(() => widget.client.assign(t.id, v)),
          ),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final to in ticketTransitions[t.status] ?? const <String>[])
              ActionChip(
                key: ValueKey('company-move-$to'),
                label: Text(to == 'todo' && (t.status == 'done' || t.status == 'cancelled') ? 'Buka lagi' : '→ ${ticketStatusLabel[to] ?? to}'),
                onPressed: busy ? null : () => _act(() => widget.client.move(t.id, to)),
              ),
          ]),
          const SizedBox(height: 12),
          for (final c in d?.comments ?? const <TicketComment>[])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '${c.author}: ', style: TextStyle(fontWeight: FontWeight.w600, color: c.fromUser ? NV.redInk : NV.text)),
                TextSpan(text: c.body, style: TextStyle(color: NV.muted)),
              ])),
            ),
          Row(children: [
            Expanded(child: TextField(key: const ValueKey('company-comment'), controller: comment, decoration: const InputDecoration(hintText: 'Tulis komentar…'))),
            IconButton(
              tooltip: 'Kirim',
              icon: const Icon(CupertinoIcons.paperplane),
              onPressed: busy
                  ? null
                  : () {
                      final text = comment.text.trim();
                      if (text.isEmpty) return;
                      comment.clear();
                      _act(() => widget.client.comment(t.id, text));
                    },
            ),
          ]),
        ]),
      ),
    );
  }
}
