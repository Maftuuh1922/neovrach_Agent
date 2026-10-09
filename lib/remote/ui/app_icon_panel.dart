// 1.4.2: "Ikon aplikasi" — launcher icon colour picker (Profil tab and the
// Tampilan sheet). Backed by [appIconProvider] (lib/remote/app_icon.dart).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/neovarch_mobile_theme.dart';
import '../../ui/widgets/common.dart' show reduceMotion, toast;
import '../app_icon.dart';
import '../appearance.dart';
import 'nv_widgets.dart';

class AppIconPanel extends ConsumerWidget {
  const AppIconPanel({super.key, this.margin = const EdgeInsets.symmetric(horizontal: 16)});
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icons = ref.watch(appIconProvider);
    final look = ref.watch(appearanceProvider);
    final dur = reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 220);
    return NvPanel(
      key: const ValueKey('app-icon-panel'),
      margin: margin,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('IKON APLIKASI', style: NV.monoLabel(size: 10)),
          const Spacer(),
          Text(appIconVariants.firstWhere((v) => v.$1 == icons.current, orElse: () => appIconVariants.first).$2,
              key: const ValueKey('app-icon-current'), style: NV.code(size: 11, color: NV.text)),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final (id, label, _) in appIconVariants)
            Semantics(
              button: true,
              selected: icons.current == id,
              label: 'Ikon $label',
              child: GestureDetector(
                key: ValueKey('app-icon-$id'),
                onTap: () async {
                  HapticFeedback.selectionClick();
                  final err = await icons.select(id);
                  if (context.mounted) toast(context, err ?? 'Ikon $label dipakai · launcher bisa perlu beberapa detik untuk memperbarui');
                },
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedContainer(
                    duration: dur,
                    curve: Curves.easeOutCubic,
                    width: 52,
                    height: 52,
                    padding: EdgeInsets.all(icons.current == id ? 3 : 1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: icons.current == id ? NV.text : NV.border, width: icons.current == id ? 2 : 1),
                    ),
                    child: ClipOval(child: Image.asset(appIconAsset(id), fit: BoxFit.cover, filterQuality: FilterQuality.medium)),
                  ),
                  const SizedBox(height: 4),
                  Text(label, style: NV.monoLabel(size: 8.5, color: icons.current == id ? NV.text : NV.muted)),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        SwitchListTile.adaptive(
          key: const ValueKey('app-icon-follow'),
          contentPadding: EdgeInsets.zero,
          title: Text('Ikuti warna aksen', style: TextStyle(fontFamily: NV.sans, fontSize: 15, color: NV.text)),
          subtitle: Text('Pilih ikon yang paling dekat dengan warna aksen', style: TextStyle(fontFamily: NV.sans, fontSize: 12.5, color: NV.muted)),
          value: icons.followAccent,
          onChanged: (v) => icons.setFollowAccent(v, look.accent),
        ),
        Text('Launcher bisa perlu beberapa detik untuk menampilkan ikon baru.',
            key: const ValueKey('app-icon-note'), style: TextStyle(fontFamily: NV.sans, fontSize: 12, height: 1.35, color: NV.faint)),
      ]),
    );
  }
}
