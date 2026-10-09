// Desktop-parity composer on the phone: the PC's composer catalog (skills,
// commands, snippets, models, reasoning), "/" and "@" triggers, the "+" glass
// menu, skill picker, selection chips, attachment previews, the prompt.submit
// payload, graceful degrade on an older PC, and colour contrast for every
// accent preset in dark and light. Run with --update-goldens and
// NV_SHOTS_DIR=… to write screenshots.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neovarch_agent/models/models.dart';
import 'package:neovarch_agent/remote/appearance.dart';
import 'package:neovarch_agent/remote/composer.dart';
import 'package:neovarch_agent/remote/remote_controller.dart';
import 'package:neovarch_agent/remote/remote_gateway.dart';
import 'package:neovarch_agent/remote/remote_transcript.dart';
import 'package:neovarch_agent/remote/saved_desktops.dart';
import 'package:neovarch_agent/remote/ui/remote_attachments.dart';
import 'package:neovarch_agent/remote/ui/remote_chat_screen.dart';
import 'package:neovarch_agent/remote/ui/remote_composer.dart';
import 'package:neovarch_agent/state/app_controller.dart' show settingsProvider;
import 'package:neovarch_agent/state/settings_controller.dart';
import 'package:neovarch_agent/theme/neovarch_mobile_theme.dart';

final _shotsDir = Platform.environment['NV_SHOTS_DIR'] ?? 'build/screenshots/composer';

Map<String, dynamic> catalogJson() => {
      'version': 1,
      'skills': [
        {'name': 'code-review', 'description': 'Tinjau perubahan untuk bug dan regresi'},
        {'name': 'deploy', 'description': 'Rilis ke server produksi'},
        {'name': 'laporan-skripsi', 'description': 'Susun laporan .docx dengan Pandoc'},
        {'name': 'riset-web', 'description': 'Cari dan rangkum sumber'},
      ],
      'commands': [
        {'name': 'new', 'description': 'Mulai percakapan baru'},
        {'name': 'model', 'description': 'Ganti model'},
      ],
      'snippets': [
        {'id': 'codeReview', 'label': 'Tinjau kode', 'description': 'Periksa perubahan ini.', 'text': 'Tolong tinjau ini untuk bug, regresi, dan tes yang kurang.'},
        {'id': 'implementationPlan', 'label': 'Rencana implementasi', 'description': 'Susun pendekatan.', 'text': 'Tolong buat rencana implementasi singkat sebelum mengubah kode.'},
      ],
      'mentions': [
        {'text': '@url:', 'display': '@url:', 'meta': 'Sebut tautan'},
        {'text': '@diff', 'display': '@diff', 'meta': 'Perubahan git yang belum di-stage'},
      ],
      'models': {
        'model': 'qwen3-coder-480b',
        'provider': 'custom:9router',
        'providers': [
          {'slug': 'custom:9router', 'name': '9router', 'models': ['qwen3-coder-480b', 'kimi-k2', 'gpt-5-mini'], 'is_current': true},
          {'slug': 'openrouter', 'name': 'OpenRouter', 'models': ['anthropic/claude-sonnet-4.5', 'deepseek/deepseek-v3.2'], 'is_current': false},
        ],
      },
      'reasoning': {
        'supported': true,
        'levels': ['none', 'minimal', 'low', 'medium', 'high', 'xhigh'],
        'labels': {'none': 'Mati', 'minimal': 'Minimal', 'low': 'Rendah', 'medium': 'Sedang', 'high': 'Tinggi', 'xhigh': 'Sangat tinggi'},
        'default': 'default',
      },
      'features': {
        'prompt_fields': ['skills', 'reasoning_effort'],
      },
    };

class _Rec {
  final requests = <http.BaseRequest>[];
  final bodies = <String>[];
}

http.Client _http(_Rec rec, {bool oldPc = false}) => MockClient.streaming((req, body) async {
      rec.requests.add(req);
      rec.bodies.add(utf8.decode(await body.toBytes(), allowMalformed: true));
      final path = req.url.path;
      Object out = {};
      var status = 200;
      if (oldPc && path.startsWith('/api/composer')) {
        out = {'ok': false, 'available': false};
      } else if (path == '/api/composer/catalog') {
        out = catalogJson();
      } else if (path == '/api/composer/complete') {
        final q = req.url.queryParameters['q'] ?? '';
        final all = [
          {'text': '@folder:lib/', 'display': 'lib/', 'meta': 'folder', 'is_dir': true},
          {'text': '@folder:test/', 'display': 'test/', 'meta': 'folder', 'is_dir': true},
          {'text': '@file:README.md', 'display': 'README.md', 'meta': '.', 'is_dir': false},
          {'text': '@file:pubspec.yaml', 'display': 'pubspec.yaml', 'meta': '.', 'is_dir': false},
        ];
        out = {'items': [for (final i in all) if ((i['display'] as String).toLowerCase().contains(q.toLowerCase())) i]};
      } else if (path == '/api/model/set') {
        out = {'ok': true};
      } else if (path == '/api/uploads' && req.method == 'POST') {
        out = {'id': 'up${rec.requests.length}', 'name': 'foto.png', 'mime': 'image/png', 'size': 67, 'kind': 'image', 'url': '/api/uploads/x'};
      } else {
        status = 404;
        out = {'detail': 'nope'};
      }
      return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(out))), status, headers: {'content-type': 'application/json'});
    });

/// The real REST client with prompt.submit captured (no WebSocket needed).
class _Gw extends RemoteGateway {
  _Gw(_Rec rec, {bool oldPc = false})
      : super(baseUrl: 'http://192.168.1.20:9319', token: 'tok-123', autoReconnect: false, httpClient: _http(rec, oldPc: oldPc));
  final submits = <Map<String, dynamic>>[];
  @override
  Future<dynamic> submit(String runtimeId, String text, {List<String> attachments = const [], Map<String, dynamic> extra = const {}}) async {
    submits.add({'session_id': runtimeId, 'text': text, if (attachments.isNotEmpty) 'attachments': attachments, ...extra});
    return {'ok': true};
  }
}

void main() {
  group('catalog + triggers', () {
    test('parses the PC catalog; older PCs yield null', () {
      final c = ComposerCatalog.tryParse(catalogJson())!;
      expect(c.skills.map((s) => s.name), ['code-review', 'deploy', 'laporan-skripsi', 'riset-web']);
      expect(c.commands.map((x) => x.name), ['new', 'model']);
      expect(c.snippets.first.label, 'Tinjau kode');
      expect(c.providers.length, 2);
      expect(c.model, 'qwen3-coder-480b');
      expect(c.canSendSkills && c.canSendEffort, isTrue);
      expect(c.effortLabel('high'), 'Tinggi');
      expect(c.effortLabel(null), 'Bawaan');
      // the core answers unknown routes with {available:false}
      expect(ComposerCatalog.tryParse({'ok': false, 'available': false}), isNull);
      expect(ComposerCatalog.tryParse(null), isNull);
      expect(ComposerCatalog.tryParse({'version': 0}), isNull);
    });

    test('"/" and "@" detection at the cursor', () {
      expect(detectTrigger('/rev', 4), const ComposerTrigger('/', 'rev', 0, 4));
      expect(detectTrigger('tolong /co', 10), const ComposerTrigger('/', 'co', 7, 10));
      expect(detectTrigger('cek @lib/ma', 11), const ComposerTrigger('@', 'lib/ma', 4, 11));
      expect(detectTrigger('cek @file:src/a', 15)!.query, 'file:src/a');
      expect(detectTrigger('a/b', 3), isNull); // path inside a word
      expect(detectTrigger('email a@b.c', 11), isNull);
      expect(detectTrigger('/rev ', 5), isNull); // finished token
      expect(detectTrigger('', 0), isNull);
      final r = applySuggestion('cek @READ', const ComposerTrigger('@', 'READ', 4, 9), '@file:README.md');
      expect(r.text, 'cek @file:README.md ');
      expect(r.cursor, r.text.length);
      final f = applySuggestion('@li', const ComposerTrigger('@', 'li', 0, 3), '@folder:lib/');
      expect(f.text, '@folder:lib/'); // folders stay open for the next level
    });

    test('slash suggestions: commands then skills, filtered', () {
      final c = ComposerCatalog.tryParse(catalogJson())!;
      expect(slashSuggestions(c, '').map((s) => s.text), ['/new', '/model', '/code-review', '/deploy', '/laporan-skripsi', '/riset-web']);
      expect(slashSuggestions(c, 'dep').single.kind, 'skill');
      expect(slashSuggestions(c, 'mod').single.kind, 'command');
    });

    test('submit fields: only what the PC understands, default effort omitted', () {
      final c = ComposerCatalog.tryParse(catalogJson())!;
      expect(composerSubmitFields(c, skills: ['deploy'], reasoningEffort: 'high'), {'skills': ['deploy'], 'reasoning_effort': 'high'});
      expect(composerSubmitFields(c, reasoningEffort: 'default'), isEmpty);
      expect(composerSubmitFields(null, skills: ['deploy'], reasoningEffort: 'high'), isEmpty);
      final noFields = ComposerCatalog.tryParse({...catalogJson(), 'features': {}})!;
      expect(composerSubmitFields(noFields, skills: ['deploy'], reasoningEffort: 'high'), isEmpty);
    });
  });

  group('REST + controller', () {
    late SharedPreferences prefs;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('catalog, completions and model switch over REST with the token', () async {
      final rec = _Rec();
      final g = _Gw(rec);
      final c = await g.composerCatalog();
      expect(c!.skills.length, 4);
      expect(rec.requests.last.headers['Authorization'] ?? rec.requests.last.url.queryParameters['token'], isNotNull);
      final items = await g.composerComplete('path', 'read', sessionId: 'rt-1');
      expect(items.single.text, '@file:README.md');
      expect(items.single.kind, 'file');
      expect(rec.requests.last.url.queryParameters, {'kind': 'path', 'q': 'read', 'session_id': 'rt-1'});
      await g.setModel(provider: 'openrouter', model: 'deepseek/deepseek-v3.2');
      expect(jsonDecode(rec.bodies.last), {'provider': 'openrouter', 'model': 'deepseek/deepseek-v3.2', 'scope': 'main'});
      expect(await _Gw(_Rec(), oldPc: true).composerCatalog(), isNull);
    });

    test('send carries skills + reasoning effort; skills clear, effort stays', () async {
      final rec = _Rec();
      final g = _Gw(rec);
      final r = RemoteController(SavedDesktops(prefs)..load())
        ..gateway = g
        ..status = RemoteStatus.connected
        ..runtimeId = 'rt-1';
      await r.refreshComposer();
      expect(r.composer, isNotNull);
      r.toggleSkill('code-review');
      r.toggleSkill('deploy');
      r.setReasoningEffort('high');
      expect(await r.send('cek login'), isNull);
      expect(g.submits.single, {'session_id': 'rt-1', 'text': 'cek login', 'skills': ['code-review', 'deploy'], 'reasoning_effort': 'high'});
      expect(r.transcript.messages.last.content, '/code-review /deploy cek login');
      expect(r.selectedSkills, isEmpty);
      await r.send('lagi');
      expect(g.submits.last, {'session_id': 'rt-1', 'text': 'lagi', 'reasoning_effort': 'high'});
      r.setReasoningEffort('default');
      await r.send('biasa');
      expect(g.submits.last, {'session_id': 'rt-1', 'text': 'biasa'});
      // model switch keeps the catalog in step
      expect(await r.selectModel('openrouter', 'deepseek/deepseek-v3.2'), isNull);
      expect(r.composer!.model, 'deepseek/deepseek-v3.2');
      expect(r.composer!.providers.firstWhere((p) => p.isCurrent).slug, 'openrouter');
      // @ suggestions: PC files first, then matching starters
      final m = await r.completeMentions('');
      expect(m.map((s) => s.text), ['@folder:lib/', '@folder:test/', '@file:README.md', '@file:pubspec.yaml', '@url:', '@diff']);
    });

    test('older PC: no catalog, plain payload', () async {
      final g = _Gw(_Rec(), oldPc: true);
      final r = RemoteController(SavedDesktops(prefs)..load())
        ..gateway = g
        ..status = RemoteStatus.connected
        ..runtimeId = 'rt-1';
      await r.refreshComposer();
      expect(r.composer, isNull);
      r.toggleSkill('deploy');
      r.setReasoningEffort('high');
      await r.send('halo');
      expect(g.submits.single, {'session_id': 'rt-1', 'text': 'halo'});
      expect(await r.completeMentions(''), isEmpty);
    });
  });

  group('contrast (every accent, dark + light)', () {
    tearDown(() => NV.palette = NvPalette.red);
    test('send label >= 4.5:1, chip text >= 4.5:1, accent glyphs >= 3:1', () {
      for (final (name, accent) in accentPresets) {
        for (final b in Brightness.values) {
          NV.palette = NvPalette.from(accent, b);
          final tag = '$name/${b.name}';
          expect(composerContrast(inkOn(prominentFill()), prominentFill()), greaterThanOrEqualTo(4.5), reason: 'send $tag');
          for (final sel in [false, true]) {
            final bg = chipFill(selected: sel);
            expect(composerContrast(NV.text, bg), greaterThanOrEqualTo(4.5), reason: 'chip text $tag sel=$sel');
            expect(composerContrast(mutedOn(bg), bg), greaterThanOrEqualTo(4.5), reason: 'chip secondary $tag sel=$sel');
            final sheet = Color.alphaBlend(Color.lerp(NV.surface, NV.red, NV.palette.dark ? 0.08 : 0.05)!.withValues(alpha: NV.palette.dark ? 0.80 : 0.84), NV.bg);
            expect(composerContrast(NV.text, sheet), greaterThanOrEqualTo(4.5), reason: 'sheet text $tag');
            expect(composerContrast(NV.muted, sheet), greaterThanOrEqualTo(4.5), reason: 'sheet secondary $tag');
            expect(composerContrast(accentInk(bg), bg), greaterThanOrEqualTo(3.0), reason: 'accent glyph $tag sel=$sel');
          }
        }
      }
    });
  });

  group('screens', () {
    late SharedPreferences prefs;
    late SettingsController settings;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
      for (final f in manifest.cast<Map<String, dynamic>>()) {
        final loader = FontLoader(f['family'] as String);
        for (final a in (f['fonts'] as List).cast<Map<String, dynamic>>()) {
          loader.addFont(rootBundle.load(a['asset'] as String));
        }
        await loader.load();
      }
    });

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
      remoteImageProvider = (url, headers) => const AssetImage('assets/art/feat-remote.webp');
    });
    tearDown(() => NV.palette = NvPalette.red);

    Future<RemoteController> controller(_Gw g, {bool withCatalog = true}) async {
      final desktops = SavedDesktops(prefs)..load();
      final r = RemoteController(desktops)
        ..desktop = desktops.items.first
        ..status = RemoteStatus.connected
        ..gateway = g
        ..runtimeId = 'rt-1'
        ..storedId = 's-1'
        ..title = 'Perbaiki login'
        ..transcript = RemoteTranscript(history: [
          ChatMsg(id: 'm0', role: 'user', content: 'Kenapa login di HP gagal terus?', ts: 1000),
          ChatMsg(id: 'm1', role: 'assistant', content: 'Token kedaluwarsa tidak diperbarui. Saya cek `auth_service.dart` dan tes yang terkait, lalu buat perbaikan kecil.', ts: 1001),
          ChatMsg(id: 'm2', role: 'user', content: 'Oke, sekalian tambahkan tes.', ts: 1002),
          ChatMsg(id: 'm3', role: 'assistant', content: 'Siap. Tes baru ada di `test/auth_refresh_test.dart` dan semuanya hijau.', ts: 1003),
        ]);
      if (withCatalog) r.composer = ComposerCatalog.tryParse(catalogJson());
      return r;
    }

    Widget host(RemoteController r, Widget home) {
      final want = NV.palette;
      final look = AppearanceController(prefs);
      NV.palette = want; // the controller applies the saved look; keep the test's
      return ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) => settings),
          remoteProvider.overrideWith((ref) => r),
          appearanceProvider.overrideWith((ref) => look),
        ],
        child: RepaintBoundary(
          key: const ValueKey('shot'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildNeovarchMobileTheme(),
            darkTheme: buildNeovarchMobileTheme(),
            themeMode: NV.palette.dark ? ThemeMode.dark : ThemeMode.light,
            home: home,
          ),
        ),
      );
    }

    Future<void> phone(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(top: 141, bottom: 102);
      tester.view.viewPadding = const FakeViewPadding(top: 141, bottom: 102);
      addTearDown(tester.view.reset);
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    Future<void> shot(WidgetTester tester, String name) async {
      if (!autoUpdateGoldenFiles) return;
      final dir = Directory(_shotsDir).absolute.path;
      Directory(dir).createSync(recursive: true);
      await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('$dir/$name.png'));
    }

    Future<void> typeAt(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField).first, text);
      await settle(tester);
    }

    for (final mode in ['gelap', 'terang']) {
      testWidgets('composer flow ($mode): +, skill picker, chips, / and @, payload', (tester) async {
        NV.palette = NvPalette.from(const Color(0xFFEE1C1C), mode == 'gelap' ? Brightness.dark : Brightness.light);
        await phone(tester);
        final rec = _Rec();
        final g = _Gw(rec);
        final r = await controller(g);
        await tester.pumpWidget(host(r, RemoteChatScreen(onOpenApprovals: () {})));
        await settle(tester);
        // idle: model + reasoning chips, + on the left, tinted send
        expect(find.byKey(const ValueKey('chip-model')), findsOneWidget);
        expect(find.text('qwen3-coder-480b'), findsOneWidget);
        expect(find.byKey(const ValueKey('chip-reasoning')), findsOneWidget);
        expect(find.byKey(const ValueKey('composer-send')), findsOneWidget);
        expect(find.byType(ComposerPlusButton), findsOneWidget);
        await shot(tester, 'composer_01_idle_$mode');

        // + menu
        await tester.tap(find.byKey(const ValueKey('attach-button')));
        await settle(tester);
        for (final t in ['Foto / Galeri', 'Kamera', 'File', 'Tempel', 'Skill', 'Model', 'Penalaran', 'Sebut file/folder di PC', 'Tautan (URL)', 'Cuplikan perintah']) {
          expect(find.text(t), findsOneWidget, reason: t);
        }
        await shot(tester, 'composer_02_plus_menu_$mode');

        // skill picker: search + multi-select
        await tester.tap(find.byKey(const ValueKey('menu-skills')));
        await settle(tester);
        expect(find.byKey(const ValueKey('skill-picker')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('skill-row-code-review')));
        await settle(tester);
        await tester.enterText(find.descendant(of: find.byKey(const ValueKey('skill-search')), matching: find.byType(TextField)), 'lap');
        await settle(tester);
        expect(find.byKey(const ValueKey('skill-row-deploy')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('skill-row-laporan-skripsi')));
        await settle(tester);
        await shot(tester, 'composer_03_skill_picker_$mode');
        await tester.tap(find.byKey(const ValueKey('skill-done')));
        await settle(tester);
        expect(r.selectedSkills, ['code-review', 'laporan-skripsi']);
        expect(find.byKey(const ValueKey('chip-skill-code-review')), findsOneWidget);

        // reasoning via its chip
        await tester.tap(find.byKey(const ValueKey('chip-reasoning')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('reasoning-high')));
        await settle(tester);
        expect(find.text('Penalaran: Tinggi'), findsOneWidget);

        // "/" suggestions: picking a skill makes a chip and removes the token
        await typeAt(tester, '/dep');
        expect(find.byKey(const ValueKey('composer-suggestions')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('suggestion-/deploy')));
        await settle(tester);
        expect(r.selectedSkills, ['code-review', 'laporan-skripsi', 'deploy']);
        expect(find.byKey(const ValueKey('composer-suggestions')), findsNothing);

        // "@" suggestions from the PC
        await typeAt(tester, 'periksa @');
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
        await settle(tester);
        expect(find.byKey(const ValueKey('suggestion-@file:README.md')), findsOneWidget);
        expect(find.byKey(const ValueKey('suggestion-@diff')), findsOneWidget);
        await shot(tester, 'composer_05_mentions_$mode');
        await tester.tap(find.byKey(const ValueKey('suggestion-@file:README.md')));
        await settle(tester);
        final field = tester.widget<TextField>(find.byType(TextField).first);
        expect(field.controller!.text, 'periksa @file:README.md ');
        await tester.enterText(find.byType(TextField).first, 'periksa @file:README.md lalu perbaiki');
        await settle(tester);
        await shot(tester, 'composer_04_selection_chips_$mode');

        // send: payload carries the picks
        await tester.tap(find.byKey(const ValueKey('composer-send')));
        await settle(tester);
        expect(g.submits.single, {
          'session_id': 'rt-1',
          'text': 'periksa @file:README.md lalu perbaiki',
          'skills': ['code-review', 'laporan-skripsi', 'deploy'],
          'reasoning_effort': 'high',
        });
        expect(find.byKey(const ValueKey('chip-skill-deploy')), findsNothing);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('attachment previews above the field with chips ($mode)', (tester) async {
        NV.palette = NvPalette.from(const Color(0xFFEE1C1C), mode == 'gelap' ? Brightness.dark : Brightness.light);
        await phone(tester);
        final rec = _Rec();
        final r = await controller(_Gw(rec));
        final photo = (await tester.runAsync(() => rootBundle.load('assets/art/feat-remote.webp')))!.buffer.asUint8List();
        attachPicker = (src) async => src == AttachSource.file
            ? (name: 'catatan-rapat.md', bytes: Uint8List.fromList(utf8.encode('# Rapat\n')), mime: 'text/markdown')
            : (name: 'layar.webp', bytes: photo, mime: 'image/webp');
        r.setSkills(['code-review']);
        await tester.pumpWidget(host(r, RemoteChatScreen(onOpenApprovals: () {})));
        await settle(tester);
        for (final k in ['attach-gallery', 'attach-file']) {
          await tester.tap(find.byKey(const ValueKey('attach-button')));
          await settle(tester);
          await tester.tap(find.byKey(ValueKey(k)));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await settle(tester);
        }
        expect(r.pendingAttachments.length, 2);
        expect(find.byKey(const ValueKey('attach-strip')), findsOneWidget);
        expect(find.byKey(const ValueKey('composer-chips')), findsOneWidget);
        expect(rec.requests.where((q) => q.url.path == '/api/uploads').length, 2);
        await tester.runAsync(() => precacheImage(MemoryImage(photo), tester.element(find.byType(MaterialApp))));
        await settle(tester);
        await shot(tester, 'composer_06_attachments_$mode');
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('older PC: no chips, "+" has uploads only, "/" opens nothing', (tester) async {
      await phone(tester);
      final r = await controller(_Gw(_Rec(), oldPc: true), withCatalog: false);
      await tester.pumpWidget(host(r, RemoteChatScreen(onOpenApprovals: () {})));
      await settle(tester);
      expect(find.byKey(const ValueKey('composer-chips')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('attach-button')));
      await settle(tester);
      expect(find.text('Foto / Galeri'), findsOneWidget);
      expect(find.text('Skill'), findsNothing);
      expect(find.text('Model'), findsNothing);
      expect(find.text('Tautan (URL)'), findsNothing);
      await tester.tapAt(const Offset(200, 120));
      await settle(tester);
      await typeAt(tester, '/dep');
      expect(find.byKey(const ValueKey('composer-suggestions')), findsNothing);
      await shot(tester, 'composer_07_old_pc');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('URL and snippet insert into the field', (tester) async {
      await phone(tester);
      final r = await controller(_Gw(_Rec()));
      await tester.pumpWidget(host(r, RemoteChatScreen(onOpenApprovals: () {})));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('attach-button')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('menu-url')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('url-field')), 'github.com/Maftuuh1922');
      await tester.tap(find.byKey(const ValueKey('url-add')));
      await settle(tester);
      TextField field() => tester.widget<TextField>(find.byType(TextField).first);
      expect(field().controller!.text, '@url:https://github.com/Maftuuh1922 ');
      await tester.tap(find.byKey(const ValueKey('attach-button')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('menu-snippets')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('snippet-codeReview')));
      await settle(tester);
      expect(field().controller!.text, '@url:https://github.com/Maftuuh1922 Tolong tinjau ini untuk bug, regresi, dan tes yang kurang.');
      await tester.pumpWidget(const SizedBox());
    });
  });
}
