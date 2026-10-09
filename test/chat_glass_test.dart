// Liquid glass chat: LiquidGlass variants, wallpaper-luminance legibility,
// colour harmony and the chat screen using glass for every bubble/card.
// Screenshots (run with --update-goldens): chat over a dark busy photo, a
// bright photo, light theme and Polos → $NV_GLASS_SHOTS_DIR.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neovarch_agent/main.dart' as app;
import 'package:neovarch_agent/models/models.dart' show ChatMsg;
import 'package:neovarch_agent/remote/appearance.dart';
import 'package:neovarch_agent/remote/remote_controller.dart';
import 'package:neovarch_agent/remote/remote_gateway.dart';
import 'package:neovarch_agent/remote/remote_transcript.dart';
import 'package:neovarch_agent/remote/saved_desktops.dart';
import 'package:neovarch_agent/remote/ui/glass/backdrop_luminance.dart';
import 'package:neovarch_agent/remote/ui/glass/glass_chat.dart';
import 'package:neovarch_agent/remote/ui/glass/glass_style.dart';
import 'package:neovarch_agent/remote/ui/glass/glass_tone.dart';
import 'package:neovarch_agent/remote/ui/glass/liquid_glass.dart';
import 'package:neovarch_agent/remote/ui/remote_app.dart' show PaletteScope, themeFor;
import 'package:neovarch_agent/remote/ui/remote_shell.dart';
import 'package:neovarch_agent/state/app_controller.dart' show settingsProvider;
import 'package:neovarch_agent/state/settings_controller.dart';
import 'package:neovarch_agent/theme/neovarch_mobile_theme.dart';
import 'package:neovarch_agent/ui/screens/chat/message_widgets.dart' show FailureCard;

const _kuning = Color(0xFFCA8A04);
final _shotsDir = Platform.environment['NV_GLASS_SHOTS_DIR'] ?? '/workspace/work/nvchatglass_shots';
final _srcDir = Platform.environment['NV_GLASS_SRC'] ?? '/workspace/work/nvchatglass_shots/src';

LuminanceGrid _grid(Color Function(int x, int y) px, {int w = 32, int h = 64}) {
  final b = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final c = px(x, y);
      final i = (y * w + x) * 4;
      b[i] = (c.r * 255).round();
      b[i + 1] = (c.g * 255).round();
      b[i + 2] = (c.b * 255).round();
      b[i + 3] = 255;
    }
  }
  return LuminanceGrid.fromRgba(w, h, b);
}

/// Dark green "lily pond": noisy dark greens with bright pink/white specks.
Color _pond(int x, int y) {
  final n = ((x * 73856093) ^ (y * 19349663)) & 0xFF;
  if (n % 23 == 0) return const Color(0xFFF2C6D6); // flower
  if (n % 7 == 0) return const Color(0xFF3F7A3A); // lit pad
  return Color.fromARGB(255, 10 + n % 20, 34 + n % 40, 22 + n % 18);
}

Color _bright(int x, int y) {
  final n = ((x * 73856093) ^ (y * 19349663)) & 0xFF;
  if (n % 9 == 0) return const Color(0xFF7ED957);
  return Color.fromARGB(255, 200 + n % 50, 225 + n % 30, 215 + n % 40);
}

void main() {
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
        {'id': 'pc1', 'name': 'MUHAMMADMAFTUH', 'url': 'http://192.168.1.20:9319', 'addedAt': DateTime.now().toIso8601String()},
      ]),
      'remote.active': 'pc1',
    });
    prefs = await SharedPreferences.getInstance();
    settings = SettingsController(prefs);
    await settings.load();
    NV.palette = NvPalette.red;
    NV.glassSigma.value = NV.glassBlur;
  });
  tearDown(() {
    NV.palette = NvPalette.red;
    NV.glassSigma.value = NV.glassBlur;
    app.previewTab = 0;
  });

  RemoteController controller(List<ChatMsg> history, {String? error}) {
    final desktops = SavedDesktops(prefs)..load();
    final r = RemoteController(desktops)
      ..transcript = (RemoteTranscript(history: history)..error = error)
      ..debugApprovals = []
      ..desktop = desktops.items.first
      ..status = RemoteStatus.connected
      ..title = 'halo';
    return r;
  }

  Future<void> pumpShell(WidgetTester tester, AppearanceController look, RemoteController r) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    app.previewTab = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => settings),
        remoteProvider.overrideWith((ref) => r),
        appearanceProvider.overrideWith((ref) => look),
      ],
      child: Consumer(builder: (context, ref, _) {
        final l = ref.watch(appearanceProvider);
        return RepaintBoundary(
          key: const ValueKey('shot'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: themeFor(l),
            builder: (context, child) => PaletteScope(revision: l.revision, look: l, child: child!),
            home: const RemoteShell(),
          ),
        );
      }),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  List<ChatMsg> history() => [
        ChatMsg(id: 'u1', role: 'user', content: 'halo', ts: DateTime(2026, 10, 9, 6, 12).millisecondsSinceEpoch),
        ChatMsg(id: 'a1', role: 'assistant', ts: DateTime(2026, 10, 9, 6, 12).millisecondsSinceEpoch, error: 'HTTP 404: model "glm-4.6" not found at endpoint /v1/chat/completions'),
        ChatMsg(id: 'u2', role: 'user', content: 'coba cek versi flutter di PC', ts: DateTime(2026, 10, 9, 6, 14).millisecondsSinceEpoch),
        ChatMsg(
            id: 'a2',
            role: 'assistant',
            ts: DateTime(2026, 10, 9, 6, 14).millisecondsSinceEpoch,
            content: 'Versi Flutter di PC kamu **3.47.6** (stable). Jalankan ini untuk memastikan:\n\n```bash\nflutter --version\n```\n\nSemua siap — lihat [catatan rilis](https://flutter.dev).'),
      ];

  group('LiquidGlass variants', () {
    for (final s in GlassStyle.values) {
      testWidgets('${s.name}: ${s == GlassStyle.tanpa ? 'no' : 'one'} BackdropFilter, RepaintBoundary, superellipse clip', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: GlassScope(
            style: s,
            child: const Center(child: LiquidGlass(padding: EdgeInsets.all(12), child: Text('kaca'))),
          ),
        ));
        final g = find.byType(LiquidGlass);
        expect(find.descendant(of: g, matching: find.byType(BackdropFilter)), s == GlassStyle.tanpa ? findsNothing : findsOneWidget);
        expect(find.descendant(of: g, matching: find.byType(ClipRSuperellipse)), findsOneWidget);
        expect(find.descendant(of: g, matching: find.byType(RepaintBoundary)), findsWidgets);
        expect(find.text('kaca'), findsOneWidget);
      });
    }

    test('enum names are the "Gaya kaca" values; parse falls back to reguler', () {
      expect(GlassStyle.values.map((e) => e.name), ['reguler', 'bening', 'gelap', 'warna', 'tanpa']);
      expect(GlassStyle.parse('gelap'), GlassStyle.gelap);
      expect(GlassStyle.parse(null), GlassStyle.reguler);
      expect(GlassStyle.tanpa.sigma, 0);
    });

    testWidgets('default scope style is reguler; glassStyleProvider drives GlassBackdrop', (tester) async {
      final look = AppearanceController(prefs, systemBrightness: Brightness.dark);
      late GlassStyle seen;
      final container = ProviderContainer(overrides: [appearanceProvider.overrideWith((ref) => look)]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: GlassBackdrop(child: Builder(builder: (c) {
          seen = GlassScope.styleOf(c);
          return const SizedBox();
        }))),
      ));
      expect(seen, GlassStyle.reguler);
      container.read(glassStyleProvider.notifier).state = GlassStyle.gelap;
      await tester.pump();
      expect(seen, GlassStyle.gelap);
    });

    testWidgets('materialize: scales in from 0.96 and settles; reduce motion skips it', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Center(child: LiquidGlass(appear: true, child: SizedBox(width: 100, height: 40)))));
      expect(find.descendant(of: find.byType(LiquidGlass), matching: find.byType(Transform)), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.descendant(of: find.byType(LiquidGlass), matching: find.byType(Transform)), findsNothing);

      await tester.pumpWidget(const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: Center(child: LiquidGlass(key: ValueKey('rm'), appear: true, child: SizedBox(width: 100, height: 40)))),
      ));
      await tester.pump();
      expect(find.descendant(of: find.byKey(const ValueKey('rm')), matching: find.byType(Transform)), findsNothing);
    });
  });

  group('Legibility', () {
    const screen = Size(390, 844);
    const rect = Rect.fromLTWH(40, 300, 300, 80);

    test('dark busy photo → light text; bright photo → dark text; both ≥ 4.5:1', () {
      final dark = GlassBackdropMap.image(_grid(_pond), screen: screen, base: NvPalette.red.bg).sample(rect);
      final bright = GlassBackdropMap.image(_grid(_bright), screen: screen, base: NvPalette.red.bg).sample(rect);
      expect(dark.luminance, lessThan(0.1));
      expect(bright.luminance, greaterThan(0.6));
      for (final role in GlassRole.values) {
        final td = resolveGlassTone(sample: dark, accent: _kuning, role: role);
        expect(td.lightText, isTrue, reason: '$role on dark');
        expect(td.contrast, greaterThanOrEqualTo(kGlassMinContrast));
        expect(relativeLuminance(td.text), greaterThan(0.7));
        final tb = resolveGlassTone(sample: bright, accent: _kuning, role: role);
        expect(tb.lightText, role == GlassRole.code, reason: '$role on bright');
        expect(tb.contrast, greaterThanOrEqualTo(kGlassMinContrast));
      }
    });

    test('every style keeps secondary text ≥ 4.5:1 over a black/white checkerboard', () {
      final board = GlassBackdropMap.image(_grid((x, y) => (x ~/ 2 + y ~/ 2).isEven ? const Color(0xFFFFFFFF) : const Color(0xFF000000)),
              screen: screen, base: NvPalette.red.bg)
          .sample(rect);
      for (final s in GlassStyle.values) {
        for (final accent in accentPresets.map((e) => e.$2)) {
          final t = resolveGlassTone(sample: board, accent: accent, style: s, role: GlassRole.accent);
          expect(t.contrast, greaterThanOrEqualTo(kGlassMinContrast), reason: '${s.name} ${hexOf(accent)}');
        }
      }
      expect(resolveGlassTone(sample: board, accent: _kuning, style: GlassStyle.gelap).lightText, isTrue);
    });

    test('flat backdrop (Polos) samples the theme background', () {
      final s = const GlassBackdropMap.flat(Color(0xFFF6F4F1)).sample(rect);
      expect(s.mean, const Color(0xFFF6F4F1));
      expect(resolveGlassTone(sample: s, accent: _kuning).lightText, isFalse);
    });

    test('accent and error are adjusted to stay legible; error stays red', () {
      final light = resolveGlassTone(sample: const BackdropSample.solid(Color(0xFFFFFFFF)), accent: _kuning);
      expect(contrastRatio(light.accent, light.composite), greaterThanOrEqualTo(4.5));
      for (final (_, a) in accentPresets) {
        final h = HSLColor.fromColor(harmonizedError(a)).hue;
        expect(h < 20 || h > 340, isTrue, reason: hexOf(a));
      }
      expect(harmonizedError(const Color(0xFFA3A3A3)), const Color(0xFFFF453A)); // mono accent: plain red
    });

    test('hysteresis keeps the previous foreground on a near tie', () {
      const mid = BackdropSample.solid(Color(0xFF8A8A8A));
      final a = resolveGlassTone(sample: mid, accent: _kuning, previousLightText: true);
      final b = resolveGlassTone(sample: mid, accent: _kuning, previousLightText: false);
      expect(a.contrast, greaterThanOrEqualTo(4.5));
      expect(b.contrast, greaterThanOrEqualTo(4.5));
    });

    testWidgets('the bubble picks light text over a dark image and dark text over a bright one', (tester) async {
      Future<Color> userText(LuminanceGrid g) async {
        await tester.pumpWidget(MaterialApp(
          home: Builder(builder: (c) {
            final map = GlassBackdropMap.image(g, screen: MediaQuery.sizeOf(c), base: NV.bg);
            return GlassScope(
              backdrop: map,
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: Center(child: GlassUserMessage(msg: ChatMsg(id: 'x', role: 'user', content: 'halo', ts: 0))),
              ),
            );
          }),
        ));
        await tester.pump();
        return tester.widget<SelectableText>(find.byType(SelectableText)).style!.color!;
      }

      expect(relativeLuminance(await userText(_grid(_pond))), greaterThan(0.7));
      expect(relativeLuminance(await userText(_grid(_bright))), lessThan(0.05));
    });
  });

  group('Chat screen uses liquid glass', () {
    testWidgets('user bubble, agent turns, sender labels, header, error card + banner, code block', (tester) async {
      final look = AppearanceController(prefs, systemBrightness: Brightness.light)..setLocal(accent: _kuning, dark: false);
      await pumpShell(tester, look, controller(history(), error: 'Giliran gagal: model tidak ditemukan (404)'));
      expect(find.descendant(of: find.byType(GlassUserMessage), matching: find.byType(LiquidGlass)), findsNWidgets(2));
      expect(find.byType(GlassAgentTurn), findsNWidgets(2));
      expect(find.byType(GlassSenderLabel), findsNWidgets(2));
      expect(find.byKey(const ValueKey('glass-chat-header')), findsOneWidget);
      expect(find.byKey(const ValueKey('glass-header-title')), findsOneWidget);
      // the failure card sits inside agent glass, the banner is glass
      expect(find.ancestor(of: find.byType(FailureCard), matching: find.byType(LiquidGlass)), findsWidgets);
      expect(find.text('Giliran gagal · Model / endpoint'), findsOneWidget);
      expect(find.byType(GlassNotice), findsOneWidget);
      expect(find.byType(GlassCode), findsOneWidget);
      // one shared backdrop read for the list
      expect(find.byType(BackdropGroup), findsOneWidget);
      // no cream/amber: user glass fill is accent-tinted translucent, error icon is red not the accent
      final ctx = tester.element(find.text('Giliran gagal · Model / endpoint'));
      final tone = GlassForeground.maybeOf(ctx)!.tone;
      expect(tone.fill.a, lessThan(0.97));
      final h = HSLColor.fromColor(tone.error).hue;
      expect(h < 20 || h > 340, isTrue);
    });

    testWidgets('new messages materialize; loaded history does not', (tester) async {
      final look = AppearanceController(prefs, systemBrightness: Brightness.dark);
      final r = controller(history().take(2).toList());
      await pumpShell(tester, look, r);
      expect(find.descendant(of: find.byType(GlassUserMessage), matching: find.byType(Transform)), findsNothing);
      r.transcript.messages.add(ChatMsg(id: 'u9', role: 'user', content: 'lagi', ts: 1));
      r.notifyListeners(); // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.descendant(of: find.byType(GlassUserMessage).last, matching: find.byType(Transform)), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.descendant(of: find.byType(GlassUserMessage).last, matching: find.byType(Transform)), findsNothing);
    });
  });

  group('Screenshots', () {
    Future<void> shot(WidgetTester tester, String name, AppearanceController look, {String? photo}) async {
      final r = controller(history(), error: 'Koneksi ke penyedia terputus (timeout 30 detik).');
      await pumpShell(tester, look, r);
      if (photo != null) {
        final img = FileImage(File('$_srcDir/$photo'));
        final ctx = tester.element(find.byType(RemoteShell));
        await tester.runAsync(() async {
          await precacheImage(img, ctx);
          await loadLuminanceGrid(img);
        });
        look.setBackground(look.background.copyWith(source: 'file:$_srcDir/$photo', blur: 0, dim: 0, tint: 0));
      }
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final dir = Directory(_shotsDir)..createSync(recursive: true);
      await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('${dir.absolute.path}/$name.png'));
    }

    final have = File('$_srcDir/lily_dark.jpg').existsSync();
    testWidgets('chat over a dark busy photo (light theme, Kuning — the reported case)', (tester) async {
      final look = AppearanceController(prefs, systemBrightness: Brightness.light)..setLocal(accent: _kuning, dark: false);
      await shot(tester, '1_dark_photo_light_theme', look, photo: 'lily_dark.jpg');
    }, skip: !autoUpdateGoldenFiles || !have);
    testWidgets('chat over a dark busy photo (dark theme)', (tester) async {
      final look = AppearanceController(prefs, systemBrightness: Brightness.dark)..setLocal(accent: _kuning, dark: true);
      await shot(tester, '2_dark_photo_dark_theme', look, photo: 'lily_dark.jpg');
    }, skip: !autoUpdateGoldenFiles || !have);
    testWidgets('chat over a bright photo', (tester) async {
      final look = AppearanceController(prefs, systemBrightness: Brightness.dark)..setLocal(accent: const Color(0xFF0D9488), dark: true);
      await shot(tester, '3_bright_photo_dark_theme', look, photo: 'lily_bright.jpg');
    }, skip: !autoUpdateGoldenFiles || !have);
    testWidgets('light theme, Polos', (tester) async {
      final look = AppearanceController(prefs, systemBrightness: Brightness.light)..setLocal(accent: _kuning, dark: false);
      await shot(tester, '4_polos_light_theme', look);
    }, skip: !autoUpdateGoldenFiles);
    testWidgets('dark theme, Polos (Merah)', (tester) async {
      final look = AppearanceController(prefs, systemBrightness: Brightness.dark);
      await shot(tester, '5_polos_dark_theme', look);
    }, skip: !autoUpdateGoldenFiles);
  });
}
