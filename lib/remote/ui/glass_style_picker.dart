// 1.4.2: "Gaya kaca" picker (Profil / Tampilan sheet) and "Warna dari
// wallpaper" (toggle + suggested swatches). Kept as their own widgets so the
// redesigned Tampilan widgets (appearance-ui branch) can sit next to them.
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/neovarch_mobile_theme.dart';
import '../appearance.dart';
import 'nv_widgets.dart';
import 'remote_background.dart' show backgroundImage;

class GlassStylePicker extends ConsumerWidget {
  const GlassStylePicker({super.key, this.margin = const EdgeInsets.symmetric(horizontal: 16)});
  final EdgeInsets margin;

  static const _effects = [NvGlassStyle.reguler, NvGlassStyle.bening, NvGlassStyle.gelap, NvGlassStyle.warna];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = ref.watch(appearanceProvider);
    final mq = MediaQuery.of(context);
    final a11y = mq.highContrast || mq.disableAnimations;
    final img = backgroundImage(look.background);
    Widget tile(NvGlassStyle st) {
      final on = look.glassStyle == st;
      return Semantics(
        button: true,
        selected: on,
        label: 'Gaya kaca ${st.label}',
        child: GestureDetector(
          key: ValueKey('glass-style-${st.name}'),
          onTap: () {
            HapticFeedback.selectionClick();
            look.setGlassStyle(st);
          },
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64,
              height: 64,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: on ? NV.text : NV.border, width: on ? 2 : 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Stack(fit: StackFit.expand, children: [
                  // live preview over the current wallpaper (or an accent wash)
                  if (img != null)
                    Image(image: img, fit: BoxFit.cover, filterQuality: FilterQuality.low)
                  else
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [NV.red, NV.bg]),
                      ),
                    ),
                  Center(
                    child: SizedBox(
                      width: 44,
                      height: 24,
                      child: NvGlass(
                        key: ValueKey('glass-preview-${st.name}'),
                        style: st,
                        radius: 12,
                        tint: st == NvGlassStyle.reguler ? NV.navGlass : null,
                        child: Center(child: Container(width: 14, height: 4, decoration: BoxDecoration(color: NV.text, borderRadius: BorderRadius.circular(2)))),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 4),
            Text(st.label, style: NV.monoLabel(size: 8.5, color: on ? NV.text : NV.muted)),
          ]),
        ),
      );
    }

    return NvPanel(
      key: const ValueKey('glass-style-panel'),
      margin: margin,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('GAYA KACA', style: NV.monoLabel(size: 10)),
          const Spacer(),
          Text(look.glassStyle.label, key: const ValueKey('glass-style-current'), style: NV.code(size: 11, color: NV.text)),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: [for (final st in _effects) tile(st)]),
        const SizedBox(height: 14),
        Text('AKSESIBILITAS', style: NV.monoLabel(size: 9.5, color: NV.faint)),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          tile(NvGlassStyle.tanpa),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              a11y && look.glassStyle != NvGlassStyle.tanpa
                  ? 'Kontras tinggi / kurangi gerakan aktif di HP ini. Disarankan: Tanpa efek (permukaan solid, tanpa blur).'
                  : 'Permukaan solid tanpa blur atau transparansi — paling mudah dibaca.',
              key: const ValueKey('glass-style-a11y-note'),
              style: TextStyle(fontFamily: NV.sans, fontSize: 12.5, height: 1.35, color: NV.muted),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// "Warna dari wallpaper": accent from the background image + suggestions.
class WallpaperColorsPanel extends ConsumerWidget {
  const WallpaperColorsPanel({super.key, this.margin = const EdgeInsets.symmetric(horizontal: 16)});
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = ref.watch(appearanceProvider);
    final on = look.background.active;
    return NvPanel(
      key: const ValueKey('wallpaper-colors-panel'),
      margin: margin,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SwitchListTile.adaptive(
          key: const ValueKey('wallpaper-colors'),
          contentPadding: EdgeInsets.zero,
          secondary: Icon(CupertinoIcons.paintbrush, color: NV.muted),
          title: Text('Warna dari wallpaper', style: TextStyle(fontFamily: NV.sans, fontSize: 15, color: NV.text)),
          subtitle: Text(on ? 'Aksen dan kaca mengikuti warna latar belakang' : 'Pilih latar belakang dulu',
              style: TextStyle(fontFamily: NV.sans, fontSize: 12.5, color: NV.muted)),
          value: look.wallpaperColors,
          onChanged: on ? (v) => look.setWallpaperColors(v) : null,
        ),
        if (on && look.wallpaperSwatches.isNotEmpty) ...[
          Text('SARAN DARI WALLPAPER', style: NV.monoLabel(size: 9.5, color: NV.faint)),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final c in look.wallpaperSwatches)
              Semantics(
                button: true,
                selected: look.accent.toARGB32() == c.toARGB32(),
                label: 'Warna ${hexOf(c)}',
                child: GestureDetector(
                  key: ValueKey('wallpaper-swatch-${hexOf(c)}'),
                  onTap: () => look.pickWallpaperSwatch(c),
                  child: Container(
                    width: 36,
                    height: 36,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: look.accent.toARGB32() == c.toARGB32() ? NV.text : NV.border, width: 2),
                    ),
                    child: DecoratedBox(decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                  ),
                ),
              ),
          ]),
        ],
      ]),
    );
  }
}
