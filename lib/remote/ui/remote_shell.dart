// Remote shell: Chat · Tugas · Setujui · PC, with a connection strip that
// appears whenever the link to the desktop is not up.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show previewTab;
import '../../theme/neovarch_mobile_theme.dart';
import '../../ui/widgets/motion.dart';
import '../remote_controller.dart';
import '../remote_gateway.dart';
import 'remote_approvals_screen.dart';
import 'remote_chat_screen.dart';
import 'remote_pc_screen.dart';
import 'nv_widgets.dart';
import 'remote_tasks_screen.dart';

class RemoteShell extends ConsumerStatefulWidget {
  const RemoteShell({super.key});
  @override
  ConsumerState<RemoteShell> createState() => _RemoteShellState();
}

class _RemoteShellState extends ConsumerState<RemoteShell> with WidgetsBindingObserver {
  int index = previewTab.clamp(0, 3);
  int _lastApprovals = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back in the foreground: phones drop sockets in the background.
    if (state == AppLifecycleState.resumed) {
      final r = ref.read(remoteProvider);
      if (!r.connected) r.reconnect();
    }
  }

  static const _barH = 64.0, _gap = 12.0;

  static const _dest = <(IconData, IconData, String)>[
    (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Chat'),
    (Icons.view_week_outlined, Icons.view_week_rounded, 'Tugas'),
    (Icons.shield_outlined, Icons.shield_rounded, 'Setujui'),
    (Icons.desktop_windows_outlined, Icons.desktop_windows_rounded, 'PC'),
  ];

  @override
  Widget build(BuildContext context) {
    final remote = ref.watch(remoteProvider);
    final pending = remote.approvals.length;
    if (pending > _lastApprovals && index != 2 && index != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Agen di PC menunggu persetujuanmu'),
          // Float above the nav bar instead of on top of it.
          margin: EdgeInsets.fromLTRB(16, 0, 16, _barH + _gap + 8),
          action: SnackBarAction(label: 'Lihat', onPressed: () => setState(() => index = 2)),
        ));
      });
    }
    _lastApprovals = pending;

    final pages = IndexedStack(index: index, children: [
      for (final (i, w) in <Widget>[
        RemoteChatScreen(onOpenApprovals: () => setState(() => index = 2)),
        const RemoteTasksScreen(),
        RemoteApprovalsScreen(onOpenChat: () => setState(() => index = 0)),
        RemotePcScreen(onOpenChat: () => setState(() => index = 0)),
      ].indexed)
        TabFade(active: index == i, child: w),
    ]);

    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom > 0;
    const barH = _barH, gap = _gap;
    final reserve = keyboard ? 0.0 : barH + gap;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: NV.bg,
        systemNavigationBarDividerColor: NV.bg,
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(children: [
          Positioned.fill(
            child: MediaQuery(
              data: mq.copyWith(
                  padding: mq.padding.copyWith(bottom: mq.padding.bottom + reserve),
                  viewPadding: mq.viewPadding.copyWith(bottom: mq.viewPadding.bottom + reserve)),
              child: Column(children: [
                if (!remote.connected) const _ConnectionStrip(),
                Expanded(
                  // Builder: removePadding must read the MediaQuery above (the
                  // one that reserves room for the floating nav bar), not the
                  // shell's own context, or the composer slides under the bar.
                  child: Builder(
                    builder: (inner) => MediaQuery.removePadding(context: inner, removeTop: !remote.connected, child: pages),
                  ),
                ),
              ]),
            ),
          ),
          // Solid band behind the lower half of the floating bar so scrolled
          // content never shows through under it or in the system nav inset.
          if (!keyboard)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: mq.viewPadding.bottom + gap + barH / 2,
              child: const IgnorePointer(child: ColoredBox(color: NV.bg)),
            ),
          if (!keyboard)
            Positioned(
              left: 16,
              right: 16,
              bottom: mq.viewPadding.bottom + gap,
              height: barH,
              child: NvNavBar(
                index: index,
                onTap: (i) => setState(() => index = i),
                items: _dest,
                badges: {2: pending},
                dots: {if (!remote.connected) 3: NV.warn},
              ),
            ),
        ]),
      ),
    );
  }
}

class _ConnectionStrip extends ConsumerWidget {
  const _ConnectionStrip();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(remoteProvider);
    final busy = r.status == RemoteStatus.connecting || r.status == RemoteStatus.reconnecting;
    final c = busy ? NV.warn : NV.red;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, MediaQuery.paddingOf(context).top + 8, 12, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(NV.rCtl),
          border: Border.all(color: c.withValues(alpha: 0.45)),
        ),
        child: Row(children: [
          Icon(busy ? Icons.sync : Icons.link_off, size: 17, color: c),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(r.desktop == null ? '// BELUM ADA PC' : '// ${r.desktop!.name.toUpperCase()} · ${r.statusLabel.toUpperCase()}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: NV.monoLabel(size: 9.5, color: c)),
              if (r.error != null && !busy)
                Text(r.error!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: NV.muted, height: 1.35)),
            ]),
          ),
          TextButton(onPressed: busy ? null : r.reconnect, child: const Text('Sambungkan')),
        ]),
      ),
    );
  }
}
