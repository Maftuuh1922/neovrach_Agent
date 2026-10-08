// Renders every main screen of the phone remote at 390x844 (dark, Neovarch
// mobile theme) with demo data, fails on any layout overflow, and writes a
// PNG per screen to $NV_SHOTS_DIR (default build/screenshots/remote).
//
//   NV_SHOTS_DIR=/path flutter test test/remote_screens_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neovarch_agent/main.dart' as app;
import 'package:neovarch_agent/models/models.dart';
import 'package:neovarch_agent/remote/remote_controller.dart';
import 'package:neovarch_agent/remote/remote_gateway.dart';
import 'package:neovarch_agent/remote/remote_transcript.dart';
import 'package:neovarch_agent/remote/saved_desktops.dart';
import 'package:neovarch_agent/remote/ui/connect_screen.dart';
import 'package:neovarch_agent/remote/ui/remote_app.dart' show neovarchMobileTheme;
import 'package:neovarch_agent/remote/ui/remote_shell.dart';
import 'package:neovarch_agent/state/app_controller.dart' show settingsProvider;
import 'package:neovarch_agent/state/settings_controller.dart';
import 'package:neovarch_agent/theme/neovarch_mobile_theme.dart';
import 'package:neovarch_agent/ui/screens/intro_screen.dart';

final _shotsDir = Platform.environment['NV_SHOTS_DIR'] ?? 'build/screenshots/remote';

Future<void> _loadFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final f in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(f['family'] as String);
    for (final a in (f['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(a['asset'] as String));
    }
    await loader.load();
  }
}

final _now = DateTime.now();
String _ago(Duration d) => _now.subtract(d).toIso8601String();

RemoteController _controller(SharedPreferences prefs, {bool connected = true, bool demo = true}) {
  final desktops = SavedDesktops(prefs)..load();
  final r = RemoteController(desktops);
  if (!demo) return r;
  r.desktop = desktops.items.first;
  r.status = connected ? RemoteStatus.connected : RemoteStatus.reconnecting;
  r.error = connected ? null : 'PC tidak menjawab. Pastikan HP dan PC di Wi-Fi yang sama.';
  r.serverInfo = const {'version': '0.9.2'};
  r.sessions = [
    ChatSessionInfo(id: 's1', title: 'Rapikan folder unduhan', profile: 'default', updatedAt: _ago(const Duration(minutes: 4)), messageCount: 12, preview: ''),
    ChatSessionInfo(id: 's2', title: 'Tes integrasi API pembayaran', profile: 'default', updatedAt: _ago(const Duration(hours: 2)), messageCount: 31, preview: ''),
    ChatSessionInfo(id: 's3', title: 'Draf laporan mingguan', profile: 'default', updatedAt: _ago(const Duration(days: 1)), messageCount: 8, preview: ''),
  ];
  r.active = const [
    ActiveSession(id: 'rt1', title: 'Rapikan folder unduhan', status: 'running', model: 'qwen3-coder', preview: ''),
    ActiveSession(id: 'rt2', title: 'Draf laporan mingguan', status: 'idle', model: 'gpt-5-mini', preview: ''),
  ];
  r.board = const KanbanSnapshot([
    KanbanLane('triage', [KanbanCard(id: 't-104', title: 'Cek log error server staging', status: 'triage')]),
    KanbanLane('ready', [
      KanbanCard(id: 't-101', title: 'Perbarui dependensi Flutter', status: 'ready', assignee: 'coder', priority: 2, summary: 'Naikkan versi paket yang usang lalu jalankan flutter test.'),
    ]),
    KanbanLane('running', [
      KanbanCard(
          id: 't-098',
          title: 'Rapikan folder unduhan',
          status: 'running',
          assignee: 'neovarch',
          priority: 1,
          summary: 'Memindahkan 214 berkas ke folder per jenis; 3 duplikat ditandai untuk ditinjau.',
          comments: 2),
      KanbanCard(id: 't-099', title: 'Tulis tes untuk modul pairing', status: 'running', assignee: 'coder', summary: '6 dari 9 kasus selesai.'),
    ]),
    KanbanLane('review', [KanbanCard(id: 't-095', title: 'Draf laporan mingguan', status: 'review', assignee: 'writer', comments: 1)]),
    KanbanLane('done', [
      KanbanCard(id: 't-090', title: 'Backup database lokal', status: 'done', assignee: 'neovarch'),
      KanbanCard(id: 't-091', title: 'Ringkas rapat Senin', status: 'done', assignee: 'writer'),
    ]),
  ], ['neovarch', 'coder', 'writer']);
  final ts = _now.millisecondsSinceEpoch;
  r.storedId = 's1';
  r.runtimeId = 'rt1';
  r.title = 'Rapikan folder unduhan';
  r.transcript = RemoteTranscript(history: [
    ChatMsg(id: 'u1', role: 'user', content: 'Rapikan folder Unduhan di PC: kelompokkan per jenis berkas, jangan hapus apa pun.', ts: ts - 240000),
    ChatMsg(
      id: 'a1',
      role: 'assistant',
      ts: ts - 200000,
      tools: [
        ToolActivity(id: 'x1', name: 'list_files', args: '~/Downloads', summary: '214 berkas', running: false, durationS: 0.4),
        ToolActivity(id: 'x2', name: 'move_files', args: '~/Downloads → per jenis', summary: '211 dipindah', running: false, durationS: 2.1),
      ],
      content: 'Selesai. Berkas di **Unduhan** sekarang dikelompokkan:\n\n- `Dokumen/` 96 berkas\n- `Gambar/` 71 berkas\n- `Arsip/` 44 berkas\n\nAda 3 berkas yang namanya sama; saya biarkan di tempat dan menandainya untuk kamu tinjau.',
    ),
    ChatMsg(id: 'u2', role: 'user', content: 'Oke. Hapus duplikatnya yang lebih lama.', ts: ts - 60000),
  ]);
  r.debugApprovals = [
    RemoteApproval(
      sessionId: 'rt1',
      requestId: 'req1',
      command: 'rm ~/Downloads/laporan_q3\\ (1).pdf ~/Downloads/foto_ktp\\ (2).jpg',
      description: 'Agen ingin menghapus 2 berkas duplikat yang lebih lama.',
      toolName: 'terminal',
      choices: const ['once', 'session', 'deny'],
      receivedAt: _now.subtract(const Duration(seconds: 20)),
    ),
  ];
  return r;
}

// Written through the golden-file pipeline (run with --update-goldens):
// RenderRepaintBoundary.toImage inside runAsync hangs on flutter_tester.
Future<void> _shot(WidgetTester tester, String name) async {
  final dir = Directory(_shotsDir).absolute.path;
  // Sync on purpose: async file I/O never completes inside the fake-async zone.
  Directory(dir).createSync(recursive: true);
  await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('$dir/$name.png'));
}

Widget _host(SettingsController settings, RemoteController remote, Widget home) => ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => settings),
        remoteProvider.overrideWith((ref) => remote),
      ],
      child: RepaintBoundary(
        key: const ValueKey('shot'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: neovarchMobileTheme,
          darkTheme: neovarchMobileTheme,
          themeMode: ThemeMode.dark,
          home: home,
        ),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _precache(WidgetTester tester) async {
  final ctx = tester.element(find.byType(MaterialApp));
  await tester.runAsync(() async {
    for (final a in const ['assets/art/feat-remote.webp', 'assets/art/portal-banner.webp', 'assets/art/feat-automation.webp', 'assets/brand/wordmark_text.png', 'assets/brand/wordmark_halo.png', 'assets/brand/logo_card.png', 'assets/intro/eva_office.webp', 'assets/intro/eva_remote.webp', 'assets/intro/eva_pairing.webp']) {
      await precacheImage(AssetImage(a), ctx);
    }
  });
}

void main() {
  late SharedPreferences prefs;
  late SettingsController settings;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'remote.desktops': jsonEncode([
        {'id': 'pc1', 'name': 'PC Kantor', 'url': 'http://192.168.1.20:9119', 'addedAt': _ago(const Duration(days: 9)), 'lastConnected': _ago(const Duration(minutes: 3))},
        {'id': 'pc2', 'name': 'Laptop Rumah', 'url': 'http://100.64.0.7:9119', 'addedAt': _ago(const Duration(days: 30)), 'lastConnected': _ago(const Duration(days: 2))},
      ]),
      'remote.active': 'pc1',
    });
    prefs = await SharedPreferences.getInstance();
    settings = SettingsController(prefs);
    await settings.load();
  });

  Future<void> run(WidgetTester tester, String name, Widget Function() home, {RemoteController? remote, Future<void> Function()? act}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 141, bottom: 102);
    tester.view.viewPadding = const FakeViewPadding(top: 141, bottom: 102);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(settings, remote ?? _controller(prefs), home()));
    debugPrint('[$name] pumped');
    await _precache(tester);
    debugPrint('[$name] precached');
    await _settle(tester);
    debugPrint('[$name] settled');
    if (act != null) {
      await act();
      await _settle(tester);
    }
    await _shot(tester, name);
    debugPrint('[$name] shot');
    // Unmount so repeating animations stop before the test ends.
    await tester.pumpWidget(const SizedBox());
  }

  test('theme: no stock Material colours, rounded system', () {
    final t = neovarchMobileTheme;
    expect(t.scaffoldBackgroundColor, NV.bg);
    expect(t.colorScheme.primary, NV.red);
    expect(t.colorScheme.surfaceTint, Colors.transparent);
    final card = t.cardTheme.shape as RoundedRectangleBorder;
    expect(card.borderRadius, BorderRadius.circular(16));
    final dlg = t.dialogTheme.shape as RoundedRectangleBorder;
    expect(dlg.borderRadius, BorderRadius.circular(20));
    expect(t.cardTheme.elevation, 0);
    expect(t.floatingActionButtonTheme.elevation, 0);
  });

  testWidgets('01 connect (first run)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await run(tester, '01_connect', () => const ConnectScreen(onboarding: true), remote: _controller(prefs, demo: false));
  });

  testWidgets('02 connect manual', (tester) async {
    await run(tester, '02_connect_manual', () => const ConnectScreen(), act: () async {
      await tester.tap(find.text('Masukkan alamat & token'));
    });
  });

  testWidgets('03 chat conversation', (tester) async {
    app.previewTab = 0;
    await run(tester, '03_chat', () => const RemoteShell());
  });

  testWidgets('04 chat empty', (tester) async {
    app.previewTab = 0;
    final r = _controller(prefs)
      ..transcript = RemoteTranscript()
      ..title = ''
      ..storedId = null
      ..debugApprovals = [];
    await run(tester, '04_chat_empty', () => const RemoteShell(), remote: r);
  });

  testWidgets('05 tasks', (tester) async {
    app.previewTab = 1;
    await run(tester, '05_tasks', () => const RemoteShell());
  });

  testWidgets('06 task sheet', (tester) async {
    app.previewTab = 1;
    await run(tester, '06_task_sheet', () => const RemoteShell(), act: () async {
      await tester.tap(find.text('Rapikan folder unduhan').first);
    });
  });

  testWidgets('07 approvals', (tester) async {
    app.previewTab = 2;
    await run(tester, '07_approvals', () => const RemoteShell());
  });

  testWidgets('08 pc', (tester) async {
    app.previewTab = 3;
    await run(tester, '08_pc', () => const RemoteShell());
  });

  testWidgets('09 offline strip', (tester) async {
    app.previewTab = 0;
    final r = _controller(prefs, connected: false)
      ..transcript = RemoteTranscript()
      ..title = ''
      ..storedId = null
      ..debugApprovals = [];
    await run(tester, '09_offline', () => const RemoteShell(), remote: r);
  });

  testWidgets('10 confirm dialog', (tester) async {
    app.previewTab = 3;
    await run(tester, '10_dialog', () => const RemoteShell(), act: () async {
      await tester.tap(find.byTooltip('Lupakan').first);
    });
  });

  testWidgets('11 intro', (tester) async {
    await run(tester, '11_intro', () => const IntroScreen(initialPage: 2), remote: _controller(prefs, demo: false));
  });

  testWidgets('12 intro start', (tester) async {
    await run(tester, '12_intro_start', () => const IntroScreen(initialPage: 3), remote: _controller(prefs, demo: false));
  });
}
