// The PC's Kanban board (Neovarch core Kanban): read the lanes, move a card,
// comment, add a task. Agents on the PC pick up ready tasks themselves.
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/neovarch_mobile_theme.dart';
import '../../ui/widgets/common.dart';
import '../home_widget.dart' show remoteLaunchAction;
import '../remote_controller.dart';
import '../remote_gateway.dart';
import 'nv_widgets.dart';

const laneLabels = {
  'triage': 'Triase',
  'todo': 'Akan dikerjakan',
  'scheduled': 'Terjadwal',
  'ready': 'Siap',
  'running': 'Jalan',
  'blocked': 'Terhambat',
  'review': 'Ditinjau',
  'done': 'Selesai',
  'archived': 'Arsip',
};

/// Manual moves the Kanban workflow allows.
const laneMoves = {
  'triage': ['todo', 'ready'],
  'todo': ['triage', 'ready'],
  'scheduled': ['triage', 'todo', 'ready'],
  'ready': ['todo', 'blocked', 'review', 'done'],
  'running': ['ready', 'blocked', 'review', 'done'],
  'blocked': ['todo', 'ready', 'done'],
  'review': ['todo', 'ready', 'done'],
  'done': ['todo', 'ready'],
};

String laneLabel(String s) => laneLabels[s] ?? s;

class RemoteTasksScreen extends ConsumerStatefulWidget {
  const RemoteTasksScreen({super.key});
  @override
  ConsumerState<RemoteTasksScreen> createState() => _RemoteTasksScreenState();
}

class _RemoteTasksScreenState extends ConsumerState<RemoteTasksScreen> {
  String? lane;

  @override
  void initState() {
    super.initState();
    remoteLaunchAction.addListener(_onLaunchAction);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onLaunchAction());
  }

  @override
  void dispose() {
    remoteLaunchAction.removeListener(_onLaunchAction);
    super.dispose();
  }

  /// Home-screen widget "Tugas baru": open the sheet once the board is in.
  bool _awaitLaunch = false;
  void _onLaunchAction() {
    if (!mounted || remoteLaunchAction.value != 'newtask') return;
    final r = ref.read(remoteProvider);
    final b = r.board;
    if (b == null || !r.connected) {
      if (_awaitLaunch) return;
      _awaitLaunch = true;
      void later() {
        if (mounted && (r.board == null || !r.connected)) return;
        r.removeListener(later);
        _awaitLaunch = false;
        _onLaunchAction();
      }
      r.addListener(later);
      return;
    }
    remoteLaunchAction.value = null;
    _newTask(context, b);
  }

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(remoteProvider);
    final b = r.board;
    final lanes = b?.lanes.where((l) => l.name != 'archived').toList() ?? const <KanbanLane>[];
    final cur = lanes.where((l) => l.name == lane).firstOrNull ??
        lanes.where((l) => l.name == 'running' && l.cards.isNotEmpty).firstOrNull ??
        lanes.where((l) => l.cards.isNotEmpty).firstOrNull ??
        lanes.firstOrNull;
    final total = lanes.fold<int>(0, (n, l) => n + l.cards.length);
    return Scaffold(
      body: Column(children: [
        NvHeader(
          kicker: 'kanban · ${r.desktop?.name ?? 'pc'}',
          title: 'Tugas',
          status: Text(b == null ? 'papan agen di PC' : '$total tugas · ${lanes.length} kolom',
              style: NV.monoLabel(size: 10).copyWith(letterSpacing: 0.4)),
          actions: [
            NvIconButton(tooltip: 'Segarkan', icon: CupertinoIcons.arrow_clockwise, onPressed: r.connected ? r.refreshBoard : null),
            NvIconButton(tooltip: 'Tugas baru', icon: CupertinoIcons.add, accent: true, onPressed: r.connected && b != null ? () => _newTask(context, b) : null),
          ],
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: r.refreshBoard,
            child: b == null
                ? ListView(children: [
                    if (r.boardLoading)
                      const Padding(padding: EdgeInsets.all(40), child: CenterLoader(label: 'memuat papan…'))
                    else
                      NvEmpty(
                        art: 'assets/art/feat-automation.webp',
                        kicker: r.connected ? 'papan' : 'offline',
                        title: r.connected ? 'Papan belum bisa dibaca' : 'Belum terhubung ke PC',
                        body: r.boardError ?? 'Papan Kanban agen di PC muncul di sini: tugas yang siap, sedang jalan, dan menunggu review.',
                      ),
                  ])
                : Column(children: [
                    SizedBox(
                      height: 78,
                      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(16, 4, 16, 10), children: [
                        for (final l in lanes)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _LaneTile(lane: l, selected: cur?.name == l.name, onTap: () => setState(() => lane = l.name)),
                          ),
                      ]),
                    ),
                    if (r.boardError != null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: NvNotice(r.boardError!)),
                    NvSection(laneLabel(cur?.name ?? ''), count: cur?.cards.length, padding: const EdgeInsets.fromLTRB(20, 6, 20, 10)),
                    Expanded(
                      child: cur == null || cur.cards.isEmpty
                          ? ListView(children: [
                              NvEmpty(title: 'Kolom ${laneLabel(cur?.name ?? '')} kosong', body: 'Tidak ada tugas di kolom ini sekarang.'),
                            ])
                          : ListView(padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.paddingOf(context).bottom), children: [
                              for (final t in cur.cards) _TaskCard(task: t, onTap: () => _detail(context, t)),
                            ]),
                    ),
                  ]),
          ),
        ),
      ]),
    );
  }

  void _detail(BuildContext context, KanbanCard t) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _TaskSheet(task: t),
      );

  void _newTask(BuildContext context, KanbanSnapshot b) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _NewTaskSheet(assignees: b.assignees),
      );
}

class _LaneTile extends StatelessWidget {
  const _LaneTile({required this.lane, required this.selected, required this.onTap});
  final KanbanLane lane;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: selected ? NV.redWash : NV.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NV.rCtl),
          side: BorderSide(color: selected ? NV.red : NV.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 84),
            padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(laneLabel(lane.name).toUpperCase(), style: NV.monoLabel(size: 9.5, color: selected ? NV.redInk : NV.muted)),
              const SizedBox(height: 2),
              Text('${lane.cards.length}', style: NV.display(size: 28, color: lane.cards.isEmpty && !selected ? NV.faint : NV.text)),
            ]),
          ),
        ),
      );
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.onTap});
  final KanbanCard task;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => NvPanel(
        margin: const EdgeInsets.only(bottom: 10),
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(task.id.toUpperCase(), style: NV.monoLabel(size: 9.5, color: NV.faint)),
            const Spacer(),
            if (task.priority > 0) NvPill('P${task.priority}', color: NV.red),
          ]),
          const SizedBox(height: 8),
          Text(task.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.3, color: NV.text)),
          if ((task.summary ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(task.summary!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, height: 1.45, color: NV.muted)),
          ],
          const SizedBox(height: 12),
          Row(children: [
            _Avatar(task.assignee),
            const SizedBox(width: 8),
            Expanded(
              child: Text(task.assignee ?? 'belum ditugaskan',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: NV.monoLabel(size: 10.5, color: NV.muted).copyWith(letterSpacing: 0.3)),
            ),
            if (task.comments > 0) ...[
              Icon(CupertinoIcons.bubble_left, size: 13, color: NV.muted),
              const SizedBox(width: 4),
              Text('${task.comments}', style: NV.monoLabel(size: 10.5)),
            ],
          ]),
        ]),
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.name);
  final String? name;
  @override
  Widget build(BuildContext context) => Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: name == null ? NV.raised : NV.redWash,
          border: Border.all(color: name == null ? NV.border : NV.darkRed),
        ),
        child: name == null
            ? Icon(CupertinoIcons.person, size: 13, color: NV.faint)
            : Text(initials(name!).substring(0, 1), style: TextStyle(fontFamily: NV.sans, fontWeight: FontWeight.w600, fontSize: 11, color: NV.text)),
      );
}

class _TaskSheet extends ConsumerStatefulWidget {
  const _TaskSheet({required this.task});
  final KanbanCard task;
  @override
  ConsumerState<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends ConsumerState<_TaskSheet> {
  final _comment = TextEditingController();
  bool busy = false;

  Future<void> _run(Future<String?> Function() f, String ok) async {
    setState(() => busy = true);
    final err = await f();
    if (!mounted) return;
    setState(() => busy = false);
    toast(context, err ?? ok);
    if (err == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final r = ref.read(remoteProvider);
    final moves = laneMoves[t.status] ?? const <String>[];
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          NvSheetTitle(kicker: '${t.id} · ${laneLabel(t.status)}', title: t.title),
          const SizedBox(height: 12),
          NvKv('Penanggung', t.assignee ?? '—'),
          if (t.priority > 0) NvKv('Prioritas', 'P${t.priority}', mono: true),
          if ((t.body ?? '').isNotEmpty) ...[const SizedBox(height: 8), Text(t.body!, style: TextStyle(fontSize: 14, height: 1.5, color: NV.text))],
          if ((t.summary ?? '').isNotEmpty) ...[
            const NvSection('ringkasan terakhir', padding: EdgeInsets.fromLTRB(0, 16, 0, 8)),
            Text(t.summary!, style: TextStyle(fontSize: 13, height: 1.5, color: NV.muted)),
          ],
          if (moves.isNotEmpty) ...[
            const NvSection('pindahkan ke', padding: EdgeInsets.fromLTRB(0, 18, 0, 10)),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final m in moves)
                // Lane moves are secondary; the one red action on the sheet is
                // "Kirim komentar".
                OutlinedButton(
                  onPressed: busy ? null : () => _run(() => r.moveTask(t.id, m), 'Dipindah ke ${laneLabel(m)}'),
                  child: Text(laneLabel(m)),
                ),
            ]),
          ],
          const NvSection('komentar / arahan', padding: EdgeInsets.fromLTRB(0, 18, 0, 10)),
          TextField(controller: _comment, minLines: 1, maxLines: 4, decoration: const InputDecoration(hintText: 'Tulis arahan untuk agen…')),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: busy
                ? null
                : () {
                    final text = _comment.text.trim();
                    if (text.isEmpty) return;
                    _run(() => r.commentTask(t.id, text), 'Komentar terkirim');
                  },
            child: const Text('Kirim komentar'),
          ),
        ]),
      ),
    );
  }
}

class _NewTaskSheet extends ConsumerStatefulWidget {
  const _NewTaskSheet({required this.assignees});
  final List<String> assignees;
  @override
  ConsumerState<_NewTaskSheet> createState() => _NewTaskSheetState();
}

class _NewTaskSheetState extends ConsumerState<_NewTaskSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String? assignee;
  bool busy = false;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          NvSheetTitle(kicker: 'kanban · tugas baru', title: 'Tugas baru di PC'),
          const SizedBox(height: 16),
          TextField(controller: _title, autofocus: true, decoration: const InputDecoration(labelText: 'Judul')),
          const SizedBox(height: 10),
          TextField(controller: _body, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Uraian (opsional)')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            initialValue: assignee,
            isExpanded: true, // long names / large text: ellipsis instead of overflow
            dropdownColor: NV.raised,
            borderRadius: BorderRadius.circular(NV.rCtl),
            decoration: const InputDecoration(labelText: 'Penanggung'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Belum ditugaskan (triase)', overflow: TextOverflow.ellipsis)),
              for (final a in widget.assignees) DropdownMenuItem(value: a, child: Text(a, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => assignee = v),
          ),
          const SizedBox(height: 6),
          Text('Tugas dengan penanggung dikerjakan agen di PC saat siap.', style: TextStyle(fontSize: 12.5, color: NV.muted)),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (_title.text.trim().isEmpty) return;
                    setState(() => busy = true);
                    final err = await ref.read(remoteProvider).createTask(title: _title.text.trim(), body: _body.text.trim(), assignee: assignee);
                    if (!context.mounted) return;
                    setState(() => busy = false);
                    toast(context, err ?? 'Tugas dibuat di PC');
                    if (err == null) Navigator.pop(context);
                  },
            child: Text(busy ? 'Mengirim…' : 'Buat tugas'),
          ),
        ]),
      );
}
