// What the Kantor 3D scene shows, derived from the PC's live Office snapshot
// (`GET /api/office`, then every `office.update` push) and handed to the
// three.js page over the JS bridge. Pure Dart, so it is unit-tested without a
// WebView.
import 'dart:convert';

import 'office_models.dart';

/// Desks in the room (two rows of four low desks).
const officeSceneDesks = 8;

/// Keeps every pegawai at the same desk while it stays in the office, so a
/// status change on the PC never reshuffles the room. Agents get a desk the
/// first time they are busy; it is freed when they leave the snapshot.
class OfficeDeskAssigner {
  final Map<String, int> _desk = {};

  Map<String, int> get desks => Map.unmodifiable(_desk);

  Map<String, int?> assign(List<OfficeAgent> agents) {
    final ids = {for (final a in agents) a.id};
    _desk.removeWhere((id, _) => !ids.contains(id));
    final used = _desk.values.toSet();
    for (final a in agents) {
      if (_desk.containsKey(a.id) || !(a.working || a.waiting)) continue;
      for (var i = 0; i < officeSceneDesks; i++) {
        if (!used.contains(i)) {
          _desk[a.id] = i;
          used.add(i);
          break;
        }
      }
    }
    return {for (final a in agents) a.id: _desk[a.id]};
  }
}

String _hex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// The scene state as the page's `nvOffice.setState(...)` expects it.
Map<String, Object?> officeSceneState(
  OfficeSnapshot office, {
  required OfficeDeskAssigner desks,
  required int accentArgb,
  required bool dark,
  bool motion = true,
}) {
  final at = desks.assign(office.agents);
  return {
    'accent': _hex(accentArgb),
    'dark': dark,
    'motion': motion,
    'kanban': office.kanban,
    'agents': [
      for (final a in office.agents)
        {
          'id': a.id,
          'name': a.name,
          'role': a.role,
          'status': a.status,
          'task': a.task,
          'tool': a.tool,
          'desk': at[a.id],
        },
    ],
  };
}

/// The JavaScript that pushes [state] into the page.
String officeSceneScript(Map<String, Object?> state) =>
    'window.nvOffice && window.nvOffice.setState(${jsonEncode(state)});';
