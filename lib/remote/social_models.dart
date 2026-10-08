// Friends & profile via GitHub, as the PC core serves them (/api/social/*).
// The phone needs no GitHub login of its own: it reads everything through the
// paired PC. Pure Dart.

int _i(Object? v, [int d = 0]) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? d;
double _d(Object? v, [double d = 0]) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? d;
String? _s(Object? v) => v == null || '$v'.isEmpty ? null : '$v';
Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};

class SocialHeatmap {
  const SocialHeatmap({required this.start, required this.end, required this.counts, this.total = 0, this.activeDays = 0, this.streak = 0, this.max = 0});
  final String start;
  final String end;
  final List<int> counts;
  final int total, activeDays, streak, max;

  factory SocialHeatmap.fromJson(Map<String, dynamic> j) {
    final counts = [for (final c in (j['counts'] as List? ?? const [])) _i(c)];
    final max = j['max'] != null ? _i(j['max']) : (counts.isEmpty ? 0 : counts.reduce((a, b) => a > b ? a : b));
    return SocialHeatmap(
      start: '${j['start'] ?? ''}',
      end: '${j['end'] ?? ''}',
      counts: counts,
      total: _i(j['total'], counts.fold(0, (a, b) => a + b)),
      activeDays: _i(j['active_days'], counts.where((c) => c > 0).length),
      streak: _i(j['streak']),
      max: max,
    );
  }

  /// 0..4 like GitHub's contribution graph, relative to the busiest day.
  static int level(int count, int max) {
    if (count <= 0 || max <= 0) return 0;
    final r = count / max;
    return r > 0.75 ? 4 : (r > 0.5 ? 3 : (r > 0.25 ? 2 : 1));
  }

  /// Sunday-first week columns; padding cells have count -1.
  List<List<int>> weeks() {
    final s = DateTime.tryParse(start);
    final lead = s == null ? 0 : s.weekday % 7; // DateTime: Mon=1..Sun=7 -> Sun=0
    final cells = [for (var i = 0; i < lead; i++) -1, ...counts];
    return [for (var i = 0; i < cells.length; i += 7) [for (var k = i; k < i + 7; k++) k < cells.length ? cells[k] : -1]];
  }
}

class StackItem {
  const StackItem(this.name, this.share, {this.source, this.count});
  final String name;
  final double share;
  final String? source;
  final int? count;
  factory StackItem.fromJson(Map<String, dynamic> j) =>
      StackItem('${j['name'] ?? ''}', _d(j['share']), source: _s(j['source']), count: j['count'] == null ? null : _i(j['count']));
}

class CodingStatus {
  const CodingStatus({this.coding = false, this.lastActiveAt, this.project});
  final bool coding;
  final DateTime? lastActiveAt;
  final String? project;
  factory CodingStatus.fromJson(Map<String, dynamic> j) => CodingStatus(
        coding: j['coding'] == true,
        lastActiveAt: DateTime.tryParse('${j['last_active_at'] ?? ''}'),
        project: _s(j['project']),
      );
}

class SocialProfile {
  const SocialProfile({
    this.login,
    this.name,
    this.bio = '',
    this.avatarUrl,
    this.htmlUrl,
    this.heatmap,
    this.languages = const [],
    this.tools = const [],
    this.status,
    this.lastPublishedAt,
    this.paused = false,
  });
  final String? login, name, avatarUrl, htmlUrl;
  final String bio;
  final SocialHeatmap? heatmap;
  final List<StackItem> languages, tools;
  final CodingStatus? status;
  final DateTime? lastPublishedAt;
  final bool paused;

  String get displayName => name ?? login ?? '?';

  factory SocialProfile.fromJson(Map<String, dynamic> j) {
    final stack = _m(j['stack']);
    final pub = _m(j['publish']);
    return SocialProfile(
      login: _s(j['login']),
      name: _s(j['name']),
      bio: '${j['bio'] ?? ''}',
      avatarUrl: _s(j['avatar_url']),
      htmlUrl: _s(j['html_url']),
      heatmap: j['heatmap'] is Map ? SocialHeatmap.fromJson(_m(j['heatmap'])) : null,
      languages: [for (final s in (stack['languages'] as List? ?? const []).whereType<Map>()) StackItem.fromJson(Map<String, dynamic>.from(s))],
      tools: [for (final s in (stack['tools'] as List? ?? const []).whereType<Map>()) StackItem.fromJson(Map<String, dynamic>.from(s))],
      status: j['status'] is Map ? CodingStatus.fromJson(_m(j['status'])) : null,
      lastPublishedAt: DateTime.tryParse('${pub['last_published_at'] ?? ''}'),
      paused: pub['paused'] == true,
    );
  }
}

class FriendCard {
  const FriendCard({
    required this.login,
    required this.name,
    this.avatarUrl,
    this.bio = '',
    this.coding = false,
    this.hasNeovarch = false,
    this.project,
    this.lastActiveAt,
    this.topStack = const [],
    this.htmlUrl,
  });
  final String login, name, bio;
  final String? avatarUrl, project, htmlUrl;
  final bool coding, hasNeovarch;
  final DateTime? lastActiveAt;
  final List<String> topStack;

  factory FriendCard.fromJson(Map<String, dynamic> j) => FriendCard(
        login: '${j['login'] ?? ''}',
        name: '${j['name'] ?? j['login'] ?? ''}',
        avatarUrl: _s(j['avatar_url']),
        bio: '${j['bio'] ?? ''}',
        coding: j['coding'] == true,
        hasNeovarch: j['has_neovarch'] == true,
        project: _s(j['project']),
        lastActiveAt: DateTime.tryParse('${j['last_active_at'] ?? ''}'),
        topStack: [for (final s in (j['top_stack'] as List? ?? const [])) '$s'],
        htmlUrl: _s(j['html_url']),
      );

  /// "lagi ngoding" first, then Neovarch users, then most recently active.
  static List<FriendCard> sorted(Iterable<FriendCard> list) => [...list]..sort((a, b) {
        if (a.coding != b.coding) return a.coding ? -1 : 1;
        if (a.hasNeovarch != b.hasNeovarch) return a.hasNeovarch ? -1 : 1;
        final ta = a.lastActiveAt?.millisecondsSinceEpoch ?? 0, tb = b.lastActiveAt?.millisecondsSinceEpoch ?? 0;
        if (ta != tb) return tb.compareTo(ta);
        return a.login.toLowerCase().compareTo(b.login.toLowerCase());
      });
}

class FriendsSnapshot {
  const FriendsSnapshot({this.signedIn = false, this.friends = const [], this.pending = const [], this.codingCount = 0});
  final bool signedIn;
  final List<FriendCard> friends;
  final List<String> pending;
  final int codingCount;

  factory FriendsSnapshot.fromJson(Map<String, dynamic> j) {
    final friends = FriendCard.sorted([for (final f in (j['friends'] as List? ?? const []).whereType<Map>()) FriendCard.fromJson(Map<String, dynamic>.from(f))]);
    return FriendsSnapshot(
      signedIn: j['signed_in'] == true,
      friends: friends,
      pending: [for (final p in (j['pending'] as List? ?? const []).whereType<Map>()) '${p['login']}'],
      codingCount: friends.where((f) => f.coding).length,
    );
  }
}

class FriendDetail {
  const FriendDetail({required this.card, this.profile, this.mutual = false});
  final FriendCard card;
  final SocialProfile? profile;
  final bool mutual;
  factory FriendDetail.fromJson(Map<String, dynamic> j) => FriendDetail(
        card: FriendCard.fromJson(j),
        profile: j['profile'] is Map ? SocialProfile.fromJson(_m(j['profile'])) : null,
        mutual: j['mutual'] == true,
      );
}

/// "Aktif 5 mnt lalu" style relative times (Indonesian).
String socialAgo(DateTime? t, [DateTime? now]) {
  if (t == null) return '—';
  final s = (now ?? DateTime.now()).difference(t).inSeconds;
  if (s < 60) return 'baru saja';
  if (s < 3600) return '${s ~/ 60} mnt lalu';
  if (s < 86400) return '${s ~/ 3600} jam lalu';
  return '${s ~/ 86400} hari lalu';
}
