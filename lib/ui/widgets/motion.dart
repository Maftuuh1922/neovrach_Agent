// Motion primitives modelled on Hermes Desktop's UI timings: short
// (160–280 ms) ease-out-cubic entrances, a shimmering "thinking" label, a
// blinking stream caret, bouncing typing dots. Everything checks the system
// "remove animations" setting and renders still frames when it is on.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

const motionFast = Duration(milliseconds: 160);
const motionBase = Duration(milliseconds: 240);
const motionSlow = Duration(milliseconds: 380);
const motionCurve = Curves.easeOutCubic;

/// Fade + 8 px rise, once, when first built (new messages, cards).
class EntranceFade extends StatefulWidget {
  const EntranceFade({super.key, required this.child, this.delay = Duration.zero, this.offset = 8});
  final Widget child;
  final Duration delay;
  final double offset;
  @override
  State<EntranceFade> createState() => _EntranceFadeState();
}

class _EntranceFadeState extends State<EntranceFade> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: motionBase);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _c.value = 1;
    } else if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () => mounted ? _c.forward() : null);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final t = motionCurve.transform(_c.value);
          if (t >= 1) return child!;
          return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, (1 - t) * widget.offset), child: child));
        },
      );
}

/// A label with a light band sweeping across it (Desktop "Thinking…").
class ShimmerText extends StatefulWidget {
  const ShimmerText(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;
  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style ?? context.tt.bodySmall ?? const TextStyle();
    final txt = Text(widget.text, style: base);
    if (reduceMotion(context)) return txt;
    // Flat pulse (no gradient shimmer): the label breathes between dim and full.
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Opacity(
        opacity: 0.45 + 0.55 * (0.5 + 0.5 * math.sin(_c.value * math.pi * 2)),
        child: txt,
      ),
    );
  }
}

/// Blinking block caret shown while a reply streams.
class BlinkingCaret extends StatefulWidget {
  const BlinkingCaret({super.key, this.height = 16});
  final double height;
  @override
  State<BlinkingCaret> createState() => _BlinkingCaretState();
}

class _BlinkingCaretState extends State<BlinkingCaret> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1060))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final box = Container(width: widget.height * 0.5, height: widget.height, color: context.cs.onSurface.withValues(alpha: 0.85));
    if (reduceMotion(context)) return box;
    return FadeTransition(
      opacity: _c.drive(TweenSequence([
        TweenSequenceItem(tween: ConstantTween(1.0), weight: 50),
        TweenSequenceItem(tween: ConstantTween(0.0), weight: 50),
      ])),
      child: box,
    );
  }
}

/// Three dots bouncing in sequence (waiting for the first token).
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, this.color, this.size = 6});
  final Color? color;
  final double size;
  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? context.hc.mutedForeground;
    final still = reduceMotion(context);
    return SizedBox(
      height: widget.size * 3,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 3; i++)
            Builder(builder: (_) {
              final ph = (_c.value - i * 0.16) % 1.0;
              final up = still ? 0.0 : math.max(0.0, math.sin(ph * math.pi * 2)) ;
              return Transform.translate(
                offset: Offset(0, -up * widget.size * 0.9),
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  margin: EdgeInsets.symmetric(horizontal: widget.size * 0.35),
                  decoration: BoxDecoration(color: c.withValues(alpha: 0.45 + 0.55 * up), shape: BoxShape.circle),
                ),
              );
            }),
        ]),
      ),
    );
  }
}

/// Fades a tab in each time it becomes the visible page of an IndexedStack.
class TabFade extends StatefulWidget {
  const TabFade({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;
  @override
  State<TabFade> createState() => _TabFadeState();
}

class _TabFadeState extends State<TabFade> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: motionBase, value: widget.active ? 1 : 0);
  @override
  void didUpdateWidget(TabFade old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      if (reduceMotion(context)) {
        _c.value = 1;
      } else {
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final t = motionCurve.transform(_c.value);
          if (t >= 1) return child!;
          return Opacity(opacity: 0.2 + 0.8 * t, child: Transform.translate(offset: Offset(0, (1 - t) * 10), child: child));
        },
      );
}

/// Route transition: fade through with a short horizontal glide (Desktop
/// panel slide). Instant when animations are disabled.
class HermesPageTransitionsBuilder extends PageTransitionsBuilder {
  const HermesPageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    if (reduceMotion(context)) return child;
    final inT = CurvedAnimation(parent: animation, curve: motionCurve, reverseCurve: Curves.easeInCubic);
    final outT = CurvedAnimation(parent: secondaryAnimation, curve: motionCurve);
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.6).animate(outT),
      child: SlideTransition(
        position: Tween(begin: Offset.zero, end: const Offset(-0.06, 0)).animate(outT),
        child: FadeTransition(
          opacity: inT,
          child: SlideTransition(position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(inT), child: child),
        ),
      ),
    );
  }
}
