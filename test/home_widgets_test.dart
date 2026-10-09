// Home-screen widgets 1.4.5: payload v2 (agents, counts, pairing, last
// activity), throttled pushes, Kantor snapshot pacing, and the widget routes.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neovarch_agent/remote/appearance.dart';
import 'package:neovarch_agent/remote/home_widget.dart';
import 'package:neovarch_agent/remote/office_models.dart';
import 'package:neovarch_agent/remote/remote_controller.dart';
import 'package:neovarch_agent/remote/remote_gateway.dart' show RemoteStatus;
import 'package:neovarch_agent/remote/saved_desktops.dart';
import 'package:neovarch_agent/remote/ui/remote_app.dart' show themeFor;
import 'package:neovarch_agent/remote/ui/remote_office_3d.dart';
import 'package:neovarch_agent/remote/ui/remote_office_screen.dart';
import 'package:neovarch_agent/state/app_controller.dart' show settingsProvider;
import 'package:neovarch_agent/state/settings_controller.dart';
import 'package:neovarch_agent/theme/neovarch_mobile_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _sec = DateTime(2026, 10, 9, 15).millisecondsSinceEpoch ~/ 1000;

Map<String, dynamic> _office() => {
      'agents': [
        {'id': 'kanban:writer', 'kind': 'kanban', 'name': 'writer', 'role': 'Pelaksana', 'status': 'idle', 'current_task': 'Draf laporan', 'last_activity': _sec - 3600},
        {'id': 'session:s2', 'kind': 'session', 'session_id': 's2', 'name': 'Ayu', 'role': 'Agen', 'status': 'waiting-approval', 'current_task': 'Hapus cache lama', 'last_activity': _sec - 60},
        {'id': 'session:s1', 'kind': 'session', 'session_id': 's1', 'name': 'Raka', 'role': 'Agen', 'status': 'working', 'current_task': 'Rapikan folder Unduhan', 'last_activity': _sec - 20, 'last_activity_text': 'menjalankan move_files'},
      ],
      'kanban': {'todo': 2, 'running': 1, 'done': 4},
      'feed': [],
    };

/// Manual timers for the throttle.
class _FakeTimers {
  final pending = <(Duration, void Function())>[];
  Timer make(Duration d, void Function() f) {
    pending.add((d, f));
    return _T(this, pending.last);
  }

  void fire() {
    final all = [...pending];
    pending.clear();
    for (final (_, f) in all) {
      f();
    }
  }
}

class _T implements Timer {
  _T(this.o, this.e);
  final _FakeTimers o;
  final (Duration, void Function()) e;
  @override
  void cancel() => o.pending.remove(e);
  @override
  bool get isActive => o.pending.contains(e);
  @override
  int get tick => 0;
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
    await settings.load(); // outside the widget tests' fake-async zone
    NV.palette = NvPalette.red;
  });

  tearDown(() {
    remoteLaunchAction.value = null;
    debugOfficeSceneBuilder = null;
  });

  RemoteController controller({bool paired = true, RemoteStatus status = RemoteStatus.connected}) {
    final desktops = SavedDesktops(prefs)..load();
    final r = RemoteController(desktops)
      ..status = status
      ..debugApprovals = []
      ..office = OfficeSnapshot.fromJson(_office());
    if (paired) r.desktop = desktops.items.first;
    return r;
  }

  group('payload v2', () {
    test('agents sorted working → waiting → idle with spec coats and initials', () {
      final p = homeWidgetPayload(controller(), accent: 0xFFEE1C1C);
      expect(p['v'], 2);
      expect(p['paired'], true);
      expect(p['connected'], true);
      expect(p['working'], 1);
      expect(p['waitingAgents'], 1);
      expect(p['agentCount'], 3);
      expect(p['tasks'], 3); // done lane not counted
      expect(p['accent'], 0xFFEE1C1C);
      final agents = (p['agents'] as List).cast<Map<String, Object?>>();
      expect(agents.map((a) => a['name']), ['Raka', 'Ayu', 'writer']);
      // agent-identity-spec reference values
      expect(agents[0]['coat'], 0xFF3A4A6E); // session:s1
      expect(agents[1]['coat'], 0xFF7A2E2E); // session:s2
      expect(agents[2]['coat'], 0xFF8A6A3A); // kanban:writer
      expect(agents[2]['initial'], 'W');
      expect(agents[0]['task'], 'Rapikan folder Unduhan');
      expect(agents[1]['status'], 'waiting-approval');
    });

    test('last activity = the newest agent activity', () {
      final p = homeWidgetPayload(controller());
      expect(p['lastName'], 'Raka');
      expect(p['lastText'], 'menjalankan move_files');
      expect(p['lastAt'], (_sec - 20) * 1000);
    });

    test('accent defaults to the app accent', () {
      expect(homeWidgetPayload(controller())['accent'], NV.red.toARGB32());
    });

    test('no paired PC: paired=false, "belum dipasangkan"', () {
      final r = controller(paired: false, status: RemoteStatus.disconnected)..office = null;
      final p = homeWidgetPayload(r);
      expect(p['paired'], false);
      expect(p['connected'], false);
      expect(p['status'], 'belum dipasangkan');
      expect(p['pc'], 'Neovarch');
      expect(p['agents'], isEmpty);
      expect(p['lastAt'], isNull);
    });

    test('paired but offline: "terputus"', () {
      final p = homeWidgetPayload(controller(status: RemoteStatus.disconnected));
      expect(p['paired'], true);
      expect(p['status'], 'terputus');
    });

    test('at most $homeWidgetMaxAgents agents are sent', () {
      final j = _office();
      j['agents'] = [
        for (var i = 0; i < 20; i++) {'id': 'session:x$i', 'kind': 'session', 'name': 'A$i', 'role': '', 'status': 'idle'},
      ];
      final r = controller()..office = OfficeSnapshot.fromJson(j);
      final p = homeWidgetPayload(r);
      expect((p['agents'] as List).length, homeWidgetMaxAgents);
      expect(p['agentCount'], 20);
    });

    test('payload is codec-safe (only maps, lists, strings, numbers, bools, null)', () {
      final p = homeWidgetPayload(controller());
      const StandardMethodCodec().encodeMethodCall(MethodCall('updateWidget', p));
      expect(jsonDecode(jsonEncode(p)), p);
    });
  });

  group('throttle', () {
    Map<String, Object?> pl(int working, {bool connected = true}) => {'connected': connected, 'paired': true, 'working': working};

    test('first send at once; changes within the interval wait; the newest goes out', () {
      var now = DateTime(2026, 10, 9, 16);
      final timers = _FakeTimers();
      final sent = <Map<String, Object?>>[];
      final t = HomeWidgetThrottle(send: sent.add, clock: () => now, timer: timers.make);
      t.push(pl(1));
      expect(sent.length, 1);
      now = now.add(const Duration(seconds: 2));
      t.push(pl(2));
      t.push(pl(3));
      expect(sent.length, 1);
      expect(timers.pending.length, 1);
      expect(timers.pending.single.$1, const Duration(seconds: 8));
      now = now.add(const Duration(seconds: 8));
      timers.fire();
      expect(sent.length, 2);
      expect(sent.last['working'], 3); // 2 was dropped
      expect(t.pending, isNull);
    });

    test('unchanged payload is never sent and cancels a queued change', () {
      var now = DateTime(2026, 10, 9, 16);
      final timers = _FakeTimers();
      final sent = <Map<String, Object?>>[];
      final t = HomeWidgetThrottle(send: sent.add, clock: () => now, timer: timers.make);
      t.push(pl(1));
      t.push(pl(1));
      expect(sent.length, 1);
      now = now.add(const Duration(seconds: 1));
      t.push(pl(2));
      expect(timers.pending.length, 1);
      t.push(pl(1)); // back to what the widget shows
      expect(timers.pending, isEmpty);
      expect(t.pending, isNull);
      expect(sent.length, 1);
    });

    test('connection change goes out at once (no stale online dot)', () {
      var now = DateTime(2026, 10, 9, 16);
      final timers = _FakeTimers();
      final sent = <Map<String, Object?>>[];
      final t = HomeWidgetThrottle(send: sent.add, clock: () => now, timer: timers.make);
      t.push(pl(1));
      now = now.add(const Duration(seconds: 1));
      t.push(pl(2));
      t.push(pl(2, connected: false));
      expect(sent.length, 2);
      expect(sent.last['connected'], false);
      expect(timers.pending, isEmpty);
    });

    test('after the interval a change is sent at once', () {
      var now = DateTime(2026, 10, 9, 16);
      final sent = <Map<String, Object?>>[];
      final t = HomeWidgetThrottle(send: sent.add, clock: () => now, timer: _FakeTimers().make);
      t.push(pl(1));
      now = now.add(const Duration(seconds: 11));
      t.push(pl(2));
      expect(sent.length, 2);
    });

    test('HomeWidgetSync throttles controller updates', () {
      var now = DateTime(2026, 10, 9, 16);
      final timers = _FakeTimers();
      final sent = <Map<String, Object?>>[];
      final sync = HomeWidgetSync(send: (p) async => sent.add(p), clock: () => now, timer: timers.make);
      final r = controller();
      sync.update(r);
      final j = _office();
      (j['agents'] as List)[2]['current_task'] = 'Tugas baru';
      r.office = OfficeSnapshot.fromJson(j);
      now = now.add(const Duration(seconds: 3));
      sync.update(r);
      expect(sent.length, 1);
      timers.fire();
      expect(sent.length, 2);
      expect(sent.last['task'], 'Raka: Tugas baru');
      sync.dispose();
    });
  });

  group('Kantor snapshot', () {
    test('only while visible, after the first delay, then paced', () {
      final t0 = DateTime(2026, 10, 9, 16);
      final s = KantorSnapshotThrottle();
      expect(s.shouldCapture(t0, visible: true), false); // scene not ready
      s.sceneReady(t0);
      expect(s.shouldCapture(t0.add(const Duration(seconds: 2)), visible: true), false);
      expect(s.shouldCapture(t0.add(const Duration(seconds: 5)), visible: false), false);
      expect(s.shouldCapture(t0.add(const Duration(seconds: 5)), visible: true), true);
      s.captured(t0.add(const Duration(seconds: 5)));
      expect(s.shouldCapture(t0.add(const Duration(seconds: 60)), visible: true), false);
      expect(s.shouldCapture(t0.add(const Duration(seconds: 126)), visible: true), true);
      s.sceneChanged();
      expect(s.shouldCapture(t0.add(const Duration(seconds: 26)), visible: true), true); // change: 20 s
    });

    test('data URL decode accepts jpeg/png, rejects junk', () {
      final bytes = List<int>.generate(2048, (i) => i % 256);
      expect(decodeSnapshotDataUrl('data:image/jpeg;base64,${base64Encode(bytes)}'), bytes);
      expect(decodeSnapshotDataUrl('data:image/png;base64,${base64Encode(bytes)}'), isNotNull);
      expect(decodeSnapshotDataUrl('data:text/html;base64,${base64Encode(bytes)}'), isNull);
      expect(decodeSnapshotDataUrl('data:image/jpeg;base64,AAAA'), isNull); // too small
      expect(decodeSnapshotDataUrl('data:image/jpeg;base64,@@@'), isNull);
      expect(decodeSnapshotDataUrl(null), isNull);
    });

    testWidgets('saveWidgetSnapshot / widgetsPlaced go over neovarch/device', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('neovarch/device'), (c) async {
        calls.add(c);
        return c.method == 'widgetsPlaced' ? true : '/data/files/widgets/kantor.jpg';
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('neovarch/device'), null));
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(await kantorWidgetPlaced(), true);
      expect(await saveKantorSnapshot(Uint8List.fromList(List.filled(1024, 7))), '/data/files/widgets/kantor.jpg');
      debugDefaultTargetPlatformOverride = null;
      expect(calls.map((c) => c.method), ['widgetsPlaced', 'saveWidgetSnapshot']);
      expect((calls.first.arguments as Map)['kind'], 'quick');
      expect(((calls.last.arguments as Map)['bytes'] as Uint8List).length, 1024);
    });
  });

  testWidgets('widget "Agen" row: agent:<id> opens that agent\'s sheet in Kantor', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    debugOfficeSceneBuilder = (state, onTap) => const SizedBox(height: 200);
    final look = AppearanceController(prefs);
    final r = controller();
    remoteLaunchAction.value = 'agent:session:s2';
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => settings),
        remoteProvider.overrideWith((ref) => r),
        appearanceProvider.overrideWith((ref) => look),
      ],
      child: MaterialApp(theme: themeFor(look), home: RemoteOfficeScreen(onOpenChat: () {}, onOpenApprovals: () {})),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AgentSheet), findsOneWidget);
    expect(tester.widget<AgentSheet>(find.byType(AgentSheet)).agentId, 'session:s2');
    expect(remoteLaunchAction.value, isNull);
  });

  testWidgets('agent:<id> for an agent that is gone is dropped', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    debugOfficeSceneBuilder = (state, onTap) => const SizedBox(height: 200);
    final look = AppearanceController(prefs);
    remoteLaunchAction.value = 'agent:session:nope';
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => settings),
        remoteProvider.overrideWith((ref) => controller()),
        appearanceProvider.overrideWith((ref) => look),
      ],
      child: MaterialApp(theme: themeFor(look), home: RemoteOfficeScreen(onOpenChat: () {}, onOpenApprovals: () {})),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AgentSheet), findsNothing);
    expect(remoteLaunchAction.value, isNull);
  });
}
