// Neovarch flat-print look: the halo monogram and wordmark, film grain,
// halftone dot fields, thin star-grid frames and bone "paper" surfaces on
// the solid red base. No gradients or glows. All drawn with CustomPainter or
// tiny tiled assets, so they stay cheap on low-end phones.
import 'dart:math' as math;
import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Neovarch identity: solid flat red base, bone-white type, near-black ink.
const brandRed = Color(0xFFC8101A);
const brandBg = brandRed;
const brandPaper = Color(0xFFF2EDE4);
const brandInk = Color(0xFF140607);
/// Small red text on dark backgrounds (legibility).
const brandRedLight = Color(0xFFF2555C);

/// Bone paper surface: re-themes [child] with the paper palette (near-black
/// text, red accents) when the current theme has one; otherwise a no-op.
class PaperScope extends StatelessWidget {
  const PaperScope({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final paper = context.hc.paper;
    if (paper == null) return child;
    final ink = paper.colorScheme.onSurface;
    return Theme(
      data: paper,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: ink),
        child: IconTheme.merge(data: IconThemeData(color: ink), child: child),
      ),
    );
  }
}

/// [showModalBottomSheet] whose content sits on bone paper.
Future<T?> showPaperSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool? showDragHandle,
}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      showDragHandle: showDragHandle,
      builder: (c) => PaperScope(child: Builder(builder: builder)),
    );

/// [showDialog] whose dialog sits on bone paper.
Future<T?> showPaperDialog<T>({required BuildContext context, required WidgetBuilder builder}) =>
    showDialog<T>(context: context, builder: (c) => PaperScope(child: Builder(builder: builder)));

/// NEOVARCHAGENT wordmark: tall condensed serif with the halo floating above
/// the N. Text and halo are separate layers so each can be tinted.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.height = 40, this.color, this.haloColor});
  final double height;
  final Color? color;
  final Color? haloColor;
  static const ratio = 1000 / 330;
  @override
  Widget build(BuildContext context) {
    final c = color ?? context.cs.onSurface;
    final h = haloColor ?? (context.hc.paper != null ? c : context.cs.primary);
    Widget layer(String a, Color col) => Image.asset(a,
        height: height, width: height * ratio, color: col, colorBlendMode: BlendMode.srcIn, filterQuality: FilterQuality.medium);
    return Semantics(
      label: 'Neovarch Agent',
      child: SizedBox(
        height: height,
        width: height * ratio,
        child: Stack(children: [layer('assets/brand/wordmark_text.png', c), layer('assets/brand/wordmark_halo.png', h)]),
      ),
    );
  }
}

/// Neovarch monogram (N + halo, from the NEOVARCHAGENT wordmark), tinted.
/// [label] = the full logo card instead (portrait 894:1377).
class BrandBadge extends StatelessWidget {
  const BrandBadge({super.key, this.height = 56, this.color, this.label = false});
  final double height;
  final Color? color;
  final bool label;
  @override
  Widget build(BuildContext context) {
    if (label) return LogoCard(height: height);
    final c = color ?? (context.hc.brand ? context.cs.onSurface : context.cs.primary);
    return Image.asset('assets/brand/monogram.png',
        height: height, width: height, color: c, colorBlendMode: BlendMode.srcIn, filterQuality: FilterQuality.medium, semanticLabel: 'Neovarch Agent');
  }
}

/// The NeovarchLabs portrait card with the NEOVARCHAGENT wordmark.
class LogoCard extends StatelessWidget {
  const LogoCard({super.key, this.height = 200});
  final double height;
  static const ratio = 894 / 1377;
  @override
  Widget build(BuildContext context) => Image.asset('assets/brand/logo_card.png',
      height: height, width: height * ratio, filterQuality: FilterQuality.medium, semanticLabel: 'Neovarch Agent');
}

/// Fine paper grain over the whole app (site texture). Ignores input.
class GrainOverlay extends StatelessWidget {
  const GrainOverlay({super.key, this.opacity = 0.55});
  final double opacity;
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/brand/grain.png'),
                repeat: ImageRepeat.repeat,
                scale: 2,
                filterQuality: FilterQuality.none,
              ),
            ),
          ),
        ),
      );
}

/// A field of halftone dots fading out from [focus] (fractional position).
class HalftonePainter extends CustomPainter {
  HalftonePainter({required this.color, this.focus = const Offset(0.85, 0.15), this.cell = 7, this.reach = 0.9, this.strength = 1});
  final Color color;
  final Offset focus;
  final double cell;
  final double reach;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final f = Offset(focus.dx * size.width, focus.dy * size.height);
    final span = math.max(size.width, size.height) * reach;
    for (var y = cell / 2; y < size.height; y += cell) {
      // offset every other row: classic 45° screen
      final shift = ((y / cell).floor().isOdd) ? cell / 2 : 0.0;
      for (var x = cell / 2 + shift; x < size.width; x += cell) {
        final t = (1 - (Offset(x, y) - f).distance / span).clamp(0.0, 1.0) * strength;
        final r = cell * 0.48 * t;
        if (r > 0.35) canvas.drawCircle(Offset(x, y), r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(HalftonePainter old) =>
      old.color != color || old.focus != focus || old.cell != cell || old.reach != reach || old.strength != strength;
}

/// Halftone accent behind a child (empty states, headers). Only drawn in the
/// brand theme unless [always] is set.
class HalftoneBackdrop extends StatelessWidget {
  const HalftoneBackdrop({super.key, required this.child, this.focus = const Offset(0.5, 0.35), this.reach = 0.55, this.always = false});
  final Widget child;
  final Offset focus;
  final double reach;
  final bool always;
  @override
  Widget build(BuildContext context) {
    if (!always && !context.hc.brand) return child;
    return CustomPaint(
      painter: HalftonePainter(color: context.cs.onSurface.withValues(alpha: 0.10), focus: focus, reach: reach, cell: 8),
      child: child,
    );
  }
}

/// Four-pointed star (the site's grid ornament).
void drawStar(Canvas c, Offset o, double r, Paint p) {
  final path = Path()
    ..moveTo(o.dx, o.dy - r)
    ..quadraticBezierTo(o.dx, o.dy, o.dx + r, o.dy)
    ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + r)
    ..quadraticBezierTo(o.dx, o.dy, o.dx - r, o.dy)
    ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - r)
    ..close();
  c.drawPath(path, p);
}

/// Thin 1px frame with a star-grid strip along the top, like the site's
/// engraving plates.
class StarFramePainter extends CustomPainter {
  StarFramePainter({required this.color, this.inset = 12, this.gridRows = 1, this.cell = 30, this.progress = 1});
  final Color color;
  final double inset;
  final int gridRows;
  final double cell;
  /// 0→1: lines "draw themselves" (path trimmed by length).
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    if (progress < 1) {
      final rec = PictureRecorder();
      final c = Canvas(rec);
      _paintFull(c, size);
      // reveal by sweeping a growing clip from the top-left corner
      canvas.save();
      final r = size.longestSide * 1.5 * Curves.easeInOutCubic.transform(progress.clamp(0, 1));
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset(inset, inset), radius: r)));
      canvas.drawPicture(rec.endRecording());
      canvas.restore();
      return;
    }
    _paintFull(canvas, size);
  }

  void _paintFull(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final fill = Paint()..color = color;
    final r = Rect.fromLTRB(inset, inset, size.width - inset, size.height - inset);
    canvas.drawRect(r, line);
    // star-grid strip at the top
    final cols = math.max(4, (r.width / cell).round());
    final cw = r.width / cols;
    for (var row = 1; row <= gridRows; row++) {
      final y = r.top + cw * row;
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), line);
    }
    for (var i = 1; i < cols; i++) {
      final x = r.left + cw * i;
      canvas.drawLine(Offset(x, r.top), Offset(x, r.top + cw * gridRows), line);
    }
    for (var row = 0; row < gridRows; row++) {
      for (var i = 0; i < cols; i++) {
        if ((i + row) % 3 == 1) drawStar(canvas, Offset(r.left + cw * (i + 0.5), r.top + cw * (row + 0.5)), cw * 0.16, fill);
      }
    }
    // corner stars just outside the frame
    for (final o in [r.bottomLeft, r.bottomRight]) {
      drawStar(canvas, o, 5, fill);
    }
  }

  @override
  bool shouldRepaint(StarFramePainter old) => old.color != color || old.inset != inset || old.gridRows != gridRows || old.progress != progress;
}

/// Mono uppercase meta label ("[ 01 ] PEMBUKA").
class MetaLabel extends StatelessWidget {
  const MetaLabel(this.text, {super.key, this.color, this.size = 11});
  final String text;
  final Color? color;
  final double size;
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: 'IBMPlexMono',
          fontSize: size,
          letterSpacing: 1.3,
          fontWeight: FontWeight.w500,
          color: color ?? context.hc.mutedForeground,
          height: 1.3,
        ),
      );
}


/// The halo ring: a tilted ellipse with a bright arc orbiting it (flat; the
/// [glow] parameter only thickens the ring, no blur).
class HaloPainter extends CustomPainter {
  HaloPainter({required this.t, required this.color, this.glow = 1, this.accent = brandPaper});
  final double t; // 0..1 loop phase
  final Color color;
  /// The orbiting arc and sparkle.
  final Color accent;
  final double glow;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-0.22);
    canvas.translate(-size.width / 2, -size.height / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.12
      ..color = color;
    canvas.drawOval(rect.deflate(size.height * 0.1), base);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.height * 0.2
      ..color = accent;
    canvas.drawArc(rect.deflate(size.height * 0.1), t * math.pi * 2, 0.9, false, arc);
    canvas.restore();
    // sparkle riding the ring
    final a = t * math.pi * 2 + 0.45;
    final p = Offset(size.width / 2 + math.cos(a) * size.width * 0.42, size.height / 2 + math.sin(a) * size.height * 0.36);
    drawStar(canvas, p, size.height * 0.45, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(HaloPainter old) => old.t != t || old.glow != glow || old.color != color || old.accent != accent;
}
