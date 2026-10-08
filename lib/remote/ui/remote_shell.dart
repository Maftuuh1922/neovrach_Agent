// Remote shell: Chat · Kantor · Profil · PC on a floating iOS-style
// liquid glass bar (content scrolls under it), with a connection strip whenever the link to the PC is not up
// and an "Update tersedia" strip when a newer phone app is released.
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../main.dart' show previewTab;
import '../../theme/neovarch_mobile_theme.dart';
import '../../ui/widgets/motion.dart';
import '../remote_controller.dart';
import '../remote_gateway.dart';
import '../../data/device_tools.dart' show deviceCall;
import 'remote_approvals_screen.dart' show showApprovalsSheet;
import 'remote_chat_screen.dart';
import 'remote_kantor_tab.dart';
import 'remote_pc_screen.dart';
import 'remote_profile_screen.dart';
import 'nv_widgets.dart';
import 'remote_background.dart' show NvAppBackground;
import '../appearance.dart' show appearanceProvider;
import '../profile_avatar.dart';

class RemoteShell extends ConsumerStatefulWidget {
  const RemoteShell({super.key});
  @override
  ConsumerState<RemoteShell> createState() => _RemoteShellState();
}

class _RemoteShellState extends ConsumerState<RemoteShell> with WidgetsBindingObserver {
  int index = previewTab.clamp(0, 3);
  int kantorSegment = previewKantorSegment;

  // 1.4.2: 4 tabs. Setujui merged into Chat (pinned chip + sheet), Tugas
  // into Kantor (segmented), Tampilan moved from PC to the new Profil tab.
  static const tabChat = 0, tabKantor = 1, tabProfile = 2, tabPc = 3;
  int _lastApprovals = 0;
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeRoute());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Chat + the pending-approvals sheet (snackbar "Lihat", Kantor's
  /// "menunggu", a tapped approval notification).
  void openApprovals() {
    setState(() => index = tabChat);
    if (_sheetOpen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _sheetOpen = true;
      await showApprovalsSheet(context, onOpenChat: () => setState(() => index = tabChat));
      _sheetOpen = false;
    });
  }

  /// Kantor tab on the Tugas segment (old Tugas tab routes).
  void openTasks() => setState(() {
        index = tabKantor;
        kantorSegment = kantorSegTasks;
      });

  /// Route handed over by a tapped notification (MainActivity `nv_route`).
  void route(String? r) {
    switch (r) {
      case 'approvals':
        openApprovals();
      case 'tasks':
        openTasks();
      case 'chat':
        setState(() => index = tabChat);
      case 'profile':
        setState(() => index = tabProfile);
    }
  }

  Future<void> _takeRoute() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      route(await deviceCall<String>('takeRoute'));
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back in the foreground: phones drop sockets in the background.
    if (state == AppLifecycleState.resumed) {
      final r = ref.read(remoteProvider);
      if (!r.connected) r.reconnect();
      _takeRoute();
    }
  }

  static const _barH = 64.0, _gap = 12.0;

  static const _dest = <(IconData, IconData, String)>[
    (CupertinoIcons.chat_bubble, CupertinoIcons.chat_bubble_fill, 'Chat'),
    (CupertinoIcons.building_2_fill, CupertinoIcons.building_2_fill, 'Kantor'),
    (CupertinoIcons.person_crop_circle, CupertinoIcons.person_crop_circle_fill, 'Profil'),
    (CupertinoIcons.desktopcomputer, CupertinoIcons.desktopcomputer, 'PC'),
  ];

  @override
  Widget build(BuildContext context) {
    final remote = ref.watch(remoteProvider);
    final pending = remote.approvals.length;
    if (pending > _lastApprovals && index != tabChat) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Agen di PC menunggu persetujuanmu'),
          // Float above the nav bar instead of on top of it.
          margin: EdgeInsets.fromLTRB(16, 0, 16, _barH + _gap + 8),
          action: SnackBarAction(label: 'Lihat', onPressed: openApprovals),
        ));
      });
    }
    _lastApprovals = pending;

    final pages = IndexedStack(index: index, children: [
      for (final (i, w) in <Widget>[
        RemoteChatScreen(onOpenApprovals: openApprovals),
        RemoteKantorTab(
          segment: kantorSegment,
          onSegment: (i) => setState(() => kantorSegment = i),
          onOpenChat: () => setState(() => index = tabChat),
          onOpenApprovals: openApprovals,
        ),
        const RemoteProfileScreen(),
        RemotePcScreen(onOpenChat: () => setState(() => index = tabChat)),
      ].indexed)
        TabFade(active: index == i, child: w),
    ]);

    // Custom background: drawn once behind every tab; the tabs' scaffolds go
    // transparent so the glass nav/composer refract the image.
    final look = ref.watch(appearanceProvider);
    final bgOn = look.background.active;
    // Always wrapped (same tree shape) so toggling keeps every tab's state.
    final theme = Theme.of(context);
    final themed = Theme(data: bgOn ? theme.copyWith(scaffoldBackgroundColor: Colors.transparent) : theme, child: pages);

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
        backgroundColor: bgOn ? NV.bg : null,
        body: Stack(children: [
          if (bgOn) const Positioned.fill(child: NvAppBackground()),
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
                    builder: (inner) => MediaQuery.removePadding(context: inner, removeTop: !remote.connected, child: themed),
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
                badges: {tabChat: pending},
                avatars: {tabProfile: ref.watch(profileAvatarProvider)},
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
          Icon(busy ? CupertinoIcons.arrow_2_circlepath : CupertinoIcons.wifi_slash, size: 17, color: c),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(r.desktop == null ? 'BELUM ADA PC' : '${r.desktop!.name.toUpperCase()} · ${r.statusLabel.toUpperCase()}',
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
            icon: Icon(CupertinoIcons.xmark, size: 18, color: NV.muted),
            onPressed: r.dismissUpdate,
          ),
        ]),
      ),
      ),
    );
  }
}
