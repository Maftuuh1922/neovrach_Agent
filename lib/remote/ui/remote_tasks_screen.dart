// The PC's Kanban board (Hermes kanban plugin): read the lanes, move a card,
// comment, add a task. Agents on the PC pick up ready tasks themselves.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../ui/widgets/common.dart';
import '../remote_controller.dart';
import '../remote_gateway.dart';

const laneLabels = {
  'triage': 'Triase',
  'todo': 'Todo',
  'scheduled': 'Terjadwal',
  'ready': 'Siap',
  'running': 'Jalan',
  'blocked': 'Terhambat',
  'review': 'Review',
  'done': 'Selesai',
  'archived': 'Arsip',
};

/// Manual moves the default Hermes workflow allows (kanban_workflow.py).
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
  Widget build(BuildContext context) {
    final r = ref.watch(remoteProvider);
    final b = r.board;
    final lanes = b?.lanes.where((l) => l.name != 'archived').toList() ?? const <KanbanLane>[];
    final cur = lanes.where((l) => l.name == lane).firstOrNull ??
        lanes.where((l) => l.name == 'running' && l.cards.isNotEmpty).firstOrNull ??
        lanes.where((l) => l.cards.isNotEmpty).firstOrNull ??
        lanes.firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text('Tugas di PC', style: context.tt.titleMedium),
        actions: [IconButton(tooltip: 'Segarkan', icon: const Icon(Icons.refresh), onPressed: r.connected ? r.refreshBoard : null)],
      ),
      floatingActionButton: r.connected && b != null
          ? Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
              child: FloatingActionButton.extended(
                onPressed: () => _newTask(context, b),
                icon: const Icon(Icons.add),
                label: const Text('Tugas'),
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: r.refreshBoard,
        child: b == null
            ? ListView(children: [
                if (r.boardLoading)
                  const Padding(padding: EdgeInsets.all(40), child: CenterLoader(label: 'memuat papan…'))
                else
                  EmptyState(
                    icon: Icons.view_kanban_outlined,
                    title: r.connected ? 'Papan belum bisa dibaca' : 'Belum terhubung ke PC',
                    body: r.boardError ?? 'Papan Kanban agen di PC muncul di sini.',
                  ),
              ])
            : Column(children: [
                SizedBox(
                  height: 52,
                  child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
                    for (final l in lanes)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text('${laneLabel(l.name)} ${l.cards.length}'),
                          selected: cur?.name == l.name,
                          onSelected: (_) => setState(() => lane = l.name),
                        ),
                      ),
                  ]),
                ),
                if (r.boardError != null) ErrorBanner(r.boardError!, dense: true),
                Expanded(
                  child: cur == null || cur.cards.isEmpty
                      ? ListView(children: [EmptyState(icon: Icons.inbox_outlined, title: 'Kolom ${laneLabel(cur?.name ?? '')} kosong')])
                      : ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 96), children: [
                          for (final t in cur.cards) _TaskCard(task: t, onTap: () => _detail(context, t)),
                        ]),
                ),
              ]),
      ),
    );
  }

  void _detail(BuildContext context, KanbanCard t) => showPaperSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _TaskSheet(task: t),
      );

  void _newTask(BuildContext context, KanbanSnapshot b) => showPaperSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _NewTaskSheet(assignees: b.assignees),
      );
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.onTap});
  final KanbanCard task;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => PaperScope(
        child: Builder(
          builder: (context) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    MetaLabel(task.id, size: 10),
                    const Spacer(),
                    if (task.priority > 0) StatusPill('P${task.priority}', mono: true, color: context.cs.primary),
                  ]),
                  const SizedBox(height: 4),
                  Text(task.title, style: context.tt.titleSmall),
                  if ((task.summary ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(task.summary!, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall),
                  ],
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(Icons.person_outline, size: 14, color: context.hc.mutedForeground),
                    const SizedBox(width: 4),
                    Text(task.assignee ?? 'belum ditugaskan', style: context.tt.bodySmall),
                    if (task.comments > 0) ...[
                      const SizedBox(width: 10),
                      Icon(Icons.mode_comment_outlined, size: 13, color: context.hc.mutedForeground),
                      const SizedBox(width: 3),
                      Text('${task.comments}', style: context.tt.bodySmall),
                    ],
                  ]),
                ]),
              ),
            ),
          ),
        ),
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
      padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          MetaLabel('${t.id} · ${laneLabel(t.status)}'),
          const SizedBox(height: 6),
          Text(t.title, style: context.tt.titleLarge),
          const SizedBox(height: 8),
          KeyValue('Penanggung', t.assignee ?? '—'),
          if ((t.body ?? '').isNotEmpty) ...[const SizedBox(height: 8), Text(t.body!, style: context.tt.bodyMedium)],
          if ((t.summary ?? '').isNotEmpty) ...[
            const SectionLabel('Ringkasan terakhir', padding: EdgeInsets.fromLTRB(0, 14, 0, 6)),
            Text(t.summary!, style: context.tt.bodySmall),
          ],
          if (moves.isNotEmpty) ...[
            const SectionLabel('Pindahkan ke', padding: EdgeInsets.fromLTRB(0, 16, 0, 6)),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final m in moves)
                m == 'done' || m == 'ready'
                    ? FilledButton.tonal(
                        onPressed: busy ? null : () => _run(() => r.moveTask(t.id, m), 'Dipindah ke ${laneLabel(m)}'),
                        child: Text(laneLabel(m)),
                      )
                    : OutlinedButton(
                        onPressed: busy ? null : () => _run(() => r.moveTask(t.id, m), 'Dipindah ke ${laneLabel(m)}'),
                        child: Text(laneLabel(m)),
                      ),
            ]),
          ],
          const SectionLabel('Komentar / arahan', padding: EdgeInsets.fromLTRB(0, 16, 0, 6)),
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
        padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('Tugas baru di PC', style: context.tt.titleMedium),
          const SizedBox(height: 12),
          TextField(controller: _title, autofocus: true, decoration: const InputDecoration(labelText: 'Judul')),
          const SizedBox(height: 8),
          TextField(controller: _body, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Uraian (opsional)')),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            initialValue: assignee,
            decoration: const InputDecoration(labelText: 'Penanggung'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Belum ditugaskan (triase)')),
              for (final a in widget.assignees) DropdownMenuItem(value: a, child: Text(a)),
            ],
            onChanged: (v) => setState(() => assignee = v),
          ),
          const SizedBox(height: 6),
          Text('Tugas dengan penanggung dikerjakan agen di PC saat siap.', style: context.tt.bodySmall),
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
