// Renders every main screen of the phone remote at 390x844 (dark, Neovarch
// mobile theme) with demo data, fails on any layout overflow, and writes a
// PNG per screen to $NV_SHOTS_DIR (default build/screenshots/remote) when run
// with --update-goldens. A plain `flutter test` checks layout only.
//
//   NV_SHOTS_DIR=/path flutter test --update-goldens test/remote_screens_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neovarch_agent/main.dart' as app;
import 'package:neovarch_agent/models/models.dart';
import 'package:neovarch_agent/remote/appearance.dart';
import 'package:neovarch_agent/remote/office_models.dart';
import 'package:neovarch_agent/remote/remote_controller.dart';
import 'package:neovarch_agent/remote/remote_gateway.dart';
import 'package:neovarch_agent/remote/remote_transcript.dart';
import 'package:neovarch_agent/remote/saved_desktops.dart';
import 'package:neovarch_agent/remote/ui/connect_screen.dart';
import 'package:neovarch_agent/remote/ui/remote_app.dart' show neovarchMobileTheme;
import 'package:neovarch_agent/remote/ui/remote_kantor_tab.dart' show previewKantorSegment, kantorSegTasks, kantorSegOffice;
import 'package:neovarch_agent/remote/ui/remote_shell.dart';
import 'package:neovarch_agent/state/app_controller.dart' show settingsProvider;
import 'package:neovarch_agent/state/settings_controller.dart';
import 'package:neovarch_agent/theme/neovarch_mobile_theme.dart';
import 'package:neovarch_agent/remote/ui/remote_intro_screen.dart';
import 'package:neovarch_agent/remote/ui/remote_launch.dart';
import 'package:neovarch_agent/remote/ui/remote_pc_screen.dart' show AppearancePanel;
import 'package:neovarch_agent/ui/screens/startup_splash.dart';

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
  final sec = _now.millisecondsSinceEpoch / 1000;
  r.office = OfficeSnapshot.fromJson({
    'host': 'pc-kantor',
    'core_version': '1.4.0',
    'agents': [
      {
        'id': 'session:s1', 'kind': 'session', 'session_id': 's1', 'name': 'Raka', 'role': 'Agen remote · HP', 'status': 'working',
        'current_task': 'Rapikan folder Unduhan per jenis berkas', 'current_tool': 'move_files: ~/Downloads → per jenis',
        'last_activity': sec - 20, 'last_activity_text': 'menjalankan move_files', 'message_count': 12,
      },
      {
        'id': 'session:s2', 'kind': 'session', 'session_id': 's2', 'name': 'Sari', 'role': 'Agen utama · desktop', 'status': 'waiting-approval',
        'current_task': 'Hapus duplikat lama', 'last_activity': sec - 60,
        'pending_approval': {'request_id': 'req1', 'command': 'rm laporan_q3 (1).pdf'},
      },
      {'id': 'kanban:writer', 'kind': 'kanban', 'name': 'writer', 'role': 'Pelaksana tugas Kanban', 'status': 'idle', 'current_task': 'Draf laporan mingguan', 'last_activity': sec - 3600},
    ],
    'counts': {'total': 3, 'working': 1, 'waiting-approval': 1, 'idle': 1},
    'kanban': {'todo': 1, 'ready': 1, 'running': 2, 'blocked': 0, 'done': 2},
    'feed': [
      {'id': 9, 'ts': sec - 20, 'kind': 'tool', 'agent': 'Raka', 'session_id': 's1', 'text': 'menjalankan move_files: ~/Downloads'},
      {'id': 8, 'ts': sec - 60, 'kind': 'approval', 'agent': 'Sari', 'session_id': 's2', 'text': 'menunggu persetujuan: rm laporan_q3 (1).pdf'},
      {'id': 7, 'ts': sec - 300, 'kind': 'task', 'agent': 'writer', 'text': 'memindahkan “Draf laporan mingguan”: ready → review'},
      {'id': 6, 'ts': sec - 900, 'kind': 'message', 'agent': 'Raka', 'session_id': 's1', 'text': 'membalas: Selesai, 211 berkas dipindah.'},
    ],
    'vault': {'configured': true, 'connected': true, 'note_count': 42},
  });
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
  // The PNGs are screenshots, not committed goldens: only write them on request.
  if (!autoUpdateGoldenFiles) return;
  final dir = Directory(_shotsDir).absolute.path;
  // Sync on purpose: async file I/O never completes inside the fake-async zone.
  Directory(dir).createSync(recursive: true);
  await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('$dir/$name.png'));
}

Widget _host(SettingsController settings, RemoteController remote, Widget home, AppearanceController look) => ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => settings),
        remoteProvider.overrideWith((ref) => remote),
        appearanceProvider.overrideWith((ref) => look),
      ],
      child: RepaintBoundary(
        key: const ValueKey('shot'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: neovarchMobileTheme,
          darkTheme: neovarchMobileTheme,
          themeMode: NV.palette.dark ? ThemeMode.dark : ThemeMode.light,
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
    for (final a in const ['assets/art/feat-remote.webp', 'assets/art/portal-banner.webp', 'assets/art/feat-automation.webp', 'assets/brand/wordmark_text.png', 'assets/brand/wordmark_halo.png', 'assets/brand/monogram.png', 'assets/brand/monogram_n.png']) {
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
        {'id': 'pc1', 'name': 'PC Kantor', 'url': 'http://192.168.1.20:9319', 'addedAt': _ago(const Duration(days: 9)), 'lastConnected': _ago(const Duration(minutes: 3))},
        {'id': 'pc2', 'name': 'Laptop Rumah', 'url': 'http://100.64.0.7:9319', 'addedAt': _ago(const Duration(days: 30)), 'lastConnected': _ago(const Duration(days: 2))},
      ]),
      'remote.active': 'pc1',
    });
    prefs = await SharedPreferences.getInstance();
    settings = SettingsController(prefs);
    await settings.load();
  });

  Future<void> run(WidgetTester tester, String name, Widget Function() home,
      {RemoteController? remote, Future<void> Function()? act, double width = 390, bool settleAfterAct = true}) async {
    tester.view.physicalSize = Size(width * 3, 2532);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 141, bottom: 102);
    tester.view.viewPadding = const FakeViewPadding(top: 141, bottom: 102);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(settings, remote ?? _controller(prefs), home(), AppearanceController(prefs)));
    debugPrint('[$name] pumped');
    await _precache(tester);
    debugPrint('[$name] precached');
    await _settle(tester);
    debugPrint('[$name] settled');
    if (act != null) {
      await act();
      if (settleAfterAct) await _settle(tester);
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
    // radii follow "Kelengkungan sudut" (default 24: card 24, dialog 28)
    expect(card.borderRadius, BorderRadius.circular(NV.rCard));
    expect(NV.rCard, NV.corner);
    final dlg = t.dialogTheme.shape as RoundedRectangleBorder;
    expect(dlg.borderRadius, BorderRadius.circular(NV.rDialog));
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
    previewKantorSegment = kantorSegTasks;
    addTearDown(() => previewKantorSegment = kantorSegOffice);
    await run(tester, '05_tasks', () => const RemoteShell());
  });

  testWidgets('06 task sheet', (tester) async {
    app.previewTab = 1;
    previewKantorSegment = kantorSegTasks;
    addTearDown(() => previewKantorSegment = kantorSegOffice);
    await run(tester, '06_task_sheet', () => const RemoteShell(), act: () async {
      await tester.tap(find.text('Rapikan folder unduhan').first);
    });
  });

  testWidgets('07 approvals (Chat chip → sheet)', (tester) async {
    app.previewTab = 0;
    await run(tester, '07_approvals', () => const RemoteShell(), act: () async {
      await tester.tap(find.byKey(const ValueKey('chat-approvals-chip')));
    });
  });

  testWidgets('08 pc', (tester) async {
    app.previewTab = 2;
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
    app.previewTab = 2;
    await run(tester, '10_dialog', () => const RemoteShell(), act: () async {
      await tester.tap(find.byTooltip('Lupakan').first);
    });
  });

  testWidgets('11 intro', (tester) async {
    await run(tester, '11_intro', () => const RemoteIntroScreen(), remote: _controller(prefs, demo: false));
  });

  testWidgets('12 intro start', (tester) async {
    await run(tester, '12_intro_start', () => const RemoteIntroScreen(initialPage: 2), remote: _controller(prefs, demo: false));
  });

  testWidgets('13 startup splash', (tester) async {
    await run(tester, '13_splash',
        () => StartupSplash(background: NV.bg, foreground: NV.text, accent: NV.red, child: ConnectScreen(onboarding: true)),
        // monogram is precached, so the reveal starts at once and the shot
        // lands mid-reveal (~0.56): halo down, wordmark mostly wiped in.
        remote: _controller(prefs, demo: false));
  });

  // v1.4.1 screenshots: themed intro, glass nav over chat in other accents,
  // theme picker.
  Future<void> accent(String hex, String base) async {
    await prefs.setBool('nv.theme.follow', false);
    await prefs.setString('nv.theme.accent', hex);
    await prefs.setString('nv.theme.base', base);
  }

  testWidgets('14 launch intro (saved theme)', (tester) async {
    await accent('#7C3AED', 'dark');
    await run(tester, '14_launch_intro', () => const NvLaunchIntro(debugFreezeAt: 0.5, child: ConnectScreen(onboarding: true)),
        remote: _controller(prefs, demo: false));
    NV.palette = NvPalette.red;
  });

  testWidgets('15 chat glass nav · ungu', (tester) async {
    await accent('#7C3AED', 'dark');
    app.previewTab = 0;
    await run(tester, '15_chat_glass_ungu', () => const RemoteShell());
    NV.palette = NvPalette.red;
  });

  testWidgets('16 chat glass nav · toska terang', (tester) async {
    await accent('#0D9488', 'light');
    app.previewTab = 0;
    await run(tester, '16_chat_glass_toska_light', () => const RemoteShell());
    NV.palette = NvPalette.red;
  });

  testWidgets('17 chat glass nav · langit', (tester) async {
    await accent('#0284C7', 'dark');
    app.previewTab = 0;
    await run(tester, '17_chat_glass_langit', () => const RemoteShell());
    NV.palette = NvPalette.red;
  });

  testWidgets('18 theme picker', (tester) async {
    await accent('#E11D48', 'dark');
    await run(tester, '18_theme_picker', () => Scaffold(
          body: ListView(padding: const EdgeInsets.only(top: 60, bottom: 40), children: const [
            NvSectionShim(),
            AppearancePanel(),
          ]),
        ));
    NV.palette = NvPalette.red;
  });
  // v1.4.2 screenshots: onboarding theme step (Merah + Biru), tinted slide
  // art, Tampilan before pairing, custom background under the glass nav /
  // composer, nav bar mid-drag, Cupertino icons + Inter.
  Future<void> background(String asset, {double dim = 0.4, double blur = 6}) async {
    await prefs.setString('nv.bg.source', 'asset:$asset');
    await prefs.setDouble('nv.bg.dim', dim);
    await prefs.setDouble('nv.bg.blur', blur);
  }

  testWidgets('19 onboarding theme step · merah', (tester) async {
    await run(tester, '19_intro_theme_merah', () => const RemoteIntroScreen(initialPage: 3), remote: _controller(prefs, demo: false));
  });

  testWidgets('20 onboarding theme step · biru', (tester) async {
    await accent('#2563EB', 'dark');
    await run(tester, '20_intro_theme_biru', () => const RemoteIntroScreen(initialPage: 3), remote: _controller(prefs, demo: false));
    NV.palette = NvPalette.red;
  });

  testWidgets('21 intro slide · biru (art tinted)', (tester) async {
    await accent('#2563EB', 'dark');
    await run(tester, '21_intro_slide_biru', () => const RemoteIntroScreen(), remote: _controller(prefs, demo: false));
    NV.palette = NvPalette.red;
  });

  testWidgets('22 connect · toska terang with Tampilan button', (tester) async {
    await accent('#0D9488', 'light');
    await run(tester, '22_connect_toska_light', () => const ConnectScreen(onboarding: true), remote: _controller(prefs, demo: false));
    NV.palette = NvPalette.red;
  });

  testWidgets('23 Tampilan sheet before pairing', (tester) async {
    await accent('#4F46E5', 'dark');
    await run(tester, '23_appearance_sheet', () => const ConnectScreen(onboarding: true), remote: _controller(prefs, demo: false), act: () async {
      await tester.tap(find.byKey(const ValueKey('connect-appearance')));
    });
    NV.palette = NvPalette.red;
  });

  testWidgets('24 chat over custom background', (tester) async {
    await accent('#7C3AED', 'dark');
    await background('assets/art/portal-banner.webp', dim: 0.35, blur: 2);
    app.previewTab = 0;
    await run(tester, '24_chat_background', () => const RemoteShell());
    NV.palette = NvPalette.red;
  });

  testWidgets('25 tasks over custom background · biru', (tester) async {
    await accent('#2563EB', 'dark');
    await background('assets/art/feat-automation.webp', dim: 0.45, blur: 8);
    app.previewTab = 1;
    previewKantorSegment = kantorSegTasks;
    addTearDown(() => previewKantorSegment = kantorSegOffice);
    await run(tester, '25_tasks_background', () => const RemoteShell());
    NV.palette = NvPalette.red;
  });

  testWidgets('26 nav bar mid-drag (lens under the finger)', (tester) async {
    await background('assets/art/feat-remote.webp', dim: 0.4, blur: 4);
    app.previewTab = 0;
    TestGesture? g;
    await run(tester, '26_nav_drag', () => const RemoteShell(), act: () async {
      final bar = tester.getRect(find.byKey(const ValueKey('nv-nav-bar')));
      final w = (bar.width - 8) / 4;
      g = await tester.startGesture(Offset(bar.left + 4 + w * 0.5, bar.center.dy));
      for (var i = 0; i < 12; i++) {
        await g!.moveBy(Offset(w * 1.6 / 12, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
    });
    await g?.up();
  });

  testWidgets('27 PC tab · Cupertino icons + Inter', (tester) async {
    app.previewTab = 2;
    await run(tester, '27_pc_icons_font', () => const RemoteShell());
  });

  // v1.4.2 (second batch): 4-tab nav, wider lens, merged tabs, Profil,
  // glass greeting, glass intro, Gaya kaca.
  Future<void> glassStyle(String name) async => prefs.setString('nv.glass.style', name);
  RemoteController emptyChat() => _controller(prefs)
    ..transcript = RemoteTranscript()
    ..title = ''
    ..storedId = null
    ..debugApprovals = [];

  for (final (tab, name) in [(1, 'kantor'), (3, 'profil')]) {
    for (final w in [390.0, 360.0]) {
      testWidgets('28 nav at rest · $name · ${w.toInt()} dp', (tester) async {
        await background('assets/art/feat-remote.webp', dim: 0.4, blur: 4);
        app.previewTab = tab;
        await run(tester, '28_nav_rest_${name}_${w.toInt()}', () => const RemoteShell(), width: w);
      });
    }
  }

  testWidgets('32 greeting · dark + background', (tester) async {
    await background('assets/art/feat-remote.webp', dim: 0.35, blur: 6);
    app.previewTab = 0;
    await run(tester, '32_greeting_dark_bg', () => const RemoteShell(), remote: emptyChat());
  });

  testWidgets('33 greeting · light', (tester) async {
    await accent('#2563EB', 'light');
    await background('assets/art/portal-banner.webp', dim: 0.3, blur: 6);
    app.previewTab = 0;
    await run(tester, '33_greeting_light', () => const RemoteShell(), remote: emptyChat());
    NV.palette = NvPalette.red;
  });

  testWidgets('34 greeting · Polos', (tester) async {
    app.previewTab = 0;
    await run(tester, '34_greeting_polos', () => const RemoteShell(), remote: emptyChat());
  });

  testWidgets('35 Kantor tab · Kantor segment', (tester) async {
    app.previewTab = 1;
    await run(tester, '35_kantor_segment', () => const RemoteShell());
  });

  testWidgets('36 Kantor tab · Tugas segment', (tester) async {
    app.previewTab = 1;
    previewKantorSegment = kantorSegTasks;
    addTearDown(() => previewKantorSegment = kantorSegOffice);
    await run(tester, '36_tugas_segment', () => const RemoteShell());
  });

  testWidgets('37 Profil tab', (tester) async {
    await background('assets/art/feat-remote.webp', dim: 0.45, blur: 8);
    app.previewTab = 3;
    await run(tester, '37_profil', () => const RemoteShell());
  });

  testWidgets('38 Profil · icon picker + Gaya kaca', (tester) async {
    await background('assets/art/feat-remote.webp', dim: 0.45, blur: 8);
    app.previewTab = 3;
    await run(tester, '38_profil_icon_glass', () => const RemoteShell(), act: () async {
      await tester.drag(find.byKey(const ValueKey('profile-list')), const Offset(0, -1500));
    });
  });

  for (final (i, n) in [(0, 1), (1, 2), (2, 3), (3, 4)]) {
    testWidgets('39 intro page $n (glass)', (tester) async {
      await run(tester, '39_intro_page_$n', () => RemoteIntroScreen(initialPage: i), remote: _controller(prefs, demo: false));
    });
  }

  testWidgets('40 intro mid-transition (drag)', (tester) async {
    TestGesture? g;
    await run(tester, '40_intro_mid_transition', () => const RemoteIntroScreen(), remote: _controller(prefs, demo: false), settleAfterAct: false,
        act: () async {
      g = await tester.startGesture(const Offset(330, 420));
      for (var i = 0; i < 10; i++) {
        await g!.moveBy(const Offset(-16, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
    });
    await g?.up();
  });

  for (final st in ['reguler', 'bening', 'gelap', 'warna', 'tanpa']) {
    testWidgets('41 chat · Gaya kaca $st', (tester) async {
      await background('assets/art/feat-remote.webp', dim: 0.3, blur: 4);
      await glassStyle(st);
      app.previewTab = 0;
      await run(tester, '41_chat_glass_$st', () => const RemoteShell());
      NV.glassStyle = NvGlassStyle.reguler;
    });
  }

}


/// "TAMPILAN" header like on the PC tab.
class NvSectionShim extends StatelessWidget {
  const NvSectionShim({super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
        child: Text('TAMPILAN', style: NV.monoLabel()),
      );
}