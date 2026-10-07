// Voice: dictation (speech_to_text) and read-back (flutter_tts), like
// Desktop's mic + "Read replies aloud" toggle.
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceService extends ChangeNotifier {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  final SpeechToText _stt = SpeechToText();
  FlutterTts? _tts;
  bool _sttReady = false;
  bool listening = false;
  bool speaking = false;
  String? error;

  Future<bool> _initStt() async {
    if (_sttReady) return true;
    try {
      _sttReady = await _stt.initialize(
        onError: (e) {
          error = e.errorMsg;
          listening = false;
          notifyListeners();
        },
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            listening = false;
            notifyListeners();
          }
        },
      );
    } catch (e) {
      error = 'pengenalan suara tidak tersedia: $e';
      _sttReady = false;
    }
    return _sttReady;
  }

  Future<void> startDictation({required String locale, required void Function(String text, bool isFinal) onText}) async {
    error = null;
    if (!await _initStt()) {
      error ??= 'pengenalan suara tidak tersedia di perangkat ini';
      notifyListeners();
      return;
    }
    listening = true;
    notifyListeners();
    await _stt.listen(
      onResult: (SpeechRecognitionResult r) => onText(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
        localeId: locale,
        pauseFor: const Duration(seconds: 4),
        listenFor: const Duration(minutes: 2),
      ),
    );
  }

  Future<void> stopDictation() async {
    await _stt.stop();
    listening = false;
    notifyListeners();
  }

  Future<void> speak(String text, {String language = 'id-ID', double rate = 0.5}) async {
    try {
      _tts ??= FlutterTts();
      final t = _tts!;
      t.setCompletionHandler(() {
        speaking = false;
        notifyListeners();
      });
      await t.setLanguage(language);
      await t.setSpeechRate(rate);
      speaking = true;
      notifyListeners();
      await t.speak(_plain(text));
    } catch (e) {
      speaking = false;
      error = 'pembacaan suara gagal: $e';
      notifyListeners();
    }
  }

  Future<void> stopSpeaking() async {
    await _tts?.stop();
    speaking = false;
    notifyListeners();
  }

  /// Strip markdown and code so TTS reads prose, not syntax.
  static String _plain(String md) => md
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' (blok kode) ')
      .replaceAll(RegExp(r'`([^`]*)`'), r'$1')
      .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
      .replaceAll(RegExp(r'[#*_>~|]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
