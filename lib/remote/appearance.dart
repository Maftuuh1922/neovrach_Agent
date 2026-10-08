// Phone theme: follows the PC's appearance (accent preset/custom hex +
// dark/light, from `GET /api/appearance` and the `appearance.changed` push)
// unless the user set a local override on this phone. The last PC look is
// cached so the app starts in it before the socket is up.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/neovarch_mobile_theme.dart';

/// Same presets as the desktop theme picker.
const accentPresets = <(String, Color)>[
  ('Merah', Color(0xFFEE1C1C)),
  ('Biru', Color(0xFF2563EB)),
  ('Hijau', Color(0xFF16A34A)),
  ('Ungu', Color(0xFF7C3AED)),
  ('Oranye', Color(0xFFEA580C)),
  ('Monokrom', Color(0xFFA3A3A3)),
];

Color? parseHexColor(String? raw) {
  var s = (raw ?? '').trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
  if (s.length != 6 || int.tryParse(s, radix: 16) == null) return null;
  return Color(0xFF000000 | int.parse(s, radix: 16));
}

String hexOf(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

class AppearanceController extends ChangeNotifier {
  AppearanceController(this._prefs) {
    _load();
    _apply();
  }
  final SharedPreferences _prefs;

  static const _kFollow = 'nv.theme.follow';
  static const _kAccent = 'nv.theme.accent';
  static const _kBase = 'nv.theme.base';
  static const _kPcAccent = 'nv.theme.pc.accent';
  static const _kPcBase = 'nv.theme.pc.base';

  /// True: use the PC's look. False: [localAccent] / [localDark].
  bool followPc = true;
  Color localAccent = NvPalette.defaultAccent;
  bool localDark = true;

  Color pcAccent = NvPalette.defaultAccent;
  bool pcDark = true;
  Color? pcOnAccent;

  /// Bumped on every palette change; the app rebuilds every element on it.
  int revision = 0;

  Color get accent => followPc ? pcAccent : localAccent;
  bool get dark => followPc ? pcDark : localDark;
  NvPalette get palette => NvPalette.from(accent, dark ? Brightness.dark : Brightness.light, onAccent: followPc ? pcOnAccent : null);

  void _load() {
    followPc = _prefs.getBool(_kFollow) ?? true;
    localAccent = parseHexColor(_prefs.getString(_kAccent)) ?? NvPalette.defaultAccent;
    localDark = (_prefs.getString(_kBase) ?? 'dark') != 'light';
    pcAccent = parseHexColor(_prefs.getString(_kPcAccent)) ?? NvPalette.defaultAccent;
    pcDark = (_prefs.getString(_kPcBase) ?? 'dark') != 'light';
  }

  void _apply() {
    final p = palette;
    if (NV.palette.accent == p.accent && NV.palette.brightness == p.brightness && NV.palette.onAccent == p.onAccent && revision > 0) return;
    NV.palette = p;
    revision++;
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

  /// Local override (turns following the PC off).
  void setLocal({Color? accent, bool? dark}) {
    if (accent != null) localAccent = accent.withAlpha(255);
    if (dark != null) localDark = dark;
    followPc = false;
    _prefs
      ..setBool(_kFollow, false)
      ..setString(_kAccent, hexOf(localAccent))
      ..setString(_kBase, localDark ? 'dark' : 'light');
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
