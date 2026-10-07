// Task detail (TaskPanel.tsx): fields, body, run history, worker log — and
// in Mandiri mode the review actions (approve, send back, run, delete).
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/markdown_view.dart';
import '../widgets/preview_sheet.dart';
import 'peek_sheet.dart';

Future<void> showTaskDetail(BuildContext context, String taskId) => showPaperSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.96,
        minChildSize: 0.4,
        builder: (ctx, scroll) => TaskDetailSheet(taskId: taskId, scroll: scroll),
      ),
    );

class TaskDetailSheet extends ConsumerStatefulWidget {
  const TaskDetailSheet({super.key, required this.taskId, required this.scroll});
  final String taskId;
  final ScrollController scroll;
  @override
  ConsumerState<TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends ConsumerState<TaskDetailSheet> {
  List<RunInfo> runs = [];
  String log = '';
  bool loading = true;
  String? err;
  String? note;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ref.read(officeProvider).backend.get('/api/hermes/tasks/${Uri.encodeComponent(widget.taskId)}');
    if (!mounted) return;
    setState(() {
      loading = false;
      if (!res.ok) {
        err = res.error ?? 'gagal memuat detail tugas';
      } else {
        err = null;
        runs = res.list('runs').map(RunInfo.fromJson).toList();
        log = '${res.map['log'] ?? ''}';
      }
    });
  }

  Future<void> _act(Map<String, dynamic> body, String ok) async {
    final e = await ref.read(officeProvider).taskAction(widget.taskId, body);
    if (!mounted) return;
    setState(() => note = e ?? ok);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final office = ref.watch(officeProvider);
    final task = office.task(widget.taskId);
    final agent = office.agent(task?.assignee);
    final local = office.backend.supportsMove;

    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 28), children: [
      Text('Detail tugas', style: context.tt.labelSmall),
      const SizedBox(height: 6),
      if (task == null) Text('Tugas ${widget.taskId} tidak ada di board aktif.', style: context.tt.bodySmall),
      if (task != null) ...[
        Text(task.title, style: context.tt.titleLarge?.copyWith(fontSize: 19)),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          StatusPill(statusLabel[task.status] ?? task.status, color: statusColor(context, task.status)),
          StatusPill('P${task.priority}'),
          if (task.origin?.label != null) StatusPill('asal: ${task.origin!.label}', color: context.hc.info),
        ]),
        const SizedBox(height: 12),
        KeyValue('penanggung', '${task.assignee ?? '—'}${agent != null ? ' (${agent.role})' : ''}'),
        if (task.updatedAt != null) KeyValue('diubah', relTime(task.updatedAt!)),
        KeyValue('id', task.id, mono: true),
        if (local) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (task.status == 'review') ...[
              FilledButton.icon(
                onPressed: () => _act({'action': 'move', 'status': 'done'}, 'Disetujui → SELESAI'),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Setujui'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final m = await promptText(context, title: 'Minta revisi', hint: 'apa yang perlu diperbaiki?', maxLines: 3, confirm: 'Kirim');
                  if (m == null || m.trim().isEmpty) return;
                  await _act({'action': 'steer', 'message': 'Revisi: ${m.trim()}'}, 'Catatan revisi ditambahkan');
                  await _act({'action': 'move', 'status': 'ready'}, 'Dikembalikan ke antrean untuk revisi');
                },
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Minta revisi'),
              ),
            ],
            if (task.status == 'running')
              OutlinedButton.icon(
                onPressed: () => showPeekSheet(context, agentName: task.assignee),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Intip layar'),
              ),
            if (task.status != 'running' && task.status != 'done' && task.assignee != null)
              OutlinedButton.icon(
                onPressed: () => _act({'action': 'run'}, 'Worker mulai mengerjakan'),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Jalankan sekarang'),
              ),
            PopupMenuButton<String>(
              tooltip: 'Pindahkan',
              onSelected: (s) => _act({'action': 'move', 'status': s}, 'Status → ${statusLabel[s]}'),
              itemBuilder: (_) => [
                for (final s in ['todo', 'ready', 'review', 'blocked', 'done'])
                  if (s != task.status) PopupMenuItem(value: s, child: Text(statusLabel[s]!)),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.swap_horiz, size: 18), SizedBox(width: 6), Text('Pindahkan')]),
              ),
            ),
            IconButton(
              tooltip: 'Hapus tugas',
              color: context.hc.destructive,
              onPressed: () async {
                if (await confirmDialog(context, title: 'Hapus tugas?', body: '"${task.title}" dihapus dari papan.', confirm: 'Hapus', destructive: true)) {
                  await ref.read(officeProvider).taskAction(task.id, {'action': 'delete'});
                  if (context.mounted) Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.delete_outline),
            ),
          ]),
        ],
        if (note != null) Padding(padding: const EdgeInsets.only(top: 10), child: NoteBanner(note!, ok: true)),
        if (task.body != null && task.body!.trim().isNotEmpty) ...[
          const SectionLabel('Uraian', padding: EdgeInsets.fromLTRB(0, 18, 0, 6)),
          MarkdownView(task.body!),
        ],
        if (task.output != null && task.output!.trim().isNotEmpty) ...[
          SectionLabel('Hasil worker',
              padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
              trailing: TextButton(
                onPressed: () => showPreview(context, TextPreview('Hasil · ${task.title}', task.output!, markdown: true)),
                child: const Text('Perbesar'),
              )),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: context.hc.card, borderRadius: BorderRadius.circular(8), border: Border.all(color: context.hc.strokeSoft)),
            child: MarkdownView(task.output!, scale: 0.95),
          ),
        ],
        SectionLabel('Riwayat run (${runs.length})', padding: const EdgeInsets.fromLTRB(0, 18, 0, 6)),
        if (loading) const Padding(padding: EdgeInsets.all(8), child: HermesLoader(size: 18)),
        if (err != null) ErrorBanner(err!, onRetry: _load, dense: true),
        if (!loading && runs.isEmpty) Text('belum ada run', style: context.tt.bodySmall),
        for (final r in runs.reversed) RunTile(run: r),
        Collapsible(label: 'Log worker', count: log.trim().isEmpty ? null : log.trim().split('\n').length, child: LogView(log, maxHeight: 320, empty: 'belum ada log')),
      ],
    ]);
  }
}
