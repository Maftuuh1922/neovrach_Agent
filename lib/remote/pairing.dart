// What a phone needs to reach the desktop's Hermes-compatible gateway:
// the gateway base URL (the `hermes serve` / dashboard HTTP origin that
// serves `/api/ws`) and its auth token. The Neovarch desktop shows this as a
// pairing QR; it can also be typed by hand. Pure Dart.
//
// Accepted forms (see docs/remote-protocol.md):
//   neovarch://pair?v=1&url=http%3A%2F%2F192.168.1.5%3A9319&token=…&name=…&profile=…
//   {"url":"http://192.168.1.5:9319","token":"…","name":"PC Kantor"}
//   http://192.168.1.5:9319/?token=…        (a dashboard URL with ?token=)
//   ws://192.168.1.5:9319/api/ws?token=…    (the WebSocket URL itself)
//   192.168.1.5:9319                        (manual: token typed separately)
import 'dart:convert';

const int defaultGatewayPort = 9319;

class GatewayPairing {
  final String url; // normalized http(s)://host:port[/base]
  final String token;
  final String name;
  final String? profile;
  final Map<String, String> headers;

  const GatewayPairing({required this.url, this.token = '', this.name = '', this.profile, this.headers = const {}});

  String get displayName => name.trim().isNotEmpty ? name.trim() : (Uri.tryParse(url)?.host ?? url);

  GatewayPairing copyWith({String? token, String? name}) =>
      GatewayPairing(url: url, token: token ?? this.token, name: name ?? this.name, profile: profile, headers: headers);

  String toUri() => Uri(scheme: 'neovarch', host: 'pair', queryParameters: {
        'v': '1',
        'url': url,
        if (token.isNotEmpty) 'token': token,
        if (name.isNotEmpty) 'name': name,
        if (profile != null && profile!.isNotEmpty) 'profile': profile!,
      }).toString();

  /// Never throws; null when [raw] carries no usable gateway address.
  static GatewayPairing? parse(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('{')) {
      try {
        final j = Map<String, dynamic>.from(jsonDecode(s) as Map);
        final url = normalizeGatewayUrl('${j['url'] ?? j['gateway'] ?? j['host'] ?? ''}');
        if (url == null) return null;
        final h = j['headers'];
        return GatewayPairing(
          url: url,
          token: '${j['token'] ?? ''}',
          name: '${j['name'] ?? ''}',
          profile: (j['profile'] as String?)?.trim().isEmpty == true ? null : j['profile'] as String?,
          headers: h is Map ? h.map((k, v) => MapEntry('$k', '$v')) : const {},
        );
      } catch (_) {
        return null;
      }
    }
    final u = Uri.tryParse(s);
    if (u != null && u.scheme == 'neovarch') {
      final q = u.queryParameters;
      final url = normalizeGatewayUrl(q['url'] ?? q['u'] ?? '');
      if (url == null) return null;
      return GatewayPairing(
          url: url,
          token: q['token'] ?? q['t'] ?? '',
          name: q['name'] ?? q['n'] ?? '',
          profile: (q['profile'] ?? '').isEmpty ? null : q['profile']);
    }
    final url = normalizeGatewayUrl(s);
    if (url == null) return null;
    final token = Uri.tryParse(s.contains('://') ? s : 'http://$s')?.queryParameters['token'] ?? '';
    return GatewayPairing(url: url, token: token);
  }
}

/// `192.168.1.5` → `http://192.168.1.5:9319`; `ws(s)://…/api/ws?token=x` →
/// `http(s)://…`; keeps a base path (reverse proxies), drops query/fragment.
String? normalizeGatewayUrl(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;
  if (!s.contains('://')) s = 'http://$s';
  final u = Uri.tryParse(s);
  if (u == null || u.host.isEmpty) return null;
  final scheme = switch (u.scheme) {
    'https' || 'wss' => 'https',
    'http' || 'ws' => 'http',
    _ => null,
  };
  if (scheme == null) return null;
  var path = u.path.replaceAll(RegExp(r'/+$'), '');
  if (path.endsWith('/api/ws')) path = path.substring(0, path.length - '/api/ws'.length);
  final port = u.hasPort ? u.port : (scheme == 'https' ? null : defaultGatewayPort);
  return Uri(scheme: scheme, host: u.host, port: port, path: path).toString();
}
