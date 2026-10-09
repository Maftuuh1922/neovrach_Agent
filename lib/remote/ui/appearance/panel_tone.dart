// Adaptive glass for the Tampilan cards: reads the wallpaper's luminance
// extremes from the chat glass's shared luminance grid
// (glass/backdrop_luminance.dart), then solves one fill opacity per section
// so the theme's text AND secondary text stay ≥ 4.5:1 over the brightest and
// darkest part of the wallpaper. Per-element chat tones (light/dark text,
// roles) stay in glass/glass_tone.dart; WCAG maths is shared from there.
// Wallpaper accent suggestions come from lib/remote/wallpaper_palette.dart.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../../theme/neovarch_mobile_theme.dart';
import '../../appearance.dart';
import '../glass/backdrop_luminance.dart' show GlassBackdropMap, LuminanceGrid, cachedLuminanceGrid, loadLuminanceGrid;
import '../glass/glass_tone.dart' show contrastRatio, relativeLuminance;

export '../glass/glass_tone.dart' show contrastRatio, relativeLuminance;

// ---------------------------------------------------------------- colour math
//
// WCAG luminance / contrast are the chat-glass ones (glass/glass_tone.dart);
// re-exported so the appearance UI and the chat share one implementation.

double _lin(double v) => v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
double _gam(double v) => v <= 0.0031308 ? 12.92 * v : 1.055 * math.pow(v, 1 / 2.4) - 0.055;

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

// ------------------------------------------------------------ wallpaper stats

/// What the glass sits on: luminance extremes and the mean colour. The
/// wallpaper's accent suggestions are not computed here: they come from
/// lib/remote/wallpaper_palette.dart (AppearanceController.wallpaperSwatches).
@immutable
class WallpaperStats {
  const WallpaperStats({required this.dark, required this.light, required this.mean});
  /// ~5th / 95th percentile colours (by luminance), mean colour.
  final Color dark, light, mean;

  /// Flat background (no wallpaper).
  factory WallpaperStats.flat(Color bg) => WallpaperStats(dark: bg, light: bg, mean: bg);

  /// Stats as seen through the app background's art tint, saturation,
  /// accent tint and dim: the same pipeline the chat glass's backdrop map
  /// applies ([GlassBackdropMap.image]).
  WallpaperStats through(NvBackground b, {required Color bg, required Color accent}) {
    Color fx(Color c) => GlassBackdropMap.image(LuminanceGrid.solid(c),
            screen: const Size(1, 1), base: bg, accent: accent, tint: b.tint, dim: b.dim, saturation: b.saturation, isAsset: b.isAsset)
        .grid!
        .cells
        .first;

    return WallpaperStats(dark: fx(dark), light: fx(light), mean: fx(mean));
  }

  double get meanLuminance => relativeLuminance(mean);

  @override
  bool operator ==(Object other) => other is WallpaperStats && other.dark == dark && other.light == light && other.mean == mean;
  @override
  int get hashCode => Object.hash(dark, light, mean);
}

/// Stats from a list of colours (pure; unit-testable).
WallpaperStats statsFromColors(List<Color> cols) {
  final n = cols.length;
  if (n == 0) return WallpaperStats.flat(const Color(0xFF000000));
  final lums = [for (final c in cols) relativeLuminance(c)];
  var sr = 0.0, sg = 0.0, sb = 0.0;
  for (final c in cols) {
    sr += c.r;
    sg += c.g;
    sb += c.b;
  }
  final idx = List.generate(n, (i) => i)..sort((a, b) => lums[a].compareTo(lums[b]));
  final lo = cols[idx[(n * 0.05).floor().clamp(0, n - 1)]];
  final hi = cols[idx[(n * 0.95).floor().clamp(0, n - 1)]];
  final mean = Color.from(alpha: 1, red: sr / n, green: sg / n, blue: sb / n);
  return WallpaperStats(dark: lo, light: hi, mean: mean);
}

/// Stats from raw RGBA pixels.
WallpaperStats statsFromRgba(Uint8List rgba) =>
    statsFromColors([for (var i = 0; i + 3 < rgba.length; i += 4) Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2])]);

/// Stats from the chat glass's backdrop luminance grid (one decode of the
/// wallpaper shared by the chat glass and the appearance cards).
WallpaperStats statsFromGrid(LuminanceGrid g) => statsFromColors(g.cells);

/// Wallpaper stats per source, read from the shared luminance grid
/// (glass/backdrop_luminance.dart; decoded once, cached by image).
class WallpaperAnalyzer {
  WallpaperAnalyzer._();
  static final instance = WallpaperAnalyzer._();

  final _cache = <String, WallpaperStats>{};
  final _pending = <String, Future<WallpaperStats?>>{};

  /// Bumped when an analysis finishes (listen to rebuild).
  final revision = ValueNotifier<int>(0);

  WallpaperStats? cached(String key) => _cache[key];

  /// Stats for [provider] if its grid is already decoded (no async work).
  WallpaperStats? peek(String key, ImageProvider provider) {
    final hit = _cache[key];
    if (hit != null) return hit;
    final g = cachedLuminanceGrid(provider);
    if (g == null) return null;
    return _cache[key] = statsFromGrid(g);
  }

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
    final hit = peek(key, provider);
    if (hit != null) return Future.value(hit);
    return _pending[key] ??= _run(key, provider);
  }

  Future<WallpaperStats?> _run(String key, ImageProvider provider) async {
    try {
      final g = await loadLuminanceGrid(provider);
      if (g == null) return null;
      final s = statsFromGrid(g);
      _cache[key] = s;
      revision.value++;
      return s;
    } catch (_) {
      return null;
    } finally {
      _pending.remove(key);
    }
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
class NvPanelTone {
  const NvPanelTone({
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
  factory NvPanelTone.resolve(NvPalette p, WallpaperStats backdrop, {bool reduced = false, double minContrast = 4.6}) {
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
    return NvPanelTone(
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

/// Provides the resolved [NvPanelTone] (and the backdrop it was solved for).
class NvPanelToneScope extends InheritedWidget {
  const NvPanelToneScope({super.key, required this.tone, required this.backdrop, required super.child});
  final NvPanelTone tone;
  final WallpaperStats backdrop;

  static NvPanelToneScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<NvPanelToneScope>();

  /// Tone in scope, or one solved for the flat theme background.
  static NvPanelTone of(BuildContext context) =>
      maybeOf(context)?.tone ?? NvPanelTone.resolve(NV.palette, WallpaperStats.flat(NV.bg), reduced: NvGlassFx.reduced(context));

  @override
  bool updateShouldNotify(NvPanelToneScope old) =>
      old.tone.fill != tone.fill || old.tone.text != tone.text || old.tone.reduced != tone.reduced || old.backdrop != backdrop;
}
