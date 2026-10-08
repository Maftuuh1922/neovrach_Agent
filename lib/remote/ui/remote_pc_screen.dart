// PC: connection status, what the desktop agent is doing, saved desktops,
// and the phone's own preferences.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_controller.dart' show settingsProvider;
import '../../state/settings_controller.dart';
import '../../theme/neovarch_mobile_theme.dart';
import '../../ui/screens/intro_screen.dart';
import '../../ui/widgets/common.dart';
import '../remote_controller.dart';
import '../remote_gateway.dart';
import 'connect_screen.dart';
import 'nv_widgets.dart';

class RemotePcScreen extends ConsumerWidget {
  const RemotePcScreen({super.key, this.onOpenChat});
  final VoidCallback? onOpenChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(remoteProvider);
    final s = ref.watch(settingsProvider);
    final d = r.desktop;
    final ok = r.connected;
    final dot = ok ? NV.ok : (r.status == RemoteStatus.failed ? NV.red : NV.warn);
    void open(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    final version = '${r.serverInfo['version'] ?? ''}';

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          if (!ok) await r.reconnect();
          await r.refreshAll();
        },
        child: ListView(padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom), children: [
          const NvHeader(kicker: 'perangkat', title: 'PC'),
          // Status card: the paired desktop at a glance.
          NvPanel(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: NV.redWash,
                    borderRadius: BorderRadius.circular(NV.rCtl),
                    border: Border.all(color: NV.darkRed),
                  ),
                  child: const Icon(Icons.desktop_windows_rounded, size: 24, color: NV.red),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d?.name ?? 'Belum ada PC', maxLines: 1, overflow: TextOverflow.ellipsis, style: NV.display(size: 28)),
                    const SizedBox(height: 4),
                    if (d != null)
                      Text(d.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: NV.mono, fontSize: 11.5, color: NV.muted)),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: dot.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: dot.withValues(alpha: 0.4)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    NvDot(dot, size: 6),
                    const SizedBox(width: 6),
                    Text(ok ? 'ONLINE' : 'OFFLINE', style: NV.monoLabel(size: 9.5, color: dot)),
                  ]),
                ),
              ]),
              const SizedBox(height: 14),
              const Divider(height: 1, color: NV.border),
              const SizedBox(height: 14),
              // three numbers in a row
              Row(children: [
                _Stat(label: 'sesi aktif', value: '${r.active.length}'),
                _Stat(label: 'persetujuan', value: '${r.approvals.length}', hot: r.approvals.isNotEmpty),
                _Stat(label: 'hermes', value: version.isEmpty ? '—' : version, mono: true),
              ]),
              const SizedBox(height: 12),
              NvKv('Status', r.statusLabel, valueColor: dot),
              if (r.error != null && !ok) ...[const SizedBox(height: 8), NvNotice(r.error!)],
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: d == null ? null : r.reconnect,
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: Text(ok ? 'Sambung ulang' : 'Sambungkan'),
                  ),
                ),
                if (d != null) ...[
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton(onPressed: r.disconnect, child: const Text('Putuskan'))),
                ],
              ]),
            ]),
          ),
          if (r.active.isNotEmpty) ...[
            NvSection('sedang berjalan di pc', count: r.active.length),
            NvList(children: [
              for (final a in r.active)
                NvRow(
                  icon: a.status == 'running' ? Icons.bolt_rounded : Icons.chat_bubble_outline_rounded,
                  accent: a.status == 'running',
                  title: a.title.isNotEmpty ? a.title : a.id,
                  subtitle: '${a.status}${a.model.isNotEmpty ? ' · ${a.model}' : ''}',
                  mono: true,
                  trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: NV.faint),
                  onTap: () async {
                    await r.openActive(a);
                    onOpenChat?.call();
                  },
                ),
            ]),
          ],
          NvSection('pc tersimpan',
              trailing: TextButton.icon(
                onPressed: () => open(const ConnectScreen()),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Tambah'),
              )),
          if (r.desktops.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('Belum ada PC tersimpan.', style: TextStyle(color: NV.muted, fontSize: 13.5)),
            )
          else
            NvList(children: [
              for (final x in r.desktops.items)
                NvRow(
                  icon: x.id == d?.id ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  accent: x.id == d?.id,
                  title: x.name,
                  subtitle: '${x.url}${x.lastConnected != null ? ' · ${relTime(x.lastConnected!.toIso8601String())}' : ''}',
                  mono: true,
                  onTap: x.id == d?.id ? null : () => r.connectTo(x),
                  trailing: NvIconButton(
                    tooltip: 'Lupakan',
                    icon: Icons.delete_outline_rounded,
                    size: 36,
                    onPressed: () async {
                      final yes = await confirmDialog(context,
                          title: 'Lupakan ${x.name}?',
                          body: 'Alamat dan token PC ini dihapus dari HP. Untuk memakainya lagi, pindai ulang QR di PC.',
                          confirm: 'Lupakan',
                          destructive: true);
                      if (yes) await r.forget(x);
                    },
                  ),
                ),
            ]),
          const NvSection('hp ini'),
          NvList(children: [
            _SwitchRow(
              icon: Icons.notifications_none_rounded,
              title: 'Notifikasi persetujuan',
              subtitle: 'Kabari saat agen di PC menunggu persetujuan',
              value: r.notifyApprovals,
              onChanged: r.setNotifyApprovals,
            ),
            _SwitchRow(
              icon: Icons.psychology_outlined,
              title: 'Tampilkan proses berpikir',
              subtitle: 'Blok penalaran agen di chat',
              value: s.showReasoning,
              onChanged: (v) => ref.read(settingsProvider).update((x) => x.showReasoning = v),
            ),
            NvRow(
              icon: Icons.slideshow_outlined,
              title: 'Putar ulang intro',
              trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: NV.faint),
              onTap: () => open(const IntroScreen(replay: true)),
            ),
          ]),
          const SizedBox(height: 24),
          Center(child: Text('NEOVARCH REMOTE · V${SettingsController.appVersion}', style: NV.monoLabel(size: 9.5, color: NV.faint))),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.hot = false, this.mono = false});
  final String label;
  final String value;
  final bool hot;
  final bool mono;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: NV.monoLabel(size: 9.5)),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono
                  ? const TextStyle(fontFamily: NV.mono, fontSize: 15, color: NV.text, height: 1.6)
                  : NV.display(size: 30, color: hot ? NV.red : NV.text)),
        ]),
      );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.icon, required this.title, required this.subtitle, required this.value, required this.onChanged});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => NvRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: () => onChanged(!value),
        trailing: Switch(value: value, onChanged: onChanged),
      );
}
