// PC: connection status, what the desktop agent is doing, saved desktops,
// and the phone's own look & feel.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_controller.dart' show settingsProvider;
import '../../state/settings_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/hermes_themes.dart';
import '../../ui/screens/intro_screen.dart';
import '../../ui/screens/settings/appearance_screen.dart';
import '../../ui/widgets/common.dart';
import '../remote_controller.dart';
import '../remote_gateway.dart';
import 'connect_screen.dart';

class RemotePcScreen extends ConsumerWidget {
  const RemotePcScreen({super.key, this.onOpenChat});
  final VoidCallback? onOpenChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(remoteProvider);
    final s = ref.watch(settingsProvider);
    final d = r.desktop;
    final ok = r.connected;
    final dot = ok ? context.hc.success : (r.status == RemoteStatus.failed ? context.hc.destructive : context.hc.warning);
    void open(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    final version = '${r.serverInfo['version'] ?? ''}';

    return Scaffold(
      appBar: AppBar(title: Text('PC', style: context.tt.titleMedium)),
      body: RefreshIndicator(
        onRefresh: () async {
          if (!ok) await r.reconnect();
          await r.refreshAll();
        },
        child: ListView(padding: EdgeInsets.only(bottom: 32 + MediaQuery.paddingOf(context).bottom), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: PaperScope(
              child: Builder(
                builder: (context) => Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.hc.popover,
                    borderRadius: BorderRadius.circular(context.hc.corner + 2),
                    border: Border.all(color: context.hc.border),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.computer, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(d?.name ?? 'Belum ada PC', style: context.tt.titleMedium),
                          if (d != null) Text(d.url, style: monoStyle(context, size: 11.5, color: context.hc.mutedForeground)),
                        ]),
                      ),
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                    ]),
                    const SizedBox(height: 10),
                    KeyValue('Status', r.statusLabel),
                    if (version.isNotEmpty) KeyValue('Hermes', version, mono: true),
                    KeyValue('Sesi aktif', '${r.active.length}'),
                    KeyValue('Persetujuan', '${r.approvals.length} menunggu'),
                    if (r.error != null && !ok) ...[const SizedBox(height: 8), ErrorBanner(r.error!, dense: true)],
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, children: [
                      FilledButton.tonalIcon(
                        onPressed: d == null ? null : r.reconnect,
                        icon: const Icon(Icons.sync, size: 18),
                        label: Text(ok ? 'Sambung ulang' : 'Sambungkan'),
                      ),
                      if (d != null)
                        OutlinedButton(onPressed: r.disconnect, child: const Text('Putuskan')),
                    ]),
                  ]),
                ),
              ),
            ),
          ),
          if (r.active.isNotEmpty) ...[
            const SectionLabel('Sedang berjalan di PC'),
            for (final a in r.active)
              ListTile(
                leading: Icon(a.status == 'running' ? Icons.bolt : Icons.chat_bubble_outline,
                    color: a.status == 'running' ? context.cs.primary : null),
                title: Text(a.title.isNotEmpty ? a.title : a.id, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${a.status}${a.model.isNotEmpty ? ' · ${a.model}' : ''}', style: context.tt.bodySmall),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () async {
                  await r.openActive(a);
                  onOpenChat?.call();
                },
              ),
          ],
          SectionLabel('PC tersimpan',
              trailing: TextButton.icon(
                onPressed: () => open(const ConnectScreen()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Tambah'),
              )),
          for (final x in r.desktops.items)
            ListTile(
              leading: Icon(x.id == d?.id ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: x.id == d?.id ? context.cs.primary : null),
              title: Text(x.name),
              subtitle: Text(
                  '${x.url}${x.lastConnected != null ? ' · ${relTime(x.lastConnected!.toIso8601String())}' : ''}',
                  style: context.tt.bodySmall),
              onTap: x.id == d?.id ? null : () => r.connectTo(x),
              trailing: IconButton(
                tooltip: 'Lupakan',
                icon: const Icon(Icons.delete_outline),
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
          const SectionLabel('HP ini'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Notifikasi persetujuan'),
            subtitle: Text('Kabari saat agen di PC menunggu persetujuan', style: context.tt.bodySmall),
            value: r.notifyApprovals,
            onChanged: r.setNotifyApprovals,
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Tampilan'),
            subtitle: Text(themeByName(s.themeName).label, style: context.tt.bodySmall),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => open(const AppearanceScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.slideshow_outlined),
            title: const Text('Putar ulang intro'),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => open(const IntroScreen(replay: true)),
          ),
          const SizedBox(height: 16),
          const Center(child: MetaLabel('Neovarch Remote · v${SettingsController.appVersion}')),
        ]),
      ),
    );
  }
}
