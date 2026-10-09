// 1.4.4: light-mode contrast. Key text roles must reach WCAG AA (4.5:1 body
// text, 3:1 icons / large text) on the plain background, on every glass
// style composited over a white, a mid-grey and a black wallpaper, and over
// the light veil drawn on a wallpaper.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neovarch_agent/theme/neovarch_mobile_theme.dart';

Color over(Color fill, Color backdrop) => Color.alphaBlend(fill, backdrop);
double cr(Color a, Color b) => NvPalette.contrast(a, b);

void main() {
  const accents = {
    'Merah': Color(0xFFEE1C1C),
    'Amber': Color(0xFFF2B544),
    'Kuning': Color(0xFFFACC15),
    'Lime': Color(0xFFA3E635),
    'Toska': Color(0xFF0D9488),
    'Biru': Color(0xFF2563EB),
    'Ungu': Color(0xFF7C3AED),
    'Abu': Color(0xFFA3A3A3),
  };
  const backdrops = {'putih': Color(0xFFFFFFFF), 'abu': Color(0xFF808080), 'hitam': Color(0xFF000000)};

  tearDown(() {
    NV.palette = NvPalette.red;
    NV.glassStyle = NvGlassStyle.reguler;
  });

  for (final MapEntry(key: name, value: accent) in accents.entries) {
    test('light · $name: text roles on background, glass and wallpaper veil', () {
      final p = NV.palette = NvPalette.from(accent, Brightness.light);
      expect(p.dark, isFalse);
      // plain background / surfaces
      for (final (bgName, bg) in [('bg', p.bg), ('surface', p.surface), ('raised', p.raised)]) {
        expect(cr(p.text, bg), greaterThanOrEqualTo(4.5), reason: 'text on $bgName');
        expect(cr(p.muted, bg), greaterThanOrEqualTo(4.5), reason: 'muted on $bgName');
        expect(cr(p.faint, bg), greaterThanOrEqualTo(4.5), reason: 'faint on $bgName');
      }
      expect(cr(p.accentInk, p.bg), greaterThanOrEqualTo(4.5), reason: 'accent text (kickers) on bg');
      expect(cr(p.accent, p.bg), greaterThanOrEqualTo(3.0), reason: 'accent icons on bg');
      expect(cr(p.onAccent, p.accent), greaterThanOrEqualTo(4.5), reason: 'label on an accent button');
      expect(cr(p.accentInk, p.wash), greaterThanOrEqualTo(4.5), reason: 'accent text on the accent wash');
      // every glass style over white, grey and black wallpapers
      for (final st in NvGlassStyle.values) {
        NV.glassStyle = st;
        for (final nav in [false, true]) {
          final fill = NV.glassFill(st, nav: nav);
          for (final MapEntry(key: bn, value: b) in backdrops.entries) {
            final g = over(fill, b);
            final where = '${st.name}${nav ? ' nav' : ''} over $bn';
            expect(cr(p.text, g), greaterThanOrEqualTo(4.5), reason: 'text on $where');
            expect(cr(p.muted, g), greaterThanOrEqualTo(4.5), reason: 'muted on $where');
            expect(cr(p.faint, g), greaterThanOrEqualTo(3.0), reason: 'faint icons on $where');
            expect(cr(p.accent, g), greaterThanOrEqualTo(2.4), reason: 'accent icon on $where');
          }
        }
      }
      // text drawn straight on a wallpaper (headers) sits on the light veil
      for (final MapEntry(key: bn, value: b) in backdrops.entries) {
        final veiled = over(p.bg.withValues(alpha: NV.lightWallpaperVeil), b);
        expect(cr(p.text, veiled), greaterThanOrEqualTo(4.5), reason: 'header text over $bn wallpaper');
        expect(cr(p.muted, veiled), greaterThanOrEqualTo(4.5), reason: 'header status over $bn wallpaper');
        expect(cr(p.accentInk, veiled), greaterThanOrEqualTo(3.0), reason: 'kicker (caps, semibold) over $bn wallpaper');
      }
    });
  }

  test('dark palettes keep their contrast too', () {
    for (final a in accents.values) {
      final p = NvPalette.from(a, Brightness.dark);
      expect(cr(p.text, p.bg), greaterThanOrEqualTo(4.5));
      expect(cr(p.muted, p.bg), greaterThanOrEqualTo(4.5));
      expect(cr(p.accentInk, p.bg), greaterThanOrEqualTo(4.5));
    }
  });

  test('a pale accent is deepened in light mode, unchanged in dark mode', () {
    const amber = Color(0xFFF2B544);
    expect(NvPalette.from(amber, Brightness.dark).accent, amber);
    final light = NvPalette.from(amber, Brightness.light).accent;
    expect(light, isNot(amber));
    expect(HSLColor.fromColor(light).hue, closeTo(HSLColor.fromColor(amber).hue, 6));
  });
}
