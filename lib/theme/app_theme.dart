// Material 3 ThemeData built from a Hermes Desktop palette.
//
// Desktop's contract, translated: flat not boxed (no elevation, hairline
// borders from the token), one primitive per concern (buttons share one
// shape), small radii, JetBrains Mono for code/terminal.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../ui/widgets/motion.dart';
import 'hermes_themes.dart';

@immutable
class HermesColors extends ThemeExtension<HermesColors> {
  final Color card, muted, mutedForeground, popover, border, strokeSoft;
  final Color midground, destructive, success, warning, info;
  final Color sidebar, sidebarBorder, userBubble, userBubbleBorder, codeBg;
  final String monoFamily;
  /// Condensed display family for big headings (null = body face).
  final String? displayFamily;
  /// Neovarch site look: grain, halftone accents, square corners.
  final bool brand;
  final double corner;
  /// Bone "paper" theme for cards / sheets / dialogs on the red base
  /// (null when surfaces simply use this theme). See [PaperScope].
  final ThemeData? paper;
  const HermesColors({
    required this.card,
    required this.muted,
    required this.mutedForeground,
    required this.popover,
    required this.border,
    required this.strokeSoft,
    required this.midground,
    required this.destructive,
    required this.success,
    required this.warning,
    required this.info,
    required this.sidebar,
    required this.sidebarBorder,
    required this.userBubble,
    required this.userBubbleBorder,
    required this.codeBg,
    required this.monoFamily,
    this.displayFamily,
    this.brand = false,
    this.corner = 8,
    this.paper,
  });

  @override
  HermesColors copyWith() => this;

  @override
  HermesColors lerp(ThemeExtension<HermesColors>? other, double t) =>
      (other is HermesColors && t > 0.5) ? other : this;
}

extension HermesThemeX on BuildContext {
  HermesColors get hc => Theme.of(this).extension<HermesColors>()!;
  ColorScheme get cs => Theme.of(this).colorScheme;
  TextTheme get tt => Theme.of(this).textTheme;
}

/// Fonts shipped in assets/fonts (no runtime download needed).
const bundledFonts = {
  'IBM Plex Mono': 'IBMPlexMono',
  'IBMPlexMono': 'IBMPlexMono',
  'Barlow': 'Barlow',
  'BigShoulders': 'BigShoulders',
  'JetBrains Mono': 'JetBrainsMono',
  'JetBrainsMono': 'JetBrainsMono',
  'IBMPlexSans': 'IBMPlexSans',
  'InstrumentSerif': 'InstrumentSerif',
};

TextStyle monoStyle(BuildContext context, {double? size, Color? color, FontWeight? weight}) {
  final fam = context.hc.monoFamily;
  final base = TextStyle(fontSize: size ?? 12.5, color: color, fontWeight: weight, height: 1.45);
  final bundled = bundledFonts[fam];
  if (bundled != null) return base.copyWith(fontFamily: bundled, fontFamilyFallback: const ['monospace']);
  try {
    return GoogleFonts.getFont(fam, textStyle: base);
  } catch (_) {
    return base.copyWith(fontFamily: 'monospace');
  }
}

ThemeData buildTheme(HermesTheme theme, Brightness brightness, {String fontChoice = 'tema'}) {
  final p = theme.palette(brightness);
  // Brightness follows the actual base colour: the red brand base carries
  // light (bone) type, so Material treats it as a dark surface.
  final b = theme.darkOnly ? Brightness.dark : ThemeData.estimateBrightnessForColor(p.background);
  final paperPalette = (brightness == Brightness.light && !theme.darkOnly) ? theme.paper : null;
  final ThemeData? paperTheme = paperPalette == null
      ? null
      : buildTheme(
          HermesTheme(
            name: '${theme.name}-paper',
            label: theme.label,
            description: theme.description,
            light: paperPalette,
            monoFont: theme.monoFont,
            sans: theme.sans,
            displayFont: theme.displayFont,
            corner: theme.corner,
            brand: theme.brand,
          ),
          Brightness.light,
          fontChoice: fontChoice);
  final isDark = b == Brightness.dark;

  final scheme = ColorScheme(
    brightness: b,
    primary: p.primary,
    onPrimary: p.primaryForeground,
    primaryContainer: p.secondary,
    onPrimaryContainer: p.foreground,
    secondary: p.midground,
    onSecondary: p.primaryForeground,
    secondaryContainer: p.secondary,
    onSecondaryContainer: p.foreground,
    tertiary: p.ring,
    onTertiary: p.primaryForeground,
    error: p.destructive,
    onError: Colors.white,
    surface: p.background,
    onSurface: p.foreground,
    onSurfaceVariant: p.mutedForeground,
    surfaceContainerLowest: p.background,
    surfaceContainerLow: p.card,
    surfaceContainer: p.muted,
    surfaceContainerHigh: p.popover,
    surfaceContainerHighest: p.accent,
    outline: p.border,
    outlineVariant: p.border.withValues(alpha: 0.6),
    inverseSurface: p.foreground,
    onInverseSurface: p.background,
    inversePrimary: p.primary,
    shadow: Colors.black,
    scrim: Colors.black54,
    surfaceTint: Colors.transparent,
  );

  TextTheme text = (isDark ? ThemeData.dark() : ThemeData.light()).textTheme;
  final family = fontChoice == 'tema'
      ? theme.sans
      : FontPreset.values.firstWhere((f) => f.name == fontChoice, orElse: () => theme.sans);
  final String? fontFamily = switch (family) {
    FontPreset.inter => GoogleFonts.inter().fontFamily,
    FontPreset.courierPrime => GoogleFonts.courierPrime().fontFamily,
    FontPreset.plexMono => 'IBMPlexMono',
    FontPreset.barlow => 'Barlow',
    FontPreset.system => null,
  };
  final display = theme.displayFont;
  final monoFam = bundledFonts[theme.monoFont];
  text = text.apply(bodyColor: p.foreground, displayColor: p.foreground, fontFamily: fontFamily);
  text = text.copyWith(
    titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 20, letterSpacing: -0.2),
    titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 15.5),
    titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 13.5),
    bodyMedium: text.bodyMedium?.copyWith(fontSize: 14, height: 1.45),
    bodySmall: text.bodySmall?.copyWith(fontSize: 12.5, color: p.mutedForeground),
    labelSmall: text.labelSmall?.copyWith(fontSize: 11, letterSpacing: 0.6, color: p.mutedForeground),
  );
  if (display != null) {
    // Site typography: thin condensed display for headings, mono meta labels.
    TextStyle? d(TextStyle? t, FontWeight w, double size, {double ls = 0.4, double h = 1.05}) =>
        t?.copyWith(fontFamily: display, fontWeight: w, fontSize: size, letterSpacing: ls, height: h);
    text = text.copyWith(
      displayLarge: d(text.displayLarge, FontWeight.w200, 64, ls: 0),
      displayMedium: d(text.displayMedium, FontWeight.w200, 52, ls: 0),
      displaySmall: d(text.displaySmall, FontWeight.w200, 40, ls: 0.2),
      headlineLarge: d(text.headlineLarge, FontWeight.w300, 34),
      headlineMedium: d(text.headlineMedium, FontWeight.w300, 30),
      headlineSmall: d(text.headlineSmall, FontWeight.w300, 27),
      titleLarge: d(text.titleLarge, FontWeight.w300, 27, ls: 0.5, h: 1.1),
      titleMedium: d(text.titleMedium, FontWeight.w500, 21, ls: 0.7, h: 1.15),
      labelSmall: text.labelSmall?.copyWith(fontFamily: monoFam, fontSize: 10.5, letterSpacing: 1.1, fontWeight: FontWeight.w500),
      labelMedium: text.labelMedium?.copyWith(fontFamily: monoFam, fontSize: 11.5, letterSpacing: 0.8),
    );
  }

  final radius = theme.corner;
  final r6 = theme.corner < 6 ? theme.corner : 6.0;
  final hairline = BorderSide(color: p.border, width: 1);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(r6));

  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    textTheme: text,
    splashFactory: theme.brand ? InkRipple.splashFactory : InkSparkle.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: HermesPageTransitionsBuilder(),
      TargetPlatform.iOS: HermesPageTransitionsBuilder(),
      TargetPlatform.linux: HermesPageTransitionsBuilder(),
      TargetPlatform.macOS: HermesPageTransitionsBuilder(),
      TargetPlatform.windows: HermesPageTransitionsBuilder(),
      TargetPlatform.fuchsia: HermesPageTransitionsBuilder(),
    }),
    visualDensity: VisualDensity.standard,
    dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.foreground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleMedium,
      shape: Border(bottom: BorderSide(color: p.border.withValues(alpha: 0.7))),
    ),
    cardTheme: CardThemeData(
      color: paperPalette?.card ?? p.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: hairline),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.sidebarBackground,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.secondary,
      indicatorShape: theme.brand
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(2), side: BorderSide(color: p.foreground.withValues(alpha: 0.7)))
          : null,
      elevation: 0,
      height: 66,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontFamily: theme.brand ? monoFam : null,
            letterSpacing: theme.brand ? 0.5 : null,
            fontSize: theme.brand ? 10.5 : 11.5,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? p.foreground : p.mutedForeground,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            size: 22,
            color: s.contains(WidgetState.selected) ? p.primary : p.mutedForeground,
          )),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: p.sidebarBackground,
      indicatorColor: p.secondary,
      selectedIconTheme: IconThemeData(color: p.primary),
      unselectedIconTheme: IconThemeData(color: p.mutedForeground),
      selectedLabelTextStyle: TextStyle(color: p.foreground, fontWeight: FontWeight.w600, fontSize: 12),
      unselectedLabelTextStyle: TextStyle(color: p.mutedForeground, fontSize: 12),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: p.sidebarBackground,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: paperPalette?.popover ?? p.popover,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: paperPalette?.popover ?? p.popover,
      showDragHandle: true,
      dragHandleColor: (paperPalette?.mutedForeground ?? p.mutedForeground).withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(radius * 2))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: paperPalette?.popover ?? p.popover,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius * 1.5), side: hairline),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.popover,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: hairline),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.input,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: TextStyle(color: p.mutedForeground),
      labelStyle: TextStyle(color: p.mutedForeground),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(r6), borderSide: hairline),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(r6), borderSide: hairline),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(r6), borderSide: BorderSide(color: p.ring, width: 1.4)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.primary,
        foregroundColor: p.primaryForeground,
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.foreground,
        side: hairline,
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.primary, shape: shape),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
          foregroundColor: p.foreground, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r6))),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.primary,
      foregroundColor: p.primaryForeground,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(theme.brand ? 2 : 14), side: theme.brand ? BorderSide(color: p.primaryForeground.withValues(alpha: 0.4)) : BorderSide.none),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.muted,
      selectedColor: p.secondary,
      side: hairline,
      labelStyle: TextStyle(color: p.foreground, fontSize: 12.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r6)),
      padding: const EdgeInsets.symmetric(horizontal: 6),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: p.background,
        selectedBackgroundColor: p.secondary,
        selectedForegroundColor: p.foreground,
        side: hairline,
        shape: shape,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.primaryForeground : p.mutedForeground),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.primary : p.muted),
      trackOutlineColor: WidgetStatePropertyAll(p.border),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.mutedForeground,
      textColor: p.foreground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r6)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.popover,
      contentTextStyle: TextStyle(color: p.foreground),
      actionTextColor: p.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: hairline),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: p.foreground,
      unselectedLabelColor: p.mutedForeground,
      indicatorColor: p.primary,
      dividerColor: p.border,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary, linearTrackColor: p.muted),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: p.popover, borderRadius: BorderRadius.circular(radius < 4 ? radius : 4), border: Border.fromBorderSide(hairline)),
      textStyle: TextStyle(color: p.foreground, fontSize: 12),
      waitDuration: const Duration(milliseconds: 200),
    ),
    extensions: [
      HermesColors(
        card: p.card,
        muted: p.muted,
        mutedForeground: p.mutedForeground,
        popover: p.popover,
        border: p.border,
        strokeSoft: p.border.withValues(alpha: 0.55),
        midground: p.midground,
        destructive: p.destructive,
        success: theme.brand && isDark ? const Color(0xFF7DF0B8) : (isDark ? const Color(0xFF46C08A) : const Color(0xFF1A7F4B)),
        warning: theme.brand && isDark ? const Color(0xFFFFD36B) : (isDark ? const Color(0xFFF0B556) : const Color(0xFFA86A00)),
        info: p.ring,
        sidebar: p.sidebarBackground,
        sidebarBorder: p.sidebarBorder,
        userBubble: p.userBubble,
        userBubbleBorder: p.userBubbleBorder,
        codeBg: isDark ? Color.alphaBlend(Colors.black.withValues(alpha: 0.25), p.card) : p.muted,
        monoFamily: theme.monoFont,
        displayFamily: display,
        brand: theme.brand,
        corner: theme.corner,
        paper: paperTheme,
      ),
    ],
  );
}
