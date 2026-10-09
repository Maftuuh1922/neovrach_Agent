// Adaptive liquid glass: reads the wallpaper (luminance extremes + a small
// harmonised palette), then solves the glass fill opacity so the theme's
// text AND secondary text stay ≥ 4.5:1 over the brightest and darkest part
// of the wallpaper. Everything is derived from the accent / wallpaper; no
// stock colours.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../../theme/neovarch_mobile_theme.dart';
import '../../appearance.dart';

// ---------------------------------------------------------------- colour math

double _lin(double v) => v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
double _gam(double v) => v <= 0.0031308 ? 12.92 * v : 1.055 * math.pow(v, 1 / 2.4) - 0.055;

/// WCAG relative luminance.
double relLuminance(Color c) => 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

/// WCAG contrast ratio (1–21).
double contrastRatio(Color a, Color b) {
  final la = relLuminance(a), lb = relLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// OKLCH (L 0–1, C ~0–0.37, h degrees).
@immutable
class Oklch {
  const Oklch(this.l, this.c, this.h);
  final double l, c, h;

  factory Oklch.fromColor(Color col) {
    final r = _lin(col.r), g = _lin(col.g), b = _lin(col.b);
    final l = math.pow(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 1 / 3).toDouble();
    final m = math.pow(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 1 / 3).toDouble();
    final s = math.pow(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 1 / 3).toDouble();
    final ll = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
    final aa = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
    final bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
    final c = math.sqrt(aa * aa + bb * bb);
    var h = math.atan2(bb, aa) * 180 / math.pi;
    if (h < 0) h += 360;
    return Oklch(ll, c, h);
  }

  Color toColor() {
    // Reduce chroma until the colour fits sRGB (keeps hue + lightness).
    var c = this.c;
    for (var i = 0; i < 24; i++) {
      final rgb = _toLinear(l, c, h);
      if (rgb.every((v) => v >= -0.0005 && v <= 1.0005)) break;
      c *= 0.92;
    }
    final rgb = _toLinear(l, c, h);
    int ch(double v) => (_gam(v.clamp(0.0, 1.0)) * 255).round().clamp(0, 255);
    return Color.fromARGB(255, ch(rgb[0]), ch(rgb[1]), ch(rgb[2]));
  }

  static List<double> _toLinear(double l, double c, double h) {
    final a = c * math.cos(h * math.pi / 180), b = c * math.sin(h * math.pi / 180);
    final l_ = l + 0.3963377774 * a + 0.2158037573 * b;
    final m_ = l - 0.1055613458 * a - 0.0638541728 * b;
    final s_ = l - 0.0894841775 * a - 1.2914855480 * b;
    final ll = l_ * l_ * l_, mm = m_ * m_ * m_, ss = s_ * s_ * s_;
    return [
      4.0767416621 * ll - 3.3077115913 * mm + 0.2309699292 * ss,
      -1.2684380046 * ll + 2.6097574011 * mm - 0.3413193965 * ss,
      -0.0041960863 * ll - 0.7034186147 * mm + 1.7076147010 * ss,
    ];
  }
}

/// Pulls any colour into the curated accent band (same lightness / chroma
/// range as [nvAccentSwatches]) so wallpaper colours harmonise with them.
Color harmonizeAccent(Color c) {
  final o = Oklch.fromColor(c);
  if (o.c < 0.03) return Oklch(0.62, 0.012, o.h).toColor(); // near-grey: graphite
  return Oklch(o.l.clamp(0.60, 0.70).toDouble(), o.c.clamp(0.08, 0.15).toDouble(), o.h).toColor();
}

// ------------------------------------------------------------ wallpaper stats

/// What the glass sits on: luminance extremes and a few palette colours.
@immutable
class WallpaperStats {
  const WallpaperStats({required this.dark, required this.light, required this.mean, this.palette = const []});
  /// ~5th / 95th percentile colours (by luminance), mean colour.
  final Color dark, light, mean;
  /// Up to five distinct, harmonised accent candidates.
  final List<Color> palette;

  /// Flat background (no wallpaper).
  factory WallpaperStats.flat(Color bg) => WallpaperStats(dark: bg, light: bg, mean: bg);

  /// Stats as seen through the app background's tint + dim overlays.
  WallpaperStats through(NvBackground b, {required Color bg, required Color accent}) {
    Color fx(Color c) {
      var o = c;
      if (b.tint > 0) o = Color.alphaBlend(accent.withValues(alpha: b.tint), o);
      if (b.dim > 0) o = Color.alphaBlend(bg.withValues(alpha: b.dim), o);
      return o;
    }

    return WallpaperStats(dark: fx(dark), light: fx(light), mean: fx(mean), palette: palette);
  }

  double get meanLuminance => relLuminance(mean);
}

/// Computes [WallpaperStats] from raw RGBA pixels (pure; unit-testable).
WallpaperStats statsFromRgba(Uint8List rgba) {
  final n = rgba.length ~/ 4;
  if (n == 0) return WallpaperStats.flat(const Color(0xFF000000));
  final cols = <Color>[];
  final lums = <double>[];
  var sr = 0.0, sg = 0.0, sb = 0.0;
  // hue buckets (12) weighted by chroma, for the palette
  final wt = List<double>.filled(12, 0);
  final acc = List.generate(12, (_) => [0.0, 0.0, 0.0]);
  for (var i = 0; i < n; i++) {
    final c = Color.fromARGB(255, rgba[i * 4], rgba[i * 4 + 1], rgba[i * 4 + 2]);
    cols.add(c);
    lums.add(relLuminance(c));
    sr += c.r;
    sg += c.g;
    sb += c.b;
    final o = Oklch.fromColor(c);
    if (o.c > 0.04 && o.l > 0.2 && o.l < 0.95) {
      final k = (o.h / 30).floor() % 12;
      final w = o.c;
      wt[k] += w;
      acc[k][0] += c.r * w;
      acc[k][1] += c.g * w;
      acc[k][2] += c.b * w;
    }
  }
  final idx = List.generate(n, (i) => i)..sort((a, b) => lums[a].compareTo(lums[b]));
  final lo = cols[idx[(n * 0.05).floor().clamp(0, n - 1)]];
  final hi = cols[idx[(n * 0.95).floor().clamp(0, n - 1)]];
  final mean = Color.from(alpha: 1, red: sr / n, green: sg / n, blue: sb / n);
  final order = List.generate(12, (i) => i)..sort((a, b) => wt[b].compareTo(wt[a]));
  final total = wt.fold<double>(0, (a, b) => a + b);
  final pal = <Color>[];
  for (final k in order) {
    if (wt[k] <= 0 || (total > 0 && wt[k] / total < 0.04) || pal.length >= 5) continue;
    final c = Color.from(alpha: 1, red: acc[k][0] / wt[k], green: acc[k][1] / wt[k], blue: acc[k][2] / wt[k]);
    final h = harmonizeAccent(c);
    final ho = Oklch.fromColor(h);
    final close = pal.any((p) {
      final d = (Oklch.fromColor(p).h - ho.h).abs();
      return math.min(d, 360 - d) < 18;
    });
    if (!close) pal.add(h);
  }
  if (pal.isEmpty) pal.add(harmonizeAccent(mean));
  return WallpaperStats(dark: lo, light: hi, mean: mean, palette: pal);
}

/// Decodes a wallpaper at 40×40 and caches its stats per source.
class WallpaperAnalyzer {
  WallpaperAnalyzer._();
  static final instance = WallpaperAnalyzer._();

  final _cache = <String, WallpaperStats>{};
  final _pending = <String, Future<WallpaperStats?>>{};

  /// Bumped when an analysis finishes (listen to rebuild).
  final revision = ValueNotifier<int>(0);

  WallpaperStats? cached(String key) => _cache[key];

  /// Tests / screenshots: inject stats for [key].
  void debugPut(String key, WallpaperStats s) {
    _cache[key] = s;
    revision.value++;
  }

  void debugClear() {
    _cache.clear();
    _pending.clear();
  }

  Future<WallpaperStats?> analyze(String key, ImageProvider provider) {
    final hit = _cache[key];
    if (hit != null) return Future.value(hit);
    return _pending[key] ??= _run(key, provider);
  }

  Future<WallpaperStats?> _run(String key, ImageProvider provider) async {
    try {
      final img = await _decode(ResizeImage(provider, width: 40, height: 40, policy: ResizeImagePolicy.exact));
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      if (data == null) return null;
      final s = statsFromRgba(data.buffer.asUint8List());
      _cache[key] = s;
      revision.value++;
      return s;
    } catch (_) {
      return null;
    } finally {
      _pending.remove(key);
    }
  }

  static Future<ui.Image> _decode(ImageProvider p) {
    final done = Completer<ui.Image>();
    final stream = p.resolve(ImageConfiguration.empty);
    late ImageStreamListener l;
    l = ImageStreamListener((info, _) {
      if (!done.isCompleted) done.complete(info.image.clone());
      info.dispose();
      stream.removeListener(l);
    }, onError: (e, s) {
      if (!done.isCompleted) done.completeError(e, s);
      stream.removeListener(l);
    });
    stream.addListener(l);
    return done.future;
  }
}

// ------------------------------------------------------------------ glass tone

/// Accessibility switches for the glass. [reduceTransparency] is meant to be
/// bound to the app's "tanpa efek" glass style; the platform high-contrast
/// flag also turns it on.
abstract final class NvGlassFx {
  static final reduceTransparency = ValueNotifier<bool>(false);

  static bool reduced(BuildContext context) =>
      reduceTransparency.value || (MediaQuery.maybeHighContrastOf(context) ?? false);

  static bool reducedMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Resolved colours for glass over the current backdrop.
@immutable
class GlassTone {
  const GlassTone({
    required this.fill,
    required this.fillAlpha,
    required this.text,
    required this.muted,
    required this.hairline,
    required this.rim,
    required this.track,
    required this.lens,
    required this.reduced,
    required this.dark,
  });

  /// Glass fill (already carries [fillAlpha]).
  final Color fill;
  final double fillAlpha;
  final Color text, muted, hairline, rim;
  /// Inactive slider / switch track and pressed wash.
  final Color track;
  /// Selection lens fill (segmented control, presets).
  final Color lens;
  final bool reduced;
  final bool dark;

  /// Solves the smallest fill opacity that keeps [NvPalette.text] and
  /// [NvPalette.muted] ≥ [minContrast] over both wallpaper extremes. With
  /// [reduced] the glass is opaque.
  factory GlassTone.resolve(NvPalette p, WallpaperStats backdrop, {bool reduced = false, double minContrast = 4.6}) {
    final base = Color.lerp(p.surface, p.accent, p.dark ? 0.08 : 0.04)!;
    // The backdrop filter lifts saturation/brightness a bit: be conservative.
    final lightest = Color.lerp(backdrop.light, const Color(0xFFFFFFFF), 0.08)!;
    final darkest = Color.lerp(backdrop.dark, const Color(0xFF000000), 0.08)!;
    var a = p.dark ? 0.42 : 0.50;
    if (reduced) {
      a = 1;
    } else {
      bool ok(double a) {
        for (final b in [lightest, darkest]) {
          final seen = Color.alphaBlend(base.withValues(alpha: a), b);
          if (contrastRatio(p.text, seen) < minContrast || contrastRatio(p.muted, seen) < minContrast) return false;
        }
        return true;
      }

      while (a < 0.96 && !ok(a)) {
        a += 0.02;
      }
    }
    return GlassTone(
      fill: base.withValues(alpha: a),
      fillAlpha: a,
      text: p.text,
      muted: p.muted,
      hairline: p.text.withValues(alpha: p.dark ? 0.12 : 0.10),
      rim: const Color(0xFFFFFFFF).withValues(alpha: reduced ? 0 : (p.dark ? 0.34 : 0.9)),
      track: p.text.withValues(alpha: p.dark ? 0.14 : 0.10),
      lens: Color.lerp(const Color(0xFFFFFFFF), p.accent, p.dark ? 0.30 : 0.08)!.withValues(alpha: p.dark ? 0.16 : 0.72),
      reduced: reduced,
      dark: p.dark,
    );
  }

  /// Contrast of [fg] over this glass on the worst backdrop extreme.
  double worstContrast(Color fg, WallpaperStats backdrop) {
    var worst = 21.0;
    for (final b in [backdrop.light, backdrop.dark]) {
      worst = math.min(worst, contrastRatio(fg, Color.alphaBlend(fill, b)));
    }
    return worst;
  }
}

/// Provides the resolved [GlassTone] (and the backdrop it was solved for).
class GlassToneScope extends InheritedWidget {
  const GlassToneScope({super.key, required this.tone, required this.backdrop, required super.child});
  final GlassTone tone;
  final WallpaperStats backdrop;

  static GlassToneScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GlassToneScope>();

  /// Tone in scope, or one solved for the flat theme background.
  static GlassTone of(BuildContext context) =>
      maybeOf(context)?.tone ?? GlassTone.resolve(NV.palette, WallpaperStats.flat(NV.bg), reduced: NvGlassFx.reduced(context));

  @override
  bool updateShouldNotify(GlassToneScope old) =>
      old.tone.fill != tone.fill || old.tone.text != tone.text || old.tone.reduced != tone.reduced || old.backdrop != backdrop;
}
