// Native isometric 2.5D office (replaces the Three.js scene).
//
// Zones: 8 desks in facing rows, a meeting room with a round table, a
// lounge with sofa and plants, and the Kanban wall on the back-left wall.
// Agents stand where their status puts them: working/review/blocked at
// their desk, meeting at the table, idle in the lounge. Light enough for a
// cheap phone: ~150 primitives per frame, no images, no shaders.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/models.dart';
import 'common.dart';

/// The scene's tight bounds in its own coordinates (see [_sceneOrigin]).
const officeCanvas = Size(850, 560);
const _sceneOrigin = Offset(78, 30);
const _tw = 56.0, _th = 28.0, _gw = 16.0, _gh = 12.0;
const _ox = 444.0, _oy = 150.0;

Offset iso(double gx, double gy, [double z = 0]) => Offset(_ox + (gx - gy) * _tw / 2, _oy + (gx + gy) * _th / 2 - z);

Offset deskCenter(int i) => Offset(1.7 + (i % 4) * 2.15, 3.0 + (i ~/ 4) * 4.2);
Offset seatOf(int i) {
  final d = deskCenter(i);
  return Offset(d.dx, d.dy + (i ~/ 4 == 0 ? 1.15 : -1.15));
}

const _tableC = Offset(13.0, 3.2);
Offset meetingSeat(int k, int n) {
  final a = -math.pi / 2 + k * 2 * math.pi / math.max(n, 1);
  return Offset(_tableC.dx + math.cos(a) * 1.9, _tableC.dy + math.sin(a) * 1.5);
}

const _loungeSpots = [
  Offset(11.4, 9.0), Offset(12.6, 9.4), Offset(13.8, 9.0), Offset(15.0, 9.4),
  Offset(11.8, 11.0), Offset(14.4, 11.2), Offset(10.8, 10.4), Offset(15.2, 10.6),
];

class OfficeColors {
  final Color floor, floorLine, wall, wallSide, desk, deskSide, accent, text, card, carpet, rug, ok, warn, bad, info, muted;
  /// Brand look: a flat two-tone "blueprint" office (red base / bone lines).
  final bool blueprint;
  const OfficeColors({
    this.blueprint = false,
    required this.floor,
    required this.floorLine,
    required this.wall,
    required this.wallSide,
    required this.desk,
    required this.deskSide,
    required this.accent,
    required this.text,
    required this.card,
    required this.carpet,
    required this.rug,
    required this.ok,
    required this.warn,
    required this.bad,
    required this.info,
    required this.muted,
  });
}

/// Neovarch flat-print office: bone floor plates, ink desks and red accents
/// on the red base ([paper]); the near-black variant in dark mode.
OfficeColors brandOfficeColors({required bool paper}) => paper
    ? const OfficeColors(
        blueprint: true,
        floor: Color(0xFFF2EDE4),
        floorLine: Color(0xFFE3B3AE),
        wall: Color(0xFFE7E0D4),
        wallSide: Color(0xFFD9D0C2),
        desk: Color(0xFF140607),
        deskSide: Color(0xFF3A1A1C),
        accent: Color(0xFFC8101A),
        text: Color(0xFF140607),
        card: Color(0xFFF2EDE4),
        carpet: Color(0xFFF1D2CD),
        rug: Color(0xFFE6B5AF),
        ok: Color(0xFF1A7F4B),
        warn: Color(0xFFA86A00),
        bad: Color(0xFFC8101A),
        info: Color(0xFFC8101A),
        muted: Color(0xFF5E4B47),
      )
    : const OfficeColors(
        blueprint: true,
        floor: Color(0xFF151515),
        floorLine: Color(0xFF4A1A1D),
        wall: Color(0xFF1E1E1E),
        wallSide: Color(0xFF181818),
        desk: Color(0xFFF2EDE4),
        deskSide: Color(0xFFB3A99A),
        accent: Color(0xFFF2EDE4),
        text: Color(0xFFF2EDE4),
        card: Color(0xFF161616),
        carpet: Color(0xFF241011),
        rug: Color(0xFF3A1214),
        ok: Color(0xFF7DF0B8),
        warn: Color(0xFFFFD36B),
        bad: Color(0xFFFF8A5C),
        info: Color(0xFFF2555C),
        muted: Color(0xFFA39A8E),
      );

class PlacedAgent {
  final Agent agent;
  final Offset grid;
  final bool walking;
  const PlacedAgent(this.agent, this.grid, {this.walking = false});
  Offset get screen => iso(grid.dx, grid.dy);
}

/// Where every agent stands this frame. Shared by painter and hit-testing.
List<PlacedAgent> placeAgents(List<Agent> agents, Meeting? meeting) {
  final out = <PlacedAgent>[];
  final used = agents.map((a) => a.deskIndex).whereType<int>().toSet();
  final free = [for (var i = 0; i < 8; i++) if (!used.contains(i)) i];
  final liveParts = meeting?.live == true ? meeting!.participants : const <String>[];
  var lounge = 0;
  for (final a in agents) {
    var desk = a.deskIndex;
    if (desk == null && free.isNotEmpty && a.status != 'idle') desk = free.removeAt(0);
    Offset g;
    if (a.status == 'meeting' || liveParts.contains(a.name)) {
      final k = liveParts.indexOf(a.name);
      g = meetingSeat(k < 0 ? 0 : k, math.max(liveParts.length, 2));
    } else if ((a.status == 'working' || a.status == 'review' || a.status == 'blocked') && desk != null && desk < 8) {
      g = seatOf(desk);
      if (a.status == 'review') g = g.translate(0.55, 0);
    } else {
      g = _loungeSpots[lounge % _loungeSpots.length];
      lounge++;
    }
    out.add(PlacedAgent(a, g));
  }
  return out;
}

/// Smoothed on-screen grid positions: agents walk to their new spot instead
/// of jumping (Desktop office animates the same way).
final Map<String, Offset> _glide = {};
double _glideLast = -1;

List<PlacedAgent> glideAgents(List<PlacedAgent> target, double t, {bool instant = false}) {
  final dt = _glideLast < 0 ? 1.0 : (t - _glideLast).clamp(0.0, 0.25);
  _glideLast = t;
  final out = <PlacedAgent>[];
  for (final p in target) {
    final cur = _glide[p.agent.name];
    Offset g;
    if (cur == null || instant) {
      g = p.grid;
    } else {
      final d = p.grid - cur;
      final dist = d.distance;
      const speed = 3.2; // grid cells per second
      g = dist <= speed * dt ? p.grid : cur + d / dist * (speed * dt);
    }
    _glide[p.agent.name] = g;
    out.add(PlacedAgent(p.agent, g, walking: (g - p.grid).distance > 0.02));
  }
  return out;
}

class OfficePainter extends CustomPainter {
  OfficePainter({
    required this.agents,
    required this.tasks,
    required this.meeting,
    required this.colors,
    required this.t,
    required this.brightness,
    this.selectedDesk,
    this.reduceMotion = false,
  });
  final bool reduceMotion;
  final List<Agent> agents;
  final List<Task> tasks;
  final Meeting? meeting;
  final OfficeColors colors;
  final double t; // seconds
  final Brightness brightness;
  final int? selectedDesk;

  late final List<PlacedAgent> placed = glideAgents(placeAgents(agents, meeting), t, instant: reduceMotion);

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width / officeCanvas.width, size.height / officeCanvas.height);
    canvas.save();
    canvas.translate((size.width - officeCanvas.width * s) / 2, (size.height - officeCanvas.height * s) / 2);
    canvas.scale(s);
    canvas.translate(-_sceneOrigin.dx, -_sceneOrigin.dy);
    _floor(canvas);
    _walls(canvas);
    _board(canvas);
    // Depth-sorted props + agents.
    final items = <(double, void Function())>[];
    for (var i = 0; i < 8; i++) {
      final d = deskCenter(i);
      items.add((d.dx + d.dy, () => _desk(canvas, i)));
    }
    items.add((_tableC.dx + _tableC.dy, () => _table(canvas)));
    items.add((12.6 + 10.2, () => _sofa(canvas)));
    items.add((15.4 + 0.8, () => _plant(canvas, 15.4, 0.8)));
    items.add((0.8 + 11.2, () => _plant(canvas, 0.8, 11.2)));
    items.add((15.4 + 11.4, () => _plant(canvas, 15.4, 11.4)));
    items.add((10.2 + 6.4, () => _plant(canvas, 10.2, 6.4)));
    for (final p in placed) {
      items.add((p.grid.dx + p.grid.dy + 0.05, () => _agent(canvas, p)));
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    for (final it in items) {
      it.$2();
    }
    // Name tags last, so a desk in front never hides who sits behind it.
    for (final p in placed) {
      _tag(canvas, p);
    }
    _bubbles(canvas);
    canvas.restore();
  }

  Path _quad(Offset a, Offset b, Offset c, Offset d) => Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy)
    ..lineTo(c.dx, c.dy)
    ..lineTo(d.dx, d.dy)
    ..close();

  Path _rect(double x0, double y0, double x1, double y1, [double z = 0]) => _quad(iso(x0, y0, z), iso(x1, y0, z), iso(x1, y1, z), iso(x0, y1, z));

  void _floor(Canvas c) {
    // flat offset ground plate (print look, no blur)
    c.drawPath(_rect(-0.2, -0.2, _gw + 0.4, _gh + 0.4).shift(const Offset(0, 10)),
        Paint()..color = Colors.black.withValues(alpha: brightness == Brightness.dark ? 0.35 : 0.12));
    c.drawPath(_rect(0, 0, _gw, _gh), Paint()..color = colors.floor);
    c.drawPath(_rect(10, 0, _gw, 6.6), Paint()..color = colors.carpet);
    c.drawPath(_rect(10.4, 8.2, 15.8, 11.8), Paint()..color = colors.rug);
    final line = Paint()
      ..color = colors.floorLine
      ..strokeWidth = 0.7;
    for (var x = 1; x < _gw; x++) {
      c.drawLine(iso(x.toDouble(), 0), iso(x.toDouble(), _gh), line);
    }
    for (var y = 1; y < _gh; y++) {
      c.drawLine(iso(0, y.toDouble()), iso(_gw, y.toDouble()), line);
    }
    // glass partition of the meeting room
    final glass = Paint()
      ..color = colors.info.withValues(alpha: 0.35)
      ..strokeWidth = 2;
    c.drawLine(iso(10, 0.2), iso(10, 5.0), glass);
    c.drawLine(iso(10, 6.6), iso(13.2, 6.6), glass);
    c.drawLine(iso(14.6, 6.6), iso(_gw, 6.6), glass);
  }

  void _walls(Canvas c) {
    const h = 92.0;
    // back-left wall (gx = 0)
    c.drawPath(_quad(iso(0, _gh), iso(0, 0), iso(0, 0, h), iso(0, _gh, h)), Paint()..color = colors.wallSide);
    // back-right wall (gy = 0)
    c.drawPath(_quad(iso(0, 0), iso(_gw, 0), iso(_gw, 0, h), iso(0, 0, h)), Paint()..color = colors.wall);
    final edge = Paint()
      ..color = colors.floorLine
      ..strokeWidth = 1.2;
    c.drawLine(iso(0, 0), iso(0, 0, h), edge);
    // top caps
    final cap = Paint()..color = Color.lerp(colors.wall, colors.text, 0.12)!;
    c.drawPath(_quad(iso(0, _gh, h), iso(0, 0, h), iso(-0.25, -0.25, h), iso(-0.25, _gh, h)), cap);
    c.drawPath(_quad(iso(0, 0, h), iso(_gw, 0, h), iso(_gw, -0.25, h), iso(-0.25, -0.25, h)), cap);
    // windows on the right wall
    final glass = Paint()..color = colors.info.withValues(alpha: brightness == Brightness.dark ? 0.22 : 0.28);
    final frame = Paint()
      ..color = colors.floorLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final x in [4.0, 7.0, 11.0, 14.0]) {
      final p = _quad(iso(x, 0, 22), iso(x + 1.8, 0, 22), iso(x + 1.8, 0, 74), iso(x, 0, 74));
      c.drawPath(p, glass);
      c.drawPath(p, frame);
      c.drawLine(iso(x + 0.9, 0, 22), iso(x + 0.9, 0, 74), frame);
    }
    // a light sweep across the glass
    final sweep = (t * 0.08) % 1.0;
    final sx = 4 + sweep * 12;
    c.drawPath(_quad(iso(sx, 0, 26), iso(sx + 0.3, 0, 26), iso(sx + 0.7, 0, 70), iso(sx + 0.4, 0, 70)),
        Paint()..color = Colors.white.withValues(alpha: 0.10));
  }

  /// The Kanban wall: 4 columns with counts and mini cards.
  void _board(Canvas c) {
    const y0 = 1.2, y1 = 9.2, z0 = 16.0, z1 = 84.0;
    final board = _quad(iso(0, y1, z0), iso(0, y0, z0), iso(0, y0, z1), iso(0, y1, z1));
    final dark = brightness == Brightness.dark;
    c.drawPath(board, Paint()..color = colors.blueprint ? const Color(0xFF2A0D0F) : (dark ? const Color(0xFF173B33) : const Color(0xFF1F5A4C)));
    c.drawPath(
        board,
        Paint()
          ..color = colors.floorLine
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    final counts = List.filled(4, 0);
    final byCol = List.generate(4, (_) => <Task>[]);
    for (final t in tasks) {
      final col = columnOf(t.status);
      counts[col]++;
      byCol[col].add(t);
    }
    final colW = (y1 - y0) / 4;
    for (var k = 0; k < 4; k++) {
            // TODO reads first (left on screen = front of the wall)
      final cy0 = y1 - (k + 1) * colW + 0.12, cy1 = y1 - k * colW - 0.12;
      final label = '${boardColumns[k]} ${counts[k]}';
      _wallText(c, label, Offset.lerp(iso(0, cy0, z1 - 10), iso(0, cy1, z1 - 10), 0.5)!, 9.5, Colors.white.withValues(alpha: 0.92));
      final show = byCol[k].take(5).toList();
      for (var r = 0; r < show.length; r++) {
        final zt = z1 - 20 - r * 11.0;
        final card = _quad(iso(0, cy1, zt - 8), iso(0, cy0, zt - 8), iso(0, cy0, zt), iso(0, cy1, zt));
        final st = show[r].status;
        final col = st == 'blocked'
            ? colors.bad
            : st == 'running'
                ? colors.ok
                : st == 'review'
                    ? colors.info
                    : st == 'done'
                        ? const Color(0xFFB9C7C2)
                        : const Color(0xFFF2E3A6);
        c.drawPath(card, Paint()..color = col.withValues(alpha: 0.92));
      }
      if (k < 3) {
        c.drawLine(iso(0, y0 + (k + 1) * colW, z0 + 4), iso(0, y0 + (k + 1) * colW, z1 - 4),
            Paint()
              ..color = Colors.white.withValues(alpha: 0.18)
              ..strokeWidth = 1);
      }
    }
  }

  void _wallText(Canvas c, String s, Offset at, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
      textDirection: TextDirection.ltr,
    )..layout();
    c.save();
    c.translate(at.dx, at.dy);
    // follow the wall's slope (gy axis goes down-left: angle of iso(0,1)-iso(0,0))
    c.transform(Matrix4.skewY(math.atan(-0.5)).storage);
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
  }

  void _box(Canvas c, double x0, double y0, double x1, double y1, double z0, double z1, Color top, Color left, Color right) {
    c.drawPath(_quad(iso(x0, y1, z0), iso(x1, y1, z0), iso(x1, y1, z1), iso(x0, y1, z1)), Paint()..color = left);
    c.drawPath(_quad(iso(x1, y0, z0), iso(x1, y1, z0), iso(x1, y1, z1), iso(x1, y0, z1)), Paint()..color = right);
    c.drawPath(_rect(x0, y0, x1, y1, z1), Paint()..color = top);
  }

  void _desk(Canvas c, int i) {
    final d = deskCenter(i);
    final occupant = agents.where((a) => a.deskIndex == i).firstOrNull;
    final working = occupant != null && (occupant.status == 'working' || occupant.status == 'review' || occupant.status == 'blocked');
    final x0 = d.dx - 0.75, x1 = d.dx + 0.75, y0 = d.dy - 0.42, y1 = d.dy + 0.42;
    c.drawPath(_rect(x0 - 0.05, y0 - 0.05, x1 + 0.1, y1 + 0.12).shift(const Offset(0, 2)), Paint()..color = Colors.black.withValues(alpha: 0.10));
    _box(c, x0, y0, x1, y1, 0, 20, colors.desk, colors.deskSide, Color.lerp(colors.deskSide, Colors.black, 0.15)!);
    if (selectedDesk == i) {
      c.drawPath(
          _rect(x0 - 0.1, y0 - 0.1, x1 + 0.1, y1 + 0.1, 20),
          Paint()
            ..color = colors.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
    // monitor faces the seat
    final front = i ~/ 4 == 0;
    final my = front ? d.dy - 0.15 : d.dy + 0.15;
    final mx0 = d.dx - 0.38, mx1 = d.dx + 0.38;
    final screen = _quad(iso(mx0, my, 24), iso(mx1, my, 24), iso(mx1, my, 46), iso(mx0, my, 46));
    c.drawPath(screen, Paint()..color = colors.blueprint ? const Color(0xFF0D0D0D) : const Color(0xFF1B2229));
    if (working) {
      final flick = 0.75 + 0.25 * math.sin(t * 3 + i);
      final glow = occupant.status == 'blocked' ? colors.bad : (occupant.status == 'review' ? colors.info : colors.ok);
      final inner = _quad(iso(mx0 + 0.05, my, 26), iso(mx1 - 0.05, my, 26), iso(mx1 - 0.05, my, 44), iso(mx0 + 0.05, my, 44));
      c.drawPath(inner, Paint()..color = glow.withValues(alpha: 0.55 * flick));
      // code lines
      final lp = Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..strokeWidth = 1;
      for (var k = 0; k < 3; k++) {
        final z = 41 - k * 5.0;
        final len = 0.2 + ((t * 2 + k + i) % 1.0) * 0.4;
        c.drawLine(iso(mx0 + 0.1, my, z), iso(mx0 + 0.1 + len, my, z), lp);
      }
    }
    c.drawLine(iso(d.dx, my, 20), iso(d.dx, my, 24), Paint()..color = const Color(0xFF1B2229)..strokeWidth = 2);
    // mug
    final mug = iso(d.dx + 0.55, d.dy + (front ? 0.2 : -0.2), 20);
    c.drawCircle(mug.translate(0, -3), 3, Paint()..color = Colors.white.withValues(alpha: 0.85));
    // desk number
    final tp = TextPainter(
      text: TextSpan(text: '${i + 1}', style: TextStyle(color: colors.muted, fontSize: 9, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    final at = iso(d.dx - 0.62, front ? y1 : y0, 8);
    tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
  }

  void _table(Canvas c) {
    final ctr = iso(_tableC.dx, _tableC.dy, 18);
    final rect = Rect.fromCenter(center: ctr, width: 150, height: 76);
    c.drawOval(rect.shift(const Offset(0, 22)), Paint()..color = Colors.black.withValues(alpha: 0.10));
    c.drawOval(rect.shift(const Offset(0, 6)), Paint()..color = colors.deskSide);
    c.drawOval(rect, Paint()..color = Color.lerp(colors.desk, Colors.white, 0.25)!);
    final live = meeting?.live == true;
    if (live) {
      c.drawOval(
          rect.deflate(16),
          Paint()
            ..color = colors.warn.withValues(alpha: 0.35 + 0.15 * math.sin(t * 2))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
    final tp = TextPainter(
      text: TextSpan(text: live ? 'RAPAT BERLANGSUNG' : 'RUANG RAPAT', style: TextStyle(color: colors.muted, fontSize: 8.5, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, ctr - Offset(tp.width / 2, tp.height / 2));
    final n = meeting?.live == true ? math.max(meeting!.participants.length, 4) : 6;
    for (var k = 0; k < n; k++) {
      final s = meetingSeat(k, n);
      final p = iso(s.dx, s.dy, 2);
      c.drawCircle(p, 6, Paint()..color = colors.wallSide);
    }
  }

  void _sofa(Canvas c) {
    final cushion = colors.blueprint ? const Color(0xFF8E1A20) : (brightness == Brightness.dark ? const Color(0xFF3F5B78) : const Color(0xFF6E93B8));
    final side = Color.lerp(cushion, Colors.black, 0.25)!;
    _box(c, 11.0, 10.0, 15.2, 10.9, 0, 14, cushion, side, Color.lerp(side, Colors.black, 0.1)!);
    _box(c, 11.0, 10.7, 15.2, 11.1, 14, 30, Color.lerp(cushion, Colors.white, 0.1)!, side, side);
    // coffee table
    _box(c, 12.4, 8.6, 13.8, 9.3, 0, 10, colors.desk, colors.deskSide, colors.deskSide);
  }

  void _plant(Canvas c, double gx, double gy) {
    final base = iso(gx, gy);
    c.drawPath(_rect(gx - 0.25, gy - 0.25, gx + 0.25, gy + 0.25), Paint()..color = Colors.black.withValues(alpha: 0.12));
    if (colors.blueprint) {
      _box(c, gx - 0.22, gy - 0.22, gx + 0.22, gy + 0.22, 0, 14, const Color(0xFFEDE6D8), const Color(0xFFB3A99A), const Color(0xFF8F877C));
    } else {
      _box(c, gx - 0.22, gy - 0.22, gx + 0.22, gy + 0.22, 0, 14, const Color(0xFF8C6A4F), const Color(0xFF6E513B), const Color(0xFF5E4532));
    }
    final sway = math.sin(t * 1.3 + gx) * 1.5;
    final green = colors.blueprint ? const Color(0xFFE0262F) : (brightness == Brightness.dark ? const Color(0xFF3E8E63) : const Color(0xFF55B07E));
    for (final o in [const Offset(-6, -26), const Offset(6, -24), const Offset(0, -34)]) {
      c.drawCircle(base + o + Offset(sway, 0), 10, Paint()..color = green);
    }
    c.drawCircle(base + Offset(sway - 2, -30), 5, Paint()..color = Colors.white.withValues(alpha: 0.12));
  }

  void _agent(Canvas c, PlacedAgent p) {
    final a = p.agent;
    final phase = nameHue(a.name) / 57.0;
    final bob = p.walking ? math.sin(t * 14 + phase).abs() * 3.0 : switch (a.status) {
      'working' => math.sin(t * 6 + phase).abs() * 1.4,
      'blocked' => 0.0,
      _ => math.sin(t * 1.6 + phase) * 2.2,
    };
    var base = p.screen;
    if (a.status == 'blocked') base = base.translate(math.sin(t * 1.4 + phase) * 6, 0); // pacing
    final body = avatarColor(a.name, brightness);
    c.drawOval(Rect.fromCenter(center: base, width: 26, height: 11), Paint()..color = Colors.black.withValues(alpha: 0.22));
    final top = base.translate(0, -bob);
    // torso
    final torso = RRect.fromRectAndRadius(Rect.fromCenter(center: top.translate(0, -15), width: 22, height: 24), const Radius.circular(9));
    c.drawRRect(torso, Paint()..color = body);
    c.drawRRect(torso.shift(const Offset(0, 0)).deflate(0), Paint()..color = Colors.black.withValues(alpha: 0.08)..style = PaintingStyle.stroke);
    // head
    final head = top.translate(0, -36);
    c.drawCircle(head, 12, Paint()..color = const Color(0xFFF1D3B5));
    c.drawCircle(head, 12, Paint()..color = Colors.black.withValues(alpha: 0.10)..style = PaintingStyle.stroke..strokeWidth = 1);
    // hair cap tinted by name
    c.drawArc(Rect.fromCircle(center: head, radius: 12), math.pi, math.pi, true, Paint()..color = Color.lerp(body, Colors.black, 0.45)!);
    // status ring
    final ring = switch (a.status) {
      'working' => colors.ok,
      'review' => colors.info,
      'blocked' => colors.bad,
      'meeting' => colors.warn,
      _ => colors.muted,
    };
    c.drawCircle(
        head,
        15.5,
        Paint()
          ..color = ring.withValues(alpha: a.status == 'idle' ? 0.35 : 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    // badges
    if (a.status == 'working') {
      for (var k = 0; k < 3; k++) {
        final on = ((t * 3).floor() % 3) == k;
        c.drawCircle(head.translate(-6 + k * 6.0, -24), 2.4, Paint()..color = on ? colors.ok : colors.ok.withValues(alpha: 0.35));
      }
    } else if (a.status == 'blocked') {
      final pulse = 1 + 0.15 * math.sin(t * 6);
      c.drawCircle(head.translate(14, -16), 7 * pulse, Paint()..color = colors.bad);
      final ex = TextPainter(
        text: const TextSpan(text: '!', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
        textDirection: TextDirection.ltr,
      )..layout();
      ex.paint(c, head.translate(14, -16) - Offset(ex.width / 2, ex.height / 2));
    } else if (a.status == 'review') {
      c.drawCircle(head.translate(14, -16), 6.5, Paint()..color = colors.info);
      c.drawCircle(head.translate(14, -16), 2.2, Paint()..color = Colors.white);
    } else if (a.status == 'idle') {
      // a slow "z" drifting up
      final k = (t * 0.5 + phase) % 1.0;
      final z = TextPainter(
        text: TextSpan(text: 'z', style: TextStyle(color: colors.muted.withValues(alpha: 1 - k), fontSize: 9 + k * 4, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      z.paint(c, head.translate(10 + k * 6, -20 - k * 14));
    }
  }

  void _tag(Canvas c, PlacedAgent p) {
    final a = p.agent;
    var base = p.screen;
    if (a.status == 'blocked') base = base.translate(math.sin(t * 1.4 + nameHue(a.name) / 57.0) * 6, 0);
    final tp = TextPainter(
      text: TextSpan(text: a.displayName, style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 90);
    final tag = RRect.fromRectAndRadius(Rect.fromCenter(center: base.translate(0, 13), width: tp.width + 12, height: tp.height + 4), const Radius.circular(5));
    c.drawRRect(tag, Paint()..color = colors.blueprint ? const Color(0xF0141414) : const Color(0xE611161B));
    if (colors.blueprint) {
      c.drawRRect(tag, Paint()..color = const Color(0x99E0262F)..style = PaintingStyle.stroke..strokeWidth = 0.8);
    }
    tp.paint(c, tag.center - Offset(tp.width / 2, tp.height / 2));
  }

  void _bubbles(Canvas c) {
    final m = meeting;
    if (m == null || !m.live || m.currentSpeaker == null) return;
    final p = placed.where((x) => x.agent.name == m.currentSpeaker).firstOrNull;
    if (p == null) return;
    final last = m.turns.where((x) => x.speaker == m.currentSpeaker).lastOrNull;
    var text = last?.text ?? 'sedang bicara…';
    if (text.length > 80) text = '${text.substring(0, 80)}…';
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: colors.text, fontSize: 10, height: 1.3)),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: 170);
    final anchor = p.screen.translate(0, -62);
    final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: anchor.translate(0, -tp.height / 2 - 6), width: tp.width + 16, height: tp.height + 12), const Radius.circular(8));
    c.drawRRect(r.shift(const Offset(0, 2)), Paint()..color = Colors.black.withValues(alpha: 0.15));
    c.drawRRect(r, Paint()..color = colors.card);
    c.drawRRect(r, Paint()..color = colors.warn..style = PaintingStyle.stroke..strokeWidth = 1.2);
    c.drawPath(Path()
      ..moveTo(anchor.dx - 5, r.bottom)
      ..lineTo(anchor.dx, r.bottom + 7)
      ..lineTo(anchor.dx + 5, r.bottom)
      ..close(), Paint()..color = colors.card);
    tp.paint(c, Offset(r.left + 8, r.top + 6));
  }

  @override
  bool shouldRepaint(OfficePainter old) => true;
}

/// Converts a tap in widget coordinates to canvas coordinates and finds
/// what was hit: an agent, a desk, the board or the meeting table.
sealed class OfficeHit {
  const OfficeHit();
}

class AgentHit extends OfficeHit {
  final Agent agent;
  const AgentHit(this.agent);
}

class DeskHit extends OfficeHit {
  final int desk;
  const DeskHit(this.desk);
}

class BoardHit extends OfficeHit {
  const BoardHit();
}

class TableHit extends OfficeHit {
  const TableHit();
}

OfficeHit? hitTestOffice(Offset local, Size size, List<Agent> agents, Meeting? meeting) {
  final s = math.min(size.width / officeCanvas.width, size.height / officeCanvas.height);
  final dx = (size.width - officeCanvas.width * s) / 2, dy = (size.height - officeCanvas.height * s) / 2;
  final p = Offset((local.dx - dx) / s, (local.dy - dy) / s) + _sceneOrigin;
  // agents first (they stand in front)
  final placed = [for (final a in placeAgents(agents, meeting)) PlacedAgent(a.agent, _glide[a.agent.name] ?? a.grid)]..sort((a, b) => (b.grid.dx + b.grid.dy).compareTo(a.grid.dx + a.grid.dy));
  for (final a in placed) {
    final r = Rect.fromCenter(center: a.screen.translate(0, -22), width: 40, height: 64);
    if (r.contains(p)) return AgentHit(a.agent);
  }
  for (var i = 0; i < 8; i++) {
    final d = deskCenter(i);
    final r = Rect.fromCenter(center: iso(d.dx, d.dy, 22), width: 92, height: 64);
    if (r.contains(p)) return DeskHit(i);
  }
  final boardPath = Path()
    ..moveTo(iso(0, 9.2, 16).dx, iso(0, 9.2, 16).dy)
    ..lineTo(iso(0, 1.2, 16).dx, iso(0, 1.2, 16).dy)
    ..lineTo(iso(0, 1.2, 84).dx, iso(0, 1.2, 84).dy)
    ..lineTo(iso(0, 9.2, 84).dx, iso(0, 9.2, 84).dy)
    ..close();
  if (boardPath.contains(p)) return const BoardHit();
  if (Rect.fromCenter(center: iso(_tableC.dx, _tableC.dy, 18), width: 170, height: 96).contains(p)) return const TableHit();
  return null;
}
