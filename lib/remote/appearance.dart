// Phone theme: follows the PC's appearance (accent preset/custom hex +
// dark/light, from `GET /api/appearance` and the `appearance.changed` push)
// unless the user set a local override on this phone. The last PC look is
// cached so the app starts in it before the socket is up.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/neovarch_mobile_theme.dart';

/// Accent presets. The first six match the desktop theme picker; the rest
/// are phone extras. Every one tints the whole UI (surfaces, glass, nav,
/// chips, buttons), not just the accent.
const accentPresets = <(String, Color)>[
  ('Merah', Color(0xFFEE1C1C)),
  ('Biru', Color(0xFF2563EB)),
  ('Hijau', Color(0xFF16A34A)),
  ('Ungu', Color(0xFF7C3AED)),
  ('Oranye', Color(0xFFEA580C)),
  ('Monokrom', Color(0xFFA3A3A3)),
  ('Mawar', Color(0xFFE11D48)),
  ('Merah muda', Color(0xFFDB2777)),
  ('Nila', Color(0xFF4F46E5)),
  ('Langit', Color(0xFF0284C7)),
  ('Toska', Color(0xFF0D9488)),
  ('Limau', Color(0xFF65A30D)),
  ('Kuning', Color(0xFFCA8A04)),
  ('Cokelat', Color(0xFF9A6B4F)),
];

Color? parseHexColor(String? raw) {
  var s = (raw ?? '').trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
  if (s.length != 6 || int.tryParse(s, radix: 16) == null) return null;
  return Color(0xFF000000 | int.parse(s, radix: 16));
}

String hexOf(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Light / dark / follow the phone's system setting (local theme only; the
/// PC look always carries its own dark/light).
enum NvBrightnessMode { dark, light, system }

class AppearanceController extends ChangeNotifier {
  AppearanceController(this._prefs, {Brightness? systemBrightness}) {
    _system = systemBrightness ?? _platformBrightness();
    _load();
    _apply();
  }
  final SharedPreferences _prefs;

  static const _kFollow = 'nv.theme.follow';
  static const _kAccent = 'nv.theme.accent';
  static const _kBase = 'nv.theme.base';
  static const _kPcAccent = 'nv.theme.pc.accent';
  static const _kPcBase = 'nv.theme.pc.base';

  /// Resolved boot colours, read natively by MainActivity (window background
  /// before Flutter draws) so a cold start opens straight in this look.
  static const kBootBg = 'nv.boot.bg';
  static const kBootDark = 'nv.boot.dark';

  /// True: use the PC's look. False: [localAccent] / [localMode].
  bool followPc = true;
  Color localAccent = NvPalette.defaultAccent;
  NvBrightnessMode localMode = NvBrightnessMode.dark;

  Color pcAccent = NvPalette.defaultAccent;
  bool pcDark = true;
  Color? pcOnAccent;

  Brightness _system = Brightness.dark;

  /// Called right before the palette changes, while the old frame is still
  /// on screen (the app snapshots it to cross-fade into the new look).
  VoidCallback? onBeforeChange;

  /// Bumped on every palette change; the app rebuilds every element on it.
  int revision = 0;

  bool get localDark => switch (localMode) {
        NvBrightnessMode.dark => true,
        NvBrightnessMode.light => false,
        NvBrightnessMode.system => _system == Brightness.dark,
      };

  Color get accent => followPc ? pcAccent : localAccent;
  bool get dark => followPc ? pcDark : localDark;
  NvPalette get palette => NvPalette.from(accent, dark ? Brightness.dark : Brightness.light, onAccent: followPc ? pcOnAccent : null);

  static Brightness _platformBrightness() {
    try {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness;
    } catch (_) {
      return Brightness.dark;
    }
  }

  void _load() {
    followPc = _prefs.getBool(_kFollow) ?? true;
    localAccent = parseHexColor(_prefs.getString(_kAccent)) ?? NvPalette.defaultAccent;
    localMode = switch (_prefs.getString(_kBase)) {
      'light' => NvBrightnessMode.light,
      'system' => NvBrightnessMode.system,
      _ => NvBrightnessMode.dark,
    };
    pcAccent = parseHexColor(_prefs.getString(_kPcAccent)) ?? NvPalette.defaultAccent;
    pcDark = (_prefs.getString(_kPcBase) ?? 'dark') != 'light';
  }

  bool _same(NvPalette p) => NV.palette.accent == p.accent && NV.palette.brightness == p.brightness && NV.palette.onAccent == p.onAccent;

  void _apply() {
    final p = palette;
    if (_same(p) && revision > 0) return;
    if (revision > 0) onBeforeChange?.call();
    NV.palette = p;
    revision++;
    _prefs
      ..setString(kBootBg, hexOf(p.bg))
      ..setString(kBootDark, p.dark ? '1' : '0');
    notifyListeners();
  }

  /// From `GET /api/appearance` or the `appearance.changed` push.
  void applyPc(Map<String, dynamic> a) {
    final c = parseHexColor('${a['accent'] ?? ''}');
    if (c == null) return;
    pcAccent = c;
    pcDark = '${a['base'] ?? 'dark'}' != 'light';
    pcOnAccent = parseHexColor('${a['on_accent'] ?? ''}');
    _prefs.setString(_kPcAccent, hexOf(c));
    _prefs.setString(_kPcBase, pcDark ? 'dark' : 'light');
    _apply();
  }

  void setFollowPc(bool v) {
    followPc = v;
    _prefs.setBool(_kFollow, v);
    _apply();
  }

  /// The phone's dark/light setting changed (matters for [NvBrightnessMode.system]).
  void setSystemBrightness(Brightness b) {
    if (_system == b) return;
    _system = b;
    _apply();
  }

  /// Local override (turns following the PC off).
  void setLocal({Color? accent, bool? dark, NvBrightnessMode? mode}) {
    if (accent != null) localAccent = accent.withAlpha(255);
    if (mode != null) {
      localMode = mode;
    } else if (dark != null) {
      localMode = dark ? NvBrightnessMode.dark : NvBrightnessMode.light;
    }
    followPc = false;
    _prefs
      ..setBool(_kFollow, false)
      ..setString(_kAccent, hexOf(localAccent))
      ..setString(_kBase, localMode.name);
    _apply();
  }
}

final appearanceProvider = ChangeNotifierProvider<AppearanceController>((ref) => throw UnimplementedError());

/// Marks every element below [context] dirty so widgets that read the
/// palette tokens (`NV.*`, incl. const ones) repaint in the new colours
/// without losing their state.
void rebuildAllChildren(BuildContext context) {
  void rebuild(Element el) {
    el.markNeedsBuild();
    el.visitChildren(rebuild);
  }

  (context as Element).visitChildren(rebuild);
}
