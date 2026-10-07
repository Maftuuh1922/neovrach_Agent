// Startup logo reveal shown on every cold start after the first-launch
// intro: picks up exactly where the native red splash ends (solid red, bone
// monogram), then the halo drops onto the N, the NEOVARCHAGENT wordmark is
// wiped in behind a hard edge and the app slides in. ~1.4 s, tap to skip,
// skipped entirely with "reduce motion". Flat print: no gradients or glows.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/brand.dart';
import '../widgets/motion.dart';

class StartupSplash extends StatefulWidget {
  const StartupSplash({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  State<StartupSplash> createState() => _StartupSplashState();
}

class _StartupSplashState extends State<StartupSplash> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700));
  late final AnimationController _halo = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  bool _started = false;
  bool _done = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.enabled || reduceMotion(context)) {
      _finish();
      return;
    }
    // decode the logo layers first so the reveal never plays on empty frames
    Future.wait([
      for (final a in const ['assets/brand/monogram.png', 'assets/brand/wordmark_text.png', 'assets/brand/wordmark_halo.png'])
        precacheImage(AssetImage(a), context),
    ]).timeout(const Duration(milliseconds: 900), onTimeout: () => const []).whenComplete(() {
      if (mounted && !_done) _c.forward().whenComplete(_finish);
    });
  }

  void _finish() {
    _halo.stop();
    if (mounted && !_done) setState(() => _done = true);
  }

  @override
  void dispose() {
    _c.dispose();
    _halo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: brandRed, systemNavigationBarColor: brandRed),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          double seg(double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
          final haloIn = Curves.easeOutBack.transform(seg(0.08, 0.32));
          final wipe = Curves.easeInOutCubic.transform(seg(0.28, 0.62));
          final out = Curves.easeInCubic.transform(seg(0.82, 1.0));
          final w = (MediaQuery.sizeOf(context).width * 0.72).clamp(200.0, 420.0);
          final wmH = w / Wordmark.ratio;
          return Stack(children: [
            // the app is already built underneath and slides up as the plate lifts
            Positioned.fill(child: Opacity(opacity: out, child: widget.child)),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: out > 0.5,
                child: GestureDetector(
                  onTap: _finish,
                  child: Transform.translate(
                    offset: Offset(0, -MediaQuery.sizeOf(context).height * out),
                    child: ColoredBox(
                      color: brandRed,
                      child: Stack(children: [
                        Positioned.fill(
                          child: CustomPaint(painter: StarFramePainter(color: brandPaper.withValues(alpha: 0.8), inset: 14, cell: 34, progress: seg(0, 0.4))),
                        ),
                        Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            SizedBox(
                              width: 96,
                              height: 110,
                              child: Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
                                const BrandBadge(height: 92, color: brandPaper),
                                Positioned(
                                  top: -34 + 30 * haloIn,
                                  left: 14,
                                  width: 70,
                                  height: 18,
                                  child: Opacity(
                                    opacity: haloIn.clamp(0.0, 1.0),
                                    child: AnimatedBuilder(
                                      animation: _halo,
                                      builder: (context, _) => CustomPaint(painter: HaloPainter(t: _halo.value, color: brandInk, glow: 0)),
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                            const SizedBox(height: 26),
                            SizedBox(
                              width: w,
                              height: wmH,
                              child: Stack(children: [
                                ClipRect(clipper: _LeftReveal(wipe), child: Wordmark(height: wmH, color: brandPaper, haloColor: brandInk)),
                                if (wipe > 0 && wipe < 1) Positioned(left: w * wipe, top: 0, bottom: 0, child: Container(width: 2, color: brandPaper)),
                              ]),
                            ),
                            const SizedBox(height: 14),
                            Opacity(opacity: seg(0.55, 0.75), child: const MetaLabel('neovarchlabs · agen ai', color: brandPaper, size: 10)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/// Clips to the left [f] fraction of the child (hard-edged wipe).
class _LeftReveal extends CustomClipper<Rect> {
  _LeftReveal(this.f);
  final double f;
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * f, size.height);
  @override
  bool shouldReclip(_LeftReveal old) => old.f != f;
}
