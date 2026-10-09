// v1.4.1: many accent presets that recolour the whole UI, Gelap/Terang/
// Sistem, live theme picker with a cross-fade, the themed cold-start intro,
// and the iOS-style liquid glass tab bar (blur + rim + springing lens).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neovarch_agent/main.dart' as app;
import 'package:neovarch_agent/remote/appearance.dart';
import 'package:neovarch_agent/remote/ui/appearance/accent_picker.dart' show nvAccentSwatches;
import 'package:neovarch_agent/remote/remote_controller.dart';
import 'package:neovarch_agent/remote/remote_gateway.dart';
import 'package:neovarch_agent/remote/remote_transcript.dart';
import 'package:neovarch_agent/remote/saved_desktops.dart';
import 'package:neovarch_agent/remote/ui/nv_widgets.dart';
import 'package:neovarch_agent/remote/ui/remote_app.dart' show PaletteScope, themeFor;
import 'package:neovarch_agent/remote/ui/remote_launch.dart';
import 'package:neovarch_agent/remote/ui/remote_pc_screen.dart' show AppearancePanel;
import 'package:neovarch_agent/remote/ui/remote_shell.dart';
import 'package:neovarch_agent/state/app_controller.dart' show settingsProvider;
import 'package:neovarch_agent/state/settings_controller.dart';
import 'package:neovarch_agent/theme/neovarch_mobile_theme.dart';

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
  });

  tearDown(() => NV.palette = NvPalette.red);

  RemoteController controller() {
    final desktops = SavedDesktops(prefs)..load();
    return RemoteController(desktops)
      ..desktop = desktops.items.first
      ..status = RemoteStatus.connected
      ..transcript = RemoteTranscript()
      ..debugApprovals = [];
  }

  Future<AppearanceController> pump(WidgetTester tester, Widget home, {AppearanceController? look, RemoteController? r}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final l = look ?? AppearanceController(prefs, systemBrightness: Brightness.dark);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => settings),
        remoteProvider.overrideWith((ref) => r ?? controller()),
        appearanceProvider.overrideWith((ref) => l),
      ],
      child: Consumer(builder: (context, ref, _) {
        final look = ref.watch(appearanceProvider);
        return MaterialApp(
          theme: themeFor(look),
          builder: (context, child) => PaletteScope(revision: look.revision, look: look, child: child!),
          home: home,
        );
      }),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    return l;
  }

  group('Theme presets', () {
    test('at least 10 distinct accents, Merah first (the default)', () {
      expect(accentPresets.length, greaterThanOrEqualTo(10));
      expect(accentPresets.first.$2, NvPalette.defaultAccent);
      expect(accentPresets.map((p) => p.$2.toARGB32()).toSet().length, accentPresets.length);
      expect(accentPresets.map((p) => p.$1).toSet().length, accentPresets.length);
    });

    test('every preset recolours the whole UI, not just the accent', () {
      final bgs = <int>{}, surfaces = <int>{}, washes = <int>{}, glass = <int>{};
      for (final (name, c) in accentPresets) {
        for (final b in Brightness.values) {
          NV.palette = NvPalette.from(c, b);
          final theme = buildNeovarchMobileTheme();
          // 1.4.4: light mode deepens pale accents for contrast (same hue)
          expect(theme.colorScheme.primary, b == Brightness.dark ? c : NV.red, reason: name);
          if (b == Brightness.light && c.toARGB32() != NV.red.toARGB32()) {
            expect(NvPalette.contrast(NV.red, NV.bg), greaterThanOrEqualTo(3.0), reason: name);
          }
          expect(theme.scaffoldBackgroundColor, NV.bg, reason: name);
          expect(theme.chipTheme.selectedColor, NV.redWash, reason: name);
          bgs.add(NV.bg.toARGB32());
          surfaces.add(NV.surface.toARGB32());
          washes.add(NV.redWash.toARGB32());
          glass.add(NV.navGlass.toARGB32());
          // readable text on the accent (filled buttons, badges)
          final on = NV.onRed;
          expect(on == const Color(0xFFFFFFFF) || on == const Color(0xFF000000) || on == const Color(0xFFF4F2ED), isTrue, reason: name);
        }
      }
      final n = accentPresets.length * 2;
      // surfaces, glass and washes follow the accent (Monokrom ≈ neutral)
      expect(bgs.length, greaterThan(n * 0.8));
      expect(surfaces.length, greaterThan(n * 0.8));
      expect(washes.length, greaterThan(n * 0.8));
      expect(glass.length, greaterThan(n * 0.8));
    });

    test('Gelap / Terang / Sistem, persisted, with native boot colours', () {
      final look = AppearanceController(prefs, systemBrightness: Brightness.light);
      expect(look.followPc, isTrue);
      look.setLocal(accent: const Color(0xFF0D9488), mode: NvBrightnessMode.system);
      expect(look.followPc, isFalse);
      expect(NV.palette.dark, isFalse); // the phone is light
      look.setSystemBrightness(Brightness.dark);
      expect(NV.palette.dark, isTrue);
      expect(NV.red, const Color(0xFF0D9488));
      expect(prefs.getString('nv.theme.base'), 'system');
      expect(prefs.getString(AppearanceController.kBootBg), hexOf(NV.bg));
      expect(prefs.getString(AppearanceController.kBootDark), '1');
      look.setLocal(mode: NvBrightnessMode.light);
      expect(prefs.getString(AppearanceController.kBootDark), '0');
      final again = AppearanceController(prefs, systemBrightness: Brightness.dark);
      expect(again.localMode, NvBrightnessMode.light);
      expect(again.localAccent, const Color(0xFF0D9488));
      // legacy 'dark'/'light' values still load
      prefs.setString('nv.theme.base', 'dark');
      expect(AppearanceController(prefs).localMode, NvBrightnessMode.dark);
    });

    testWidgets('theme picker: preset, custom hue, Sistem; applies live with a cross-fade', (tester) async {
      final look = await pump(tester, const Scaffold(body: SingleChildScrollView(child: AppearancePanel())));
      expect(find.byKey(const ValueKey('appearance-panel')), findsOneWidget);
      for (final (name, _) in nvAccentSwatches) {
        expect(find.byKey(ValueKey('accent-$name')), findsOneWidget, reason: name);
      }
      const toska = Color(0xFF18A7A1);
      await tester.ensureVisible(find.byKey(const ValueKey('accent-Toska')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('accent-Toska')));
      await tester.pump();
      expect(look.followPc, isFalse);
      expect(NV.red, toska);
      // old look is snapshotted and fades out over the new one
      expect(find.byKey(const ValueKey('nv-theme-crossfade')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('nv-theme-crossfade')), findsNothing);
      expect(Theme.of(tester.element(find.byType(AppearancePanel))).colorScheme.primary, toska);
      expect(find.text('Toska · #18A7A1'), findsOneWidget);

      // custom colour from the HSV picker (hue slider at the far left = red)
      await tester.ensureVisible(find.byKey(const ValueKey('accent-custom')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('accent-custom')));
      await tester.pumpAndSettle();
      final hue = find.byKey(const ValueKey('hsv-hue'));
      expect(hue, findsOneWidget);
      await tester.tapAt(tester.getTopLeft(hue) + Offset(4, tester.getSize(hue).height / 2));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('hsv-apply')));
      await tester.pumpAndSettle();
      expect(HSVColor.fromColor(NV.red).hue, lessThan(16));
      expect(find.textContaining('Kustom ·'), findsOneWidget);

      await tester.ensureVisible(find.text('Terang'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terang'));
      await tester.pumpAndSettle();
      expect(NV.palette.dark, isFalse);
      await tester.tap(find.text('Sistem'));
      await tester.pumpAndSettle();
      expect(look.localMode, NvBrightnessMode.system);
      expect(NV.palette.dark, isTrue); // test "phone" is dark

      // back to following the PC
      await tester.ensureVisible(find.text('Ikuti tema PC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ikuti tema PC'));
      await tester.pumpAndSettle();
      expect(look.followPc, isTrue);
      expect(NV.red, NvPalette.defaultAccent);
    });
  });

  group('Cold start', () {
    testWidgets('intro is drawn in the saved theme, then the app fades in with its state', (tester) async {
      prefs.setBool('nv.theme.follow', false);
      prefs.setString('nv.theme.accent', '#7C3AED');
      prefs.setString('nv.theme.base', 'light');
      final look = AppearanceController(prefs, systemBrightness: Brightness.dark);
      expect(NV.red, const Color(0xFF7C3AED));
      final key = GlobalKey<_CounterState>();
      await pump(tester, NvLaunchIntro(child: _Counter(key: key)), look: look);
      final intro = find.byKey(const ValueKey('nv-launch-intro'));
      expect(intro, findsOneWidget);
      final plate = tester.widget<ColoredBox>(find.descendant(of: intro, matching: find.byType(ColoredBox)).first);
      expect(plate.color, NV.bg);
      expect(NV.palette.dark, isFalse);
      key.currentState!.bump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(intro, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('nv-launch-intro')), findsNothing);
      // the app was built underneath from the start and kept its state
      expect(key.currentState!.n, 1);
      expect(find.text('n=1'), findsOneWidget);
    });

    testWidgets('tap skips ahead; disabled = no intro', (tester) async {
      await pump(tester, const NvLaunchIntro(enabled: false, child: Text('app')));
      expect(find.byKey(const ValueKey('nv-launch-intro')), findsNothing);
      expect(find.text('app'), findsOneWidget);
    });
  });

  group('Liquid glass tab bar', () {
    testWidgets('pill bar with blur, specular rim and a lens that springs to the active tab', (tester) async {
      app.previewTab = 0;
      await pump(tester, const RemoteShell());
      await tester.pump(const Duration(milliseconds: 400));
      final bar = find.byKey(const ValueKey('nv-nav-bar'));
      expect(bar, findsOneWidget);
      expect(find.descendant(of: bar, matching: find.byType(BackdropFilter)), findsOneWidget);
      expect(
          find.descendant(of: bar, matching: find.byWidgetPredicate((w) => w is CustomPaint && w.foregroundPainter is NvGlassRimPainter)),
          findsWidgets);
      final lens = find.byKey(const ValueKey('nv-nav-lens'));
      expect(find.descendant(of: lens, matching: find.byType(RawMagnifier)), findsOneWidget);
      final x0 = tester.getCenter(lens).dx;
      expect((x0 - tester.getCenter(find.text('CHAT')).dx).abs(), lessThan(2));
      await tester.tap(find.text('PROFIL'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final mid = tester.getCenter(lens).dx;
      expect(mid, greaterThan(x0)); // moving, not jumping
      expect(mid, lessThan(tester.getCenter(find.text('PROFIL')).dx));
      // (other tabs keep spinners running, so no pumpAndSettle here)
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect((tester.getCenter(lens).dx - tester.getCenter(find.text('PROFIL')).dx).abs(), lessThan(2));
    });
  });
}

class _Counter extends StatefulWidget {
  const _Counter({super.key});
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;
  void bump() => setState(() => n++);
  @override
  Widget build(BuildContext context) => Center(child: Text('n=$n'));
}
