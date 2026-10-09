// 1.4.2: launcher icon colour, switched from Profil → Ikon aplikasi.
//
// Android side: one <activity-alias> per variant (AndroidManifest.xml), only
// one enabled at a time, toggled by MainActivity "setLauncherIcon" with
// PackageManager.setComponentEnabledSetting(DONT_KILL_APP). Artwork:
// /workspace/work/nva142_icon/make_icon_variants.py (assets/app_icons/*.png
// are the in-app previews).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/device_tools.dart' show deviceCall, DeviceUnavailable;
import 'appearance.dart';

/// id (alias suffix + asset name), label, representative accent.
const appIconVariants = <(String, String, Color)>[
  ('merah', 'Merah', Color(0xFFEE1C1C)),
  ('biru', 'Biru', Color(0xFF2563EB)),
  ('ungu', 'Ungu', Color(0xFF7C3AED)),
  ('toska', 'Toska', Color(0xFF0D9488)),
  ('hijau', 'Hijau', Color(0xFF16A34A)),
  ('oranye', 'Oranye', Color(0xFFEA580C)),
  ('monokrom', 'Monokrom', Color(0xFFA3A3A3)),
];

String appIconAsset(String id) => 'assets/app_icons/$id.png';

/// The variant closest to [accent]: Monokrom for greys, otherwise the
/// nearest hue (circular distance).
String nearestAppIcon(Color accent) {
  final h = HSLColor.fromColor(accent);
  if (h.saturation < 0.18 || h.lightness < 0.08 || h.lightness > 0.94) return 'monokrom';
  String best = 'merah';
  var bestD = 999.0;
  for (final (id, _, c) in appIconVariants) {
    if (id == 'monokrom') continue;
    final d0 = (HSLColor.fromColor(c).hue - h.hue).abs();
    final d = d0 > 180 ? 360 - d0 : d0;
    if (d < bestD) {
      bestD = d;
      best = id;
    }
  }
  return best;
}

typedef AppIconChannel = Future<String?> Function(String method, Map<String, dynamic>? args);

class AppIconController extends ChangeNotifier {
  AppIconController(this._prefs, {AppIconChannel? channel}) : _channel = channel ?? _device {
    current = _prefs.getString(_kId) ?? 'merah';
    followAccent = _prefs.getBool(_kFollow) ?? false;
  }
  final SharedPreferences _prefs;
  final AppIconChannel _channel;
  static const _kId = 'nv.icon.id';
  static const _kFollow = 'nv.icon.follow';

  static Future<String?> _device(String m, Map<String, dynamic>? a) => deviceCall<String>(m, a);

  String current = 'merah';
  bool followAccent = false;
  /// Last error from the platform side (e.g. not on Android).
  String? error;

  /// Reads the enabled alias from Android (the launcher is the truth).
  Future<void> sync() async {
    try {
      final id = await _channel('launcherIcon', null);
      if (id != null && id != current) {
        current = id;
        await _prefs.setString(_kId, id);
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Switches the launcher icon; null on success, else a message.
  Future<String?> select(String id, {bool fromFollow = false}) async {
    if (!fromFollow && followAccent) {
      followAccent = false;
      await _prefs.setBool(_kFollow, false);
    }
    if (id == current && error == null) {
      notifyListeners();
      return null;
    }
    try {
      await _channel('setLauncherIcon', {'id': id});
      current = id;
      error = null;
      await _prefs.setString(_kId, id);
    } catch (e) {
      error = e is DeviceUnavailable ? e.message : '$e';
    }
    notifyListeners();
    return error;
  }

  Future<void> setFollowAccent(bool v, Color accent) async {
    followAccent = v;
    await _prefs.setBool(_kFollow, v);
    notifyListeners();
    if (v) await select(nearestAppIcon(accent), fromFollow: true);
  }

  /// Called when the accent changes.
  Future<void> onAccent(Color accent) async {
    if (followAccent) await select(nearestAppIcon(accent), fromFollow: true);
  }
}

final appIconProvider = ChangeNotifierProvider<AppIconController>((ref) {
  final look = ref.read(appearanceProvider);
  final c = AppIconController(look.prefs);
  var last = look.accent.toARGB32();
  void onLook() {
    final a = look.accent.toARGB32();
    if (a != last) {
      last = a;
      c.onAccent(look.accent);
    }
  }

  look.addListener(onLook);
  ref.onDispose(() => look.removeListener(onLook));
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) c.sync();
  return c;
});
