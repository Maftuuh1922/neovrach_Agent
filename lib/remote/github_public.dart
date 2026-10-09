// Profil without the PC's GitHub sign-in: the user's public GitHub profile by
// a username set on the phone. No token: name/bio/avatar from the public REST
// API, top languages from public repos, and the contribution graph parsed from
// the public page github.com/users/<login>/contributions (GraphQL's
// contributionsCollection needs a token). Cached in shared_preferences so the
// Profil tab still shows the last copy offline.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'social_models.dart';

/// Parses GitHub's public contributions HTML (`<td data-date data-level>`
/// cells plus `<tool-tip for=…>N contributions on …</tool-tip>` texts).
SocialHeatmap? parseContributionsHtml(String html) {
  final cell = RegExp(r'<td\b[^>]*>', caseSensitive: false);
  final attr = RegExp(r'([\w-]+)="([^"]*)"');
  final days = <String, (int level, String? id)>{};
  for (final m in cell.allMatches(html)) {
    final a = {for (final x in attr.allMatches(m.group(0)!)) x.group(1)!: x.group(2)!};
    final date = a['data-date'];
    if (date == null) continue;
    days[date] = (int.tryParse(a['data-level'] ?? '') ?? 0, a['id']);
  }
  if (days.isEmpty) return null;
  final tips = <String, int>{};
  for (final m in RegExp(r'<tool-tip\b[^>]*\bfor="([^"]+)"[^>]*>([^<]*)</tool-tip>').allMatches(html)) {
    final t = m.group(2)!.trim();
    final n = RegExp(r'^(\d[\d,]*)').firstMatch(t);
    tips[m.group(1)!] = n == null ? 0 : int.parse(n.group(1)!.replaceAll(',', ''));
  }
  final dates = days.keys.toList()..sort();
  final start = DateTime.parse(dates.first), end = DateTime.parse(dates.last);
  final counts = <int>[];
  for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
    final key = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final v = days[key];
    if (v == null) {
      counts.add(0);
    } else {
      // exact count from the tooltip when present, else the 0..4 level
      counts.add(v.$2 != null && tips.containsKey(v.$2) ? tips[v.$2]! : v.$1);
    }
  }
  var streak = 0;
  for (var i = counts.length - 1; i >= 0 && counts[i] > 0; i--) {
    streak++;
  }
  if (streak == 0 && counts.length > 1) {
    // today may have nothing yet; count from yesterday
    for (var i = counts.length - 2; i >= 0 && counts[i] > 0; i--) {
      streak++;
    }
  }
  final max = counts.fold(0, (a, b) => a > b ? a : b);
  return SocialHeatmap(
    start: dates.first,
    end: dates.last,
    counts: counts,
    total: counts.fold(0, (a, b) => a + b),
    activeDays: counts.where((c) => c > 0).length,
    streak: streak,
    max: max,
  );
}

/// Top languages of public, non-fork repos as stack items (share of repos).
List<StackItem> languagesFromRepos(List<dynamic> repos, {int top = 8}) {
  final n = <String, int>{};
  for (final r in repos.whereType<Map>()) {
    if (r['fork'] == true) continue;
    final l = r['language'];
    if (l is String && l.isNotEmpty) n[l] = (n[l] ?? 0) + 1;
  }
  final total = n.values.fold(0, (a, b) => a + b);
  final items = n.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return [for (final e in items.take(top)) StackItem(e.key, total == 0 ? 0 : e.value / total, source: 'github', count: e.value)];
}

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&#x27;', "'")
    .replaceAll('\u200b', '');

int _count(String s) {
  final t = s.trim().toLowerCase().replaceAll(',', '');
  if (t.endsWith('k')) return ((double.tryParse(t.substring(0, t.length - 1)) ?? 0) * 1000).round();
  return int.tryParse(t) ?? 0;
}

/// Parses the pinned repositories from the public profile page
/// `github.com/<login>` (`li.pinned-item-list-item` cards). Empty when none.
List<PinnedRepo> parsePinnedReposHtml(String html) {
  final out = <PinnedRepo>[];
  final starts = RegExp(r'<li\b[^>]*class="[^"]*\bpinned-item-list-item\b[^"]*"', caseSensitive: false).allMatches(html).map((m) => m.start).toList();
  for (var i = 0; i < starts.length && out.length < 6; i++) {
    final end = i + 1 < starts.length ? starts[i + 1] : (html.indexOf('</ol>', starts[i]) < 0 ? html.length : html.indexOf('</ol>', starts[i]));
    final b = html.substring(starts[i], end);
    final link = RegExp(r'''href="/([^/"]+)/([^/"]+)"[^>]*>\s*(?:<span class="owner[^"]*"[^>]*>[^<]*</span>\s*/?\s*)?<span class="repo"[^>]*>([^<]*)</span>''', dotAll: true).firstMatch(b);
    if (link == null) continue;
    final owner = _unescape(link.group(1)!), repo = _unescape(link.group(2)!);
    final desc = RegExp(r'<p class="pinned-item-desc[^"]*"[^>]*>(.*?)</p>', dotAll: true).firstMatch(b)?.group(1) ?? '';
    final lang = RegExp(r'itemprop="programmingLanguage"[^>]*>([^<]*)<').firstMatch(b)?.group(1);
    final color = RegExp(r'repo-language-color"[^>]*style="background-color:\s*(#[0-9a-fA-F]{3,8})').firstMatch(b)?.group(1);
    int meta(String kind) {
      final m = RegExp('href="/[^"]+/$kind"[^>]*>(.*?)</a>', dotAll: true).firstMatch(b);
      if (m == null) return 0;
      return _count(m.group(1)!.replaceAll(RegExp(r'<[^>]*>', dotAll: true), ''));
    }

    out.add(PinnedRepo(
      name: repo,
      owner: owner,
      description: _unescape(desc.replaceAll(RegExp(r'<[^>]*>'), '')).replaceAll(RegExp(r'\s+'), ' ').trim(),
      language: lang == null || lang.trim().isEmpty ? null : _unescape(lang.trim()),
      languageColor: color,
      stars: meta('stargazers'),
      forks: meta('forks'),
      url: 'https://github.com/$owner/$repo',
    ));
  }
  return out;
}

/// No pins: the top-starred public non-fork repos from the REST repos list.
List<PinnedRepo> pinnedFromRepos(List<dynamic> repos, {int top = 6}) {
  final list = [for (final r in repos.whereType<Map>()) if (r['fork'] != true) Map<String, dynamic>.from(r)]
    ..sort((a, b) {
      final s = ((b['stargazers_count'] as num?) ?? 0).compareTo((a['stargazers_count'] as num?) ?? 0);
      return s != 0 ? s : '${b['pushed_at'] ?? ''}'.compareTo('${a['pushed_at'] ?? ''}');
    });
  return [
    for (final r in list.take(top))
      PinnedRepo(
        name: '${r['name'] ?? ''}',
        owner: (r['owner'] is Map ? '${(r['owner'] as Map)['login'] ?? ''}' : null),
        description: '${r['description'] ?? ''}',
        language: r['language'] is String ? r['language'] as String : null,
        stars: ((r['stargazers_count'] as num?) ?? 0).toInt(),
        forks: ((r['forks_count'] as num?) ?? 0).toInt(),
        url: '${r['html_url'] ?? ''}',
      ),
  ];
}

Map<String, dynamic> _heatJson(SocialHeatmap h) =>
    {'start': h.start, 'end': h.end, 'counts': h.counts, 'total': h.total, 'active_days': h.activeDays, 'streak': h.streak, 'max': h.max};

/// Fetches and caches the public profile for [login].
class GithubPublicController extends ChangeNotifier {
  GithubPublicController({SharedPreferences? prefs, http.Client? client, Future<SharedPreferences> Function()? prefsLoader})
      : _prefs = prefs,
        _client = client, // ignore: prefer_initializing_formals
        _prefsLoader = prefsLoader ?? SharedPreferences.getInstance {
    if (prefs != null) _readCache(prefs);
  }

  static const kLogin = 'nv.github.login', kCache = 'nv.github.cache';
  SharedPreferences? _prefs;
  final http.Client? _client;
  final Future<SharedPreferences> Function() _prefsLoader;

  String? login;
  SocialProfile? profile;
  DateTime? fetchedAt;
  bool loading = false;
  String? error;

  Future<SharedPreferences> _p() async => _prefs ??= await _prefsLoader();

  void _readCache(SharedPreferences p) {
    login = p.getString(kLogin);
    final raw = p.getString(kCache);
    if (raw == null) return;
    try {
      final j = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (j['login'] != login) return;
      profile = SocialProfile.fromJson(Map<String, dynamic>.from(j['profile'] as Map));
      fetchedAt = DateTime.tryParse('${j['at']}');
    } catch (_) {}
  }

  /// Loads the saved username and cache (call once; cheap).
  Future<void> load() async {
    if (login != null || profile != null) return;
    _readCache(await _p());
    notifyListeners();
  }

  Future<void> setLogin(String? value) async {
    final v = value?.trim().replaceFirst(RegExp(r'^@'), '');
    final p = await _p();
    if (v == null || v.isEmpty) {
      login = null;
      profile = null;
      await p.remove(kLogin);
      await p.remove(kCache);
      notifyListeners();
      return;
    }
    if (v != login) {
      login = v;
      profile = null;
      await p.setString(kLogin, v);
    }
    notifyListeners();
    await refresh();
  }

  Future<void> refresh() async {
    final l = login;
    if (l == null || loading) return;
    loading = true;
    error = null;
    notifyListeners();
    final c = _client ?? http.Client();
    try {
      final enc = Uri.encodeComponent(l);
      final headers = {'Accept': 'application/vnd.github+json', 'User-Agent': 'Neovarch-Remote'};
      final res = await Future.wait([
        c.get(Uri.parse('https://api.github.com/users/$enc'), headers: headers),
        c.get(Uri.parse('https://github.com/users/$enc/contributions'), headers: {'User-Agent': 'Neovarch-Remote'}),
        c.get(Uri.parse('https://api.github.com/users/$enc/repos?per_page=100&sort=pushed'), headers: headers),
        c.get(Uri.parse('https://github.com/$enc'), headers: {'User-Agent': 'Neovarch-Remote'}).catchError((_) => http.Response('', 599)),
      ]).timeout(const Duration(seconds: 20));
      if (res[0].statusCode == 404) throw 'Akun GitHub "$l" tidak ditemukan.';
      if (res[0].statusCode != 200) throw 'GitHub menjawab ${res[0].statusCode}.';
      final u = Map<String, dynamic>.from(jsonDecode(res[0].body) as Map);
      final heat = res[1].statusCode == 200 ? parseContributionsHtml(res[1].body) : null;
      final repos = res[2].statusCode == 200 ? jsonDecode(res[2].body) as List : null;
      final langs = repos != null ? languagesFromRepos(repos) : const <StackItem>[];
      var pinned = res[3].statusCode == 200 ? parsePinnedReposHtml(res[3].body) : const <PinnedRepo>[];
      if (pinned.isEmpty && repos != null) pinned = pinnedFromRepos(repos);
      if (pinned.isEmpty) pinned = profile?.pinned ?? const [];
      final j = {
        'login': u['login'] ?? l,
        'name': u['name'],
        'bio': u['bio'] ?? '',
        'avatar_url': u['avatar_url'],
        'html_url': u['html_url'],
        'heatmap': heat == null ? (profile?.heatmap == null ? null : _heatJson(profile!.heatmap!)) : _heatJson(heat),
        'stack': {
          'languages': [for (final s in langs) {'name': s.name, 'share': s.share, 'source': s.source, 'count': s.count}],
        },
        'pinned': [for (final r in pinned) r.toJson()],
      };
      profile = SocialProfile.fromJson(j);
      fetchedAt = DateTime.now();
      await (await _p()).setString(kCache, jsonEncode({'login': l, 'at': fetchedAt!.toIso8601String(), 'profile': j}));
    } catch (e) {
      error = profile == null ? 'Tidak bisa memuat GitHub ($e).' : 'Offline: menampilkan salinan terakhir.';
    } finally {
      if (_client == null) c.close();
      loading = false;
      notifyListeners();
    }
  }
}

final githubPublicProvider = ChangeNotifierProvider<GithubPublicController>((ref) => GithubPublicController());
