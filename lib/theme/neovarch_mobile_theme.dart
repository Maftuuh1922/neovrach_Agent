// Neovarch Remote (Android/iOS) — the phone's own design system, shared with
// Neovarch Desktop and the landing page:
//   flat dark-red palette, no gradients / glows / elevation shadows,
//   one rounded system (16 cards & sheets · 12 controls · 20 dialogs ·
//   14 chat blocks · full for avatars & badges), 1px borders,
//   Instrument Serif for big titles, IBM Plex Sans for body,
//   JetBrains Mono for labels and "// LABEL" section headers.
// Every Material component theme is set explicitly so no stock purple/blue
// (or Material You dynamic colour) can leak in.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/widgets/motion.dart';
import 'app_theme.dart';

/// One resolved colour set. The phone follows the PC's appearance (accent +
/// dark/light, `GET /api/appearance` / `appearance.changed`) unless the user
/// set a local override; see `state/appearance.dart`.
class NvPalette {
  const NvPalette({
    required this.brightness,
    required this.accent,
    required this.onAccent,
    required this.bg,
    required this.surface,
    required this.raised,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.muted,
    required this.faint,
    required this.darkAccent,
    required this.wash,
  });
  final Brightness brightness;
  final Color accent, onAccent, bg, surface, raised, border, borderStrong, text, muted, faint, darkAccent, wash;
  bool get dark => brightness == Brightness.dark;

  static const defaultAccent = Color(0xFFEE1C1C);

  /// The original Neovarch dark red set (exactly the v1.3 tokens).
  static const red = NvPalette(
    brightness: Brightness.dark,
    accent: Color(0xFFEE1C1C),
    onAccent: Color(0xFFF4F2ED),
    bg: Color(0xFF0D0606),
    surface: Color(0xFF140808),
    raised: Color(0xFF1B0C0C),
    border: Color(0xFF2A1212),
    borderStrong: Color(0xFF3D1B1B),
    text: Color(0xFFF4F2ED),
    muted: Color(0xFFB8ADA6),
    faint: Color(0xFF7D706A),
    darkAccent: Color(0xFF8F0A0A),
    wash: Color(0xFF2A0B0B),
  );

  /// Flat colours only: every token is the base neutral lightly tinted by the
  /// accent (Color.lerp), never a gradient.
  factory NvPalette.from(Color accent, Brightness b, {Color? onAccent}) {
    final a = accent.withAlpha(255);
    if (b == Brightness.dark && a.toARGB32() == defaultAccent.toARGB32()) return red;
    Color t(int base, double f) => Color.lerp(Color(base), a, f)!;
    final on = onAccent ?? (_contrast(a, const Color(0xFFFFFFFF)) >= 4.0 ? const Color(0xFFFFFFFF) : const Color(0xFF000000));
    if (b == Brightness.dark) {
      return NvPalette(
        brightness: b,
        accent: a,
        onAccent: on,
        bg: t(0xFF0A0A0A, 0.035),
        surface: t(0xFF111111, 0.05),
        raised: t(0xFF181818, 0.06),
        border: t(0xFF242424, 0.10),
        borderStrong: t(0xFF343434, 0.14),
        text: const Color(0xFFF4F2ED),
        muted: const Color(0xFFB3ADA8),
        faint: const Color(0xFF78716C),
        darkAccent: Color.lerp(a, const Color(0xFF000000), 0.45)!,
        wash: t(0xFF0D0D0D, 0.16),
      );
    }
    return NvPalette(
      brightness: b,
      accent: a,
      onAccent: on,
      bg: t(0xFFF5F3EF, 0.03),
      surface: t(0xFFFFFFFF, 0.02),
      raised: t(0xFFEDEAE5, 0.04),
      border: t(0xFFDDD8D1, 0.08),
      borderStrong: t(0xFFC9C2B9, 0.12),
      text: const Color(0xFF151111),
      muted: const Color(0xFF5C5450),
      faint: const Color(0xFF8A827C),
      darkAccent: Color.lerp(a, const Color(0xFF000000), 0.35)!,
      wash: t(0xFFFFFFFF, 0.12),
    );
  }

  static double _lum(Color c) {
    double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  static double _contrast(Color a, Color b) {
    final la = _lum(a), lb = _lum(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }
}

/// Design tokens. Colours read the current [NvPalette] (set by the app from
/// the PC appearance or the local override); radii and fonts are fixed.
abstract final class NV {
  static NvPalette palette = NvPalette.red;

  static Color get bg => palette.bg;
  static Color get surface => palette.surface;
  static Color get raised => palette.raised;
  static Color get border => palette.border;
  static Color get borderStrong => palette.borderStrong;
  static Color get text => palette.text;
  static Color get muted => palette.muted;
  static Color get faint => palette.faint;
  static Color get red => palette.accent; // the accent (red by default)
  static Color get onRed => palette.onAccent;
  static Color get darkRed => palette.darkAccent;
  static Color get redWash => palette.wash; // accent-tinted surface (selection, user message)
  // Status colours stay inside the palette: no stock green / amber.
  static Color get ok => text; // connected / online
  static Color get warn => muted; // connecting / waiting

  /// Liquid glass: flat translucent tint of the surface (no gradient).
  static Color get glass => palette.surface.withValues(alpha: palette.dark ? 0.62 : 0.70);
  static Color get glassBorder => palette.text.withValues(alpha: palette.dark ? 0.10 : 0.12);
  static const glassBlur = 24.0;

  static const rCard = 16.0;
  static const rCtl = 12.0;
  static const rDialog = 20.0;
  static const rMsg = 14.0;

  static const serif = 'InstrumentSerif';
  static const sans = 'IBMPlexSans';
  static const mono = 'JetBrainsMono';

  static BorderRadius get card => BorderRadius.circular(rCard);
  static BorderRadius get ctl => BorderRadius.circular(rCtl);

  static TextStyle monoLabel({double size = 10.5, Color? color, FontWeight weight = FontWeight.w500}) =>
      TextStyle(fontFamily: mono, fontSize: size, letterSpacing: 1.2, fontWeight: weight, color: color ?? muted, height: 1.3);

  static TextStyle display({double size = 34, Color? color}) =>
      TextStyle(fontFamily: serif, fontSize: size, height: 1.0, letterSpacing: -0.3, color: color ?? text, fontWeight: FontWeight.w400);
}

ThemeData buildNeovarchMobileTheme() {
  final scheme = ColorScheme(
    brightness: NV.palette.brightness,
    primary: NV.red,
    onPrimary: NV.onRed,
    primaryContainer: NV.redWash,
    onPrimaryContainer: NV.text,
    primaryFixed: NV.red,
    primaryFixedDim: NV.darkRed,
    onPrimaryFixed: NV.text,
    onPrimaryFixedVariant: NV.text,
    secondary: NV.muted,
    onSecondary: NV.bg,
    secondaryContainer: NV.raised,
    onSecondaryContainer: NV.text,
    secondaryFixed: NV.muted,
    secondaryFixedDim: NV.faint,
    onSecondaryFixed: NV.bg,
    onSecondaryFixedVariant: NV.bg,
    tertiary: NV.darkRed,
    onTertiary: NV.text,
    tertiaryContainer: NV.redWash,
    onTertiaryContainer: NV.text,
    tertiaryFixed: NV.darkRed,
    tertiaryFixedDim: NV.darkRed,
    onTertiaryFixed: NV.text,
    onTertiaryFixedVariant: NV.text,
    error: NV.red,
    onError: NV.text,
    errorContainer: NV.redWash,
    onErrorContainer: NV.text,
    surface: NV.bg,
    onSurface: NV.text,
    surfaceDim: NV.bg,
    surfaceBright: NV.raised,
    surfaceContainerLowest: NV.bg,
    surfaceContainerLow: NV.surface,
    surfaceContainer: NV.surface,
    surfaceContainerHigh: NV.raised,
    surfaceContainerHighest: NV.raised,
    onSurfaceVariant: NV.muted,
    outline: NV.border,
    outlineVariant: NV.border,
    shadow: Colors.transparent,
    scrim: const Color(0xB3000000),
    inverseSurface: NV.text,
    onInverseSurface: NV.bg,
    inversePrimary: NV.darkRed,
    surfaceTint: Colors.transparent,
  );

  final base = (NV.palette.dark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true)).textTheme.apply(
        fontFamily: NV.sans,
        bodyColor: NV.text,
        displayColor: NV.text,
      );
  TextStyle serif(TextStyle? t, double size) =>
      (t ?? const TextStyle()).copyWith(fontFamily: NV.serif, fontSize: size, fontWeight: FontWeight.w400, height: 1.05, letterSpacing: -0.2, color: NV.text);
  final text = base.copyWith(
    displayLarge: serif(base.displayLarge, 56),
    displayMedium: serif(base.displayMedium, 46),
    displaySmall: serif(base.displaySmall, 40),
    headlineLarge: serif(base.headlineLarge, 36),
    headlineMedium: serif(base.headlineMedium, 32),
    headlineSmall: serif(base.headlineSmall, 28),
    titleLarge: serif(base.titleLarge, 26),
    titleMedium: base.titleMedium?.copyWith(fontSize: 15.5, fontWeight: FontWeight.w600, letterSpacing: -0.1),
    titleSmall: base.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
    bodyLarge: base.bodyLarge?.copyWith(fontSize: 15, height: 1.5),
    bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, height: 1.5),
    bodySmall: base.bodySmall?.copyWith(fontSize: 12.5, height: 1.45, color: NV.muted),
    labelLarge: base.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1),
    labelMedium: base.labelMedium?.copyWith(fontFamily: NV.mono, fontSize: 11.5, letterSpacing: 0.8, color: NV.muted),
    labelSmall: base.labelSmall?.copyWith(fontFamily: NV.mono, fontSize: 10.5, letterSpacing: 1.2, fontWeight: FontWeight.w500, color: NV.muted),
  );

  final line = BorderSide(color: NV.border, width: 1);
  final ctlShape = RoundedRectangleBorder(borderRadius: NV.ctl);
  final ctlShapeLined = RoundedRectangleBorder(borderRadius: NV.ctl, side: line);
  final cardShape = RoundedRectangleBorder(borderRadius: NV.card, side: line);
  const btnPad = EdgeInsets.symmetric(horizontal: 18, vertical: 14);
  const btnText = TextStyle(fontFamily: NV.sans, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1);
  // Subdued press feedback: a faint warm wash, no sparkle, no coloured ripple.
  const press = Color(0x14F4F2ED);
  WidgetStateProperty<Color?> overlay([Color c = press]) =>
      WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.pressed) || s.contains(WidgetState.focused) || s.contains(WidgetState.hovered) ? c : null);
  OutlineInputBorder inBorder(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: NV.ctl, borderSide: BorderSide(color: c, width: w));

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: NV.sans,
    textTheme: text,
    primaryTextTheme: text,
    scaffoldBackgroundColor: NV.bg,
    canvasColor: NV.bg,
    cardColor: NV.surface,
    dividerColor: NV.border,
    disabledColor: NV.faint,
    hintColor: NV.faint,
    focusColor: press,
    hoverColor: press,
    highlightColor: Colors.transparent,
    splashColor: press,
    splashFactory: InkRipple.splashFactory,
    shadowColor: Colors.transparent,
    applyElevationOverlayColor: false,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    iconTheme: IconThemeData(color: NV.text, size: 22),
    primaryIconTheme: IconThemeData(color: NV.text),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: HermesPageTransitionsBuilder(),
      TargetPlatform.iOS: HermesPageTransitionsBuilder(),
      TargetPlatform.linux: HermesPageTransitionsBuilder(),
      TargetPlatform.macOS: HermesPageTransitionsBuilder(),
      TargetPlatform.windows: HermesPageTransitionsBuilder(),
      TargetPlatform.fuchsia: HermesPageTransitionsBuilder(),
    }),
    dividerTheme: DividerThemeData(color: NV.border, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: NV.bg,
      foregroundColor: NV.text,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 20,
      toolbarHeight: 60,
      iconTheme: IconThemeData(color: NV.text, size: 22),
      actionsIconTheme: IconThemeData(color: NV.muted, size: 22),
      titleTextStyle: TextStyle(fontFamily: NV.serif, fontSize: 28, color: NV.text, height: 1.0),
    ),
    cardTheme: CardThemeData(
      color: NV.surface,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: cardShape,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: NV.surface,
      modalBackgroundColor: NV.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      dragHandleColor: NV.borderStrong,
      dragHandleSize: Size(40, 4),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(NV.rCard)),
        side: line,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: NV.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NV.rDialog), side: line),
      titleTextStyle: TextStyle(fontFamily: NV.serif, fontSize: 26, color: NV.text, height: 1.1),
      contentTextStyle: TextStyle(fontFamily: NV.sans, fontSize: 14, color: NV.muted, height: 1.5),
      barrierColor: const Color(0xB3000000),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: NV.raised,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      shape: cardShape,
      textStyle: TextStyle(fontFamily: NV.sans, fontSize: 14, color: NV.text),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(NV.raised),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(cardShape),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(NV.raised),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(cardShape),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: NV.surface,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      hintStyle: TextStyle(color: NV.faint, fontFamily: NV.sans),
      labelStyle: TextStyle(color: NV.muted, fontFamily: NV.sans),
      floatingLabelStyle: TextStyle(color: NV.text, fontFamily: NV.sans),
      helperStyle: TextStyle(color: NV.faint, fontSize: 12, fontFamily: NV.sans),
      errorStyle: TextStyle(color: NV.red, fontSize: 12),
      prefixIconColor: NV.muted,
      suffixIconColor: NV.muted,
      border: inBorder(NV.border),
      enabledBorder: inBorder(NV.border),
      disabledBorder: inBorder(NV.border.withValues(alpha: 0.5)),
      focusedBorder: inBorder(NV.red),
      errorBorder: inBorder(NV.darkRed),
      focusedErrorBorder: inBorder(NV.red),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: NV.red,
      selectionColor: Color(0x668F0A0A),
      selectionHandleColor: NV.red,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? NV.raised : NV.red),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? NV.faint : NV.text),
        overlayColor: overlay(const Color(0x1F0D0606)),
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(ctlShape),
        padding: const WidgetStatePropertyAll(btnPad),
        minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
        textStyle: const WidgetStatePropertyAll(btnText),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(NV.raised),
        foregroundColor: WidgetStatePropertyAll(NV.text),
        overlayColor: overlay(),
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(ctlShapeLined),
        padding: const WidgetStatePropertyAll(btnPad),
        textStyle: const WidgetStatePropertyAll(btnText),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? NV.faint : NV.text),
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        overlayColor: overlay(),
        side: WidgetStateProperty.resolveWith((s) => BorderSide(color: s.contains(WidgetState.disabled) ? NV.border : NV.borderStrong)),
        shape: WidgetStatePropertyAll(ctlShape),
        padding: const WidgetStatePropertyAll(btnPad),
        minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
        textStyle: const WidgetStatePropertyAll(btnText),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? NV.faint : NV.red),
        overlayColor: overlay(),
        shape: WidgetStatePropertyAll(ctlShape),
        textStyle: const WidgetStatePropertyAll(btnText),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? NV.faint : NV.text),
        overlayColor: overlay(),
        shape: WidgetStatePropertyAll(ctlShape),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: NV.red,
      foregroundColor: NV.text,
      splashColor: const Color(0x1F0D0606),
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      disabledElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NV.rCard)),
      extendedTextStyle: btnText,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: NV.surface,
      selectedColor: NV.redWash,
      disabledColor: NV.surface,
      secondarySelectedColor: NV.redWash,
      checkmarkColor: NV.red,
      deleteIconColor: NV.muted,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      selectedShadowColor: Colors.transparent,
      elevation: 0,
      pressElevation: 0,
      side: WidgetStateBorderSide.resolveWith(
          (s) => BorderSide(color: s.contains(WidgetState.selected) ? NV.red : NV.border)),
      labelStyle: TextStyle(fontFamily: NV.sans, color: NV.text, fontSize: 13),
      secondaryLabelStyle: TextStyle(fontFamily: NV.sans, color: NV.text, fontSize: 13),
      shape: ctlShape,
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? NV.redWash : NV.surface),
        foregroundColor: WidgetStatePropertyAll(NV.text),
        side: WidgetStatePropertyAll(line),
        shape: WidgetStatePropertyAll(ctlShape),
        overlayColor: overlay(),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? NV.text : NV.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? NV.red : NV.raised),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? NV.red : NV.borderStrong),
      overlayColor: overlay(),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? NV.red : Colors.transparent),
      checkColor: WidgetStatePropertyAll(NV.text),
      side: BorderSide(color: NV.borderStrong, width: 1.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? NV.red : NV.muted),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: NV.red,
      inactiveTrackColor: NV.border,
      thumbColor: NV.text,
      overlayColor: press,
      valueIndicatorColor: NV.raised,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: NV.muted,
      textColor: NV.text,
      selectedColor: NV.text,
      selectedTileColor: NV.redWash,
      tileColor: Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      shape: ctlShape,
      titleTextStyle: TextStyle(fontFamily: NV.sans, fontSize: 15, color: NV.text, fontWeight: FontWeight.w500),
      subtitleTextStyle: TextStyle(fontFamily: NV.sans, fontSize: 12.5, color: NV.muted),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      iconColor: NV.muted,
      collapsedIconColor: NV.muted,
      textColor: NV.text,
      collapsedTextColor: NV.text,
      shape: ctlShape,
      collapsedShape: ctlShape,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: NV.raised,
      elevation: 0,
      contentTextStyle: TextStyle(fontFamily: NV.sans, color: NV.text, fontSize: 14),
      actionTextColor: NV.red,
      closeIconColor: NV.muted,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NV.rCard), side: BorderSide(color: NV.borderStrong)),
    ),
    bannerTheme: MaterialBannerThemeData(
      backgroundColor: NV.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      dividerColor: NV.border,
      elevation: 0,
      contentTextStyle: TextStyle(fontFamily: NV.sans, color: NV.text, fontSize: 13.5),
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: NV.red,
      textColor: NV.text,
      textStyle: TextStyle(fontFamily: NV.mono, fontSize: 10, fontWeight: FontWeight.w500),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: NV.text,
      unselectedLabelColor: NV.muted,
      indicatorColor: NV.red,
      dividerColor: NV.border,
      overlayColor: WidgetStatePropertyAll(press),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: NV.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      indicatorColor: NV.redWash,
      indicatorShape: ctlShape,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => NV.monoLabel(color: s.contains(WidgetState.selected) ? NV.text : NV.muted)),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? NV.red : NV.muted)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: NV.surface,
      indicatorColor: NV.redWash,
      selectedIconTheme: IconThemeData(color: NV.red),
      unselectedIconTheme: IconThemeData(color: NV.muted),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: NV.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: NV.red,
      linearTrackColor: NV.border,
      circularTrackColor: Colors.transparent,
      refreshBackgroundColor: NV.surface,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: NV.raised, borderRadius: BorderRadius.circular(8), border: Border.all(color: NV.borderStrong)),
      textStyle: TextStyle(fontFamily: NV.sans, color: NV.text, fontSize: 12),
      waitDuration: const Duration(milliseconds: 300),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(NV.borderStrong.withValues(alpha: 0.9)),
      radius: const Radius.circular(8),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: NV.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NV.rDialog), side: line),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: NV.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NV.rDialog), side: line),
    ),
    searchBarTheme: SearchBarThemeData(
      backgroundColor: WidgetStatePropertyAll(NV.surface),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(0),
      shape: WidgetStatePropertyAll(ctlShapeLined),
    ),
    extensions: [
      HermesColors(
        card: NV.surface,
        muted: NV.raised,
        mutedForeground: NV.muted,
        popover: NV.surface,
        border: NV.border,
        strokeSoft: NV.border,
        midground: NV.red,
        destructive: NV.red,
        success: NV.ok,
        warning: NV.warn,
        info: NV.muted,
        sidebar: NV.surface,
        sidebarBorder: NV.border,
        userBubble: NV.redWash,
        userBubbleBorder: NV.darkRed,
        codeBg: Color(0xFF0A0404),
        monoFamily: NV.mono,
        displayFamily: NV.serif,
        brand: false,
        corner: NV.rCtl,
        paper: null,
      ),
    ],
  );
}
