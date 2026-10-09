import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neovarch_agent/remote/github_public.dart';
import 'package:neovarch_agent/remote/social_models.dart';
import 'package:neovarch_agent/remote/ui/profile_header_slot.dart';
import 'package:neovarch_agent/remote/ui/remote_social_screen.dart';
import 'package:neovarch_agent/theme/neovarch_mobile_theme.dart';

void main() {
  group('pinned repos parser', () {
    test('parses the real profile page fixture (Maftuuh1922)', () {
      final html = File('test/fixtures/github_profile_maftuuh1922.html').readAsStringSync();
      final pins = parsePinnedReposHtml(html);
      expect(pins.length, 6);
      expect(pins.map((p) => p.name).toList(), ['aplikasi_berita', 'Academic-Reference-Reader', 'Pagarnet', 'wastra', 'Nalar.Ai', 'omarchy-boxtop']);
      final first = pins.first;
      expect(first.owner, 'Maftuuh1922');
      expect(first.url, 'https://github.com/Maftuuh1922/aplikasi_berita');
      expect(first.language, 'Dart');
      expect(first.languageColor, '#00B4AB');
      expect(first.languageArgb, 0xFF00B4AB);
      expect(first.stars, 2);
      expect(first.description, '');
      expect(pins[2].description, startsWith('Anti-Judol Extension: Blokir Iklan & Konten'));
      expect(pins[5].language, 'QML');
    });

    test('stars, forks with k suffix, entities and owner span', () {
      const html = '''
<ol class="js-pinned-items-reorder-list">
<li class="mb-3 pinned-item-list-item js-pinned-item-list-item">
  <a href="/octo/hello-world" class="Link"><span class="owner text-normal">octo</span>/<span class="repo">hello-world</span></a>
  <p class="pinned-item-desc color-fg-muted">  My &quot;first&quot; repo
  &amp; more </p>
  <span class="repo-language-color" style="background-color: #3178c6"></span>
  <span itemprop="programmingLanguage">TypeScript</span>
  <a href="/octo/hello-world/stargazers" class="pinned-item-meta"><svg aria-label="stars"><path/></svg> 1.2k </a>
  <a href="/octo/hello-world/forks" class="pinned-item-meta"><svg aria-label="forks"><path/></svg> 1,034 </a>
</li>
</ol>''';
      final p = parsePinnedReposHtml(html).single;
      expect(p.name, 'hello-world');
      expect(p.owner, 'octo');
      expect(p.description, 'My "first" repo & more');
      expect(p.stars, 1200);
      expect(p.forks, 1034);
      expect(p.language, 'TypeScript');
    });

    test('no pins -> empty; fallback picks top-starred non-forks', () {
      expect(parsePinnedReposHtml('<html><body>nothing</body></html>'), isEmpty);
      final repos = [
        {'name': 'a', 'fork': false, 'stargazers_count': 1, 'forks_count': 0, 'html_url': 'https://github.com/u/a', 'owner': {'login': 'u'}},
        {'name': 'b', 'fork': true, 'stargazers_count': 99, 'html_url': 'https://github.com/u/b'},
        {'name': 'c', 'fork': false, 'stargazers_count': 7, 'forks_count': 2, 'language': 'Go', 'html_url': 'https://github.com/u/c', 'owner': {'login': 'u'}},
      ];
      final f = pinnedFromRepos(repos);
      expect(f.map((r) => r.name).toList(), ['c', 'a']);
      expect(f.first.forks, 2);
      expect(f.first.language, 'Go');
    });
  });

  group('model JSON', () {
    test('PinnedRepo roundtrip and SocialProfile.pinned from cache / PC payload', () {
      const r = PinnedRepo(name: 'x', owner: 'o', description: 'd', language: 'Dart', languageColor: '#00B4AB', stars: 3, forks: 1, url: 'https://github.com/o/x');
      expect(PinnedRepo.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>), r);
      final p = SocialProfile.fromJson({
        'login': 'o',
        'pinned': [r.toJson()],
      });
      expect(p.pinned.single, r);
      // GraphQL-shaped item from the PC
      final g = PinnedRepo.fromJson({
        'nameWithOwner': 'o/y',
        'description': null,
        'url': 'https://github.com/o/y',
        'stargazerCount': 5,
        'forkCount': 2,
        'primaryLanguage': {'name': 'Rust', 'color': '#dea584'},
      });
      expect(g.name, 'y');
      expect(g.owner, 'o');
      expect(g.language, 'Rust');
      expect(g.stars, 5);
      expect(g.forks, 2);
      expect(SocialProfile.fromJson({'login': 'o'}).pinned, isEmpty);
    });
  });

  group('heatmap accent levels', () {
    tearDown(() => NV.palette = NvPalette.red);
    for (final (name, accent, b) in [
      ('red dark', const Color(0xFFEE1C1C), Brightness.dark),
      ('orange dark', const Color(0xFFFF8A00), Brightness.dark),
      ('blue light', const Color(0xFF2F6BFF), Brightness.light),
    ]) {
      test('levels follow the accent ($name)', () {
        final pal = NvPalette.from(accent, b);
        NV.palette = pal;
        final c = [for (var l = 0; l <= 4; l++) contributionColor(l)];
        expect(c[4], pal.accent);
        expect(c.toSet().length, 5);
        // monotonic approach to the accent
        double dist(Color x) => (x.r - pal.accent.r).abs() + (x.g - pal.accent.g).abs() + (x.b - pal.accent.b).abs();
        for (var l = 1; l <= 4; l++) {
          expect(dist(c[l]), lessThan(dist(c[l - 1])));
        }
        expect(SocialHeatmapView.levelColor(2), c[2]);
        expect(contributionColor(9), c[4]);
        // never GitHub green
        expect(c[4], isNot(const Color(0xFF39D353)));
      });
    }
  });

  testWidgets('PinnedReposCard renders and opens the repo', (tester) async {
    final opened = <String>[];
    const repos = [
      PinnedRepo(name: 'aplikasi_berita', owner: 'Maftuuh1922', language: 'Dart', languageColor: '#00B4AB', stars: 2, url: 'https://github.com/Maftuuh1922/aplikasi_berita'),
      PinnedRepo(name: 'Pagarnet', owner: 'Maftuuh1922', description: 'Anti-Judol Extension', language: 'HTML', stars: 1, forks: 3, url: 'https://github.com/Maftuuh1922/Pagarnet'),
    ];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PinnedReposCard(repos: repos, onOpen: opened.add)))));
    expect(find.text('REPO DISEMATKAN'), findsOneWidget);
    expect(find.text('aplikasi_berita'), findsOneWidget);
    expect(find.text('Anti-Judol Extension'), findsOneWidget);
    expect(find.text('Dart'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pinned-Pagarnet')));
    expect(opened, ['https://github.com/Maftuuh1922/Pagarnet']);
  });
}
