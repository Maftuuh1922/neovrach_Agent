// The phone app: a remote for the Neovarch desktop. No local agent runtime,
// providers or keys here — every action goes to the desktop's gateway.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../state/app_controller.dart' show settingsProvider;
import '../../state/settings_controller.dart';
import '../../theme/neovarch_mobile_theme.dart';
import '../../ui/screens/startup_splash.dart';
import '../appearance.dart';
import '../remote_controller.dart';
import '../saved_desktops.dart';
import 'connect_screen.dart';
import 'remote_intro_screen.dart';
import 'remote_shell.dart';

Future<void> runRemoteApp(
    {required SharedPreferences prefs, required SettingsController settings, bool skipSplash = false, String? openSession}) async {
  final desktops = SavedDesktops(prefs)..load();
  final remote = RemoteController(desktops);
  final look = AppearanceController(prefs);
  remote.onAppearance = look.applyPc;
  runApp(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((ref) => settings),
      remoteProvider.overrideWith((ref) => remote),
      appearanceProvider.overrideWith((ref) => look),
    ],
    child: RemoteNeovarchApp(skipSplash: skipSplash),
  ));
  await remote.start();
  // Web preview: open a stored session straight away.
  if (openSession != null && remote.connected) await remote.openSession(openSession);
}

ThemeData? _theme;
int _themeRev = -1;

/// Rebuilt only when the palette changes (PC appearance / local override).
ThemeData themeFor(AppearanceController look) {
  if (_theme == null || _themeRev != look.revision) {
    _theme = buildNeovarchMobileTheme();
    _themeRev = look.revision;
  }
  return _theme!;
}

class RemoteNeovarchApp extends ConsumerWidget {
  const RemoteNeovarchApp({super.key, this.skipSplash = false});
  final bool skipSplash;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final remote = ref.watch(remoteProvider);
    final look = ref.watch(appearanceProvider);
    final paired = remote.desktop != null || remote.desktops.items.isNotEmpty;
    final theme = themeFor(look);
    return MaterialApp(
      title: 'Neovarch Remote',
      debugShowCheckedModeBanner: false,
      // Follows the PC's look (accent + dark/light) unless overridden on the
      // phone; flat, rounded, no gradients/shadows/glow in every variant.
      theme: theme,
      darkTheme: theme,
      themeMode: look.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => PaletteScope(revision: look.revision, child: child!),
      home: !s.introSeen
          ? const RemoteIntroScreen()
          : StartupSplash(
              enabled: !skipSplash,
              background: NV.bg,
              foreground: NV.text,
              accent: NV.red,
              child: paired ? const RemoteShell() : const ConnectScreen(onboarding: true),
            ),
    );
  }
}

/// Repaints the whole tree (state kept) when the palette revision changes.
class PaletteScope extends StatefulWidget {
  const PaletteScope({super.key, required this.revision, required this.child});
  final int revision;
  final Widget child;
  @override
  State<PaletteScope> createState() => _PaletteScopeState();
}

class _PaletteScopeState extends State<PaletteScope> {
  @override
  void didUpdateWidget(PaletteScope old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) rebuildAllChildren(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The current palette's theme (tests / previews).
ThemeData get neovarchMobileTheme => buildNeovarchMobileTheme();
