// v1.4.4: Kantor 3D (three.js WebView fed over the JS bridge), the agent
// sheet with "Kasih tugas", the list/3D toggle and live updates from the
// gateway event stream.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neovarch_agent/data/gateway_client.dart';
import 'package:neovarch_agent/remote/appearance.dart';
import 'package:neovarch_agent/remote/office_models.dart';
import 'package:neovarch_agent/remote/office_scene_state.dart';
import 'package:neovarch_agent/remote/remote_controller.dart';
import 'package:neovarch_agent/remote/remote_gateway.dart' show RemoteStatus;
import 'package:neovarch_agent/remote/saved_desktops.dart';
import 'package:neovarch_agent/remote/ui/remote_office_3d.dart';
import 'package:neovarch_agent/remote/ui/remote_app.dart' show themeFor;
import 'package:neovarch_agent/remote/ui/remote_office_screen.dart';
import 'package:neovarch_agent/state/app_controller.dart' show settingsProvider;
import 'package:neovarch_agent/state/settings_controller.dart';
import 'package:neovarch_agent/theme/neovarch_mobile_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> officeJson({String rakaStatus = 'working', String rakaTask = 'Rapikan folder Unduhan'}) => {
      'agents': [
        {'id': 'session:s1', 'kind': 'session', 'session_id': 's1', 'name': 'Raka', 'role': 'Agen remote · HP', 'status': rakaStatus, 'current_task': rakaTask},
        {'id': 'session:s2', 'kind': 'session', 'session_id': 's2', 'name': 'Ayu', 'role': 'Agen utama · desktop', 'status': 'waiting-approval',
          'current_task': 'Hapus cache lama', 'pending_approval': {'command': 'rm -rf ~/.cache/old'}},
        {'id': 'kanban:writer', 'kind': 'kanban', 'name': 'writer', 'role': 'Pelaksana tugas Kanban', 'status': 'idle', 'current_task': 'Draf laporan'},
      ],
      'kanban': {'todo': 2, 'running': 1},
      'feed': [],
    };

class SpyController extends RemoteController {
  SpyController(super.desktops);
  final created = <Map<String, String?>>[];
  @override
  Future<String?> createTask({required String title, String? body, String? assignee}) async {
    created.add({'title': title, 'body': body, 'assignee': assignee});
    return null;
  }
}

void main() {
  late SharedPreferences prefs;
  late SettingsController settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'remote.desktops': jsonEncode([
        {'id': 'pc1', 'name': 'PC Kantor', 'url': 'http://192.168.1.20:9319', 'addedAt': DateTime.now().toIso8601String()},
      ]),
      'remote.active': 'pc1',
    });
    prefs = await SharedPreferences.getInstance();
    settings = SettingsController(prefs);
    await settings.load();
    NV.palette = NvPalette.red;
    previewOfficeList = false;
  });

  tearDown(() => debugOfficeSceneBuilder = null);

  SpyController controller() {
    final desktops = SavedDesktops(prefs)..load();
    return SpyController(desktops)
      ..desktop = desktops.items.first
      ..status = RemoteStatus.connected
      ..debugApprovals = []
      ..office = OfficeSnapshot.fromJson(officeJson());
  }

  Future<void> pump(WidgetTester tester, RemoteController r, {double width = 390}) async {
    tester.view.physicalSize = Size(width * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final look = AppearanceController(prefs);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => settings),
        remoteProvider.overrideWith((ref) => r),
        appearanceProvider.overrideWith((ref) => look),
      ],
      child: MaterialApp(
        theme: themeFor(look),
        home: RemoteOfficeScreen(onOpenChat: () {}, onOpenApprovals: () {}),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Stand-in for the WebView: records every state the page would get and
  /// renders one tappable figure per agent.
  List<Map<String, Object?>> fakeScene() {
    final pushed = <Map<String, Object?>>[];
    debugOfficeSceneBuilder = (state, onTap) {
      pushed.add(state);
      final agents = (state['agents'] as List).cast<Map<String, Object?>>();
      return Column(key: const ValueKey('fake-scene'), children: [
        for (final a in agents)
          GestureDetector(
            key: ValueKey('figure-${a['id']}'),
            onTap: () => onTap('${a['id']}'),
            child: Text('${a['name']}:${a['status']}:${a['desk']}'),
          ),
      ]);
    };
    return pushed;
  }

  group('scene state', () {
    test('agents keep their desk across status changes; idle agents get none until busy', () {
      final desks = OfficeDeskAssigner();
      var s = officeSceneState(OfficeSnapshot.fromJson(officeJson()), desks: desks, accentArgb: 0xFFEE1C1C, dark: true);
      List<Map<String, Object?>> agents() => (s['agents'] as List).cast<Map<String, Object?>>();
      expect(s['accent'], '#ee1c1c');
      expect(s['kanban'], {'todo': 2, 'running': 1});
      expect(agents().map((a) => a['desk']).toList(), [0, 1, null]);
      expect(agents()[1]['status'], 'waiting-approval');
      expect(agents()[0]['task'], 'Rapikan folder Unduhan');
      // Raka goes idle (keeps desk 0), writer starts working (gets desk 2)
      final j = officeJson(rakaStatus: 'idle');
      (j['agents'] as List)[2]['status'] = 'working';
      s = officeSceneState(OfficeSnapshot.fromJson(j), desks: desks, accentArgb: 0xFFEE1C1C, dark: false);
      expect(agents().map((a) => a['desk']).toList(), [0, 1, 2]);
      expect(s['dark'], false);
      // Ayu leaves the office: her desk is freed
      (j['agents'] as List).removeAt(1);
      officeSceneState(OfficeSnapshot.fromJson(j), desks: desks, accentArgb: 0, dark: false);
      expect(desks.desks.containsKey('session:s2'), isFalse);
      expect(officeSceneScript({'a': 1}), 'window.nvOffice && window.nvOffice.setState({"a":1});');
    });
  });

  group('Kantor 3D', () {
    testWidgets('default is the 3D view, rendered from the remote office data', (tester) async {
      final pushed = fakeScene();
      await pump(tester, controller());
      expect(find.byKey(const ValueKey('office-scene-panel')), findsOneWidget);
      expect(find.text('Raka:working:0'), findsOneWidget);
      expect(find.text('Ayu:waiting-approval:1'), findsOneWidget);
      expect(find.text('writer:idle:null'), findsOneWidget);
      expect(pushed.last['kanban'], {'todo': 2, 'running': 1});
      // compact roster under the room carries the current tasks
      expect(find.byKey(const ValueKey('roster-session:s1')), findsOneWidget);
      expect(find.text('Rapikan folder Unduhan'), findsOneWidget);
      expect(find.byType(AgentDesk), findsNothing);
    });

    testWidgets('toggle switches between 3D and the list (with Kasih tugas on every card)', (tester) async {
      fakeScene();
      await pump(tester, controller());
      await tester.tap(find.byKey(const ValueKey('office-view-list')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('office-scene-panel')), findsNothing);
      expect(find.byType(AgentDesk), findsNWidgets(3));
      expect(find.byKey(const ValueKey('assign-session:s1')), findsOneWidget);
      expect(find.byKey(const ValueKey('assign-kanban:writer')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('office-view-visual')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('office-scene-panel')), findsOneWidget);
      expect(find.byType(AgentDesk), findsNothing);
    });

    testWidgets('no WebView on the platform: falls back to the list with a note', (tester) async {
      await pump(tester, controller()); // flutter test has no WebViewPlatform
      await tester.pump();
      expect(find.byKey(const ValueKey('office-3d-fallback')), findsOneWidget);
      expect(find.byType(AgentDesk), findsWidgets);
      expect(find.byKey(const ValueKey('office-scene-panel')), findsNothing);
    });

    testWidgets('a gateway office.update event updates the scene without a refresh', (tester) async {
      final pushed = fakeScene();
      final r = controller();
      await pump(tester, r);
      expect(find.text('Raka:working:0'), findsOneWidget);
      final before = pushed.length;
      // exactly what the WebSocket subscription delivers
      r.debugEvent(GatewayEventFrame('office.update', null, officeJson(rakaStatus: 'idle', rakaTask: 'Selesai, 3 berkas')));
      await tester.pump();
      expect(pushed.length, greaterThan(before));
      expect(find.text('Raka:idle:0'), findsOneWidget); // same desk kept
      expect(find.text('Selesai, 3 berkas'), findsOneWidget);
    });

    testWidgets('tapping an agent opens the sheet; Kasih tugas creates a Kanban task assigned to it', (tester) async {
      fakeScene();
      final r = controller();
      await pump(tester, r);
      await tester.tap(find.byKey(const ValueKey('figure-session:s1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('agent-sheet')), findsOneWidget);
      expect(find.byKey(const ValueKey('agent-sheet-task')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('assign-task-field')), 'Cek email kampus\nBalas yang penting saja');
      await tester.tap(find.byKey(const ValueKey('assign-task-send')));
      await tester.pumpAndSettle();
      expect(r.created, [
        {'title': 'Cek email kampus', 'body': 'Balas yang penting saja', 'assignee': 'Raka'}
      ]);
      expect(find.byKey(const ValueKey('agent-sheet')), findsNothing);
      expect(find.text('Tugas dikirim ke Raka'), findsOneWidget);
    });

    testWidgets('Kasih tugas from a list card uses that agent as assignee', (tester) async {
      previewOfficeList = true;
      final r = controller();
      await pump(tester, r);
      await tester.dragUntilVisible(find.byKey(const ValueKey('assign-kanban:writer')), find.byKey(const ValueKey('office-list')), const Offset(0, -200));
      await tester.ensureVisible(find.byKey(const ValueKey('assign-kanban:writer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('assign-kanban:writer')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('assign-task-field')), 'Bab 3');
      await tester.tap(find.byKey(const ValueKey('assign-task-send')));
      await tester.pumpAndSettle();
      expect(r.created.single['assignee'], 'writer');
      expect(r.created.single['title'], 'Bab 3');
    });

    testWidgets('the open sheet follows live pushes', (tester) async {
      fakeScene();
      final r = controller();
      await pump(tester, r);
      await tester.tap(find.byKey(const ValueKey('roster-session:s1')));
      await tester.pumpAndSettle();
      r.debugEvent(GatewayEventFrame('office.update', null, officeJson(rakaTask: 'Tugas baru dari PC')));
      await tester.pump();
      expect(find.descendant(of: find.byKey(const ValueKey('agent-sheet')), matching: find.text('Tugas baru dari PC')), findsOneWidget);
    });
  });
}
