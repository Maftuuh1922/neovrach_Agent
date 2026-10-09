// The redesigned "Tampilan" section: separate liquid glass cards (Tema,
// Warna aksen, Kelengkungan sudut, Latar belakang) on a 4-pt rhythm, whose
// fill is solved per wallpaper so every label stays ≥ 4.5:1. Drop-in body
// for `AppearancePanel` (remote_pc_screen.dart).
import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../theme/neovarch_mobile_theme.dart';
import '../../appearance.dart';
import '../remote_background.dart' show artTintFor, backgroundImage;
import 'accent_picker.dart';
import 'corner_radius.dart';
import 'corner_radius_section.dart';
import 'glass_segmented.dart';
import 'glass_surfaces.dart';
import 'panel_tone.dart';

/// Resolves the [NvPanelTone] for the current wallpaper (analysed once per
/// source, then cached) and provides it to [child].
class NvPanelToneHost extends ConsumerStatefulWidget {
  const NvPanelToneHost({super.key, required this.child, this.debugImage});
  final Widget child;
  /// Tests / screenshots: analyse this image instead of the configured one.
  final ImageProvider? debugImage;
  @override
  ConsumerState<NvPanelToneHost> createState() => _NvPanelToneHostState();
}

class _NvPanelToneHostState extends ConsumerState<NvPanelToneHost> {
  @override
  Widget build(BuildContext context) {
    final look = ref.watch(appearanceProvider);
    final b = look.background;
    return ValueListenableBuilder<int>(
      valueListenable: WallpaperAnalyzer.instance.revision,
      builder: (context, _, _) => ValueListenableBuilder<bool>(
        valueListenable: NvGlassFx.reduceTransparency,
        builder: (context, _, _) {
          WallpaperStats backdrop = WallpaperStats.flat(NV.bg);
          if (b.active) {
            final key = widget.debugImage != null ? 'debug:${b.source}' : b.source;
            final img = widget.debugImage ?? backgroundImage(b);
            final raw = WallpaperAnalyzer.instance.cached(key) ?? (img == null ? null : WallpaperAnalyzer.instance.peek(key, img));
            if (raw != null) {
              backdrop = raw.through(b, bg: NV.bg, accent: NV.red);
            } else {
              if (img != null) WallpaperAnalyzer.instance.analyze(key, img);
              // until analysed: assume the worst (pure black and white)
              backdrop = const WallpaperStats(dark: Color(0xFF000000), light: Color(0xFFFFFFFF), mean: Color(0xFF808080))
                  .through(b, bg: NV.bg, accent: NV.red);
            }
          }
          final tone = NvPanelTone.resolve(NV.palette, backdrop, reduced: NvGlassFx.reduced(context));
          return NvPanelToneScope(tone: tone, backdrop: backdrop, child: widget.child);
        },
      ),
    );
  }
}

class NvAppearanceSection extends ConsumerWidget {
  const NvAppearanceSection({super.key, this.showFollowPc = true, this.showBackground = true, this.showCorners = true, this.margin = const EdgeInsets.symmetric(horizontal: 16), this.picker, this.debugImage});
  final bool showFollowPc;
  final bool showBackground;
  final bool showCorners;
  final EdgeInsets margin;
  /// Gallery picker override (tests).
  final Future<String?> Function()? picker;
  final ImageProvider? debugImage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NvPanelToneHost(
      debugImage: debugImage,
      child: Padding(
        key: const ValueKey('appearance-panel'),
        padding: margin,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          _ThemeCard(showFollowPc: showFollowPc),
          const SizedBox(height: NvSpace.m),
          const _AccentCard(),
          if (showCorners) ...[const SizedBox(height: NvSpace.m), const NvCornerRadiusCard()],
          if (showBackground) ...[const SizedBox(height: NvSpace.m), NvBackgroundCard(picker: picker)],
        ]),
      ),
    );
  }
}

class _ThemeCard extends ConsumerWidget {
  const _ThemeCard({required this.showFollowPc});
  final bool showFollowPc;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = ref.watch(appearanceProvider);
    final tone = NvPanelToneScope.of(context);
    return NvGlassCard(
      icon: CupertinoIcons.circle_lefthalf_fill,
      title: 'Tema',
      caption: look.followPc ? 'Mengikuti PC · ${look.pcDark ? 'gelap' : 'terang'}' : 'Khusus HP ini',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (showFollowPc) ...[
          Semantics(
            toggled: look.followPc,
            child: GestureDetector(
              key: const ValueKey('follow-pc-row'),
              behavior: HitTestBehavior.opaque,
              onTap: () => look.setFollowPc(!look.followPc),
              child: Row(children: [
                Icon(CupertinoIcons.desktopcomputer, size: 20, color: tone.muted),
                const SizedBox(width: NvSpace.m),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Ikuti tema PC', style: TextStyle(fontFamily: NV.sans, fontSize: 15, fontWeight: FontWeight.w500, color: tone.text)),
                    const SizedBox(height: 2),
                    Text(look.followPc ? 'Warna ${hexOf(look.pcAccent)} · ${look.pcDark ? 'gelap' : 'terang'}' : 'Pakai tema khusus HP ini',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: NV.sans, fontSize: 12.5, color: tone.muted)),
                  ]),
                ),
                const SizedBox(width: NvSpace.m),
                NvGlassSwitch(key: const ValueKey('follow-pc-switch'), value: look.followPc, onChanged: look.setFollowPc),
              ]),
            ),
          ),
          Padding(padding: const EdgeInsets.symmetric(vertical: NvSpace.m), child: Container(height: 0.8, color: tone.hairline)),
        ],
        NvGlassSegmented<NvBrightnessMode>(
          key: const ValueKey('theme-mode'),
          segments: const [
            NvSegment(NvBrightnessMode.dark, 'Gelap', icon: CupertinoIcons.moon_fill),
            NvSegment(NvBrightnessMode.light, 'Terang', icon: CupertinoIcons.sun_max_fill),
            NvSegment(NvBrightnessMode.system, 'Sistem', icon: CupertinoIcons.device_phone_portrait),
          ],
          selected: look.followPc ? (look.pcDark ? NvBrightnessMode.dark : NvBrightnessMode.light) : look.localMode,
          onChanged: (m) => look.setLocal(mode: m),
        ),
      ]),
    );
  }
}

class _AccentCard extends ConsumerWidget {
  const _AccentCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = ref.watch(appearanceProvider);
    final tone = NvPanelToneScope.of(context);
    // "Dari wallpaper": the suggestions from lib/remote/wallpaper_palette.dart
    // (the same extraction that drives "Warna dari wallpaper").
    final wall = look.background.active ? look.wallpaperSwatches : const <Color>[];
    return NvGlassCard(
      icon: CupertinoIcons.paintbrush_fill,
      title: 'Warna aksen',
      trailing: Text('${accentName(look.accent) ?? 'Kustom'} · ${hexOf(look.accent)}',
          key: const ValueKey('accent-current'), maxLines: 1, style: NV.code(size: 11.5, color: tone.muted)),
      child: NvAccentPicker(
          current: look.accent,
          wallpaper: wall,
          // a wallpaper suggestion keeps "Warna dari wallpaper" on; any other pick turns it off
          onPick: (c) => wall.any((w) => w.toARGB32() == c.toARGB32()) ? look.pickWallpaperSwatch(c) : look.setLocal(accent: c)),
    );
  }
}

/// "Latar belakang": thumbnails (radius follows the user's corner setting),
/// glass sliders, and a subtle "Reset" chip.
class NvBackgroundCard extends ConsumerStatefulWidget {
  const NvBackgroundCard({super.key, this.picker});
  final Future<String?> Function()? picker;
  @override
  ConsumerState<NvBackgroundCard> createState() => _NvBackgroundCardState();
}

class _NvBackgroundCardState extends ConsumerState<NvBackgroundCard> {
  bool _busy = false;

  Future<String?> _pickFromGallery() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, maxHeight: 2400, imageQuality: 90);
    if (x == null) return null;
    final dir = await getApplicationDocumentsDirectory();
    final ext = x.path.contains('.') ? x.path.substring(x.path.lastIndexOf('.')) : '.jpg';
    final dest = File('${dir.path}/nv_background_${DateTime.now().millisecondsSinceEpoch}$ext');
    await File(x.path).copy(dest.path);
    return dest.path;
  }

  Future<void> _gallery(AppearanceController look) async {
    setState(() => _busy = true);
    try {
      final path = await (widget.picker ?? _pickFromGallery)();
      if (path == null || !mounted) return;
      final old = look.background;
      look.setBackground(old.copyWith(source: 'file:$path'));
      if (old.isFile && old.path != path) {
        try {
          File(old.path).deleteSync();
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Gagal memuat gambar: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final look = ref.watch(appearanceProvider);
    final tone = NvPanelToneScope.of(context);
    final radii = AppCornerRadius.of(context);
    final b = look.background;
    String pct(double v) => '${(v * 100).round()}%';
    final thumbR = radii.inner(radii.card, NvSpace.l).clamp(radii.card > 0 ? 4.0 : 0.0, 18.0);

    Widget slider(String key, String label, double value, double min, double max, String Function(double) fmt, ValueChanged<double> onChanged, {bool enabled = true}) =>
        Row(children: [
          SizedBox(
            width: 104,
            child: Text(label, style: TextStyle(fontFamily: NV.sans, fontSize: 14, fontWeight: FontWeight.w500, color: enabled ? tone.text : tone.muted)),
          ),
          Expanded(
            child: NvGlassSlider(key: ValueKey('bg-$key'), value: value.clamp(min, max), min: min, max: max, semanticLabel: label, onChanged: enabled ? onChanged : null),
          ),
          SizedBox(
            width: 44,
            child: Text(fmt(value), textAlign: TextAlign.right, style: NV.code(size: 12, color: tone.muted).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ]);

    Widget choice(String key, String label, bool selected, VoidCallback onTap, {ImageProvider? image, IconData? icon}) {
      final dur = nvMotion(context, 220);
      Widget pic = image != null
          ? (key.startsWith('preset') && artTintFor(NV.red) != null
              ? ColorFiltered(colorFilter: artTintFor(NV.red)!, child: Image(image: image, fit: BoxFit.cover))
              : Image(image: image, fit: BoxFit.cover, errorBuilder: (c, e, s) => const SizedBox()))
          : Center(child: Icon(icon, color: selected ? tone.text : tone.muted, size: 22));
      return Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          key: ValueKey('bg-choice-$key'),
          onTap: onTap,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: dur,
              curve: Curves.easeOutCubic,
              width: 68,
              height: 96,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(thumbR + 3),
                border: Border.all(color: selected ? NV.red : const Color(0x00000000), width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(thumbR),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: tone.track, border: Border.all(color: tone.hairline)),
                  child: SizedBox.expand(child: pic),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontFamily: NV.sans, fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? tone.text : tone.muted)),
          ]),
        ),
      );
    }

    return NvGlassCard(
      key: const ValueKey('background-section'),
      icon: CupertinoIcons.photo_fill_on_rectangle_fill,
      title: 'Latar belakang',
      bleed: true,
      trailing: NvGlassChip(
        key: const ValueKey('bg-reset'),
        label: 'Reset',
        icon: CupertinoIcons.arrow_counterclockwise,
        onPressed: b == const NvBackground() ? null : look.resetBackground,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 122,
          child: ListView(
            key: const ValueKey('bg-thumbs'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: NvSpace.l - 3),
            children: [
              choice('none', 'Polos', !b.active, () => look.setBackground(b.copyWith(source: '')), icon: CupertinoIcons.nosign),
              const SizedBox(width: NvSpace.s),
              choice('gallery', _busy ? 'Memuat…' : 'Galeri', b.isFile, _busy ? () {} : () => _gallery(look),
                  image: b.isFile ? backgroundImage(b) : null, icon: CupertinoIcons.photo_on_rectangle),
              for (final (name, asset) in backgroundPresets) ...[
                const SizedBox(width: NvSpace.s),
                choice('preset-$name', name, b.source == 'asset:$asset', () => look.setBackground(b.copyWith(source: 'asset:$asset')), image: AssetImage(asset)),
              ],
            ],
          ),
        ),
        const SizedBox(height: NvSpace.s),
        Padding(padding: const EdgeInsets.symmetric(horizontal: NvSpace.l), child: Column(children: [
        slider('blur', 'Blur', b.blur, 0, 30, (v) => v.round().toString(), (v) => look.setBackground(b.copyWith(blur: v)), enabled: b.active),
        slider('dim', 'Kegelapan', b.dim, 0, 0.8, pct, (v) => look.setBackground(b.copyWith(dim: v)), enabled: b.active),
        slider('tint', 'Tint aksen', b.tint, 0, 0.6, pct, (v) => look.setBackground(b.copyWith(tint: v)), enabled: b.active),
        slider('saturation', 'Saturasi', b.saturation, 0, 2, pct, (v) => look.setBackground(b.copyWith(saturation: v)), enabled: b.active),
        slider('glass', 'Kekuatan kaca', b.glass, 0, 40, (v) => v.round().toString(), (v) => look.setBackground(b.copyWith(glass: v))),
        ])),
      ]),
    );
  }
}
