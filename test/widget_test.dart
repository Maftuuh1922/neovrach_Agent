// Smoke tests for the Neovarch theme.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neovarch_agent/theme/app_theme.dart';
import 'package:neovarch_agent/theme/hermes_themes.dart';

void main() {
  test('Neovarch Red is the default theme: flat red base, bone type, bone paper', () {
    final t = themeByName('neovarch');
    expect(hermesThemes.first.name, 'neovarch');
    final light = buildTheme(t, Brightness.light);
    expect(light.scaffoldBackgroundColor, const Color(0xFFC8101A));
    expect(light.colorScheme.onSurface, const Color(0xFFF2EDE4));
    final paper = light.extension<HermesColors>()!.paper!;
    expect(paper.scaffoldBackgroundColor, const Color(0xFFF2EDE4));
    expect(paper.colorScheme.onSurface, const Color(0xFF140607));
    expect(paper.colorScheme.primary, const Color(0xFFC8101A));
    final dark = buildTheme(t, Brightness.dark);
    expect(dark.scaffoldBackgroundColor, const Color(0xFF0A0A0A));
    expect(dark.extension<HermesColors>()!.paper, isNull);
  });
}
