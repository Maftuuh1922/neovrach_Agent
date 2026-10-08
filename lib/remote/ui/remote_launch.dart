// Cold-start intro of the phone remote, drawn in the user's saved theme
// (accent + dark/light are applied before the first frame, and MainActivity
// paints the same background natively, so there is no colour jump).
// Calm, ~860 ms: the mark fades and scales in, holds briefly, then lifts away
// while the app fades and slides up into place. Tap skips; "reduce motion"
// skips it entirely. The app is built underneath from the first frame and
// keeps its place in the tree, so no state is lost when the intro ends.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/neovarch_mobile_theme.dart';
import '../../ui/widgets/motion.dart' show reduceMotion;

class NvLaunchIntro extends StatefulWidget {
  const NvLaunchIntro({super.key, required this.child, this.enabled = true, this.duration = const Duration(milliseconds: 860), this.debugFreezeAt});
  final Widget child;
  final bool enabled;
  final Duration duration;
  /// Screenshots/tests: hold the intro at this point of its timeline.
  @visibleForTesting
  final double? debugFreezeAt;

  static const markAsset = 'assets/brand/monogram_n.png';

  @override
  State<NvLaunchIntro> createState() => _NvLaunchIntroState();
}

class _NvLaunchIntroState extends State<NvLaunchIntro> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  bool _started = false;
  bool _done = false;

  // Timeline (fractions of the duration).
  static const _outFrom = 0.56;
  late final Animation<double> _markIn = CurvedAnimation(parent: _c, curve: const Interval(0, 0.42, curve: Curves.easeOutCubic));
  late final Animation<double> _labelIn = CurvedAnimation(parent: _c, curve: const Interval(0.14, 0.50, curve: Curves.easeOut));
  late final Animation<double> _out = CurvedAnimation(parent: _c, curve: const Interval(_outFrom, 1, curve: Curves.easeInOutCubic));
  late final Animation<double> _appIn = CurvedAnimation(parent: _c, curve: const Interval(_outFrom, 1, curve: Curves.easeOutCubic));
  late final Animation<Offset> _appSlide = Tween(begin: const Offset(0, 0.035), end: Offset.zero).animate(_appIn);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.debugFreezeAt != null) {
      _c.value = widget.debugFreezeAt!;
      return;
    }
    if (!widget.enabled || reduceMotion(context)) {
      _c.value = 1;
      _done = true;
      return;
    }
    // Decode the mark first so the reveal never plays on an empty frame,
    // but never hold the app back for it.
    precacheImage(const AssetImage(NvLaunchIntro.markAsset), context)
        .timeout(const Duration(milliseconds: 350), onTimeout: () {})
        .catchError((_) {})
        .whenComplete(() {
      if (mounted && !_done) _c.forward().whenComplete(_finish);
    });
  }

  void _finish() {
    if (mounted && !_done) setState(() => _done = true);
  }

  void _skip() {
    if (_c.value < _outFrom) _c.value = _outFrom;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The app keeps index 0 of this Stack for its whole life (state kept).
    return Stack(children: [
      Positioned.fill(
        child: FadeTransition(
          opacity: _appIn,
          child: SlideTransition(position: _appSlide, child: widget.child),
        ),
      ),
      if (!_done)
        Positioned.fill(
          key: const ValueKey('nv-launch-intro'),
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: (NV.palette.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                .copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _skip,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final out = _out.value;
                  return IgnorePointer(
                    ignoring: out > 0.5,
                    child: Opacity(
                      opacity: 1 - out,
                      child: ColoredBox(
                        color: NV.bg,
                        // no Material above the app yet: plain text style
                        child: DefaultTextStyle(
                          style: TextStyle(fontFamily: NV.sans, color: NV.text, decoration: TextDecoration.none),
                          child: Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Opacity(
                              opacity: _markIn.value,
                              child: Transform.scale(
                                scale: 0.84 + 0.16 * _markIn.value + 0.06 * out,
                                child: _Mark(color: NV.red),
                              ),
                            ),
                            const SizedBox(height: 22),
                            Opacity(
                              opacity: _labelIn.value,
                              child: Transform.translate(
                                offset: Offset(0, 6 * (1 - _labelIn.value)),
                                child: Text('NEOVARCH', style: NV.monoLabel(size: 11, color: NV.muted).copyWith(letterSpacing: 5)),
                              ),
                            ),
                          ]),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
    ]);
  }
}

/// The N monogram on a rounded accent-wash tile with a hairline: flat.
class _Mark extends StatelessWidget {
  const _Mark({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: NV.redWash,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        alignment: Alignment.center,
        child: Image.asset(
          NvLaunchIntro.markAsset,
          height: 52,
          color: color,
          colorBlendMode: BlendMode.srcIn,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => Text('N', style: NV.display(size: 52, color: color)),
        ),
      );
}
