import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/kv_store.dart';
import 'data/local_store.dart';
import 'models/models.dart';
import 'state/app_controller.dart';
import 'state/settings_controller.dart';
import 'theme/app_theme.dart';
import 'theme/nv_themes.dart';
import 'ui/app_shell.dart';
import 'ui/screens/intro_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/startup_splash.dart';
import 'ui/widgets/brand.dart';
import 'ui/widgets/office_snapshot.dart';
import 'data/agent_runtime.dart';
import 'remote/pairing.dart';
import 'remote/saved_desktops.dart';
import 'remote/ui/remote_app.dart';

/// Product split: the phone is ONLY a remote for the Neovarch desktop app
/// (which runs the agent). Android/iOS → RemoteApp. Other platforms keep the
/// legacy standalone Flutter app (not the shipped desktop product). The web
/// build shows the remote with `?app=remote` (screenshots / preview).
bool get isPhoneRemote =>
    kIsWeb ? Uri.base.queryParameters['app'] == 'remote' : (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = true;
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsController(prefs);
  await settings.load();
  _applyPreviewParams(settings);
  if (isPhoneRemote) {
    await _applyRemotePreview(prefs);
    await runRemoteApp(
        prefs: prefs, settings: settings, skipSplash: skipSplash, openSession: kIsWeb ? Uri.base.queryParameters['open'] : null);
    return;
  }
  final kv = await KvStore.open();
  final store = LocalStore(kv);
  await store.load();
  final app = AppController(kv: kv, store: store, settings: settings);
  // office_view tool: let the agent see the rendered office.
  AgentRuntime.officeSnapshot = () => renderOfficeSnapshot(app.officeCtl);
  runApp(ProviderScope(
    overrides: [
      appProvider.overrideWith((ref) => app),
      settingsProvider.overrideWith((ref) => settings),
      storeProvider.overrideWith((ref) => store),
      officeProvider.overrideWith((ref) => app.officeCtl),
      chatProvider.overrideWith((ref) => app.chatCtl),
    ],
    child: const NeovarchApp(),
  ));
}

/// Web preview only: `?preview=1&mode=demo&theme=neovarch&dark=1&tab=1` lets a
/// static web build show a given state (used for screenshots / demos).
/// Ignored on Android.
int previewTab = 0;
int previewSlide = 0;
bool skipSplash = false;
void _applyPreviewParams(SettingsController s) {
  if (!kIsWeb) return;
  final q = Uri.base.queryParameters;
  if (q['preview'] != '1') return;
  skipSplash = q['splash'] != '1';
  s.onboarded = q['onboard'] != '1';
  s.introSeen = q['intro'] != '1';
  previewSlide = int.tryParse(q['slide'] ?? '') ?? 0;
  s.mode = ConnectionMode.values.firstWhere((m) => m.name == q['mode'], orElse: () => s.mode);
  if (q['theme'] != null) s.themeName = q['theme']!;
  if (q['dark'] != null) s.themeMode = q['dark'] == '1' ? ThemeMode.dark : ThemeMode.light;
  previewTab = int.tryParse(q['tab'] ?? '') ?? 0;
  final llm = q['llm'];
  if (llm != null && llm.startsWith('http')) {
    final p = ProviderConfig(id: 'preview', label: 'Pratinjau lokal', baseUrl: llm, model: q['model'] ?? 'neovarch-mock');
    s.providers = [p, ...s.providers.where((x) => x.id != 'preview')];
    s.activeProviderId = 'preview';
  }
  s.resumeLastSession = false;
}

/// Web preview of the remote: `?app=remote&preview=1&gw=<pairing or url>&token=…`
/// pre-pairs a desktop so screenshots open straight on the remote shell.
Future<void> _applyRemotePreview(SharedPreferences prefs) async {
  if (!kIsWeb) return;
  final q = Uri.base.queryParameters;
  final gw = q['gw'];
  if (q['preview'] != '1' || gw == null) return;
  final p = GatewayPairing.parse(gw);
  if (p == null) return;
  await (SavedDesktops(prefs)..load()).upsert(p.copyWith(token: q['token'] ?? p.token, name: q['name']));
}

class NeovarchApp extends ConsumerWidget {
  const NeovarchApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final theme = themeByName(s.themeName);
    return MaterialApp(
      title: 'Neovarch Agent',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(theme, Brightness.light, fontChoice: s.fontChoice),
      darkTheme: buildTheme(theme, Brightness.dark, fontChoice: s.fontChoice),
      themeMode: theme.darkOnly ? ThemeMode.dark : s.themeMode,
      // Brand theme: the site's fine paper grain over everything.
      builder: theme.brand
          ? (context, child) => Stack(children: [child!, const Positioned.fill(child: GrainOverlay())])
          : null,
      home: !s.introSeen
          ? IntroScreen(initialPage: previewSlide)
          : StartupSplash(
              enabled: !skipSplash,
              child: s.onboarded ? const AppShell() : const OnboardingScreen(),
            ),
    );
  }
}
