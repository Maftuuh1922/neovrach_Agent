// The phone app: a remote for the Neovarch desktop. No local agent runtime,
// providers or keys here — every action goes to the desktop's gateway.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../state/app_controller.dart' show settingsProvider;
import '../../state/settings_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/hermes_themes.dart';
import '../../ui/screens/intro_screen.dart';
import '../../ui/screens/startup_splash.dart';
import '../../ui/widgets/brand.dart';
import '../remote_controller.dart';
import '../saved_desktops.dart';
import 'connect_screen.dart';
import 'remote_shell.dart';

Future<void> runRemoteApp(
    {required SharedPreferences prefs, required SettingsController settings, bool skipSplash = false, String? openSession}) async {
  final desktops = SavedDesktops(prefs)..load();
  final remote = RemoteController(desktops);
  runApp(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((ref) => settings),
      remoteProvider.overrideWith((ref) => remote),
    ],
    child: RemoteNeovarchApp(skipSplash: skipSplash),
  ));
  await remote.start();
  // Web preview: open a stored session straight away.
  if (openSession != null && remote.connected) await remote.openSession(openSession);
}

class RemoteNeovarchApp extends ConsumerWidget {
  const RemoteNeovarchApp({super.key, this.skipSplash = false});
  final bool skipSplash;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final remote = ref.watch(remoteProvider);
    final theme = themeByName(s.themeName);
    final paired = remote.desktop != null || remote.desktops.items.isNotEmpty;
    return MaterialApp(
      title: 'Neovarch Remote',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(theme, Brightness.light, fontChoice: s.fontChoice),
      darkTheme: buildTheme(theme, Brightness.dark, fontChoice: s.fontChoice),
      themeMode: theme.darkOnly ? ThemeMode.dark : s.themeMode,
      builder: theme.brand ? (context, child) => Stack(children: [child!, const Positioned.fill(child: GrainOverlay())]) : null,
      home: !s.introSeen
          ? const IntroScreen()
          : StartupSplash(
              enabled: !skipSplash,
              child: paired ? const RemoteShell() : const ConnectScreen(onboarding: true),
            ),
    );
  }
}
