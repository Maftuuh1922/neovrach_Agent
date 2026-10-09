// Redesigned "Tampilan" (lib/remote/ui/appearance/): corner radius
// persistence + provider, liquid glass segmented control, HSV picker hex
// round-trip, adaptive glass legibility, and (with --update-goldens and
// NV_APPEARANCE_SHOTS=dir) screenshots over photo wallpapers.
//
//   NV_APPEARANCE_SHOTS=/workspace/work/nvappearance_shots \
//   NV_APPEARANCE_PHOTOS=/workspace/work/nvappearance_shots/src \
//     flutter test --update-goldens test/appearance_ui_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neovarch_agent/remote/appearance.dart';
import 'package:neovarch_agent/remote/remote_controller.dart';
import 'package:neovarch_agent/remote/saved_desktops.dart';
import 'package:neovarch_agent/remote/ui/appearance/accent_picker.dart';
import 'package:neovarch_agent/remote/ui/appearance/appearance_section.dart';
import 'package:neovarch_agent/remote/ui/appearance/corner_radius.dart';
import 'package:neovarch_agent/remote/ui/appearance/glass_segmented.dart';
import 'package:neovarch_agent/remote/ui/appearance/glass_surfaces.dart';
import 'package:neovarch_agent/remote/ui/appearance/panel_tone.dart';
import 'package:neovarch_agent/remote/ui/glass/backdrop_luminance.dart' show LuminanceGrid;
import 'package:neovarch_agent/remote/wallpaper_palette.dart' show WallpaperPalette;
import 'package:neovarch_agent/remote/ui/nv_widgets.dart' show NvHeader;
import 'package:neovarch_agent/remote/ui/remote_app.dart' show PaletteScope, themeFor;
import 'package:neovarch_agent/remote/ui/remote_background.dart' show NvAppBackground;
import 'package:neovarch_agent/remote/ui/remote_pc_screen.dart' show AppearancePanel;
import 'package:neovarch_agent/state/app_controller.dart' show settingsProvider;
import 'package:neovarch_agent/state/settings_controller.dart';
import 'package:neovarch_agent/theme/neovarch_mobile_theme.dart';

final _shotsDir = Platform.environment['NV_APPEARANCE_SHOTS'] ?? 'build/screenshots/appearance';
final _photos = Platform.environment['NV_APPEARANCE_PHOTOS'] ?? '/workspace/work/nvappearance_shots/src';

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

void main() {
  late SharedPreferences prefs;
  late SettingsController settings;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    settings = SettingsController(prefs);
    await settings.load();
    NV.palette = NvPalette.red;
    NV.corner = NV.defaultCorner;
    NvGlassFx.reduceTransparency.value = false;
  });

  tearDown(() {
    NV.palette = NvPalette.red;
    NV.corner = NV.defaultCorner;
    NvGlassFx.reduceTransparency.value = false;
  });

  Future<(AppearanceController, CornerRadiusController)> pump(WidgetTester tester, Widget home,
      {AppearanceController? look, CornerRadiusController? corners, Size size = const Size(390, 844), bool disableAnimations = false}) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final l = look ?? AppearanceController(prefs, systemBrightness: Brightness.dark);
    final c = corners ?? CornerRadiusController(prefs);
    final desktops = SavedDesktops(prefs)..load();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => settings),
        remoteProvider.overrideWith((ref) => RemoteController(desktops)),
        appearanceProvider.overrideWith((ref) => l),
        cornerRadiusProvider.overrideWith((ref) => c),
      ],
      child: RepaintBoundary(
        key: const ValueKey('shot'),
        child: Consumer(builder: (context, ref, _) {
          final look = ref.watch(appearanceProvider);
          final corners = ref.watch(cornerRadiusProvider);
          final theme = themeFor(look);
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            darkTheme: theme,
            themeMode: look.dark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
              child: AppCornerRadius(controller: corners, child: PaletteScope(revision: look.revision, look: look, child: child!)),
            ),
            home: home,
          );
        }),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    return (l, c);
  }

  // ------------------------------------------------------------ corner radius
  group('Kelengkungan sudut', () {
    test('controller persists, clamps, snaps and drives the NV radius tokens', () {
      final c = CornerRadiusController(prefs);
      expect(c.value, 24);
      expect(NV.rCard, 24);
      expect(c.presetName, 'Bulat');
      c.set(16.4);
      expect(c.value, 16);
      expect(prefs.getDouble(CornerRadiusController.kPrefKey), 16);
      expect(NV.rCard, 16);
      expect(NV.rCtl, 8);
      expect(NV.rMsg, 12);
      expect(NV.rDialog, 20);
      // concentric: inner = outer - padding, never negative
      expect(NV.inner(16, 12), 4);
      expect(NV.inner(8, 12), 0);
      expect(CornerRadiusController(prefs).value, 16, reason: 'reloaded from prefs');
      c.set(99);
      expect(c.value, kCornerMax);
      expect(c.presetName, 'Pil');
      c.set(-3);
      expect(c.value, 0);
      expect(NV.rCtl, 0);
      expect(NV.navFor(64), 0);
      c.reset();
      expect(c.value, NV.defaultCorner);
      expect(NV.navFor(64), 32, reason: 'capsule nav at the default');
    });

    testWidgets('provider + AppCornerRadius: dependants and the theme follow a change', (tester) async {
      var builds = 0;
      final (_, corners) = await pump(
          tester,
          Scaffold(body: Builder(builder: (context) {
            builds++;
            final r = AppCornerRadius.of(context);
            return Text('r=${r.card.round()} ctl=${r.control.round()}', key: const ValueKey('probe'));
          })));
      expect(find.text('r=24 ctl=12'), findsOneWidget);
      final b0 = builds;
      corners.set(28);
      await tester.pumpAndSettle();
      expect(find.text('r=28 ctl=16'), findsOneWidget);
      expect(builds, greaterThan(b0));
      final theme = Theme.of(tester.element(find.byKey(const ValueKey('probe'))));
      expect((theme.cardTheme.shape as RoundedRectangleBorder).borderRadius, BorderRadius.circular(28));
      final input = theme.inputDecorationTheme.border as OutlineInputBorder;
      expect(input.borderRadius, BorderRadius.circular(16));
      expect(prefs.getDouble('nv.ui.corner'), 28);
    });

    testWidgets('card: presets and slider change + persist the radius, preview follows', (tester) async {
      final (_, corners) = await pump(tester, const Scaffold(body: SingleChildScrollView(child: AppearancePanel())), size: const Size(390, 2000));
      expect(find.text('Kelengkungan sudut'), findsOneWidget);
      for (final (n, _) in cornerPresets) {
        expect(find.byKey(ValueKey('corner-preset-$n')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('corner-preset-Pil')));
      await tester.pumpAndSettle();
      expect(corners.value, 28);
      expect(prefs.getDouble('nv.ui.corner'), 28);
      final preview = tester.widget<AnimatedContainer>(find.byKey(const ValueKey('corner-preview')));
      expect((preview.decoration as BoxDecoration).borderRadius, BorderRadius.circular(28));
      await tester.tap(find.byKey(const ValueKey('corner-preset-Kotak')));
      await tester.pumpAndSettle();
      expect(corners.value, 0);
      // slider: tap at ~half → ~14 dp
      final s = find.byKey(const ValueKey('corner-slider'));
      await tester.tapAt(tester.getCenter(s));
      await tester.pumpAndSettle();
      expect(corners.value, inInclusiveRange(13, 15));
      expect(find.byKey(const ValueKey('corner-value')), findsOneWidget);
    });
  });

  // ----------------------------------------------------------- segmented
  group('Glass segmented control', () {
    Widget host(NvBrightnessMode sel, ValueChanged<NvBrightnessMode> on) => Scaffold(
          body: Center(
            child: SizedBox(
              width: 330,
              child: NvGlassSegmented<NvBrightnessMode>(
                key: const ValueKey('seg'),
                segments: const [
                  NvSegment(NvBrightnessMode.dark, 'Gelap'),
                  NvSegment(NvBrightnessMode.light, 'Terang'),
                  NvSegment(NvBrightnessMode.system, 'Sistem'),
                ],
                selected: sel,
                onChanged: on,
              ),
            ),
          ),
        );

    Rect lensRect(WidgetTester tester) {
      final seg = find.byKey(const ValueKey('seg'));
      final pos = find.descendant(of: seg, matching: find.byType(Positioned));
      return tester.getRect(pos.first);
    }

    testWidgets('tap selects; the lens springs over the selected segment (stretching on the way)', (tester) async {
      var sel = NvBrightnessMode.dark;
      late StateSetter setOuter;
      await pump(tester, StatefulBuilder(builder: (context, set) {
        setOuter = set;
        return host(sel, (v) => set(() => sel = v));
      }));
      final segRect = tester.getRect(find.byKey(const ValueKey('seg')));
      final start = lensRect(tester);
      expect(start.center.dx, lessThan(segRect.left + segRect.width / 3));
      await tester.tap(find.text('Sistem'));
      await tester.pump();
      expect(sel, NvBrightnessMode.system);
      await tester.pump(const Duration(milliseconds: 60));
      final mid = lensRect(tester);
      expect(mid.width, greaterThan(start.width), reason: 'lens stretches while travelling');
      await tester.pumpAndSettle();
      final end = lensRect(tester);
      expect(end.center.dx, greaterThan(segRect.right - segRect.width / 3));
      expect(end.width, closeTo(start.width, 0.5));
      setOuter(() {});
    });

    testWidgets('drag the lens across and release: snaps to the nearest segment', (tester) async {
      var sel = NvBrightnessMode.dark;
      await pump(tester, StatefulBuilder(builder: (context, set) => host(sel, (v) => set(() => sel = v))));
      final r = tester.getRect(find.byKey(const ValueKey('seg')));
      final g = await tester.startGesture(Offset(r.left + r.width / 6, r.center.dy));
      for (var i = 0; i < 10; i++) {
        await g.moveBy(Offset(r.width * 0.035, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(sel, NvBrightnessMode.light);
    });

    testWidgets('reduce motion: the lens jumps without animating', (tester) async {
      var sel = NvBrightnessMode.dark;
      await pump(tester, StatefulBuilder(builder: (context, set) => host(sel, (v) => set(() => sel = v))), disableAnimations: true);
      final r = tester.getRect(find.byKey(const ValueKey('seg')));
      await tester.tap(find.text('Terang'));
      await tester.pump();
      await tester.pump();
      expect(lensRect(tester).center.dx, closeTo(r.center.dx, 2));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('Tampilan: Gelap / Terang / Sistem through the glass control', (tester) async {
      final (look, _) = await pump(tester, const Scaffold(body: SingleChildScrollView(child: AppearancePanel())), size: const Size(390, 2000));
      await tester.tap(find.text('Terang'));
      await tester.pumpAndSettle();
      expect(look.localMode, NvBrightnessMode.light);
      expect(NV.palette.dark, isFalse);
      await tester.tap(find.text('Sistem'));
      await tester.pumpAndSettle();
      expect(look.localMode, NvBrightnessMode.system);
      // glass switch toggles "Ikuti tema PC"
      await tester.tap(find.byKey(const ValueKey('follow-pc-switch')));
      await tester.pumpAndSettle();
      expect(look.followPc, isTrue);
    });
  });

  // -------------------------------------------------------------- HSV / hex
  group('Accent picker', () {
    test('hex normalisation + HSV round trip are lossless for 6-digit colours', () {
      expect(normalizeHex('3a8fd0'), '#3A8FD0');
      expect(normalizeHex('#abc'), '#AABBCC');
      expect(normalizeHex(' #ff0066 '), '#FF0066');
      expect(normalizeHex('#12345'), isNull);
      expect(normalizeHex('zzzzzz'), isNull);
      final rnd = math.Random(7);
      for (var i = 0; i < 500; i++) {
        final c = Color(0xFF000000 | rnd.nextInt(0xFFFFFF));
        expect(parseHexColor(hexOf(c)), c);
      }
    });

    test('curated swatches are distinct, harmonised and legible as accents', () {
      final all = [nvBrandSwatch, ...nvAccentSwatches];
      expect(all.map((s) => s.$2.toARGB32()).toSet().length, all.length);
      for (final (n, c) in nvAccentSwatches) {
        final o = Oklch.fromColor(c);
        expect(o.l, inInclusiveRange(0.58, 0.76), reason: n);
        // text on a filled accent button stays ≥ 4.5:1
        final on = NvPalette.from(c, Brightness.dark).onAccent;
        expect(contrastRatio(on, c), greaterThanOrEqualTo(4.5), reason: n);
      }
      expect(accentName(const Color(0xFF18A7A1)), 'Toska');
      expect(accentName(NvPalette.defaultAccent), 'Neovarch');
      expect(accentName(const Color(0xFF123456)), isNull);
    });

    testWidgets('Kustom → HSV picker: typed hex round-trips exactly; pad + hue update the hex', (tester) async {
      Color? applied;
      await pump(
          tester,
          Scaffold(
              body: Builder(
                  builder: (context) => Center(
                        child: TextButton(
                          onPressed: () async => applied = await showNvHsvPicker(context, initial: const Color(0xFF18A7A1)),
                          child: const Text('open'),
                        ),
                      ))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('hsv-picker')), findsOneWidget);
      final field = find.descendant(of: find.byKey(const ValueKey('hsv-hex')), matching: find.byType(TextField));
      expect(tester.widget<TextField>(field).controller!.text, '#18A7A1');
      await tester.enterText(field, '#3a8fd0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, '#3A8FD0');
      await tester.tap(find.byKey(const ValueKey('hsv-apply')));
      await tester.pumpAndSettle();
      expect(applied, const Color(0xFF3A8FD0));

      // open again: drag on the pad (top-right = full saturation & value)
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final pad = find.byKey(const ValueKey('hsv-pad'));
      await tester.tapAt(tester.getTopRight(pad) + const Offset(-1, 1));
      await tester.pump();
      final hex = tester.widget<TextField>(field).controller!.text;
      final st = tester.state<NvHsvPickerState>(find.byType(NvHsvPicker));
      expect(hex, hexOf(st.color));
      final hsv = HSVColor.fromColor(st.color);
      expect(hsv.saturation, greaterThan(0.95));
      expect(hsv.value, greaterThan(0.95));
      // hue slider far right ≈ 360° → red
      final hue = find.byKey(const ValueKey('hsv-hue'));
      await tester.tapAt(tester.getTopRight(hue) + Offset(-2, tester.getSize(hue).height / 2));
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, hexOf(st.color));
      final h = HSVColor.fromColor(st.color).hue;
      expect(h > 340 || h < 10, isTrue, reason: 'hue $h');
      await tester.tap(find.byKey(const ValueKey('hsv-apply')));
      await tester.pumpAndSettle();
      expect(applied, st.color);
    });

    testWidgets('swatches: tap applies; "Dari wallpaper" shows the wallpaper palette', (tester) async {
      final (look, _) = await pump(tester, const Scaffold(body: SingleChildScrollView(child: AppearancePanel())), size: const Size(390, 2000));
      expect(find.byKey(const ValueKey('accent-wallpaper-row')), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('accent-Langit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('accent-Langit')));
      await tester.pumpAndSettle();
      expect(NV.red, const Color(0xFF369DD1));
      expect(find.text('Langit · #369DD1'), findsOneWidget);
      WallpaperAnalyzer.instance.debugPut(
          'asset:${backgroundPresets.first.$2}',
          const WallpaperStats(dark: Color(0xFF101418), light: Color(0xFFE8D8C0), mean: Color(0xFF6A5A50)));
      look.setBackground(look.background.copyWith(source: 'asset:${backgroundPresets.first.$2}'));
      // the suggestions come from the one wallpaper palette extractor
      look.applyWallpaperPalette(const WallpaperPalette(Color(0xFFDF7752), [Color(0xFFDF7752), Color(0xFF369DD1)]));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('accent-wallpaper-row')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('accent-wall-0')));
      await tester.pumpAndSettle();
      expect(NV.red, const Color(0xFFDF7752));
      WallpaperAnalyzer.instance.debugClear();
    });
  });

  // ------------------------------------------------------------- legibility
  group('Adaptive glass', () {
    test('fill opacity keeps text and secondary text ≥ 4.5:1 over any wallpaper', () {
      const extremes = [
        WallpaperStats(dark: Color(0xFF000000), light: Color(0xFFFFFFFF), mean: Color(0xFF808080)),
        WallpaperStats(dark: Color(0xFFF0F0F0), light: Color(0xFFFFFFFF), mean: Color(0xFFF8F8F8)),
        WallpaperStats(dark: Color(0xFF000000), light: Color(0xFF202020), mean: Color(0xFF101010)),
        WallpaperStats(dark: Color(0xFF203040), light: Color(0xFFFFE070), mean: Color(0xFF808060)),
      ];
      for (final accent in [NvPalette.defaultAccent, ...nvAccentSwatches.map((s) => s.$2)]) {
        for (final b in Brightness.values) {
          final p = NvPalette.from(accent, b);
          for (final w in extremes) {
            final t = NvPanelTone.resolve(p, w);
            expect(t.worstContrast(p.text, w), greaterThanOrEqualTo(4.5), reason: '$accent $b text');
            expect(t.worstContrast(p.muted, w), greaterThanOrEqualTo(4.5), reason: '$accent $b muted');
          }
        }
      }
      // flat dark background: stays translucent (real glass), not opaque
      expect(NvPanelTone.resolve(NvPalette.red, WallpaperStats.flat(NvPalette.red.bg)).fillAlpha, lessThan(0.6));
      // reduce transparency: opaque, no rim
      final r = NvPanelTone.resolve(NvPalette.red, extremes.first, reduced: true);
      expect(r.fillAlpha, 1);
      expect(r.rim.a, 0);
    });

    test('wallpaper stats: extremes ordered; same stats from the shared luminance grid', () {
      final px = Uint8List(40 * 40 * 4);
      for (var i = 0; i < 1600; i++) {
        final warm = i % 2 == 0;
        px[i * 4] = warm ? 230 : 20;
        px[i * 4 + 1] = warm ? 120 : 60;
        px[i * 4 + 2] = warm ? 40 : 160;
        px[i * 4 + 3] = 255;
      }
      final s = statsFromRgba(px);
      expect(relativeLuminance(s.light), greaterThan(relativeLuminance(s.dark)));
      final g = statsFromGrid(LuminanceGrid.fromRgba(40, 40, px, cols: 40, rows: 40));
      expect(g, s);
    });

    testWidgets('reduce transparency ("Gaya kaca: Tanpa"): no backdrop blur in the appearance cards', (tester) async {
      final (look, _) = await pump(tester, const Scaffold(body: SingleChildScrollView(child: AppearancePanel())), size: const Size(390, 2000));
      look.setGlassStyle(NvGlassStyle.tanpa);
      await tester.pumpAndSettle();
      expect(NvGlassFx.reduceTransparency.value, isTrue);
      expect(find.descendant(of: find.byKey(const ValueKey('appearance-panel')), matching: find.byType(BackdropFilter)), findsNothing);
      look.setGlassStyle(NvGlassStyle.reguler);
      await tester.pumpAndSettle();
      expect(NvGlassFx.reduceTransparency.value, isFalse);
      expect(find.descendant(of: find.byKey(const ValueKey('appearance-panel')), matching: find.byType(BackdropFilter)), findsWidgets);
    });
  });

  // ------------------------------------------------------------ screenshots
  group('Screenshots', () {
    Future<void> shot(WidgetTester tester, String name) async {
      if (!autoUpdateGoldenFiles) return;
      final dir = Directory(_shotsDir).absolute.path;
      Directory(dir).createSync(recursive: true);
      await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('$dir/$name.png'));
    }

    Widget screen(ImageProvider? photo) => Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(children: [
            Positioned.fill(child: NvAppBackground(debugImage: photo)),
            ListView(padding: const EdgeInsets.only(bottom: 40), children: const [
              NvHeader(kicker: 'pc kantor', title: 'Pengaturan'),
              NvPanelToneHost(child: NvGlassSectionHeader('Tampilan', icon: Icons.palette_outlined, padding: EdgeInsets.fromLTRB(20, 4, 20, 12))),
              AppearancePanel(),
            ]),
          ]),
        );

    Future<void> run(WidgetTester tester, String name,
        {required String? photo, String accent = '#EE1C1C', String base = 'dark', double corner = 24, double dim = 0.25, double blur = 2}) async {
      final file = photo == null ? null : File('$_photos/$photo');
      if (file != null && !file.existsSync()) {
        markTestSkipped('photo $photo missing');
        return;
      }
      prefs.setBool('nv.theme.follow', false);
      prefs.setString('nv.theme.accent', accent);
      prefs.setString('nv.theme.base', base);
      prefs.setDouble('nv.ui.corner', corner);
      if (file != null) {
        prefs.setString('nv.bg.source', 'file:${file.path}');
        prefs.setDouble('nv.bg.dim', dim);
        prefs.setDouble('nv.bg.blur', blur);
        prefs.setDouble('nv.bg.tint', 0.05);
        // Pixel read-back (Image.toByteData) never completes on flutter_tester:
        // feed the analyser the same 40×40 RGBA sample decoded offline.
        final rgba = File('${file.path}.rgba');
        if (rgba.existsSync()) WallpaperAnalyzer.instance.debugPut('file:${file.path}', statsFromRgba(rgba.readAsBytesSync()));
      }
      final look = AppearanceController(prefs, systemBrightness: Brightness.dark);
      final img = file == null ? null : MemoryImage(file.readAsBytesSync());
      debugPrint('[$name] pump');
      await pump(tester, screen(img), look: look, size: const Size(390, 1720));
      if (img != null) {
        await tester.runAsync(() async {
          await precacheImage(img, tester.element(find.byType(Scaffold).first));
        });
      }
      debugPrint('[$name] precached');
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      debugPrint('[$name] settled');
      await shot(tester, name);
      debugPrint('[$name] shot');
      await tester.pumpWidget(const SizedBox());
      WallpaperAnalyzer.instance.debugClear();
    }

    testWidgets('1 dark busy photo', (tester) => run(tester, '1_dark_photo', photo: 'dark.jpg'));
    testWidgets('2 bright photo (dark theme)', (tester) => run(tester, '2_bright_photo', photo: 'bright.jpg', accent: '#DF7752', dim: 0.15));
    testWidgets('3 light theme over bright photo', (tester) => run(tester, '3_light_theme', photo: 'bright.jpg', accent: '#369DD1', base: 'light', dim: 0.2));
    testWidgets('4 radius 0', (tester) => run(tester, '4_radius_0', photo: 'dark.jpg', accent: '#8968D4', corner: 0));
    testWidgets('5 radius 16', (tester) => run(tester, '5_radius_16', photo: 'dark.jpg', accent: '#8968D4', corner: 16));
    testWidgets('6 radius 32', (tester) => run(tester, '6_radius_32', photo: 'dark.jpg', accent: '#8968D4', corner: 32));
    testWidgets('7 flat (no wallpaper)', (tester) => run(tester, '7_flat_dark', photo: null, accent: '#18A7A1'));
  });
}
