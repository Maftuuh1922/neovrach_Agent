// Hermes Desktop theme presets, ported from
// apps/shared/src/theme-presets.ts (THEME_PRESET_PALETTES) and
// apps/desktop/src/themes/presets.ts (labels, typography).
//
// Every preset carries the same Tailwind-style slots Desktop uses; dark-only
// skins (Midnight, Ember, Mono, Cyberpunk, Slate) have no light palette.
// "Neovarch Red" (first) is the app's own brand theme and the default;
// Desktop's blue Nous presets are not shipped (Neovarch's accent is red).
// "Kantor Hermes" is the extra teal look of the original virtual office.
import 'package:flutter/material.dart';

class HermesPalette {
  final Color background, foreground, card, muted, mutedForeground, popover;
  final Color primary, primaryForeground, secondary, accent, border, input;
  final Color ring, midground, destructive, sidebarBackground, sidebarBorder;
  final Color userBubble, userBubbleBorder;
  const HermesPalette({
    required this.background,
    required this.foreground,
    required this.card,
    required this.muted,
    required this.mutedForeground,
    required this.popover,
    required this.primary,
    required this.primaryForeground,
    required this.secondary,
    required this.accent,
    required this.border,
    required this.input,
    required this.ring,
    required this.midground,
    required this.destructive,
    required this.sidebarBackground,
    required this.sidebarBorder,
    required this.userBubble,
    required this.userBubbleBorder,
  });
}

enum FontPreset { inter, system, courierPrime, plexMono, barlow }

class HermesTheme {
  final String name;
  final String label;
  final String description;
  final HermesPalette light;
  final HermesPalette? dark; // null => light palette reused / dark-only flag below
  final bool darkOnly;
  final String monoFont; // google font family (or a bundled one, see app_theme)
  final FontPreset sans;
  /// Bundled condensed display face for titles/headlines (null = body face).
  final String? displayFont;
  /// Base corner radius; the site-style theme is almost square.
  final double corner;
  /// Hermes Agent site look: grain overlay, halftone accents, mono labels.
  final bool brand;
  /// Light "paper" palette for cards / sheets / dialogs on a coloured base
  /// (null = surfaces use this theme's own palette).
  final HermesPalette? paper;
  const HermesTheme({
    required this.name,
    required this.label,
    required this.description,
    required this.light,
    this.dark,
    this.darkOnly = false,
    this.monoFont = 'JetBrains Mono',
    this.sans = FontPreset.inter,
    this.displayFont,
    this.corner = 8,
    this.brand = false,
    this.paper,
  });

  HermesPalette palette(Brightness b) {
    if (darkOnly) return light;
    if (b == Brightness.dark) return dark ?? light;
    return light;
  }
}

Color _c(String hex) {
  final h = hex.replaceAll('#', '');
  return Color(int.parse(h.length == 6 ? 'FF$h' : h, radix: 16));
}

HermesPalette _p(Map<String, String> m) => HermesPalette(
      background: _c(m['background']!),
      foreground: _c(m['foreground']!),
      card: _c(m['card']!),
      muted: _c(m['muted']!),
      mutedForeground: _c(m['mutedForeground']!),
      popover: _c(m['popover']!),
      primary: _c(m['primary']!),
      primaryForeground: _c(m['primaryForeground']!),
      secondary: _c(m['secondary']!),
      accent: _c(m['accent']!),
      border: _c(m['border']!),
      input: _c(m['input']!),
      ring: _c(m['ring']!),
      midground: _c(m['midground'] ?? m['ring']!),
      destructive: _c(m['destructive']!),
      sidebarBackground: _c(m['sidebarBackground'] ?? m['card']!),
      sidebarBorder: _c(m['sidebarBorder'] ?? m['border']!),
      userBubble: _c(m['userBubble'] ?? m['secondary']!),
      userBubbleBorder: _c(m['userBubbleBorder'] ?? m['border']!),
    );

/// Bone paper with near-black ink and red accents (Neovarch surfaces).
final neovarchPaper = _p({
  'background': '#F2EDE4', 'foreground': '#140607', 'card': '#F2EDE4', 'muted': '#E7E0D4',
  'mutedForeground': '#5E4B47', 'popover': '#F2EDE4', 'primary': '#C8101A', 'primaryForeground': '#F2EDE4',
  'secondary': '#F1D2CD', 'accent': '#EADFD3', 'border': '#40140607', 'input': '#F2EDE4', 'ring': '#C8101A',
  'midground': '#C8101A', 'destructive': '#C8101A', 'sidebarBackground': '#F2EDE4', 'sidebarBorder': '#33140607',
  'userBubble': '#EADFD3', 'userBubbleBorder': '#40140607',
});

final hermesThemes = <HermesTheme>[
  // Default — Neovarch identity, flat print (Hermes-site style): solid red
  // #C8101A base with bone-white type and 1px bone frame lines; cards,
  // sheets and dialogs are solid bone "paper" (see [neovarchPaper]) with
  // near-black text and red accents. No gradients, glows or scrims.
  // Dark mode = near-black variant with crimson accents.
  HermesTheme(
    name: 'neovarch',
    label: 'Neovarch Red',
    description: 'Merah datar, kertas tulang, garis tipis',
    monoFont: 'IBM Plex Mono',
    sans: FontPreset.barlow,
    displayFont: 'BigShoulders',
    corner: 2,
    brand: true,
    paper: neovarchPaper,
    light: _p({
      'background': '#C8101A', 'foreground': '#F2EDE4', 'card': '#C8101A', 'muted': '#B30E17',
      'mutedForeground': '#F0CFC9', 'popover': '#C8101A', 'primary': '#F2EDE4', 'primaryForeground': '#C8101A',
      'secondary': '#9E0C14', 'accent': '#B30E17', 'border': '#B3F2EDE4', 'input': '#C8101A', 'ring': '#F2EDE4',
      'midground': '#F2EDE4', 'destructive': '#140607', 'sidebarBackground': '#C8101A', 'sidebarBorder': '#99F2EDE4',
      'userBubble': '#A80D15', 'userBubbleBorder': '#B3F2EDE4',
    }),
    dark: _p({
      'background': '#0A0A0A', 'foreground': '#F2EDE4', 'card': '#141414', 'muted': '#1A1A1A',
      'mutedForeground': '#A39A8E', 'popover': '#161616', 'primary': '#E0262F', 'primaryForeground': '#F2EDE4',
      'secondary': '#3A1214', 'accent': '#241011', 'border': '#4DF2EDE4', 'input': '#0A0A0A', 'ring': '#F2555C',
      'midground': '#F2555C', 'destructive': '#FF8A5C', 'sidebarBackground': '#0F0F0F', 'sidebarBorder': '#40F2EDE4',
      'userBubble': '#2A0D0F', 'userBubbleBorder': '#80E0262F',
    }),
  ),
  HermesTheme(
    name: 'github',
    label: 'GitHub',
    description: 'Netral ala GitHub, aksen hijau',
    light: _p({
      'background': '#ffffff', 'foreground': '#1f2328', 'card': '#f6f8fa', 'muted': '#f6f6f6',
      'mutedForeground': '#656d76', 'popover': '#ffffff', 'primary': '#196d31', 'primaryForeground': '#ffffff',
      'secondary': '#dfebe2', 'accent': '#e3ede6', 'border': '#d0d7de', 'input': '#ffffff', 'ring': '#196d31',
      'destructive': '#cf222e', 'sidebarBackground': '#f6f8fa', 'userBubble': '#dbe7e2', 'userBubbleBorder': '#d0d7de',
    }),
    dark: _p({
      'background': '#0d1117', 'foreground': '#e6edf3', 'card': '#010409', 'muted': '#1a1e24',
      'mutedForeground': '#7d8590', 'popover': '#161b22', 'primary': '#4f9e5e', 'primaryForeground': '#ffffff',
      'secondary': '#1f382b', 'accent': '#192a24', 'border': '#30363d', 'input': '#0d1117', 'ring': '#4f9e5e',
      'destructive': '#f85149', 'sidebarBackground': '#010409', 'userBubble': '#0f2018', 'userBubbleBorder': '#30363d',
    }),
  ),
  HermesTheme(
    name: 'classic',
    label: 'Classic',
    description: 'Emas di atas biru tua, tampilan asli CLI',
    light: _p({
      'background': '#F5F5F5', 'foreground': '#2B2109', 'card': '#EDEBE6', 'muted': '#ECE8DE',
      'mutedForeground': '#6E5A2A', 'popover': '#FFFFFF', 'primary': '#B07E03', 'primaryForeground': '#FFFFFF',
      'secondary': '#F1E6C8', 'accent': '#EFE3C2', 'border': '#D9CBA3', 'input': '#FFFFFF', 'ring': '#D89B04',
      'destructive': '#C62828', 'sidebarBackground': '#EFEDE8', 'userBubble': '#F3E7C6', 'userBubbleBorder': '#D9CBA3',
    }),
    dark: _p({
      'background': '#1a1a2e', 'foreground': '#FFF8DC', 'card': '#151526', 'muted': '#24243c',
      'mutedForeground': '#B8A676', 'popover': '#202036', 'primary': '#FFBF00', 'primaryForeground': '#1a1a2e',
      'secondary': '#33304a', 'accent': '#2a2840', 'border': '#3d3a55', 'input': '#151526', 'ring': '#FFBF00',
      'midground': '#CD7F32', 'destructive': '#ef5350', 'sidebarBackground': '#141424', 'userBubble': '#2c2a42',
      'userBubbleBorder': '#4a4565',
    }),
  ),
  HermesTheme(
    name: 'catppuccin',
    label: 'Catppuccin',
    description: 'Latte / Mocha, aksen mauve',
    light: _p({
      'background': '#eff1f5', 'foreground': '#4c4f69', 'card': '#e6e9ef', 'muted': '#e8ebef',
      'mutedForeground': '#6c6f85', 'popover': '#e6e9ef', 'primary': '#6d2ebf', 'primaryForeground': '#ffffff',
      'secondary': '#ddd6ed', 'accent': '#dfdaef', 'border': '#acb0be', 'input': '#ccd0da', 'ring': '#6d2ebf',
      'destructive': '#d20f39', 'sidebarBackground': '#e6e9ef', 'userBubble': '#d7d3e9', 'userBubbleBorder': '#acb0be',
    }),
    dark: _p({
      'background': '#1e1e2e', 'foreground': '#cdd6f4', 'card': '#181825', 'muted': '#29293a',
      'mutedForeground': '#a6adc8', 'popover': '#181825', 'primary': '#cba6f7', 'primaryForeground': '#1e1e2e',
      'secondary': '#4e4466', 'accent': '#3d3652', 'border': '#585b70', 'input': '#313244', 'ring': '#cba6f7',
      'destructive': '#f38ba8', 'sidebarBackground': '#181825', 'userBubble': '#38324b', 'userBubbleBorder': '#585b70',
    }),
  ),
  HermesTheme(
    name: 'everforest',
    label: 'Everforest',
    description: 'Hijau hutan yang lembut',
    light: _p({
      'background': '#fdf6e3', 'foreground': '#5c6a72', 'card': '#f8f0dc', 'muted': '#f7f0de',
      'mutedForeground': '#939f91', 'popover': '#fdf6e3', 'primary': '#586b35', 'primaryForeground': '#ffffff',
      'secondary': '#e6e3cb', 'accent': '#e9e5ce', 'border': '#e6dfc8', 'input': '#fdf6e3', 'ring': '#586b35',
      'destructive': '#f1706f', 'sidebarBackground': '#f8f0dc', 'userBubble': '#e9e5ce', 'userBubbleBorder': '#e0dac2',
    }),
    dark: _p({
      'background': '#2d353b', 'foreground': '#d3c6aa', 'card': '#293136', 'muted': '#373e42',
      'mutedForeground': '#859289', 'popover': '#2d353b', 'primary': '#a7c080', 'primaryForeground': '#2d353b',
      'secondary': '#4f5c4e', 'accent': '#434e47', 'border': '#3d474d', 'input': '#2d353b', 'ring': '#a7c080',
      'destructive': '#da6362', 'sidebarBackground': '#293136', 'userBubble': '#434e47', 'userBubbleBorder': '#3d474d',
    }),
  ),
  HermesTheme(
    name: 'solarized',
    label: 'Solarized',
    description: 'Palet klasik Ethan Schoonover',
    light: _p({
      'background': '#fdf6e3', 'foreground': '#1f1f1f', 'card': '#eee8d5', 'muted': '#f4eddb',
      'mutedForeground': '#7f8c8a', 'popover': '#eee8d5', 'primary': '#675e34', 'primaryForeground': '#ffffff',
      'secondary': '#e8e1cb', 'accent': '#ebe4ce', 'border': '#ddd6c1', 'input': '#ddd6c1', 'ring': '#675e34',
      'destructive': '#e25563', 'sidebarBackground': '#eee8d5', 'userBubble': '#e4dcc4', 'userBubbleBorder': '#ddd6c1',
    }),
    dark: _p({
      'background': '#002b36', 'foreground': '#93a1a1', 'card': '#00232c', 'muted': '#08313c',
      'mutedForeground': '#657b83', 'popover': '#001f26', 'primary': '#6ea1c4', 'primaryForeground': '#002b36',
      'secondary': '#1f4c5e', 'accent': '#144050', 'border': '#234751', 'input': '#073642', 'ring': '#6ea1c4',
      'destructive': '#e35957', 'sidebarBackground': '#001f26', 'userBubble': '#144050', 'userBubbleBorder': '#234751',
    }),
  ),
  HermesTheme(
    name: 'midnight',
    label: 'Midnight',
    description: 'Biru-ungu pekat, khusus gelap',
    darkOnly: true,
    light: _p({
      'background': '#08081c', 'foreground': '#ddd6ff', 'card': '#0d0d28', 'muted': '#13133a',
      'mutedForeground': '#7c7ab0', 'popover': '#0f0f2e', 'primary': '#ddd6ff', 'primaryForeground': '#08081c',
      'secondary': '#1a1a4a', 'accent': '#1a1a44', 'border': '#1e1e52', 'input': '#1e1e52', 'ring': '#8b80e8',
      'destructive': '#b03060', 'sidebarBackground': '#06061a', 'sidebarBorder': '#12123a', 'userBubble': '#14143a',
      'userBubbleBorder': '#242466',
    }),
  ),
  HermesTheme(
    name: 'ember',
    label: 'Ember',
    description: 'Bara oranye hangat, khusus gelap',
    darkOnly: true,
    monoFont: 'IBM Plex Mono',
    light: _p({
      'background': '#160800', 'foreground': '#ffd8b0', 'card': '#1e0e04', 'muted': '#2a1408',
      'mutedForeground': '#aa7a56', 'popover': '#221008', 'primary': '#ffd8b0', 'primaryForeground': '#160800',
      'secondary': '#341800', 'accent': '#301600', 'border': '#3a1c08', 'input': '#3a1c08', 'ring': '#d97316',
      'destructive': '#c43010', 'sidebarBackground': '#100600', 'sidebarBorder': '#2a1004', 'userBubble': '#2a1000',
      'userBubbleBorder': '#4a2010',
    }),
  ),
  HermesTheme(
    name: 'mono',
    label: 'Mono',
    description: 'Hitam-putih tanpa warna',
    darkOnly: true,
    light: _p({
      'background': '#0e0e0e', 'foreground': '#eaeaea', 'card': '#141414', 'muted': '#1e1e1e',
      'mutedForeground': '#808080', 'popover': '#181818', 'primary': '#eaeaea', 'primaryForeground': '#0e0e0e',
      'secondary': '#262626', 'accent': '#222222', 'border': '#2a2a2a', 'input': '#2a2a2a', 'ring': '#9a9a9a',
      'destructive': '#a84040', 'sidebarBackground': '#0a0a0a', 'sidebarBorder': '#202020', 'userBubble': '#1a1a1a',
      'userBubbleBorder': '#363636',
    }),
  ),
  HermesTheme(
    name: 'cyberpunk',
    label: 'Cyberpunk',
    description: 'Hijau terminal di atas hitam',
    darkOnly: true,
    monoFont: 'Courier Prime',
    sans: FontPreset.courierPrime,
    light: _p({
      'background': '#000a00', 'foreground': '#00ff41', 'card': '#001200', 'muted': '#001a00',
      'mutedForeground': '#1a8a30', 'popover': '#001000', 'primary': '#00ff41', 'primaryForeground': '#000a00',
      'secondary': '#002800', 'accent': '#002000', 'border': '#003000', 'input': '#003000', 'ring': '#00ff41',
      'destructive': '#ff003c', 'sidebarBackground': '#000600', 'sidebarBorder': '#001800', 'userBubble': '#001400',
      'userBubbleBorder': '#004800',
    }),
  ),
  HermesTheme(
    name: 'slate',
    label: 'Slate',
    description: 'Abu-abu batu tulis, aksen biru',
    darkOnly: true,
    light: _p({
      'background': '#0d1117', 'foreground': '#c9d1d9', 'card': '#161b22', 'muted': '#21262d',
      'mutedForeground': '#8b949e', 'popover': '#1c2128', 'primary': '#c9d1d9', 'primaryForeground': '#0d1117',
      'secondary': '#2a3038', 'accent': '#1e2530', 'border': '#30363d', 'input': '#30363d', 'ring': '#58a6ff',
      'destructive': '#cf4848', 'sidebarBackground': '#090d13', 'sidebarBorder': '#1c2228', 'userBubble': '#1e2a38',
      'userBubbleBorder': '#2e4060',
    }),
  ),
  HermesTheme(
    name: 'office',
    label: 'Kantor Teal',
    description: 'Teal dari kantor virtual awal',
    light: _p({
      'background': '#f4f8f7', 'foreground': '#14211d', 'card': '#ffffff', 'muted': '#e9f1ee',
      'mutedForeground': '#5b6f69', 'popover': '#ffffff', 'primary': '#139c72', 'primaryForeground': '#ffffff',
      'secondary': '#d6f2e7', 'accent': '#e0f5ec', 'border': '#cfdcd8', 'input': '#ffffff', 'ring': '#139c72',
      'destructive': '#c9423f', 'sidebarBackground': '#eaf2ef', 'userBubble': '#d9f1e7', 'userBubbleBorder': '#bfe3d4',
    }),
    dark: _p({
      'background': '#0f1418', 'foreground': '#dfe7ec', 'card': '#131b21', 'muted': '#18222a',
      'mutedForeground': '#8fa2ae', 'popover': '#141c22', 'primary': '#2ecc9a', 'primaryForeground': '#08130d',
      'secondary': '#1d3329', 'accent': '#172a24', 'border': '#26333d', 'input': '#0f161b', 'ring': '#2ecc9a',
      'destructive': '#e5726f', 'sidebarBackground': '#0b1015', 'userBubble': '#16302a', 'userBubbleBorder': '#2f5340',
    }),
  ),
];

HermesTheme themeByName(String name) =>
    hermesThemes.firstWhere((t) => t.name == name, orElse: () => hermesThemes.first);
