// Kantor — the isometric office plus a roster strip. Tap an agent or a desk
// to peek at its screen; tap the Kanban wall to open the board.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/office_painter.dart';
import 'new_task_sheet.dart';
import 'peek_sheet.dart';

class OfficeScreen extends ConsumerStatefulWidget {
  const OfficeScreen({super.key, required this.onOpenBoard, required this.onOpenMeetings});
  final VoidCallback onOpenBoard;
  final VoidCallback onOpenMeetings;
  @override
  ConsumerState<OfficeScreen> createState() => _OfficeScreenState();
}

class _OfficeScreenState extends ConsumerState<OfficeScreen> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(0);
  int? _selectedDesk;
  final _tc = TransformationController();
  Size? _viewSize;

  @override
  void initState() {
    super.initState();
    // ~30 fps is plenty for idle bobbing and keeps phones cool.
    var last = Duration.zero;
    _ticker = createTicker((d) {
      if (d - last >= const Duration(milliseconds: 33)) {
        last = d;
        _time.value = d.inMilliseconds / 1000.0;
      }
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _tc.dispose();
    super.dispose();
  }

  OfficeColors _colors(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hc = context.hc;
    if (hc.brand) return brandOfficeColors(paper: hc.paper != null);
    final wood = dark ? const Color(0xFF3B3328) : const Color(0xFFE7D5BA);
    return OfficeColors(
      floor: Color.lerp(wood, hc.muted, 0.35)!,
      floorLine: Color.lerp(wood, dark ? Colors.black : const Color(0xFF8A7458), 0.22)!,
      wall: Color.lerp(hc.card, dark ? const Color(0xFF2A3440) : const Color(0xFFF4F6F8), 0.6)!,
      wallSide: Color.lerp(hc.card, dark ? const Color(0xFF222B35) : const Color(0xFFE3E8EC), 0.6)!,
      desk: dark ? const Color(0xFFB38E66) : const Color(0xFFD9B48A),
      deskSide: dark ? const Color(0xFF7D6146) : const Color(0xFFB08C66),
      accent: context.cs.primary,
      text: context.cs.onSurface,
      card: hc.popover,
      carpet: Color.lerp(Color.lerp(wood, hc.info, 0.18)!, hc.muted, 0.3)!,
      rug: Color.lerp(wood, context.cs.primary, dark ? 0.22 : 0.16)!,
      ok: hc.success,
      warn: hc.warning,
      bad: hc.destructive,
      info: hc.info,
      muted: hc.mutedForeground,
    );
  }

  void _peekAgent(Agent a) => showPeekSheet(context, agentName: a.name, desk: a.deskIndex);

  @override
  Widget build(BuildContext context) {
    final office = ref.watch(officeProvider);
    final app = ref.watch(appProvider);
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final status = office.loading
        ? 'menghubungkan…'
        : office.online
            ? '${office.agents.length} agent · ${office.running} jalan · ${office.pct}% rilis'
            : 'backend offline';
    final dotColor = office.loading ? context.hc.warning : (office.online ? context.hc.success : context.hc.destructive);

    final canvas = LayoutBuilder(builder: (context, c) {
      // Portrait phones: fill the height and let the floor pan sideways
      // instead of shrinking the whole office to a sliver.
      final vw = c.maxWidth, vh = c.maxHeight;
      final fit = (vh / officeCanvas.height).clamp(0.0, (vw / officeCanvas.width) * 1.9);
      final size = Size(
        (officeCanvas.width * fit).clamp(vw, double.infinity),
        (officeCanvas.height * fit).clamp(vh, double.infinity),
      );
      if (_viewSize != Size(vw, vh)) {
        _viewSize = Size(vw, vh);
        // open slightly left of centre so the Kanban wall is in view
        _tc.value = Matrix4.translationValues(-(size.width - vw) * 0.3, -(size.height - vh) / 2, 0);
      }
      return InteractiveViewer(
        transformationController: _tc,
        constrained: false,
        minScale: (vw / size.width).clamp(0.2, 1.0),
        maxScale: 3.2,
        boundaryMargin: const EdgeInsets.all(40),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final hit = hitTestOffice(d.localPosition, size, office.agents, office.meeting);
            switch (hit) {
              case AgentHit(:final agent):
                _peekAgent(agent);
              case DeskHit(:final desk):
                setState(() => _selectedDesk = desk);
                showPeekSheet(context, desk: desk).then((_) => mounted ? setState(() => _selectedDesk = null) : null);
              case BoardHit():
                widget.onOpenBoard();
              case TableHit():
                widget.onOpenMeetings();
              case null:
                break;
            }
          },
          child: RepaintBoundary(
            child: ValueListenableBuilder<double>(
              valueListenable: _time,
              builder: (context, t, _) => CustomPaint(
                size: size,
                painter: OfficePainter(
                  agents: office.agents,
                  tasks: office.tasks,
                  meeting: office.meeting,
                  colors: _colors(context),
                  t: t,
                  brightness: Theme.of(context).brightness,
                  selectedDesk: _selectedDesk,
                  reduceMotion: reduceMotion(context),
                ),
              ),
            ),
          ),
        ),
      );
    });

    final roster = office.agents.isEmpty
        ? (office.loading
            ? const Padding(padding: EdgeInsets.all(16), child: Skeleton(height: 44))
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                    app.mode == ConnectionMode.server
                        ? 'Belum ada agent — agent muncul di kantor saat punya tugas.'
                        : 'Belum ada agent. Tambahkan di Lainnya → Agent.',
                    style: context.tt.bodySmall),
              ))
        : null;

    Widget agentTile(Agent a, {bool compact = false}) {
      final task = office.task(a.currentTaskId);
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _peekAgent(a),
        child: Container(
          width: compact ? 168 : null,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: compact
              ? BoxDecoration(color: context.hc.card, borderRadius: BorderRadius.circular(8), border: Border.all(color: context.hc.strokeSoft))
              : null,
          child: Row(children: [
            AgentAvatar(a.name, size: 32, status: a.status),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(a.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(task?.title ?? '${agentStatusLabel[a.status] ?? a.status} · ${a.role}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall?.copyWith(fontSize: 11.5)),
              ]),
            ),
          ]),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Text('Kantor', style: context.tt.titleMedium),
          const SizedBox(width: 12),
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Flexible(child: Text(status, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall)),
        ]),
        actions: [
          IconButton(tooltip: 'Segarkan', onPressed: office.refresh, icon: const Icon(Icons.refresh)),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12)),
              onPressed: () => showNewTaskSheet(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Tugas'),
            ),
          ),
        ],
      ),
      body: Column(children: [
        if (office.error != null) ErrorBanner(office.error!, onRetry: office.refresh),
        if (office.meeting?.live == true)
          Material(
            color: context.hc.warning.withValues(alpha: 0.1),
            child: InkWell(
              onTap: widget.onOpenMeetings,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  Icon(Icons.record_voice_over_outlined, size: 18, color: context.hc.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Rapat: ${office.meeting!.topic} · ${office.meeting!.currentSpeaker ?? office.meeting!.phase}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  ),
                  const Icon(Icons.chevron_right, size: 18),
                ]),
              ),
            ),
          ),
        Expanded(
          child: wide
              ? Row(children: [
                  Expanded(child: canvas),
                  Container(
                    width: 300,
                    decoration: BoxDecoration(border: Border(left: BorderSide(color: context.hc.strokeSoft))),
                    child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                      const SectionLabel('Agent di kantor'),
                      ?roster,
                      for (final a in office.agents) agentTile(a),
                      const SectionLabel('Legenda'),
                      const _Legend(),
                    ]),
                  ),
                ])
              : Column(children: [
                  Expanded(child: canvas),
                  Container(
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: context.hc.strokeSoft))),
                    height: 72,
                    child: roster ??
                        ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          itemCount: office.agents.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (_, i) => agentTile(office.agents[i], compact: true),
                        ),
                  ),
                ]),
        ),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) {
    final items = [('working', 'bekerja di meja'), ('review', 'review'), ('meeting', 'rapat di meja bundar'), ('blocked', 'terhambat — butuh bantuan'), ('idle', 'santai di lounge')];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: [
        for (final (s, l) in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: statusColor(context, s), shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Text(l, style: context.tt.bodySmall),
            ]),
          ),
      ]),
    );
  }
}
