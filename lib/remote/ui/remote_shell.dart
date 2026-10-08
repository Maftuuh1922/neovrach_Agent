// Remote shell: Chat · Kantor · Tugas · Setujui · PC on a floating iOS-style
// liquid glass bar (content scrolls under it), with a connection strip whenever the link to the PC is not up
// and an "Update tersedia" strip when a newer phone app is released.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../main.dart' show previewTab;
import '../../theme/neovarch_mobile_theme.dart';
import '../../ui/widgets/motion.dart';
import '../remote_controller.dart';
import '../remote_gateway.dart';
import 'remote_approvals_screen.dart';
import 'remote_office_screen.dart';
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
  int index = previewTab.clamp(0, 4);

  static const tabChat = 0, tabApprovals = 3, tabPc = 4; // 1 Kantor, 2 Tugas
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
    (Icons.apartment_outlined, Icons.apartment_rounded, 'Kantor'),
    (Icons.view_week_outlined, Icons.view_week_rounded, 'Tugas'),
    (Icons.shield_outlined, Icons.shield_rounded, 'Setujui'),
    (Icons.desktop_windows_outlined, Icons.desktop_windows_rounded, 'PC'),
  ];

  @override
  Widget build(BuildContext context) {
    final remote = ref.watch(remoteProvider);
    final pending = remote.approvals.length;
    if (pending > _lastApprovals && index != tabApprovals && index != tabChat) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Agen di PC menunggu persetujuanmu'),
          // Float above the nav bar instead of on top of it.
          margin: EdgeInsets.fromLTRB(16, 0, 16, _barH + _gap + 8),
          action: SnackBarAction(label: 'Lihat', onPressed: () => setState(() => index = tabApprovals)),
        ));
      });
    }
    _lastApprovals = pending;

    final pages = IndexedStack(index: index, children: [
      for (final (i, w) in <Widget>[
        RemoteChatScreen(onOpenApprovals: () => setState(() => index = tabApprovals)),
        RemoteOfficeScreen(
            onOpenChat: () => setState(() => index = tabChat), onOpenApprovals: () => setState(() => index = tabApprovals)),
        const RemoteTasksScreen(),
        RemoteApprovalsScreen(onOpenChat: () => setState(() => index = tabChat)),
        RemotePcScreen(onOpenChat: () => setState(() => index = tabChat)),
      ].indexed)
        TabFade(active: index == i, child: w),
    ]);

    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom > 0;
    const barH = _barH, gap = _gap;
    final reserve = keyboard ? 0.0 : barH + gap;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (NV.palette.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
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
                if (remote.connected && remote.updateAvailable) const _UpdateStrip(),
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
          // Liquid glass: every tab's content runs edge to edge and scrolls
          // under the floating bar, so the blur/lens has something to show.
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
                badges: {tabApprovals: pending},
                dots: {if (!remote.connected) tabPc: NV.warn},
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
      child: NvGlass(
        key: const ValueKey('nv-connection-strip'),
        radius: NV.rCtl,
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(children: [
          Icon(busy ? Icons.sync : Icons.link_off, size: 17, color: c),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(r.desktop == null ? '// BELUM ADA PC' : '// ${r.desktop!.name.toUpperCase()} · ${r.statusLabel.toUpperCase()}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: NV.monoLabel(size: 9.5, color: c)),
              if (r.error != null && !busy)
                Text(r.error!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: NV.muted, height: 1.35)),
            ]),
          ),
          TextButton(onPressed: busy ? null : r.reconnect, child: const Text('Sambungkan')),
        ]),
      ),
    );
  }
}


/// "Update tersedia vX" — flat strip under the status bar, links to the release.
class _UpdateStrip extends ConsumerWidget {
  const _UpdateStrip();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(remoteProvider);
    final u = r.update;
    final url = '${u['download_url'] ?? u['url'] ?? ''}';
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: NvGlass(
        key: const ValueKey('nv-update-strip'),
        radius: 14,
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: NV.red, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Update tersedia v${u['latest']}',
                style: TextStyle(color: NV.text, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          if (url.isNotEmpty)
            TextButton(
              onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
              child: const Text('Unduh'),
            ),
          IconButton(
            tooltip: 'Tutup',
            icon: Icon(Icons.close_rounded, size: 18, color: NV.muted),
            onPressed: r.dismissUpdate,
          ),
        ]),
      ),
      ),
    );
  }
}
