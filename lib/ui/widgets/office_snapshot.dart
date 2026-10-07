// Renders the isometric office off-screen to a PNG data URL so the agent can
// literally look at it (tool office_view). Same painter as the Kantor tab, in
// the flat Neovarch colours, frozen (no motion).
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../state/office_controller.dart';
import 'office_painter.dart';

Future<String?> renderOfficeSnapshot(OfficeController office, {double scale = 1.4}) async {
  final w = (officeCanvas.width * scale).round();
  final h = (officeCanvas.height * scale).round();
  final size = Size(w.toDouble(), h.toDouble());
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFC8101A));
  OfficePainter(
    agents: office.agents,
    tasks: office.tasks,
    meeting: office.meeting,
    colors: brandOfficeColors(paper: true),
    t: 0,
    brightness: Brightness.light,
    reduceMotion: true,
  ).paint(canvas, size);
  final img = await rec.endRecording().toImage(w, h);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  if (bytes == null) return null;
  return 'data:image/png;base64,${base64Encode(bytes.buffer.asUint8List())}';
}
