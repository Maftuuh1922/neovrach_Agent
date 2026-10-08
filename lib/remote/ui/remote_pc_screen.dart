// PC: connection status, what the desktop agent is doing, saved desktops,
// and the phone's own preferences.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_controller.dart' show settingsProvider;
import '../../state/settings_controller.dart';
import '../../theme/neovarch_mobile_theme.dart';
import 'remote_intro_screen.dart';
import '../../ui/widgets/common.dart';
import '../appearance.dart';
import '../pairing.dart';
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
                  child: Icon(Icons.desktop_windows_rounded, size: 24, color: NV.red),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d?.name ?? 'Belum ada PC', maxLines: 1, overflow: TextOverflow.ellipsis, style: NV.display(size: 28)),
                    const SizedBox(height: 4),
                    if (d != null)
                      Text(d.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: NV.mono, fontSize: 11.5, color: NV.muted)),
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
              Divider(height: 1, color: NV.border),
              const SizedBox(height: 14),
              // three numbers in a row
              Row(children: [
                _Stat(label: 'sesi aktif', value: '${r.active.length}'),
                _Stat(label: 'persetujuan', value: '${r.approvals.length}', hot: r.approvals.isNotEmpty),
                _Stat(label: 'versi', value: version.isEmpty ? '—' : version, mono: true),
              ]),
              const SizedBox(height: 12),
              // status on the same column grid as the numbers above:
              // label in column 1, value from column 2, one shared baseline
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Expanded(child: Text('STATUS', style: NV.monoLabel(size: 9.5))),
                Expanded(
                  flex: 2,
                  child: Text(r.statusLabel,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: dot, fontWeight: FontWeight.w500)),
                ),
              ]),
              if (ok && r.gateway != null) ...[
                const SizedBox(height: 8),
                Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Expanded(child: Text('JALUR', style: NV.monoLabel(size: 9.5))),
                  Expanded(
                    flex: 2,
                    child: Text(
                      key: const ValueKey('pc-route'),
                      '${routeLabel(r.gateway!.activeUrl)}${r.gateway!.lastRtt != null ? ' · ${r.gateway!.lastRtt!.inMilliseconds} ms' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: NV.text, fontWeight: FontWeight.w500),
                    ),
                  ),
                ]),
              ],
              if (r.error != null && !ok) ...[const SizedBox(height: 8), NvNotice(r.error!)],
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  // Red only when there is something to do (not connected).
                  child: ok
                      ? OutlinedButton(onPressed: r.reconnect, child: const Text('Sambung ulang', maxLines: 1))
                      : FilledButton(onPressed: d == null ? null : r.reconnect, child: const Text('Sambungkan', maxLines: 1)),
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
                  trailing: Icon(Icons.chevron_right_rounded, size: 18, color: NV.faint),
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
            Padding(
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
          const NvSection('tampilan'),
          const AppearancePanel(),
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
              trailing: Icon(Icons.chevron_right_rounded, size: 18, color: NV.faint),
              onTap: () => open(const RemoteIntroScreen(replay: true)),
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
                  ? TextStyle(fontFamily: NV.mono, fontSize: 15, color: NV.text, height: 1.6)
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

/// "LAN" / "Tailscale" / "Internet" for the address the socket uses.
String routeLabel(String url) => switch (gatewayRoute(url)) {
      'lan' => 'LAN · ${Uri.tryParse(url)?.host ?? url}',
      'tailscale' => 'Tailscale · ${Uri.tryParse(url)?.host ?? url}',
      _ => Uri.tryParse(url)?.host ?? url,
    };

/// Theme picker: follow the PC (default) or a local look — 14 accent
/// presets, a custom colour (flat hue strip or hex) and Gelap / Terang /
/// Sistem. Every change applies live and cross-fades the whole app.
class AppearancePanel extends ConsumerStatefulWidget {
  const AppearancePanel({super.key});
  @override
  ConsumerState<AppearancePanel> createState() => _AppearancePanelState();
}

class _AppearancePanelState extends ConsumerState<AppearancePanel> {
  late final TextEditingController _hex = TextEditingController(text: hexOf(ref.read(appearanceProvider).localAccent));

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _pick(AppearanceController look, Color c) {
    look.setLocal(accent: c);
    _hex.text = hexOf(c);
  }

  @override
  Widget build(BuildContext context) {
    final look = ref.watch(appearanceProvider);
    final current = look.accent.toARGB32();
    String? presetName;
    for (final (n, c) in accentPresets) {
      if (c.toARGB32() == current) presetName = n;
    }
    final dur = reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 220);
    return NvPanel(
      key: const ValueKey('appearance-panel'),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _SwitchRow(
          icon: Icons.desktop_windows_outlined,
          title: 'Ikuti tema PC',
          subtitle: look.followPc ? 'Warna ${hexOf(look.pcAccent)} · ${look.pcDark ? 'gelap' : 'terang'}' : 'Pakai tema khusus HP ini',
          value: look.followPc,
          onChanged: look.setFollowPc,
        ),
        Divider(height: 1, color: NV.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
          child: Row(children: [
            Text('// WARNA AKSEN', style: NV.monoLabel(size: 10)),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${presetName ?? 'Kustom'} · ${hexOf(look.accent)}',
                  key: const ValueKey('accent-current'),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NV.monoLabel(size: 10, color: NV.text)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
          child: Wrap(spacing: 10, runSpacing: 10, children: [
            for (final (name, c) in accentPresets)
              Semantics(
                button: true,
                selected: current == c.toARGB32(),
                label: name,
                child: Tooltip(
                  message: name,
                  child: GestureDetector(
                    key: ValueKey('accent-$name'),
                    onTap: () => _pick(look, c),
                    child: AnimatedContainer(
                      duration: dur,
                      curve: Curves.easeOutCubic,
                      width: 40,
                      height: 40,
                      padding: EdgeInsets.all(current == c.toARGB32() ? 3 : 0),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: current == c.toARGB32() ? NV.text : NV.border, width: current == c.toARGB32() ? 2 : 1),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                        child: AnimatedOpacity(
                          duration: dur,
                          opacity: current == c.toARGB32() ? 1 : 0,
                          child: Icon(Icons.check_rounded, size: 18, color: NvPalette.from(c, Brightness.dark).onAccent),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Text('// WARNA KUSTOM', style: NV.monoLabel(size: 10)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: _HueStrip(key: const ValueKey('accent-hue'), current: look.accent, onPick: (c) => _pick(look, c)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: TextField(
            key: const ValueKey('accent-hex'),
            controller: _hex,
            decoration: InputDecoration(
              labelText: 'Warna kustom (hex)',
              hintText: '#FF0066',
              prefixIcon: Padding(
                padding: const EdgeInsets.all(12),
                child: AnimatedContainer(duration: dur, width: 20, height: 20, decoration: BoxDecoration(color: look.accent, shape: BoxShape.circle)),
              ),
            ),
            onSubmitted: (v) {
              final c = parseHexColor(v);
              if (c != null) _pick(look, c);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: SegmentedButton<NvBrightnessMode>(
            key: const ValueKey('theme-mode'),
            segments: const [
              ButtonSegment(value: NvBrightnessMode.dark, label: Text('Gelap'), icon: Icon(Icons.dark_mode_outlined, size: 18)),
              ButtonSegment(value: NvBrightnessMode.light, label: Text('Terang'), icon: Icon(Icons.light_mode_outlined, size: 18)),
              ButtonSegment(value: NvBrightnessMode.system, label: Text('Sistem'), icon: Icon(Icons.brightness_auto_outlined, size: 18)),
            ],
            selected: {look.followPc ? (look.pcDark ? NvBrightnessMode.dark : NvBrightnessMode.light) : look.localMode},
            onSelectionChanged: (v) => look.setLocal(mode: v.first),
          ),
        ),
      ]),
    );
  }
}

/// Custom accent: a strip of flat hue blocks (no gradient). Tap or drag.
class _HueStrip extends StatelessWidget {
  const _HueStrip({super.key, required this.current, required this.onPick});
  final Color current;
  final ValueChanged<Color> onPick;
  static const steps = 24;
  static Color hueColor(int i) => HSLColor.fromAHSL(1, i * 360 / steps, 0.72, 0.50).toColor();

  @override
  Widget build(BuildContext context) {
    final curHue = HSLColor.fromColor(current).hue;
    var sel = -1;
    var best = 999.0;
    for (var i = 0; i < steps; i++) {
      final d = ((i * 360 / steps) - curHue).abs();
      final dd = d > 180 ? 360 - d : d;
      if (dd < best) {
        best = dd;
        sel = i;
      }
    }
    if (best > 360 / steps / 2 || HSLColor.fromColor(current).saturation < 0.2) sel = -1;
    return LayoutBuilder(builder: (context, c) {
      void at(double x) => onPick(hueColor((x / c.maxWidth * steps).floor().clamp(0, steps - 1)));
      return GestureDetector(
        onTapDown: (d) => at(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => at(d.localPosition.dx),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(NV.rCtl),
          child: SizedBox(
            height: 34,
            child: Row(children: [
              for (var i = 0; i < steps; i++)
                Expanded(
                  child: Container(
                    color: hueColor(i),
                    alignment: Alignment.center,
                    child: i == sel ? Container(width: 4, height: 18, decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(2))) : null,
                  ),
                ),
            ]),
          ),
        ),
      );
    });
  }
}
