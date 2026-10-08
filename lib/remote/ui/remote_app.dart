// The phone app: a remote for the Neovarch desktop. No local agent runtime,
// providers or keys here — every action goes to the desktop's gateway.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../state/app_controller.dart' show settingsProvider;
import '../../state/settings_controller.dart';
import '../../theme/neovarch_mobile_theme.dart';
import '../../ui/screens/startup_splash.dart';
import '../remote_controller.dart';
import '../saved_desktops.dart';
import 'connect_screen.dart';
import 'remote_intro_screen.dart';
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

/// Built once; the remote never switches themes.
final neovarchMobileTheme = buildNeovarchMobileTheme();

class RemoteNeovarchApp extends ConsumerWidget {
  const RemoteNeovarchApp({super.key, this.skipSplash = false});
  final bool skipSplash;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final remote = ref.watch(remoteProvider);
    final paired = remote.desktop != null || remote.desktops.items.isNotEmpty;
    return MaterialApp(
      title: 'Neovarch Remote',
      debugShowCheckedModeBanner: false,
      // The phone has one look (Neovarch dark red, rounded, flat): the
      // desktop theme presets / light mode do not apply to the remote.
      theme: neovarchMobileTheme,
      darkTheme: neovarchMobileTheme,
      themeMode: ThemeMode.dark,
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
