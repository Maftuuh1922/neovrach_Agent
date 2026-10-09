// Colour maths for liquid glass legibility: WCAG contrast, the fill a glass
// needs over a given backdrop so its text reaches 4.5:1, accent harmony and
// the harmonized error red. Pure functions (no widgets) so they are unit
// testable and cheap to call on every scroll frame.
import 'dart:math' as math;

import 'dart:ui' show Brightness;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

import 'glass_style.dart';

/// WCAG relative luminance (0 = black, 1 = white).
double relativeLuminance(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

/// WCAG contrast ratio (1..21).
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a), lb = relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Minimum contrast for body text (WCAG AA).
const kGlassMinContrast = 4.5;

/// What the glass sits on: the blurred average colour under it and the
/// lightest / darkest local colours (cells) it covers.
@immutable
class BackdropSample {
  const BackdropSample({required this.mean, required this.lightest, required this.darkest});
  const BackdropSample.solid(Color c) : mean = c, lightest = c, darkest = c;
  final Color mean, lightest, darkest;

  double get luminance => relativeLuminance(mean);

  /// The backdrop blur averages cells, so the effective worst case is
  /// between the mean and the extreme.
  Color worstForLightText() => Color.lerp(mean, lightest, 0.5)!;
  Color worstForDarkText() => Color.lerp(mean, darkest, 0.5)!;

  @override
  bool operator ==(Object other) => other is BackdropSample && other.mean == mean && other.lightest == lightest && other.darkest == darkest;
  @override
  int get hashCode => Object.hash(mean, lightest, darkest);
}

/// What a glass surface is for; picks its tint.
enum GlassRole {
  /// Agent turns, cards, labels: neutral glass.
  neutral,

  /// The user's own message: accent-tinted glass.
  accent,

  /// Error cards / banners: neutral glass, only the icon is red.
  error,

  /// Code blocks: always a darker glass with light text.
  code,
}

const _darkBase = Color(0xFF1C1C1E); // iOS systemGray6 (dark)
const _lightBase = Color(0xFFF5F5F7);
const _lightText = Color(0xFFF7F7F9);
const _darkText = Color(0xFF111114);

/// The resolved look of one glass element over its backdrop.
@immutable
class GlassTone {
  const GlassTone({
    required this.lightText,
    required this.fill,
    required this.text,
    required this.secondary,
    required this.faint,
    required this.accent,
    required this.error,
    required this.rim,
    required this.composite,
    required this.contrast,
  });

  /// True = light text on a darker glass.
  final bool lightText;

  /// Glass fill (translucent) painted over the blurred backdrop.
  final Color fill;

  /// Body text, secondary (labels, timestamps), faint (hints).
  final Color text, secondary, faint;

  /// Accent adjusted to stay legible on this glass (links, buttons).
  final Color accent;

  /// Harmonized error red, legible on this glass (icons only).
  final Color error;

  /// Specular rim colour.
  final Color rim;

  /// Approximate final colour behind the text (fill over worst backdrop).
  final Color composite;

  /// Contrast of [secondary] over [composite] (body text is higher).
  final double contrast;

  Brightness get foregroundBrightness => lightText ? Brightness.dark : Brightness.light;

  @override
  bool operator ==(Object other) =>
      other is GlassTone &&
      other.lightText == lightText &&
      other.fill == fill &&
      other.text == text &&
      other.secondary == secondary &&
      other.accent == accent &&
      other.error == error;
  @override
  int get hashCode => Object.hash(lightText, fill, text, secondary, accent, error);
}

/// Error red pulled a little toward the accent hue so it sits in the same
/// palette, but stays clearly red (hue clamped to the red band).
Color harmonizedError(Color accent, {Color base = const Color(0xFFFF453A)}) {
  final b = HSLColor.fromColor(base);
  final a = HSLColor.fromColor(accent);
  if (a.saturation < 0.12) return base; // monochrome accent: plain red
  var d = a.hue - b.hue;
  if (d > 180) d -= 360;
  if (d < -180) d += 360;
  // 15% of the way toward the accent, at most ±14° (stays red/red-orange/crimson).
  final shift = (d * 0.15).clamp(-14.0, 14.0);
  var h = (b.hue + shift) % 360;
  if (h < 0) h += 360;
  return b.withHue(h).toColor();
}

/// Moves [c]'s lightness until it reaches [target] contrast on [bg]
/// (keeps hue & saturation, so the accent still reads as the accent).
Color legibleOn(Color c, Color bg, {double target = kGlassMinContrast}) {
  if (contrastRatio(c, bg) >= target) return c;
  final hsl = HSLColor.fromColor(c);
  final lighter = relativeLuminance(bg) < 0.18;
  for (var i = 1; i <= 40; i++) {
    final l = (hsl.lightness + (lighter ? 1 : -1) * i * 0.025).clamp(0.0, 1.0);
    final t = hsl.withLightness(l).toColor();
    if (contrastRatio(t, bg) >= target) return t;
  }
  return lighter ? _lightText : _darkText;
}

// Starting fill opacities follow liquid-glass-spec §5.2 (regular: light
// wash 0.22 / dark wash 0.30; clear: dimming 0.30; tinted dark 0.68 → gelap
// 0.62; reduce transparency 0.88+). The solver only ever raises them.
double _minAlpha(GlassStyle s, GlassRole r, bool lightText, bool highContrast) {
  if (highContrast) return 0.92;
  if (r == GlassRole.code) return 0.62;
  return switch (s) {
    GlassStyle.reguler => lightText ? 0.30 : 0.22,
    GlassStyle.bening => 0.30,
    GlassStyle.gelap => 0.62,
    GlassStyle.warna => 0.45,
    GlassStyle.tanpa => 0.92,
  };
}

Color _fillBase(GlassStyle s, GlassRole r, Color accent, bool lightText) {
  final base = lightText ? _darkBase : _lightBase;
  if (s == GlassStyle.bening && r != GlassRole.code && r != GlassRole.accent) return const Color(0xFF000000); // dimming layer
  if (r == GlassRole.code) return Color.lerp(const Color(0xFF0B0B0D), accent, 0.05)!;
  final tint = switch ((s, r)) {
    (GlassStyle.warna, GlassRole.accent) => 0.62,
    (GlassStyle.warna, _) => 0.38,
    (_, GlassRole.accent) => lightText ? 0.42 : 0.30,
    _ => lightText ? 0.07 : 0.05,
  };
  return Color.lerp(base, accent, tint)!;
}

Color _textFor(bool lightText, Color accent) => Color.lerp(lightText ? _lightText : _darkText, accent, 0.03)!;

/// Composite of [fill] at [alpha] over [bg] (what the eye sees).
Color _over(Color fill, double alpha, Color bg) => Color.alphaBlend(fill.withValues(alpha: alpha), bg);

/// Secondary text: body text pulled 22% toward the glass colour.
Color _secondary(Color text, Color comp) => Color.lerp(text, comp, 0.22)!;

({double alpha, double contrast}) _solve(GlassStyle s, GlassRole r, Color accent, bool lightText, Color worst, bool hc) {
  final fill = _fillBase(s, r, accent, lightText);
  final text = _textFor(lightText, accent);
  var best = (alpha: 0.96, contrast: 0.0);
  for (var a = _minAlpha(s, r, lightText, hc); a <= 0.961; a += 0.02) {
    final comp = _over(fill, a, worst);
    final c = contrastRatio(_secondary(text, comp), comp);
    if (c >= kGlassMinContrast) return (alpha: a, contrast: c);
    if (c > best.contrast) best = (alpha: a, contrast: c);
  }
  return best;
}

/// Picks light or dark text and the fill opacity so that even the
/// secondary text reaches 4.5:1 over [sample]. Prefers the option that needs
/// the thinner glass (more see-through). [GlassStyle.gelap] and code are
/// always light text, as is [GlassStyle.bening] (white text over a dimming
/// layer, spec §1.2). [previousLightText] adds hysteresis so an element
/// scrolling over a mid-grey area does not flicker between the two.
/// [highContrast] (Increase Contrast / Reduce Transparency) makes the glass
/// near-opaque.
GlassTone resolveGlassTone({
  required BackdropSample sample,
  required Color accent,
  GlassStyle style = GlassStyle.reguler,
  GlassRole role = GlassRole.neutral,
  bool? previousLightText,
  bool highContrast = false,
}) {
  final forceLight = style == GlassStyle.gelap || style == GlassStyle.bening || role == GlassRole.code;
  final light = _solve(style, role, accent, true, sample.worstForLightText(), highContrast);
  final dark = forceLight ? null : _solve(style, role, accent, false, sample.worstForDarkText(), highContrast);
  bool useLight;
  if (dark == null) {
    useLight = true;
  } else {
    final lOk = light.contrast >= kGlassMinContrast, dOk = dark.contrast >= kGlassMinContrast;
    if (lOk != dOk) {
      useLight = lOk;
    } else if (lOk) {
      // both legible: thinner glass wins; a near-tie keeps the previous
      // choice (hysteresis), else follows the backdrop (spec 0.45/0.55).
      final diff = (light.alpha - dark.alpha).abs();
      if (previousLightText != null && diff < 0.10) {
        useLight = previousLightText;
      } else {
        useLight = diff < 0.04 ? sample.luminance < 0.30 : light.alpha < dark.alpha;
      }
    } else {
      useLight = light.contrast >= dark.contrast;
    }
  }
  final sol = useLight ? light : dark!;
  final fillBase = _fillBase(style, role, accent, useLight);
  final worst = useLight ? sample.worstForLightText() : sample.worstForDarkText();
  final comp = _over(fillBase, sol.alpha, worst);
  final text = _textFor(useLight, accent);
  final secondary = _secondary(text, comp);
  return GlassTone(
    lightText: useLight,
    fill: fillBase.withValues(alpha: sol.alpha),
    text: text,
    secondary: secondary,
    faint: Color.lerp(text, comp, 0.42)!,
    accent: legibleOn(accent, comp),
    error: legibleOn(harmonizedError(accent), comp, target: 3.0),
    rim: const Color(0xFFFFFFFF).withValues(alpha: useLight ? 0.30 : 0.65), // spec §5.2 rim top
    composite: comp,
    contrast: contrastRatio(secondary, comp),
  );
}

/// Foreground for text drawn straight on the backdrop (no plate): the
/// colour with the better contrast and whether it needs a soft halo
/// (shadow) to reach 4.5:1.
({Color color, bool lightText, bool needsHalo}) legibleTextOn(BackdropSample s, Color accent) {
  final lt = Color.lerp(_lightText, accent, 0.03)!, dt = Color.lerp(_darkText, accent, 0.04)!;
  final cl = contrastRatio(lt, s.worstForLightText()), cd = contrastRatio(dt, s.worstForDarkText());
  final light = cl >= cd;
  return (color: light ? lt : dt, lightText: light, needsHalo: (light ? cl : cd) < kGlassMinContrast);
}
