// Kartu Neovarch: where the card PNG can go. A fixed list of the apps people
// actually post to (Instagram Story / feed, WhatsApp, TikTok, X, Facebook,
// Telegram); only the installed ones are shown, and anything that fails falls
// back to the system share sheet. Pure Dart so the selection is unit-tested
// with a fake package list; the Android side lives in MainActivity.kt
// ("installedPackages", "shareImage" with `package` / `mode`).

/// How the card is handed to the target app.
enum ShareMode {
  /// ACTION_SEND with the PNG, restricted to the app's package.
  send,

  /// Instagram's `com.instagram.share.ADD_TO_STORY` (background image).
  igStory,
}

class ShareTarget {
  const ShareTarget({required this.id, required this.label, required this.packages, this.mode = ShareMode.send, this.hint});

  /// Stable key ("ig-story", "whatsapp", …) used for widget keys and tests.
  final String id;
  final String label;

  /// Candidate packages, first installed one wins (e.g. WhatsApp, then WA Business).
  final List<String> packages;
  final ShareMode mode;

  /// Short line under the label ("Status ada di daftar WhatsApp").
  final String? hint;
}

/// Order = order of the buttons.
const kShareTargets = <ShareTarget>[
  ShareTarget(id: 'ig-story', label: 'IG Story', packages: ['com.instagram.android'], mode: ShareMode.igStory),
  ShareTarget(id: 'ig-feed', label: 'Instagram', packages: ['com.instagram.android']),
  ShareTarget(id: 'whatsapp', label: 'WhatsApp', packages: ['com.whatsapp', 'com.whatsapp.w4b'], hint: 'Pilih "Status saya" untuk WA Status'),
  ShareTarget(id: 'tiktok', label: 'TikTok', packages: ['com.zhiliaoapp.musically', 'com.ss.android.ugc.trill']),
  ShareTarget(id: 'x', label: 'X', packages: ['com.twitter.android']),
  ShareTarget(id: 'facebook', label: 'Facebook', packages: ['com.facebook.katana', 'com.facebook.lite']),
  ShareTarget(id: 'telegram', label: 'Telegram', packages: ['org.telegram.messenger', 'org.telegram.messenger.web', 'org.thunderdog.challegram']),
];

/// Every package the manifest's `<queries>` must list (kept in sync by a test).
List<String> get kShareTargetPackages => {for (final t in kShareTargets) ...t.packages}.toList();

/// A target resolved against what is installed: the package to send to.
class ResolvedShareTarget {
  const ResolvedShareTarget(this.target, this.package);
  final ShareTarget target;
  final String package;
  String get id => target.id;
  String get label => target.label;
  ShareMode get mode => target.mode;
}

/// The buttons to show for [installed] (package names reported by Android).
List<ResolvedShareTarget> availableShareTargets(Iterable<String> installed) {
  final have = installed.toSet();
  return [
    for (final t in kShareTargets)
      if (t.packages.any(have.contains)) ResolvedShareTarget(t, t.packages.firstWhere(have.contains)),
  ];
}

/// Channel arguments for "shareImage". No package = the system chooser.
Map<String, Object?> shareImageArgs({required String path, required String text, ResolvedShareTarget? target}) => {
      'path': path,
      'mime': 'image/png',
      'text': text,
      'title': 'Bagikan Kartu Neovarch',
      if (target != null) 'package': target.package,
      if (target != null) 'mode': target.mode == ShareMode.igStory ? 'ig-story' : 'send',
    };

/// What the Android side answered: "shared" (went to the app), "chooser"
/// (fell back to the system sheet) or an error string.
bool shareFellBack(Object? result) => result == 'chooser';
