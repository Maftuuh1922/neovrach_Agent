// The shell: Chat is the home surface (as in Hermes Desktop); the office
// (Kantor), Kanban (Papan), meetings (Rapat) and the management hub
// (Lainnya) sit beside it. Phones get a bottom NavigationBar, wide screens
// a NavigationRail. Pages stay mounted when hidden (visibility ≠ lifecycle).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show previewTab;
import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import 'widgets/common.dart';
import 'screens/chat/chat_home.dart';
import 'screens/kanban_screen.dart';
import 'screens/meetings_screen.dart';
import 'screens/more_screen.dart';
import 'screens/new_task_sheet.dart';
import 'screens/office_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int index = previewTab;
  StreamSubscription? _notices;
  bool _navHidden = false;

  bool _onScroll(UserScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    // Content scrolls toward the end → tuck the bar away; back up → show it.
    final hide = n.direction == ScrollDirection.reverse ? true : (n.direction == ScrollDirection.forward ? false : _navHidden);
    if (hide != _navHidden) setState(() => _navHidden = hide);
    return false;
  }

  @override
  void initState() {
    super.initState();
    final office = ref.read(officeProvider);
    office.attach();
    _notices = office.notices.listen((n) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${n.title}\n${n.body}'),
        action: SnackBarAction(label: 'Lihat', onPressed: () => setState(() => index = 2)),
      ));
    });
    final chat = ref.read(chatProvider);
    chat.loadSessions();
  }

  @override
  void dispose() {
    _notices?.cancel();
    ref.read(officeProvider).detach();
    super.dispose();
  }

  void go(int i) => setState(() => index = i);

  static const _dest = [
    (Icons.forum_outlined, Icons.forum, 'Chat'),
    (Icons.apartment_outlined, Icons.apartment, 'Kantor'),
    (Icons.view_kanban_outlined, Icons.view_kanban, 'Papan'),
    (Icons.groups_2_outlined, Icons.groups_2, 'Rapat'),
    (Icons.widgets_outlined, Icons.widgets, 'Lainnya'),
  ];

  @override
  Widget build(BuildContext context) {
    final office = ref.watch(officeProvider);
    final meetingLive = office.meeting?.live == true;
    final review = office.tasks.where((t) => t.status == 'review').length;
    final wide = MediaQuery.sizeOf(context).width >= 840;

    final pages = IndexedStack(index: index, children: [
      for (final (i, w) in <Widget>[
        const ChatHome(),
        OfficeScreen(onOpenBoard: () => go(2), onOpenMeetings: () => go(3)),
        const KanbanScreen(),
        const MeetingsScreen(),
        const MoreScreen(),
      ].indexed)
        TabFade(active: index == i, child: w),
    ]);

    Widget badge(int i, Widget icon) {
      if (i == 2 && review > 0) return Badge(label: Text('$review'), child: icon);
      if (i == 3 && meetingLive) return Badge(backgroundColor: context.hc.warning, smallSize: 8, child: icon);
      return icon;
    }

    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyN, alt: true): () => showNewTaskSheet(context),
      const SingleActivator(LogicalKeyboardKey.keyM, alt: true): () => go(3),
      const SingleActivator(LogicalKeyboardKey.keyC, alt: true): () => go(0),
      const SingleActivator(LogicalKeyboardKey.digit1, alt: true): () => go(1),
      const SingleActivator(LogicalKeyboardKey.digit2, alt: true): () => go(2),
    };

    if (wide) {
      return CallbackShortcuts(
        bindings: shortcuts,
        child: Scaffold(
          body: Row(children: [
            Container(
              decoration: BoxDecoration(border: Border(right: BorderSide(color: context.hc.sidebarBorder))),
              child: NavigationRail(
                selectedIndex: index,
                onDestinationSelected: go,
                labelType: NavigationRailLabelType.all,
                groupAlignment: -0.85,
                leading: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  child: Text('☤', style: TextStyle(fontSize: 26, color: context.cs.primary)),
                ),
                destinations: [
                  for (var i = 0; i < _dest.length; i++)
                    NavigationRailDestination(
                      icon: badge(i, Icon(_dest[i].$1)),
                      selectedIcon: badge(i, Icon(_dest[i].$2)),
                      label: Text(_dest[i].$3),
                    ),
                ],
              ),
            ),
            Expanded(child: pages),
          ]),
        ),
      );
    }
    // Phone: floating pill navigation over the content.
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom > 0;
    final hidden = _navHidden || keyboard;
    const barH = 62.0, gap = 12.0;
    final reserve = keyboard ? 0.0 : (hidden ? 0.0 : barH + gap);
    return CallbackShortcuts(
      bindings: shortcuts,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(children: [
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: reserve),
              duration: reduceMotion(context) ? Duration.zero : motionBase,
              curve: motionCurve,
              builder: (context, r, child) => MediaQuery(
                data: mq.copyWith(padding: mq.padding.copyWith(bottom: mq.padding.bottom + r), viewPadding: mq.viewPadding.copyWith(bottom: mq.viewPadding.bottom + r)),
                child: child!,
              ),
              child: NotificationListener<UserScrollNotification>(onNotification: _onScroll, child: pages),
            ),
          ),
          AnimatedPositioned(
            duration: reduceMotion(context) ? Duration.zero : motionSlow,
            curve: motionCurve,
            left: 14,
            right: 14,
            bottom: hidden ? -(barH + 40) : mq.viewPadding.bottom + gap,
            height: barH,
            child: FloatingNavBar(
              index: index,
              onTap: (i) {
                if (_navHidden) setState(() => _navHidden = false);
                go(i);
              },
              items: [for (var i = 0; i < _dest.length; i++) (_dest[i].$1, _dest[i].$2, _dest[i].$3)],
              badge: badge,
            ),
          ),
        ]),
      ),
    );
  }
}

/// Floating navigation plate: a solid flat panel (bone paper on the red
/// base, deep black in dark mode) with a 1px frame, a sliding active plate,
/// mono labels and press feedback. Flat print: no blur, glow or shadow.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({super.key, required this.index, required this.onTap, required this.items, required this.badge});
  final int index;
  final ValueChanged<int> onTap;
  final List<(IconData, IconData, String)> items;
  final Widget Function(int i, Widget icon) badge;

  @override
  Widget build(BuildContext context) {
    final paper = context.hc.paper;
    if (paper != null) {
      // Red base → the bar is a bone paper plate with ink icons, red active.
      return PaperScope(child: Builder(builder: _plate));
    }
    return _plate(context);
  }

  Widget _plate(BuildContext context) {
    final brand = context.hc.brand;
    final bg = brand ? context.hc.popover : context.hc.sidebar;
    final line = brand ? context.cs.onSurface.withValues(alpha: 0.55) : context.hc.border;
    final active = context.cs.primary;
    final radius = BorderRadius.circular(brand ? 3 : 22);
    return Container(
      decoration: BoxDecoration(color: bg, borderRadius: radius, border: Border.all(color: line, width: 1)),
      padding: const EdgeInsets.all(5),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / items.length;
        return Stack(children: [
          // sliding indicator
          AnimatedPositioned(
            duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 320),
            curve: Curves.easeOutBack,
            left: w * index + 3,
            top: 0,
            bottom: 0,
            width: w - 6,
            child: Container(
              decoration: BoxDecoration(
                color: brand ? active.withValues(alpha: 0.10) : active.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(brand ? 2 : 17),
                border: Border.all(color: active, width: 1),
              ),
              alignment: Alignment.topCenter,
              child: Container(height: 2, width: 18, margin: const EdgeInsets.only(top: 3), color: active),
            ),
          ),
          Row(children: [
            for (var i = 0; i < items.length; i++)
              Expanded(child: _NavItem(item: items[i], selected: i == index, color: active, badge: (icon) => badge(i, icon), onTap: () => onTap(i))),
          ]),
        ]);
      }),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({required this.item, required this.selected, required this.color, required this.badge, required this.onTap});
  final (IconData, IconData, String) item;
  final bool selected;
  final Color color;
  final Widget Function(Widget icon) badge;
  final VoidCallback onTap;
  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final muted = context.hc.mutedForeground;
    final c = widget.selected ? widget.color : muted;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.item.$3,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _down ? 0.9 : 1,
          duration: motionFast,
          curve: motionCurve,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            AnimatedSwitcher(
              duration: motionFast,
              transitionBuilder: (child, a) => ScaleTransition(scale: Tween(begin: 0.7, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: child)),
              child: widget.badge(Icon(widget.selected ? widget.item.$2 : widget.item.$1, key: ValueKey(widget.selected), size: 21, color: c)),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: motionFast,
              style: TextStyle(
                fontFamily: 'IBMPlexMono',
                fontSize: 9.5,
                letterSpacing: 0.8,
                fontWeight: widget.selected ? FontWeight.w500 : FontWeight.w400,
                color: c,
              ),
              child: Text(widget.item.$3.toUpperCase(), maxLines: 1),
            ),
          ]),
        ),
      ),
    );
  }
}
