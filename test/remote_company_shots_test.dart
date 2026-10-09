// Screenshots of Kantor → Perusahaan on a phone (Organisasi, Tiket, Setujui,
// Biaya, Rencana, Rekrut). Run with --update-goldens and NV_SHOTS_DIR=… to
// write PNGs; a plain run only checks each view renders without errors.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neovarch_agent/remote/appearance.dart';
import 'package:neovarch_agent/remote/remote_controller.dart';
import 'package:neovarch_agent/remote/remote_gateway.dart' show RemoteStatus;
import 'package:neovarch_agent/remote/saved_desktops.dart';
import 'package:neovarch_agent/remote/ui/remote_app.dart' show PaletteScope, themeFor;
import 'package:neovarch_agent/remote/ui/remote_company_screen.dart';
import 'package:neovarch_agent/state/app_controller.dart' show settingsProvider;
import 'package:neovarch_agent/state/settings_controller.dart';
import 'package:neovarch_agent/theme/neovarch_mobile_theme.dart';

import 'remote_company_test.dart' show FakeCompany;

final _shotsDir = Platform.environment['NV_SHOTS_DIR'] ?? 'build/screenshots/company';

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
        {'id': 'pc1', 'name': 'PC Kantor', 'url': 'http://192.168.1.20:9319', 'addedAt': DateTime.now().toIso8601String()},
      ]),
      'remote.active': 'pc1',
    });
    prefs = await SharedPreferences.getInstance();
    settings = SettingsController(prefs);
    await settings.load();
    NV.palette = NvPalette.red;
  });

  Future<void> shot(WidgetTester tester, String name, int segment, {Future<void> Function()? act}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final desktops = SavedDesktops(prefs)..load();
    final r = RemoteController(desktops)
      ..desktop = desktops.items.first
      ..status = RemoteStatus.connected
      ..debugApprovals = []
      ..debugCompanyApi = FakeCompany();
    final look = AppearanceController(prefs);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => settings),
        remoteProvider.overrideWith((ref) => r),
        appearanceProvider.overrideWith((ref) => look),
      ],
      child: RepaintBoundary(
        key: const ValueKey('shot'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: themeFor(look),
          builder: (context, child) => PaletteScope(revision: look.revision, child: child!),
          home: ColoredBox(
            color: NV.bg,
            child: MediaQuery(
              data: const MediaQueryData(size: Size(390, 844), padding: EdgeInsets.only(top: 47, bottom: 34)),
              child: RemoteCompanyScreen(initialSegment: segment),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    if (act != null) {
      await act();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    if (autoUpdateGoldenFiles) {
      final dir = Directory(_shotsDir).absolute.path;
      Directory(dir).createSync(recursive: true);
      await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('$dir/$name.png'));
    }
  }

  testWidgets('organisasi', (tester) => shot(tester, '01_organisasi', companySegOrg));
  testWidgets('tiket', (tester) => shot(tester, '02_tiket', companySegTickets));
  testWidgets('setujui', (tester) => shot(tester, '03_setujui', companySegApprovals));
  testWidgets('biaya', (tester) => shot(tester, '04_biaya', companySegCosts));
  testWidgets('rencana', (tester) => shot(tester, '05_rencana', companySegPlan));
  testWidgets('rekrut', (tester) => shot(tester, '06_rekrut', companySegOrg, act: () => tester.tap(find.byKey(const ValueKey('company-hire')))));
}
