// "Update tersedia" for the phone app: GitHub Releases API
// (`releases/latest`), with the PC core's cached check (`/api/update`) as the
// fallback when GitHub is unreachable (rate limit, no internet but LAN).
// Compares against THIS app's version, not the PC's. Pure Dart.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../state/settings_controller.dart';

const githubRepo = 'Maftuuh1922/neovrach_Agent';
const releasesPage = 'https://github.com/$githubRepo/releases/latest';

List<int> parseVersion(String v) {
  final m = RegExp(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?').firstMatch(v.trim().replaceFirst(RegExp(r'^[vV]'), ''));
  if (m == null) return const [0, 0, 0];
  return [for (var i = 1; i <= 3; i++) int.tryParse(m.group(i) ?? '0') ?? 0];
}

bool isNewerVersion(String latest, String current) {
  final a = parseVersion(latest), b = parseVersion(current);
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

/// Android asset: an arm64 split APK first, then any APK.
String? pickApk(List assets) {
  final apks = [
    for (final a in assets.whereType<Map>())
      if ('${a['name'] ?? ''}'.toLowerCase().endsWith('.apk')) a,
  ];
  final arm = apks.where((a) => '${a['name']}'.toLowerCase().contains('arm64')).firstOrNull;
  final pick = arm ?? apks.where((a) => !'${a['name']}'.toLowerCase().contains('x86')).firstOrNull ?? apks.firstOrNull;
  return pick?['browser_download_url'] as String?;
}

class UpdateChecker {
  UpdateChecker({http.Client? client, this.current = SettingsController.appVersion, this.minInterval = const Duration(hours: 6)})
      : _client = client ?? http.Client();
  final http.Client _client;
  final String current;
  final Duration minInterval;
  DateTime? _lastAt;
  Map<String, dynamic>? _last;

  /// `{current, latest, available, url, download_url, source}` or null when
  /// neither GitHub nor the PC answered.
  Future<Map<String, dynamic>?> check({Future<Map<String, dynamic>> Function()? fallback, bool force = false}) async {
    if (!force && _last != null && _lastAt != null && DateTime.now().difference(_lastAt!) < minInterval) return _last;
    Map<String, dynamic>? r;
    try {
      final res = await _client.get(Uri.parse('https://api.github.com/repos/$githubRepo/releases/latest'),
          headers: const {'Accept': 'application/vnd.github+json', 'User-Agent': 'neovarch-remote'}).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map;
        final tag = '${j['tag_name'] ?? ''}';
        final latest = tag.replaceFirst(RegExp(r'^[vV]'), '');
        if (latest.isNotEmpty) {
          final url = '${j['html_url'] ?? releasesPage}';
          r = {
            'current': current,
            'latest': latest,
            'available': isNewerVersion(latest, current),
            'url': url,
            'download_url': pickApk(j['assets'] as List? ?? const []) ?? url,
            'source': 'github',
          };
        }
      }
    } catch (_) {}
    if (r == null && fallback != null) {
      try {
        final u = await fallback();
        final latest = '${u['latest'] ?? ''}';
        if (latest.isNotEmpty && latest != 'null') {
          r = {
            'current': current,
            'latest': latest,
            'available': isNewerVersion(latest, current),
            'url': '${u['url'] ?? releasesPage}',
            'download_url': '${u['download_url'] ?? u['url'] ?? releasesPage}',
            'source': 'pc',
          };
        }
      } catch (_) {}
    }
    if (r != null) {
      _last = r;
      _lastAt = DateTime.now();
    }
    return r;
  }
}
