// Remote shell: Chat · Tugas · Setujui · PC, with a connection strip that
// appears whenever the link to the desktop is not up.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show previewTab;
import '../../theme/app_theme.dart';
import '../../ui/app_shell.dart' show FloatingNavBar;
import '../../ui/widgets/motion.dart';
import '../remote_controller.dart';
import '../remote_gateway.dart';
import 'remote_approvals_screen.dart';
import 'remote_chat_screen.dart';
import 'remote_pc_screen.dart';
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

  static const _dest = [
    (Icons.forum_outlined, Icons.forum, 'Chat'),
    (Icons.view_kanban_outlined, Icons.view_kanban, 'Tugas'),
    (Icons.verified_user_outlined, Icons.verified_user, 'Setujui'),
    (Icons.computer_outlined, Icons.computer, 'PC'),
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

    Widget badge(int i, Widget icon) {
      if (i == 2 && pending > 0) return Badge(label: Text('$pending'), child: icon);
      if (i == 3 && !remote.connected) return Badge(backgroundColor: context.hc.warning, smallSize: 8, child: icon);
      return icon;
    }

    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom > 0;
    const barH = 62.0, gap = 12.0;
    final reserve = keyboard ? 0.0 : barH + gap;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(children: [
        Positioned.fill(
          child: MediaQuery(
            data: mq.copyWith(
                padding: mq.padding.copyWith(bottom: mq.padding.bottom + reserve),
                viewPadding: mq.viewPadding.copyWith(bottom: mq.viewPadding.bottom + reserve)),
            child: Column(children: [
              if (!remote.connected) const _ConnectionStrip(),
              Expanded(child: pages),
            ]),
          ),
        ),
        if (!keyboard)
          Positioned(
            left: 14,
            right: 14,
            bottom: mq.viewPadding.bottom + gap,
            height: barH,
            child: FloatingNavBar(
              index: index,
              onTap: (i) => setState(() => index = i),
              items: [for (final d in _dest) (d.$1, d.$2, d.$3)],
              badge: badge,
            ),
          ),
      ]),
    );
  }
}

class _ConnectionStrip extends ConsumerWidget {
  const _ConnectionStrip();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(remoteProvider);
    final busy = r.status == RemoteStatus.connecting || r.status == RemoteStatus.reconnecting;
    final c = busy ? context.hc.warning : context.hc.destructive;
    return Material(
      color: c.withValues(alpha: 0.14),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(children: [
            Icon(busy ? Icons.sync : Icons.link_off, size: 18, color: c),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                r.desktop == null
                    ? 'Belum memilih PC'
                    : '${r.desktop!.name}: ${r.statusLabel}${r.error != null && !busy ? ' — ${r.error}' : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
            TextButton(onPressed: busy ? null : r.reconnect, child: const Text('Sambungkan')),
          ]),
        ),
      ),
    );
  }
}
