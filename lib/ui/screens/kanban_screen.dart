// Papan — Kanban with the four office columns (TODO / JALAN / REVIEW /
// SELESAI, as board.ts groups them). Phones swipe between columns with
// snapping; wide screens show all four. Pull to refresh, FAB "+ Tugas".
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import 'new_task_sheet.dart';
import 'task_detail_sheet.dart';

class KanbanScreen extends ConsumerStatefulWidget {
  const KanbanScreen({super.key});
  @override
  ConsumerState<KanbanScreen> createState() => _KanbanScreenState();
}

class _KanbanScreenState extends ConsumerState<KanbanScreen> {
  final _page = PageController(viewportFraction: 0.88);
  int _col = 0;
  String? _assignee;
  Task? _dragging;
  int? _hoverCol;

  static const _colStatus = ['todo', 'running', 'review', 'done'];

  Future<void> _drop(Task t, int col) async {
    setState(() {
      _dragging = null;
      _hoverCol = null;
    });
    if (columnOf(t.status) == col) return;
    final office = ref.read(officeProvider);
    if (!office.backend.supportsMove) {
      toast(context, 'Memindah kartu hanya di mode Mandiri');
      return;
    }
    HapticFeedback.mediumImpact();
    final err = await office.taskAction(t.id, {'action': 'move', 'status': _colStatus[col]});
    if (!mounted) return;
    toast(context, err ?? '"${t.title}" → ${boardColumns[col]}');
  }

  Widget _target(int col, Widget child) => DragTarget<Task>(
        onWillAcceptWithDetails: (d) {
          setState(() => _hoverCol = col);
          return true;
        },
        onLeave: (_) => setState(() => _hoverCol = _hoverCol == col ? null : _hoverCol),
        onAcceptWithDetails: (d) => _drop(d.data, col),
        builder: (context, cand, _) => AnimatedContainer(
          duration: motionFast,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(context.hc.corner + 2),
            border: Border.all(color: cand.isNotEmpty ? context.cs.primary : Colors.transparent, width: 1.5),
          ),
          child: child,
        ),
      );

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  List<List<Task>> _columns(List<Task> tasks) {
    final cols = List.generate(4, (_) => <Task>[]);
    final sorted = [...tasks]
      ..sort((a, b) {
        // board.ts: priority desc, then newest first
        final p = b.priority.compareTo(a.priority);
        if (p != 0) return p;
        return (b.updatedAt ?? '').compareTo(a.updatedAt ?? '');
      });
    for (final t in sorted) {
      if (_assignee != null && t.assignee != _assignee) continue;
      cols[columnOf(t.status)].add(t);
    }
    return cols;
  }

  Color _colColor(BuildContext context, int i) => switch (i) {
        1 => context.hc.success,
        2 => context.hc.info,
        3 => context.hc.mutedForeground,
        _ => context.hc.warning,
      };

  @override
  Widget build(BuildContext context) {
    final office = ref.watch(officeProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final cols = _columns(office.tasks);
    final names = office.tasks.map((t) => t.assignee).whereType<String>().toSet().toList()..sort();

    Widget column(int i) {
      final items = cols[i];
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: wide ? 6 : 5, vertical: 8),
        child: Container(
          decoration: BoxDecoration(color: context.hc.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: context.hc.strokeSoft)),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
              child: Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: _colColor(context, i), shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(boardColumns[i], style: context.tt.labelSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1.2, color: context.cs.onSurface)),
                const SizedBox(width: 8),
                StatusPill('${items.length}'),
              ]),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: office.refresh,
                child: office.loading && office.tasks.isEmpty
                    ? ListView(padding: const EdgeInsets.all(10), children: const [Skeleton(height: 74), SizedBox(height: 8), Skeleton(height: 74)])
                    : items.isEmpty
                        ? ListView(children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Center(child: Text('kosong', style: context.tt.bodySmall)),
                            ),
                          ])
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(10, 2, 10, 90),
                            itemCount: items.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (_, k) => EntranceFade(
                              key: ValueKey('k${items[k].id}${items[k].status}'),
                              delay: Duration(milliseconds: 30 * (k < 8 ? k : 8)),
                              child: TaskCard(
                                task: items[k],
                                onDragStart: () => setState(() => _dragging = items[k]),
                                onDragEnd: () => setState(() {
                                  _dragging = null;
                                  _hoverCol = null;
                                }),
                              ),
                            ),
                          ),
              ),
            ),
          ]),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Papan', style: context.tt.titleMedium),
        actions: [
          PopupMenuButton<String?>(
            tooltip: 'Saring penanggung',
            icon: Icon(_assignee == null ? Icons.filter_list : Icons.filter_list_alt, color: _assignee == null ? null : context.cs.primary),
            onSelected: (v) => setState(() => _assignee = v == '' ? null : v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: '', child: Text('Semua penanggung')),
              for (final n in names) PopupMenuItem(value: n, child: Text(n)),
            ],
          ),
          IconButton(tooltip: 'Segarkan', onPressed: office.refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'kanban-fab',
        onPressed: () => showNewTaskSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Tugas'),
      ),
      body: Column(children: [
        if (office.error != null) ErrorBanner(office.error!, onRetry: office.refresh),
        if (!wide)
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              children: [
                for (var i = 0; i < 4; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('${boardColumns[i]}  ${cols[i].length}'),
                      selected: _col == i,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => _page.animateToPage(i, duration: const Duration(milliseconds: 220), curve: Curves.easeOut),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: wide
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(children: [for (var i = 0; i < 4; i++) Expanded(child: _target(i, column(i)))]),
                )
              : PageView.builder(
                  controller: _page,
                  padEnds: false,
                  itemCount: 4,
                  onPageChanged: (i) => setState(() => _col = i),
                  itemBuilder: (_, i) => Padding(padding: EdgeInsets.only(left: i == 0 ? 8 : 0), child: column(i)),
                ),
        ),
        // Phone: while a card is held, a drop bar slides up with all four columns.
        if (!wide)
          AnimatedSize(
            duration: motionBase,
            curve: motionCurve,
            child: _dragging == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: EdgeInsets.fromLTRB(10, 4, 10, 10 + MediaQuery.paddingOf(context).bottom),
                    child: Row(children: [
                      for (var i = 0; i < 4; i++)
                        Expanded(
                          child: _target(
                            i,
                            AnimatedContainer(
                              duration: motionFast,
                              height: 56,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _hoverCol == i ? _colColor(context, i).withValues(alpha: 0.25) : context.hc.card,
                                borderRadius: BorderRadius.circular(context.hc.corner + 2),
                                border: Border.all(color: _colColor(context, i).withValues(alpha: 0.7)),
                              ),
                              child: Text(boardColumns[i], style: monoStyle(context, size: 11, weight: FontWeight.w600, color: context.cs.onSurface)),
                            ),
                          ),
                        ),
                    ]),
                  ),
          ),
      ]),
    );
  }
}

class TaskCard extends ConsumerWidget {
  const TaskCard({super.key, required this.task, this.onDragStart, this.onDragEnd});
  final Task task;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // bone paper card on the red base (no-op in other themes)
    final card = PaperScope(child: Builder(builder: _card));
    if (onDragStart == null) return card;
    return LayoutBuilder(
      builder: (context, c) => LongPressDraggable<Task>(
        data: task,
        hapticFeedbackOnStart: true,
        onDragStarted: onDragStart,
        onDragEnd: (_) => onDragEnd?.call(),
        onDraggableCanceled: (_, _) => onDragEnd?.call(),
        feedback: SizedBox(
          width: c.maxWidth,
          child: Transform.rotate(
            angle: -0.03,
            child: Material(
              elevation: 0,
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: Opacity(opacity: 0.95, child: card),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: card),
        child: card,
      ),
    );
  }

  Widget _card(BuildContext context) {
    final prioColor = switch (task.priority) {
      0 => context.hc.destructive,
      1 => context.hc.warning,
      _ => context.hc.mutedForeground,
    };
    return Material(
      color: context.cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: context.hc.strokeSoft)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showTaskDetail(context, task.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(task.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, height: 1.35)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StatusPill('P${task.priority}', color: prioColor, mono: true),
              if (task.status == 'blocked') StatusPill('terhambat', color: context.hc.destructive),
              if (task.status == 'ready') StatusPill('siap', color: context.hc.info),
              if (task.status == 'running') StatusPill('berjalan', color: context.hc.success),
              // Where the task came from: without it the board is a flat pile.
              if (task.origin != null && task.origin!.kind != 'manual')
                StatusPill(switch (task.origin!.kind) { 'meeting' => 'rapat', 'cron' => 'cron', _ => task.origin!.kind },
                    color: task.origin!.kind == 'meeting' ? context.hc.warning : context.hc.info),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              if (task.assignee != null) ...[
                AgentAvatar(task.assignee!, size: 20),
                const SizedBox(width: 6),
                Text(task.assignee!, style: context.tt.bodySmall?.copyWith(fontSize: 12)),
              ] else
                Text('tanpa penanggung', style: context.tt.bodySmall),
              const Spacer(),
              Text(task.id, style: monoStyle(context, size: 10, color: context.hc.mutedForeground)),
            ]),
          ]),
        ),
      ),
    );
  }
}
