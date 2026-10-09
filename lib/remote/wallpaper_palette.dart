// 1.4.2: "Warna dari wallpaper" — Material You-style accent from the app
// background. The image is decoded downscaled (~128 px), quantised with
// QuantizerCelebi and ranked with Score in a background isolate; the best
// seed is re-toned for the current dark/light so it keeps its contrast, and
// 3–5 suggested swatches are kept for the picker. A greyscale image falls
// back to Monokrom.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// Monokrom accent preset (lib/remote/appearance.dart accentPresets).
const monochromeAccent = Color(0xFFA3A3A3);

@immutable
class WallpaperPalette {
  const WallpaperPalette(this.seed, this.swatches);
  final Color seed;
  final List<Color> swatches;
  bool get monochrome => seed.toARGB32() == monochromeAccent.toARGB32();
}

/// Minimum HCT chroma for a wallpaper colour to count as "a colour".
const _minChroma = 12.0;

/// Accent tone per brightness: light enough on dark surfaces, dark enough
/// on light ones (accent as text/icons stays readable).
Color _toned(Hct h, bool dark) => Color(Hct.from(h.hue, h.chroma.clamp(_minChroma, 84.0), dark ? 66 : 44).toInt());

/// Pure part (runs in an isolate): ARGB pixels → seed + swatches.
Future<WallpaperPalette> paletteFromPixels(List<int> argb, {bool dark = true}) async {
  final opaque = [for (final p in argb) if ((p >> 24) & 0xFF > 200) p | 0xFF000000];
  if (opaque.isEmpty) return const WallpaperPalette(monochromeAccent, [monochromeAccent]);
  final q = await QuantizerCelebi().quantize(opaque, 128);
  const none = 0x00000000;
  final ranked = Score.score(q.colorToCount, desired: 5, fallbackColorARGB: none, filter: true)
      .where((c) => c != none)
      .map(Hct.fromInt)
      .where((h) => h.chroma >= _minChroma)
      .toList();
  if (ranked.isEmpty) return const WallpaperPalette(monochromeAccent, [monochromeAccent]);
  final swatches = <Color>[];
  for (final h in ranked) {
    final c = _toned(h, dark);
    if (!swatches.any((s) => s.toARGB32() == c.toARGB32())) swatches.add(c);
  }
  if (swatches.length < 3) swatches.add(monochromeAccent);
  return WallpaperPalette(swatches.first, swatches.take(5).toList());
}

Future<WallpaperPalette> _isolateEntry((List<int>, bool) a) => paletteFromPixels(a.$1, dark: a.$2);

/// Decodes [image] at ~128 px and extracts the palette off the UI isolate.
Future<WallpaperPalette?> extractWallpaperPalette(ImageProvider image, {bool dark = true}) async {
  final px = await _pixels(ResizeImage(image, width: 128, policy: ResizeImagePolicy.fit));
  if (px == null) return null;
  return compute(_isolateEntry, (px, dark));
}

Future<List<int>?> _pixels(ImageProvider p) async {
  final done = Completer<ui.Image?>();
  final stream = p.resolve(ImageConfiguration.empty);
  late final ImageStreamListener l;
  l = ImageStreamListener((info, _) {
    if (!done.isCompleted) done.complete(info.image);
    stream.removeListener(l);
  }, onError: (e, s) {
    if (!done.isCompleted) done.complete(null);
    stream.removeListener(l);
  });
  stream.addListener(l);
  final img = await done.future.timeout(const Duration(seconds: 10), onTimeout: () => null);
  if (img == null) return null;
  final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bd == null) return null;
  final out = List<int>.filled(bd.lengthInBytes ~/ 4, 0);
  for (var i = 0; i < out.length; i++) {
    final r = bd.getUint8(i * 4), g = bd.getUint8(i * 4 + 1), b = bd.getUint8(i * 4 + 2), a = bd.getUint8(i * 4 + 3);
    out[i] = (a << 24) | (r << 16) | (g << 8) | b;
  }
  return out;
}

/// Image for a stored background source (`asset:` / `file:`), or null.
ImageProvider? imageForSource(String source) {
  if (source.startsWith('asset:')) return AssetImage(source.substring(6));
  if (source.startsWith('file:')) {
    final f = File(source.substring(5));
    return f.existsSync() ? FileImage(f) : null;
  }
  return null;
}
