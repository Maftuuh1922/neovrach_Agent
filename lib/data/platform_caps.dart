// What the current platform can do. Mobile (Android/iOS) keeps every
// feature; desktop builds (Linux/Windows/macOS) hide what their plugins
// cannot provide instead of crashing on a MissingPluginException.
import 'package:flutter/foundation.dart';

bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
bool get _macos => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
bool get _windows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// Running as a desktop app (Linux, Windows, macOS).
bool get isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Dictation (speech_to_text): mobile, web, macOS and Windows. Not Linux.
bool get canDictate => kIsWeb || _android || _ios || _macos || _windows;

/// Read-aloud (flutter_tts): mobile, web, macOS and Windows. Not Linux.
bool get canSpeak => kIsWeb || _android || _ios || _macos || _windows;

/// Taking a photo with the camera (image_picker): mobile only. Desktop can
/// still attach images from a file picker.
bool get canUseCamera => _android || _ios;

/// Phone tools over the 'neovarch/device' channel. Hidden on desktop, where
/// there is no native bridge; mobile/web behaviour is unchanged.
bool get offersDeviceTools => !isDesktop;
