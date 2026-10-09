// "Gaya kaca": the liquid glass variants and the scope that hands the
// current one (and the backdrop's luminance map) to every LiquidGlass.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'backdrop_luminance.dart';

/// Liquid glass variants (Apple Liquid Glass: regular / clear, plus a dark,
/// a tinted and an off variant). The enum names are the stored values.
enum GlassStyle {
  /// Regular: strong blur, adaptive fill — the default.
  reguler,

  /// Clear: thin blur, a black dimming layer (spec: 30–35%) and light text;
  /// the dimming is raised only as far as 4.5:1 needs.
  bening,

  /// Dark: always a dark glass with light text.
  gelap,

  /// Color: accent-tinted glass everywhere.
  warna,

  /// None: no backdrop blur, a near-solid adaptive surface.
  tanpa;

  /// Indonesian label for the "Gaya kaca" picker.
  String get label => switch (this) {
        GlassStyle.reguler => 'Reguler',
        GlassStyle.bening => 'Bening',
        GlassStyle.gelap => 'Gelap',
        GlassStyle.warna => 'Warna',
        GlassStyle.tanpa => 'Tanpa',
      };

  /// Backdrop blur sigma for content bubbles (0 = no BackdropFilter).
  double get sigma => switch (this) {
        // liquid-glass-spec §5.2 [emulasi]: regular large 18, clear 2–4
        // (6 here: content bubbles), tinted 28 → gelap 24.
        GlassStyle.reguler => 18,
        GlassStyle.bening => 6,
        GlassStyle.gelap => 24,
        GlassStyle.warna => 18,
        GlassStyle.tanpa => 0,
      };

  /// Saturation boost of the refracted backdrop.
  double get saturation => switch (this) {
        GlassStyle.bening => 1.25,
        GlassStyle.gelap => 1.2,
        GlassStyle.tanpa => 1.0,
        _ => 1.5,
      };

  static GlassStyle parse(String? s) => GlassStyle.values.firstWhere((v) => v.name == s, orElse: () => GlassStyle.reguler);
}

/// App-wide "Gaya kaca" value. The settings screen writes it; [GlassScope]
/// consumers (e.g. the chat screen) read it. Default: [GlassStyle.reguler].
final glassStyleProvider = StateProvider<GlassStyle>((ref) => GlassStyle.reguler);

/// Hands the glass style and the backdrop luminance map down the tree.
/// Without a scope, LiquidGlass uses [GlassStyle.reguler] and treats the
/// backdrop as the theme background colour.
class GlassScope extends InheritedWidget {
  const GlassScope({super.key, this.style = GlassStyle.reguler, this.backdrop, required super.child});
  final GlassStyle style;

  /// What the glass sits on (null = flat theme background).
  final GlassBackdropMap? backdrop;

  static GlassScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GlassScope>();
  static GlassStyle styleOf(BuildContext context) => maybeOf(context)?.style ?? GlassStyle.reguler;

  @override
  bool updateShouldNotify(GlassScope old) => old.style != style || old.backdrop != backdrop;
}
