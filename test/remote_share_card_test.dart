// "Bagikan profil" share card + technology logos: path parsing for every bundled
// Simple Icons logo, linguist aliases, the card in story/square, PNG export at
// the exact pixel size, the preview sheet's share / save actions, and
// screenshots in three accents (run with --update-goldens, NV_SHOTS_DIR=…).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neovarch_agent/remote/appearance.dart';
import 'package:neovarch_agent/remote/social_models.dart';
import 'package:neovarch_agent/remote/tech_icons.g.dart';
import 'package:neovarch_agent/remote/ui/profile_share_card.dart';
import 'package:neovarch_agent/remote/ui/remote_app.dart' show neovarchMobileTheme;
import 'package:neovarch_agent/remote/ui/remote_social_screen.dart';
import 'package:neovarch_agent/remote/ui/tech_logo.dart';
import 'package:neovarch_agent/theme/neovarch_mobile_theme.dart';

final _shotsDir = Platform.environment['NV_SHOTS_DIR'] ?? 'build/screenshots/remote';

SocialProfile _profile() {
  final counts = List<int>.generate(365, (i) => (i * 7 + 3) % 11 < 4 ? 0 : (i * 13) % 9 + (i > 330 ? 2 : 0));
  return SocialProfile.fromJson({
    'login': 'aku',
    'name': 'Aku Dev',
    'bio': 'Ngoding Flutter & Python tiap hari. Lagi bangun agen AI di PC sendiri.',
    'heatmap': {'start': '2025-10-10', 'end': '2026-10-09', 'counts': counts, 'total': counts.fold<int>(0, (a, b) => a + b), 'active_days': 230, 'streak': 6},
    'stack': {
      'languages': [
        {'name': 'Python', 'share': 0.34},
        {'name': 'TypeScript', 'share': 0.22},
        {'name': 'Dart', 'share': 0.18},
        {'name': 'Kotlin', 'share': 0.1},
        {'name': 'Shell', 'share': 0.08},
        {'name': 'Brainfuck', 'share': 0.03},
      ],
      'tools': [],
    },
    'status': {'coding': true, 'last_active_at': DateTime.now().toUtc().toIso8601String(), 'project': 'neovarch'},
    'publish': {'gist_url': 'https://gist.github.com/aku/abc123'},
  });
}

void main() {
  group('tech logos', () {
    test('every bundled logo parses to a path inside the 24×24 box', () {
      expect(kTechIcons.length, greaterThanOrEqualTo(40));
      for (final icon in kTechIcons.values) {
        final b = parseSvgPath(icon.path).getBounds();
        expect(b.isEmpty, isFalse, reason: icon.slug);
        // getBounds includes curve control points, so allow a little slack
        expect(b.left, greaterThanOrEqualTo(-2), reason: icon.slug);
        expect(b.top, greaterThanOrEqualTo(-2), reason: icon.slug);
        expect(b.right, lessThanOrEqualTo(26), reason: icon.slug);
        expect(b.bottom, lessThanOrEqualTo(26), reason: icon.slug);
        expect(b.width, greaterThan(8), reason: icon.slug);
      }
    });

    test('GitHub linguist names map to logos; unknown -> fallback', () {
      expect(techIconFor('C++')!.slug, 'cplusplus');
      expect(techIconFor('Java')!.slug, 'openjdk');
      expect(techIconFor('C#')!.slug, 'dotnet');
      expect(techIconFor('Jupyter Notebook')!.slug, 'jupyter');
      expect(techIconFor('HTML')!.slug, 'html5');
      expect(techIconFor('Shell')!.slug, 'gnubash');
      expect(techIconFor('Next.js')!.slug, 'nextdotjs');
      expect(techIconFor('Tailwind CSS')!.slug, 'tailwindcss');
      expect(techIconFor('Brainfuck'), isNull);
      for (final s in ['python', 'typescript', 'javascript', 'dart', 'flutter', 'kotlin', 'go', 'rust', 'c', 'php', 'ruby', 'swift', 'css', 'react',
        'nodedotjs', 'vuedotjs', 'svelte', 'docker', 'electron', 'vite']) {
        expect(kTechIcons.containsKey(s), isTrue, reason: s);
      }
    });

    test('svg arc flags glued to numbers are split', () {
      final p = parseSvgPath('M2 12a10 10 0 0120 0z');
      final b = p.getBounds();
      expect(b.width, closeTo(20, 0.5));
      expect(b.top, closeTo(2, 0.5));
    });
  });

  group('share card', () {
    late SharedPreferences prefs;

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
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      socialAvatarProvider = (url) => null;
    });

    tearDown(() => NV.palette = NvPalette.red);

    Widget backdrop() => Stack(fit: StackFit.expand, children: [
          Image.asset('assets/art/feat-remote.webp', fit: BoxFit.cover),
          ColoredBox(color: NV.red.withValues(alpha: 0.18)),
          ColoredBox(color: NV.bg.withValues(alpha: 0.35)),
        ]);

    Widget host(Widget child) => ProviderScope(
          overrides: [appearanceProvider.overrideWith((ref) => AppearanceController(prefs))],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: neovarchMobileTheme,
            darkTheme: neovarchMobileTheme,
            themeMode: NV.palette.dark ? ThemeMode.dark : ThemeMode.light,
            home: Scaffold(body: Center(child: child)),
          ),
        );

    Future<void> precache(WidgetTester tester) async {
      final ctx = tester.element(find.byType(MaterialApp));
      await tester.runAsync(() async {
        await precacheImage(const AssetImage('assets/art/feat-remote.webp'), ctx);
        await precacheImage(const AssetImage('assets/brand/monogram.png'), ctx);
      });
    }

    for (final format in ShareCardFormat.values) {
      testWidgets('exports a ${format.pixelSize.width.toInt()}×${format.pixelSize.height.toInt()} PNG (${format.name})', (tester) async {
        tester.view.physicalSize = const Size(1200, 2100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        await tester.pumpWidget(host(RepaintBoundary(key: key, child: ProfileShareCard(profile: _profile(), format: format, background: backdrop()))));
        await precache(tester);
        await tester.pump();
        expect(find.text('Aku Dev'), findsOneWidget);
        expect(find.text('Lagi ngoding · neovarch'), findsOneWidget);
        expect(find.byKey(const ValueKey('tech-python')), findsOneWidget);
        expect(find.byKey(const ValueKey('share-glass')), findsOneWidget);
        final png = (await tester.runAsync(() => renderShareCardPng(key)))!;
        expect(png.sublist(1, 4), utf8.encode('PNG'));
        final (w, h) = pngSize(png);
        expect(w, 1080);
        expect(h, format == ShareCardFormat.story ? 1920 : 1080);
      });
    }

    testWidgets('preview sheet: share sends the PNG to the share sheet, save goes to the gallery, link copies the gist', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final calls = <(String, Map<String, dynamic>)>[];
      final written = <int>[];
      writeShareFile = (png, name) async {
        written.add(png.length);
        return '/cache/share/$name';
      };
      shareChannel = (m, a) async {
        calls.add((m, a));
        return true;
      };
      await tester.pumpWidget(host(MediaQuery(
        data: const MediaQueryData(size: Size(390, 844), disableAnimations: true),
        child: ProfileSharePreview(profile: _profile(), gistUrl: 'https://gist.github.com/aku/abc123', debugBackground: backdrop(), animate: false),
      )));
      await precache(tester);
      await tester.pump();
      expect(find.byKey(const ValueKey('share-card-preview')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('share-send')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      expect(calls.single.$1, 'shareImage');
      expect(calls.single.$2['mime'], 'image/png');
      expect(calls.single.$2['text'], 'https://gist.github.com/aku/abc123');
      await tester.tap(find.byKey(const ValueKey('share-save')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      expect(calls.last.$1, 'saveImageToGallery');
      expect(written.length, 2);
      expect(written.first, greaterThan(10000));
      // square format
      await tester.tap(find.text('Kotak 1:1'));
      await tester.pump();
      expect(find.byKey(const ValueKey('share-card-preview')), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('profile section has a "Bagikan profil" button', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(SingleChildScrollView(child: SocialProfileCard(profile: _profile()))));
      await tester.pump();
      expect(find.byKey(const ValueKey('chip-Python')), findsOneWidget);
      expect(find.byKey(const ValueKey('tech-typescript')), findsOneWidget);
    });

    // Screenshots: the exported card in three accents (story + one square).
    for (final (name, hex, bright, format) in const [
      ('share_card_merah_story', 0xFFEE1C1C, Brightness.dark, ShareCardFormat.story),
      ('share_card_ungu_story', 0xFF7C3AED, Brightness.dark, ShareCardFormat.story),
      ('share_card_toska_terang_story', 0xFF0D9488, Brightness.light, ShareCardFormat.story),
      ('share_card_ungu_square', 0xFF7C3AED, Brightness.dark, ShareCardFormat.square),
    ]) {
      testWidgets('shot $name', (tester) async {
        NV.palette = NvPalette.from(Color(hex), bright);
        final size = format.logicalSize;
        tester.view.physicalSize = format.pixelSize;
        tester.view.devicePixelRatio = kShareCardPixelRatio;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ProviderScope(
          overrides: [appearanceProvider.overrideWith((ref) => AppearanceController(prefs))],
          child: RepaintBoundary(
            key: const ValueKey('shot'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: neovarchMobileTheme,
              home: SizedBox.fromSize(size: size, child: ProfileShareCard(profile: _profile(), format: format, background: backdrop())),
            ),
          ),
        ));
        await precache(tester);
        await tester.pump();
        if (autoUpdateGoldenFiles) {
          final dir = Directory(_shotsDir).absolute.path;
          Directory(dir).createSync(recursive: true);
          await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('$dir/$name.png'));
        }
      });
    }
  });
}
