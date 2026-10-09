// 1.4.2: custom app background behind the shell tabs (so the liquid glass
// has something to refract), its controls in Tampilan, the "Tampilan" sheet
// reachable before pairing, and the accent tint for the red slide artwork.
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../theme/neovarch_mobile_theme.dart';
import '../appearance.dart';
import 'app_icon_panel.dart';
import 'glass_style_picker.dart';
import 'nv_widgets.dart';
import 'remote_pc_screen.dart' show AppearancePanel;

/// Saturation colour matrix (Rec. 709 luma weights).
List<double> saturationMatrix(double s) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final a = 1 - s;
  return <double>[
    lr * a + s, lg * a, lb * a, 0, 0, //
    lr * a, lg * a + s, lb * a, 0, 0, //
    lr * a, lg * a, lb * a + s, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

/// Recolours the red Neovarch artwork to [accent]: per channel
/// `out = R·a + G·(1−a)`, so red ink becomes the accent while neutral
/// highlights (R≈G≈B) stay neutral. Null for the default red (art unchanged).
List<double>? artTintMatrix(Color accent) {
  if (accent.toARGB32() == NvPalette.defaultAccent.toARGB32()) return null;
  final r = accent.r, g = accent.g, b = accent.b;
  return <double>[
    r, 1 - r, 0, 0, 0, //
    g, 1 - g, 0, 0, 0, //
    b, 1 - b, 0, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

ColorFilter? artTintFor(Color accent) {
  final m = artTintMatrix(accent);
  return m == null ? null : ColorFilter.matrix(m);
}

/// Art image tinted to the current accent (unchanged in Merah).
class NvAccentArt extends StatelessWidget {
  const NvAccentArt(this.asset, {super.key, this.alignment = Alignment.center});
  final String asset;
  final Alignment alignment;
  @override
  Widget build(BuildContext context) {
    final img = Image.asset(asset, fit: BoxFit.cover, alignment: alignment, filterQuality: FilterQuality.medium);
    final f = artTintFor(NV.red);
    return f == null ? img : ColorFiltered(key: const ValueKey('nv-art-tint'), colorFilter: f, child: img);
  }
}

ImageProvider? backgroundImage(NvBackground b) {
  if (!b.active) return null;
  if (b.isAsset) return AssetImage(b.path);
  if (b.isFile) {
    final f = File(b.path);
    return f.existsSync() ? FileImage(f) : null;
  }
  return null;
}

/// Full-bleed background: image (blur + saturation), accent tint and a dim
/// layer of the theme background so text on top stays readable.
class NvAppBackground extends ConsumerWidget {
  const NvAppBackground({super.key, this.debugImage});
  /// Tests/screenshots: use this image instead of the configured one.
  final ImageProvider? debugImage;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(appearanceProvider).background;
    final img = debugImage ?? backgroundImage(b);
    if (img == null) return const SizedBox.shrink();
    Widget pic = Image(image: img, fit: BoxFit.cover, filterQuality: FilterQuality.medium, gaplessPlayback: true,
        errorBuilder: (context, e, s) => const SizedBox.shrink());
    if (b.isAsset) {
      final f = artTintFor(NV.red);
      if (f != null) pic = ColorFiltered(colorFilter: f, child: pic);
    }
    if (b.saturation != 1.0) pic = ColorFiltered(colorFilter: ColorFilter.matrix(saturationMatrix(b.saturation)), child: pic);
    if (b.blur > 0) {
      pic = ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: b.blur, sigmaY: b.blur, tileMode: TileMode.mirror), child: pic);
    }
    return IgnorePointer(
      child: Stack(key: const ValueKey('nv-app-background'), fit: StackFit.expand, children: [
        ColoredBox(color: NV.bg),
        ClipRect(child: pic),
        if (b.tint > 0) ColoredBox(color: NV.red.withValues(alpha: b.tint)),
        // light mode: at least a light veil, so dark text over a dark photo stays readable
        if (b.dim > 0 || !NV.palette.dark)
          ColoredBox(color: NV.bg.withValues(alpha: NV.palette.dark ? b.dim : (b.dim > NV.lightWallpaperVeil ? b.dim : NV.lightWallpaperVeil))),
      ]),
    );
  }
}

/// "Tampilan" bottom sheet (theme + background), e.g. from the connect
/// screen before any PC is paired.
Future<void> showAppearanceSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (context, sc) => ListView(
          key: const ValueKey('appearance-sheet'),
          controller: sc,
          padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
          children: const [
            Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 14), child: NvSheetTitle(kicker: 'hp ini', title: 'Tampilan')),
            AppearancePanel(),
            SizedBox(height: 12),
            WallpaperColorsPanel(),
            NvSection('gaya kaca'),
            GlassStylePicker(),
            NvSection('ikon aplikasi'),
            AppIconPanel(),
          ],
        ),
      ),
    );

/// "Latar belakang" controls inside [AppearancePanel].
class BackgroundSection extends ConsumerStatefulWidget {
  const BackgroundSection({super.key, this.picker});
  /// Override for tests (returns a picked file path or null).
  final Future<String?> Function()? picker;
  @override
  ConsumerState<BackgroundSection> createState() => _BackgroundSectionState();
}

class _BackgroundSectionState extends ConsumerState<BackgroundSection> {
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
      // Drop the previous copied image.
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

  Widget _slider(String key, String label, double value, double min, double max, String Function(double) fmt, ValueChanged<double> onChanged,
          {bool enabled = true}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 6, 0),
        child: Row(children: [
          SizedBox(width: 112, child: Text(label, style: TextStyle(fontSize: 14, color: enabled ? NV.text : NV.faint))),
          Expanded(
            child: Slider(
              key: ValueKey('bg-$key'),
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: enabled ? onChanged : null,
            ),
          ),
          SizedBox(width: 44, child: Text(fmt(value), textAlign: TextAlign.right, style: NV.code(size: 11.5, color: NV.muted))),
        ]),
      );

  Widget _choice(String key, String label, bool selected, VoidCallback onTap, {ImageProvider? image, IconData? icon}) => Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          key: ValueKey('bg-choice-$key'),
          onTap: onTap,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64,
              height: 88,
              decoration: BoxDecoration(
                color: NV.raised,
                borderRadius: BorderRadius.circular(NV.rCtl),
                border: Border.all(color: selected ? NV.red : NV.border, width: selected ? 2 : 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: image != null
                  ? (key.startsWith('preset') && artTintFor(NV.red) != null
                      ? ColorFiltered(colorFilter: artTintFor(NV.red)!, child: Image(image: image, fit: BoxFit.cover))
                      : Image(image: image, fit: BoxFit.cover, errorBuilder: (c, e, s) => const SizedBox()))
                  : Icon(icon, color: selected ? NV.red : NV.muted, size: 22),
            ),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 12, color: selected ? NV.text : NV.muted)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final look = ref.watch(appearanceProvider);
    final b = look.background;
    String pct(double v) => '${(v * 100).round()}%';
    return Column(key: const ValueKey('background-section'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Divider(height: 1, color: NV.border),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 6, 4),
        child: Row(children: [
          Expanded(child: Text('LATAR BELAKANG', style: NV.monoLabel(size: 10))),
          TextButton.icon(
            key: const ValueKey('bg-reset'),
            onPressed: b == const NvBackground() ? null : look.resetBackground,
            icon: const Icon(CupertinoIcons.arrow_counterclockwise, size: 16),
            label: const Text('Reset'),
          ),
        ]),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
        child: Row(children: [
          _choice('none', 'Polos', !b.active, () => look.setBackground(b.copyWith(source: '')), icon: CupertinoIcons.nosign),
          const SizedBox(width: 10),
          _choice('gallery', _busy ? 'Memuat…' : 'Galeri', b.isFile, _busy ? () {} : () => _gallery(look),
              image: b.isFile ? backgroundImage(b) : null, icon: CupertinoIcons.photo_on_rectangle),
          for (final (name, asset) in backgroundPresets) ...[
            const SizedBox(width: 10),
            _choice('preset-$name', name, b.source == 'asset:$asset', () => look.setBackground(b.copyWith(source: 'asset:$asset')),
                image: AssetImage(asset)),
          ],
        ]),
      ),
      _slider('blur', 'Blur', b.blur, 0, 30, (v) => v.round().toString(), (v) => look.setBackground(b.copyWith(blur: v)), enabled: b.active),
      _slider('dim', 'Kegelapan', b.dim, 0, 0.8, pct, (v) => look.setBackground(b.copyWith(dim: v)), enabled: b.active),
      _slider('tint', 'Tint aksen', b.tint, 0, 0.6, pct, (v) => look.setBackground(b.copyWith(tint: v)), enabled: b.active),
      _slider('saturation', 'Saturasi', b.saturation, 0, 2, pct, (v) => look.setBackground(b.copyWith(saturation: v)), enabled: b.active),
      _slider('glass', 'Kekuatan kaca', b.glass, 0, 40, (v) => v.round().toString(), (v) => look.setBackground(b.copyWith(glass: v))),
      const SizedBox(height: 10),
    ]);
  }
}
