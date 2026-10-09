// "Hey Neo" wake word (opt-in). Android only: a microphone foreground
// service (NvWakeService.kt) listens offline with Vosk for exactly the phrase
// "hey neo" and opens Chat dictation. The ~40 MB English model is downloaded
// the first time it is switched on. After a reboot Android 11+ does not let it
// restart with the microphone, so a notification asks for one tap
// (`nv_route=wake`, handled by RemoteShell -> [WakeWordController.resume]).
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/device_tools.dart';

class WakeWordStatus {
  const WakeWordStatus({this.enabled = false, this.state = 'off', this.modelReady = false});
  factory WakeWordStatus.fromMap(Map<dynamic, dynamic>? m) => WakeWordStatus(
        enabled: m?['enabled'] == true,
        state: '${m?['state'] ?? 'off'}',
        modelReady: m?['modelReady'] == true,
      );
  final bool enabled;
  /// `off`, `downloading`, `listening`, `stopped` or `error:` + reason
  final String state;
  final bool modelReady;

  String get label {
    if (!enabled) return 'Mati';
    if (state == 'downloading') return 'Mengunduh model suara…';
    if (state == 'listening') return 'Mendengarkan "Hey Neo"';
    if (state == 'stopped') return 'Berhenti (ketuk notifikasi atau nyalakan lagi)';
    if (state.startsWith('error:')) return 'Gagal: ${state.substring(6)}';
    return 'Menyiapkan…';
  }
}

/// Talks to the native side over `neovarch/device` (`wakeWord`, `wakeStatus`).
class WakeWordController extends ChangeNotifier {
  WakeWordController({
    Future<Object?> Function(String method, [Map<String, dynamic>? args])? call,
    Future<bool> Function()? permissions,
  })  : _call = call ?? _deviceCall,
        _permissions = permissions ?? _askPermissions;

  final Future<Object?> Function(String method, [Map<String, dynamic>? args]) _call;
  final Future<bool> Function() _permissions;

  WakeWordStatus status = const WakeWordStatus();
  String? error;
  bool busy = false;

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<Object?> _deviceCall(String method, [Map<String, dynamic>? args]) => deviceCall<Object?>(method, args);

  // Microphone (required) and notifications (the "ketuk untuk bicara" and
  // restart prompts; Android 13+). Only the microphone decides.
  static Future<bool> _askPermissions() async {
    final mic = await ensurePermissions(const ['android.permission.RECORD_AUDIO']);
    try {
      await ensurePermissions(const ['android.permission.POST_NOTIFICATIONS']);
    } catch (_) {}
    return mic;
  }

  Future<void> refresh() async {
    try {
      status = WakeWordStatus.fromMap(await _call('wakeStatus') as Map?);
      error = null;
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  /// Opt-in switch. Turning on asks for the microphone first.
  Future<void> setEnabled(bool on) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (on && !await _permissions()) {
        error = 'Izin mikrofon ditolak. Izinkan di Setelan → Aplikasi → Neovarch Agent → Izin.';
        return;
      }
      status = WakeWordStatus.fromMap(await _call('wakeWord', {'enable': on}) as Map?);
    } catch (e) {
      error = '$e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// From the after-reboot notification: start again from the foreground.
  Future<void> resume() async {
    await refresh();
    if (status.enabled) await setEnabled(true);
  }
}

final wakeWordProvider = ChangeNotifierProvider<WakeWordController>((ref) => WakeWordController());
