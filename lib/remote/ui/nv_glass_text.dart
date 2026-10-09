// 1.4.2: liquid-glass display text (the chat greeting).
//
// The glyphs are a translucent, slightly brightened glass fill, so the app
// background (already blurred by NvAppBackground) shows through them — no
// BackdropFilter. On top: a soft inner shade at the bottom of each glyph, a
// thin specular rim that is brightest top-left, and a slow sheen sweeping
// across the letters. Entrance: fade + blur-to-sharp + rise on a spring,
// replayed when the text changes or its tab becomes visible again.
//
// One AnimationController drives everything (its value is a clock in
// seconds); with reduce-motion it never runs and the glass is static.
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringDescription, SpringSimulation, Simulation;

import '../../theme/neovarch_mobile_theme.dart';
import '../../ui/widgets/common.dart' show reduceMotion;

/// x(t) = t forever: turns an unbounded controller into a clock.
class _Clock extends Simulation {
  @override
  double x(double time) => time;
  @override
  double dx(double time) => 1;
  @override
  bool isDone(double time) => false;
}

class NvGlassText extends StatefulWidget {
  const NvGlassText(this.text, {super.key, required this.style, this.textAlign = TextAlign.center, this.entrance = true, this.sheen = true});
  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  /// Play its own fade/blur/rise entrance (off when a parent staggers it).
  final bool entrance;
  /// Slow specular sheen loop.
  final bool sheen;

  /// Sheen loop length.
  static const sheenPeriod = 5.0; // seconds
  /// Entrance rise in logical px and peak blur sigma.
  static const rise = 14.0;
  static const entranceBlur = 6.0;
  static const _spring = SpringDescription(mass: 1, stiffness: 170, damping: 23);

  /// Entrance progress (0 → 1, may overshoot slightly) [t] seconds in.
  static double entranceAt(double t) => t <= 0 ? 0 : SpringSimulation(_spring, 0, 1, 0).x(t);

  @override
  State<NvGlassText> createState() => NvGlassTextState();
}

class NvGlassTextState extends State<NvGlassText> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController.unbounded(vsync: this);
  double _start = 0; // clock value when the entrance (re)started
  bool _static = false;
  ValueListenable<TickerModeData>? _tickerMode;

  /// Entrance progress, for tests.
  double get entrance => _static || !widget.entrance ? 1 : NvGlassText.entranceAt(_clock.value - _start);
  /// Whether the sheen is animating (false with reduce-motion).
  bool get animating => _clock.isAnimating;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _static = reduceMotion(context) || (!widget.entrance && !widget.sheen);
    final tm = TickerMode.getValuesNotifier(context);
    if (tm != _tickerMode) {
      _tickerMode?.removeListener(_onTickerMode);
      _tickerMode = tm..addListener(_onTickerMode);
    }
    if (_static) {
      _clock.stop();
    } else if (!_clock.isAnimating) {
      _restart();
    }
  }

  // The tab came back on screen (IndexedStack mutes offstage tickers).
  void _onTickerMode() {
    if (_tickerMode!.value.enabled && !_static) _restart();
  }

  @override
  void didUpdateWidget(NvGlassText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text && !_static) _restart();
  }

  // Restart the clock itself: a muted ticker (offstage tab) keeps counting
  // time, so continuing it would skip the entrance.
  void _restart() {
    _clock.stop();
    _clock.value = 0;
    _start = 0;
    _clock.animateWith(_Clock());
  }

  @override
  void dispose() {
    _tickerMode?.removeListener(_onTickerMode);
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // "Tanpa efek" (reduce transparency): plain solid text, no glass.
    if (NV.glassStyle == NvGlassStyle.tanpa) {
      return RepaintBoundary(
          key: const ValueKey('nv-glass-text-solid'), child: Text(widget.text, textAlign: widget.textAlign, style: widget.style.copyWith(color: NV.text)));
    }
    final clear = NV.glassStyle == NvGlassStyle.bening;
    final dark = NV.palette.dark;
    final accent = NV.red;
    final base = widget.style.copyWith(color: null, foreground: null, shadows: null);
    final semanticText = Text(widget.text, textAlign: widget.textAlign, style: base.copyWith(color: Colors.transparent));

    // Glass body: bright at the top (light catching the surface), deeper and
    // a touch of accent at the bottom; translucent so the background reads
    // through. Light theme uses darker glass so it stays legible on white.
    final bodyTop = dark ? Colors.white.withValues(alpha: 0.86) : Color.lerp(NV.text, accent, 0.10)!.withValues(alpha: 0.80);
    final bodyBottom = dark ? Color.lerp(Colors.white, accent, 0.30)!.withValues(alpha: 0.56) : Color.lerp(NV.text, accent, 0.38)!.withValues(alpha: 0.62);
    final rimHi = Colors.white.withValues(alpha: dark ? 0.95 : 1.0);
    final rimLo = dark ? Colors.white.withValues(alpha: 0.12) : NV.text.withValues(alpha: 0.30);
    final shade = (dark ? Colors.black : NV.text).withValues(alpha: dark ? 0.30 : 0.22);
    final halo = dark ? Colors.black.withValues(alpha: clear ? 0.55 : 0.38) : Colors.white.withValues(alpha: 0.75);

    final scaler = MediaQuery.textScalerOf(context);
    Widget layer(TextStyle s) => ExcludeSemantics(child: RichText(textAlign: widget.textAlign, textScaler: scaler, text: TextSpan(text: widget.text, style: s)));
    Widget masked(Shader Function(Rect) shader, Widget child, {BlendMode mode = BlendMode.srcIn}) =>
        ShaderMask(blendMode: mode, shaderCallback: shader, child: child);

    final white = base.copyWith(color: Colors.white);
    // static glass (everything but the sheen)
    final glass = Stack(alignment: AlignmentDirectional.topStart, children: [
      // soft halo behind, keeps the edge readable over busy or plain backgrounds
      layer(base.copyWith(color: Colors.transparent, shadows: [Shadow(color: halo, blurRadius: 18, offset: const Offset(0, 3))])),
      masked((r) => LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [bodyTop, bodyBottom]).createShader(r), layer(white)),
      // inner shade: darkens the lower part of each glyph
      masked(
          (r) => LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: const [0.45, 1], colors: [shade.withValues(alpha: 0), shade])
              .createShader(r),
          layer(white)),
      // specular rim, brightest top-left
      masked(
          (r) => LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [rimHi, rimLo]).createShader(r),
          layer(base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.1
                ..color = Colors.white))),
      semanticText,
    ]);

    if (_static) return RepaintBoundary(key: const ValueKey('nv-glass-text-static'), child: glass);

    final sheenText = layer(white);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _clock,
        child: glass,
        builder: (context, child) {
          final t = _clock.value;
          final e = widget.entrance ? NvGlassText.entranceAt(t - _start) : 1.0;
          final phase = (t % NvGlassText.sheenPeriod) / NvGlassText.sheenPeriod;
          // band travels from off the left edge to off the right edge, then
          // rests a while (only ~60% of the loop is visible sweep)
          final x = -1.6 + phase * 4.4;
          Widget out = Stack(alignment: AlignmentDirectional.topStart, children: [
            child!,
            if (widget.sheen && x < 1.6)
              masked(
                  (r) => LinearGradient(
                        begin: Alignment(x - 0.55, -1),
                        end: Alignment(x + 0.55, 1),
                        colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: dark ? 0.42 : 0.55), Colors.white.withValues(alpha: 0)],
                      ).createShader(r),
                  sheenText),
          ]);
          final blur = NvGlassText.entranceBlur * (1 - e).clamp(0.0, 1.0);
          if (blur > 0.05) out = ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: out);
          return Opacity(
            opacity: e.clamp(0.0, 1.0),
            child: Transform.translate(offset: Offset(0, NvGlassText.rise * (1 - math.min(e, 1.04))), child: out),
          );
        },
      ),
    );
  }
}
