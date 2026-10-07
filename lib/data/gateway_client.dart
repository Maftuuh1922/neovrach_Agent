// JSON-RPC 2.0 over WebSocket to a Hermes `hermes serve` backend
// (tui_gateway), modelled on apps/shared/src/json-rpc-channel.ts:
//
//   client → {jsonrpc:'2.0', id, method, params}
//   server → {id, result} | {id, error:{code,message}}
//   server → {method:'event', params:{type, session_id, payload}}
//   server → {id:'<string>', method, params}   (server request; we answer)
//
// Auth: token mode puts `?token=` on the URL (as buildHermesWebSocketUrl
// does) and also sends `Authorization: Bearer` plus any extra headers on
// native platforms.
import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'ws_connect.dart';

class GatewayEventFrame {
  final String type;
  final String? sessionId;
  final Map<String, dynamic> payload;
  const GatewayEventFrame(this.type, this.sessionId, this.payload);
}

class RpcError implements Exception {
  final int code;
  final String message;
  const RpcError(this.code, this.message);
  @override
  String toString() => message;
}

const jsonRpcMethodNotFound = -32601;

Uri buildGatewayWsUri(String baseUrl, {String? token, String path = '/api/ws'}) {
  var u = Uri.parse(baseUrl.trim());
  final scheme = (u.scheme == 'https' || u.scheme == 'wss') ? 'wss' : 'ws';
  final basePath = u.path.replaceAll(RegExp(r'/+$'), '');
  final p = basePath.endsWith(path) ? basePath : '$basePath$path';
  return Uri(
    scheme: scheme,
    host: u.host,
    port: u.hasPort ? u.port : null,
    path: p,
    queryParameters: {
      ...u.queryParameters,
      if (token != null && token.isNotEmpty) 'token': token,
    },
  );
}

class GatewayClient {
  GatewayClient({required this.baseUrl, this.token, this.headers = const {}});
  final String baseUrl;
  final String? token;
  final Map<String, String> headers;

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  int _seq = 0;
  final Map<String, Completer<dynamic>> _pending = {};
  final _events = StreamController<GatewayEventFrame>.broadcast();
  Completer<void>? _connecting;
  bool get connected => _ch != null;
  String? lastError;

  Stream<GatewayEventFrame> get events => _events.stream;

  Future<void> ensureConnected() async {
    if (_ch != null) return;
    if (_connecting != null) return _connecting!.future;
    final c = _connecting = Completer<void>();
    try {
      final uri = buildGatewayWsUri(baseUrl, token: token);
      final ch = connectWs(uri, {
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
        ...headers,
      });
      await ch.ready.timeout(const Duration(seconds: 15));
      _ch = ch;
      _sub = ch.stream.listen(_onFrame, onDone: _onClose, onError: (e) {
        lastError = '$e';
        _onClose();
      });
      c.complete();
    } catch (e) {
      lastError = 'tidak bisa terhubung ke gateway: $e';
      c.completeError(RpcError(0, lastError!));
    } finally {
      _connecting = null;
    }
    return c.future;
  }

  void _onClose() {
    _ch = null;
    _sub?.cancel();
    _sub = null;
    for (final p in _pending.values) {
      if (!p.isCompleted) p.completeError(const RpcError(0, 'koneksi gateway terputus'));
    }
    _pending.clear();
    _events.add(const GatewayEventFrame('gateway.disconnected', null, {}));
  }

  void _onFrame(dynamic raw) {
    Map<String, dynamic> f;
    try {
      f = Map<String, dynamic>.from(jsonDecode('$raw') as Map);
    } catch (_) {
      return;
    }
    final id = f['id'];
    final method = f['method'];
    if (method == 'event' && f['params'] is Map) {
      final p = Map<String, dynamic>.from(f['params'] as Map);
      final payload = p['payload'] is Map ? Map<String, dynamic>.from(p['payload'] as Map) : <String, dynamic>{};
      _events.add(GatewayEventFrame('${p['type']}', p['session_id'] as String?, payload));
      return;
    }
    if (method is String && id != null) {
      // A server request. Approvals arrive this way on some versions.
      final params = f['params'] is Map ? Map<String, dynamic>.from(f['params'] as Map) : <String, dynamic>{};
      _events.add(GatewayEventFrame('server.$method', params['session_id'] as String?, {...params, '_rid': id}));
      if (!method.startsWith('approval')) {
        _send({'jsonrpc': '2.0', 'id': id, 'error': {'code': jsonRpcMethodNotFound, 'message': 'no handler for server request: $method'}});
      }
      return;
    }
    if (id != null) {
      final c = _pending.remove('$id');
      if (c == null || c.isCompleted) return;
      if (f['error'] is Map) {
        final e = f['error'] as Map;
        c.completeError(RpcError((e['code'] as num?)?.toInt() ?? -1, '${e['message'] ?? 'galat gateway'}'));
      } else {
        c.complete(f['result']);
      }
    }
  }

  void _send(Map<String, dynamic> frame) => _ch?.sink.add(jsonEncode(frame));

  void respondServerRequest(dynamic rid, dynamic result) =>
      _send({'jsonrpc': '2.0', 'id': rid, 'result': result});

  Future<dynamic> call(String method, [Map<String, dynamic> params = const {}, Duration timeout = const Duration(seconds: 60)]) async {
    await ensureConnected();
    final id = 'm${++_seq}';
    final c = Completer<dynamic>();
    _pending[id] = c;
    _send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    return c.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      throw RpcError(0, 'request timed out after ${timeout.inSeconds}s: $method');
    });
  }

  void close() {
    _sub?.cancel();
    _ch?.sink.close();
    _ch = null;
  }
}
