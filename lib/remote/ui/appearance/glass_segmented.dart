// Liquid glass segmented control: a glass track with a clear lens that
// springs to the selected segment, stretching along its travel and settling
// back (iOS 26). Drag the lens to scrub; release snaps to the nearest
// segment. Reduce motion: the lens jumps.
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringDescription, SpringSimulation;
import 'package:flutter/services.dart' show HapticFeedback;

import '../../../theme/neovarch_mobile_theme.dart';
import '../nv_widgets.dart' show NvGlassRimPainter;
import 'corner_radius.dart';
import 'glass_surfaces.dart';
import 'glass_tone.dart';

@immutable
class NvSegment<T> {
  const NvSegment(this.value, this.label, {this.icon});
  final T value;
  final String label;
  final IconData? icon;
}

class NvGlassSegmented<T> extends StatefulWidget {
  const NvGlassSegmented({super.key, required this.segments, required this.selected, required this.onChanged, this.height = 44});
  final List<NvSegment<T>> segments;
  final T selected;
  final ValueChanged<T>? onChanged;
  final double height;
  @override
  State<NvGlassSegmented<T>> createState() => _NvGlassSegmentedState<T>();
}

class _NvGlassSegmentedState<T> extends State<NvGlassSegmented<T>> with SingleTickerProviderStateMixin {
  // Lens position in segment units (0 .. n-1); unbounded so the spring can overshoot.
  late final AnimationController _pos = AnimationController.unbounded(vsync: this, value: _index(widget.selected).toDouble());
  double? _dragFrom;
  bool _pressed = false;

  static const _spring = SpringDescription(mass: 1, stiffness: 420, damping: 30);

  int _index(T v) {
    final i = widget.segments.indexWhere((s) => s.value == v);
    return i < 0 ? 0 : i;
  }

  @override
  void didUpdateWidget(NvGlassSegmented<T> old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected && _dragFrom == null) _springTo(_index(widget.selected).toDouble());
  }

  void _springTo(double target) {
    if (NvGlassFx.reducedMotion(context)) {
      _pos.value = target;
      return;
    }
    _pos.animateWith(SpringSimulation(_spring, _pos.value, target, _pos.velocity));
  }

  void _select(int i) {
    final v = widget.segments[i].value;
    _springTo(i.toDouble());
    if (v != widget.selected) {
      HapticFeedback.selectionClick();
      widget.onChanged?.call(v);
    }
  }

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tone = GlassToneScope.of(context);
    final radii = AppCornerRadius.of(context);
    final n = widget.segments.length;
    const pad = 4.0;
    final h = widget.height;
    // Track: control radius but never more than a capsule; lens concentric.
    final trackR = (radii.control + 4).clamp(0.0, h / 2);
    final lensR = radii.inner(trackR, pad);
    return LayoutBuilder(builder: (context, c) {
      final segW = (c.maxWidth - 2 * pad) / n;
      int nearest(double units) => units.round().clamp(0, n - 1);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (d) {
          setState(() => _pressed = false);
          _select(((d.localPosition.dx - pad) / segW).floor().clamp(0, n - 1));
        },
        onHorizontalDragStart: (d) {
          _pos.stop();
          _dragFrom = _pos.value;
          setState(() => _pressed = true);
        },
        onHorizontalDragUpdate: (d) {
          final before = nearest(_pos.value);
          _pos.value = (_pos.value + d.delta.dx / segW).clamp(-0.15, n - 1 + 0.15);
          if (nearest(_pos.value) != before) HapticFeedback.selectionClick();
        },
        onHorizontalDragEnd: (d) {
          _dragFrom = null;
          setState(() => _pressed = false);
          _select(nearest(_pos.value));
        },
        child: NvGlassSurface(
          radius: trackR,
          rimStrength: 0.7,
          fill: Color.alphaBlend(tone.track, tone.fill.withValues(alpha: tone.fillAlpha * 0.6)),
          child: SizedBox(
            height: h,
            child: AnimatedBuilder(
              animation: _pos,
              builder: (context, _) {
                final p = _pos.value;
                final target = _index(widget.selected).toDouble();
                // stretch with distance-to-target (travel) and while pressed
                final travel = (p - target).abs().clamp(0.0, 1.0);
                final dragging = _dragFrom != null;
                final sx = 1 + 0.16 * travel + (_pressed ? 0.06 : 0);
                final sy = 1 - 0.08 * travel + (_pressed ? 0.06 : 0);
                final lensW = segW * sx;
                final lensH = (h - 2 * pad) * sy;
                final left = pad + p * segW + (segW - lensW) / 2;
                return Stack(clipBehavior: Clip.none, children: [
                  Positioned(
                    left: left,
                    top: (h - lensH) / 2,
                    width: lensW,
                    height: lensH,
                    child: _Lens(radius: lensR * sy, tone: tone, lifted: dragging || _pressed),
                  ),
                  Row(children: [
                    const SizedBox(width: pad),
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: _SegLabel(
                          seg: widget.segments[i],
                          // label emphasis follows the lens (cross-fades while it moves)
                          t: (1 - (p - i).abs()).clamp(0.0, 1.0),
                          selected: i == _index(widget.selected),
                          tone: tone,
                        ),
                      ),
                    const SizedBox(width: pad),
                  ]),
                ]);
              },
            ),
          ),
        ),
      );
    });
  }
}

class _Lens extends StatelessWidget {
  const _Lens({required this.radius, required this.tone, required this.lifted});
  final double radius;
  final GlassTone tone;
  final bool lifted;
  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    final fill = tone.reduced ? (tone.dark ? NV.raised : const Color(0xFFFFFFFF)) : tone.lens;
    return CustomPaint(
      foregroundPainter: tone.reduced ? null : NvGlassRimPainter(borderRadius: br, rim: tone.rim, chroma: lifted, strength: lifted ? 1.4 : 1.1),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: br,
          border: tone.reduced ? Border.all(color: NV.borderStrong) : null,
          boxShadow: tone.reduced
              ? null
              : [BoxShadow(color: const Color(0xFF000000).withValues(alpha: tone.dark ? 0.28 : 0.10), blurRadius: lifted ? 14 : 8, offset: const Offset(0, 2))],
        ),
      ),
    );
  }
}

class _SegLabel<T> extends StatelessWidget {
  const _SegLabel({required this.seg, required this.t, required this.selected, required this.tone});
  final NvSegment<T> seg;
  final double t;
  final bool selected;
  final GlassTone tone;
  @override
  Widget build(BuildContext context) {
    final c = Color.lerp(tone.muted, tone.text, t)!;
    return Semantics(
      button: true,
      selected: selected,
      label: seg.label,
      excludeSemantics: true,
      child: Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (seg.icon != null) ...[Icon(seg.icon, size: 16, color: c), const SizedBox(width: 6)],
          Flexible(
            child: Text(seg.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: NV.sans, fontSize: 14, fontWeight: FontWeight.lerp(FontWeight.w500, FontWeight.w600, t), color: c, letterSpacing: -0.1)),
          ),
        ]),
      ),
    );
  }
}
