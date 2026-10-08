// Technology logos for the profile "stack": Simple Icons (CC0) path data bundled
// in tech_icons.g.dart, drawn as a Flutter Path (no SVG package, no network).
// Monochrome in the accent by default; brand colours optional.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../theme/neovarch_mobile_theme.dart';
import '../social_models.dart';
import '../tech_icons.g.dart';

/// Icon for a GitHub linguist / agent language name, or null (fallback glyph).
TechIconData? techIconFor(String name) {
  final k = name.trim().toLowerCase();
  return kTechIcons[kTechAliases[k] ?? k] ?? kTechIcons[k.replaceAll(RegExp(r'[^a-z0-9]'), '')];
}

final _pathCache = <String, Path>{};

/// SVG path data (M L H V C S Q T A Z, absolute + relative) → [Path].
Path parseSvgPath(String d) {
  final cached = _pathCache[d];
  if (cached != null) return cached;
  final path = Path();
  final tok = RegExp(r'[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?').allMatches(d).map((m) => m.group(0)!).toList();
  var i = 0;
  var cmd = '';
  var x = 0.0, y = 0.0, sx = 0.0, sy = 0.0;
  double? cx2, cy2; // last control point for S/T
  String lastCmd = '';
  bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double n() => double.parse(tok[i++]);
  // arc flags may be glued ("011" -> 0,1,1): read one char at a time
  double flag() {
    final t = tok[i];
    if (t.length > 1 && (t[0] == '0' || t[0] == '1')) {
      tok[i] = t.substring(1);
      return t[0] == '1' ? 1 : 0;
    }
    i++;
    return double.parse(t);
  }

  while (i < tok.length) {
    if (isCmd(tok[i])) cmd = tok[i++];
    final rel = cmd == cmd.toLowerCase();
    final c = cmd.toUpperCase();
    double ax(double v) => rel ? x + v : v;
    double ay(double v) => rel ? y + v : v;
    switch (c) {
      case 'M':
        x = ax(n());
        y = ay(n());
        path.moveTo(x, y);
        sx = x;
        sy = y;
        cmd = rel ? 'l' : 'L';
        cx2 = cy2 = null;
      case 'L':
        x = ax(n());
        y = ay(n());
        path.lineTo(x, y);
        cx2 = cy2 = null;
      case 'H':
        x = rel ? x + n() : n();
        path.lineTo(x, y);
        cx2 = cy2 = null;
      case 'V':
        y = rel ? y + n() : n();
        path.lineTo(x, y);
        cx2 = cy2 = null;
      case 'C':
        final x1 = ax(n()), y1 = ay(n()), x2 = ax(n()), y2 = ay(n()), ex = ax(n()), ey = ay(n());
        path.cubicTo(x1, y1, x2, y2, ex, ey);
        cx2 = x2;
        cy2 = y2;
        x = ex;
        y = ey;
      case 'S':
        final r1x = ('CS'.contains(lastCmd) && cx2 != null) ? 2 * x - cx2 : x;
        final r1y = ('CS'.contains(lastCmd) && cy2 != null) ? 2 * y - cy2 : y;
        final x2 = ax(n()), y2 = ay(n()), ex = ax(n()), ey = ay(n());
        path.cubicTo(r1x, r1y, x2, y2, ex, ey);
        cx2 = x2;
        cy2 = y2;
        x = ex;
        y = ey;
      case 'Q':
        final x1 = ax(n()), y1 = ay(n()), ex = ax(n()), ey = ay(n());
        path.quadraticBezierTo(x1, y1, ex, ey);
        cx2 = x1;
        cy2 = y1;
        x = ex;
        y = ey;
      case 'T':
        final qx = ('QT'.contains(lastCmd) && cx2 != null) ? 2 * x - cx2 : x;
        final qy = ('QT'.contains(lastCmd) && cy2 != null) ? 2 * y - cy2 : y;
        final ex = ax(n()), ey = ay(n());
        path.quadraticBezierTo(qx, qy, ex, ey);
        cx2 = qx;
        cy2 = qy;
        x = ex;
        y = ey;
      case 'A':
        final rx = n(), ry = n(), rot = n();
        final large = flag(), sweep = flag();
        final ex = ax(n()), ey = ay(n());
        path.arcToPoint(Offset(ex, ey), radius: Radius.elliptical(rx, ry), rotation: rot, largeArc: large == 1, clockwise: sweep == 1);
        x = ex;
        y = ey;
        cx2 = cy2 = null;
      case 'Z':
        path.close();
        x = sx;
        y = sy;
        cx2 = cy2 = null;
      default:
        i++; // unknown token: skip
    }
    lastCmd = c;
  }
  return _pathCache[d] = path;
}

Color _hex(String h) => Color(int.parse('FF$h', radix: 16));

/// A 24×24 Simple Icons logo scaled to [size]; generic code glyph when unknown.
class TechLogo extends StatelessWidget {
  const TechLogo(this.name, {super.key, this.size = 16, this.color, this.brand = false});
  final String name;
  final double size;
  final Color? color;
  final bool brand;
  @override
  Widget build(BuildContext context) {
    final icon = techIconFor(name);
    final c = brand && icon != null ? _hex(icon.hex) : (color ?? NV.red);
    if (icon == null) {
      return Icon(CupertinoIcons.chevron_left_slash_chevron_right, size: size, color: c, semanticLabel: name);
    }
    return Semantics(
      label: icon.title,
      child: CustomPaint(key: ValueKey('tech-${icon.slug}'), size: Size.square(size), painter: _LogoPainter(parseSvgPath(icon.path), c)),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.path, this.color);
  final Path path;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(path, Paint()..color = color..isAntiAlias = true);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.path != path || old.color != color;
}

/// Glass chip with the logo; the name is the tooltip / semantic label, shown
/// as a tiny caption when [caption] (and the share when [share]).
class TechChip extends StatelessWidget {
  const TechChip({super.key, required this.item, this.caption = true, this.share = true, this.brand = false, this.size = 18});
  final StackItem item;
  final bool caption, share, brand;
  final double size;
  @override
  Widget build(BuildContext context) {
    final title = techIconFor(item.name)?.title ?? item.name;
    return Tooltip(
      message: '$title · ${(item.share * 100).round()}%',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: caption ? 9 : 8, vertical: 6),
        decoration: BoxDecoration(
          color: NV.glass,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: NV.glassBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          TechLogo(item.name, size: size, brand: brand),
          if (caption) ...[
            const SizedBox(width: 6),
            Text(title, style: TextStyle(fontSize: 11.5, color: NV.text)),
          ],
          if (share) ...[
            const SizedBox(width: 5),
            Text('${(item.share * 100).round()}%', style: NV.monoLabel(size: 9, color: NV.muted)),
          ],
        ]),
      ),
    );
  }
}

class TechStackChips extends StatelessWidget {
  const TechStackChips({super.key, required this.items, this.caption = true, this.brand = false});
  final List<StackItem> items;
  final bool caption, brand;
  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: [
        for (final it in items) TechChip(key: ValueKey('chip-${it.name}'), item: it, caption: caption, brand: brand),
      ]);
}

/// Up to [max] small logos in a row (friend list).
class TechLogoRow extends StatelessWidget {
  const TechLogoRow({super.key, required this.names, this.max = 3, this.size = 14});
  final List<String> names;
  final int max;
  final double size;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (final n in names.take(max))
          Padding(padding: const EdgeInsets.only(left: 6), child: Tooltip(message: n, child: TechLogo(n, size: size, color: NV.muted))),
      ]);
}
