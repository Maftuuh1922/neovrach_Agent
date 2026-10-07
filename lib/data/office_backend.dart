// The office seam: every office surface (Kantor, Papan, Rapat, Cron, Agent,
// per-agent chat in server mode) talks to `/api/hermes/*`-shaped routes.
//
// Three implementations answer them:
//   * ServerBackend — HTTP to the Next.js server (it shells out to hermes CLI)
//   * LocalBackend  — the on-device runtime (Mandiri mode)
//   * DemoBackend   — a port of src/lib/offline-mock.ts
//
// Keeping one request shape means one UI, and behaviour stays equivalent to
// the web app whichever backend answers.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_result.dart';

abstract class OfficeBackend {
  String get kind; // local | server | demo

  /// Local mode can move a card between columns (approve review, reopen).
  /// The Next.js API has no such route, so the UI hides those buttons there.
  bool get supportsMove => false;

  /// Meetings need an LLM in local mode; the server reports `configured`.
  Future<ApiResult> request(String method, String path,
      {Map<String, String>? query, Map<String, dynamic>? body, Duration? timeout});

  Future<ApiResult> get(String path, [Map<String, String>? query]) =>
      request('GET', path, query: query);
  Future<ApiResult> post(String path, Map<String, dynamic> body,
          {Duration? timeout}) =>
      request('POST', path, body: body, timeout: timeout);
  Future<ApiResult> delete(String path, [Map<String, String>? query]) =>
      request('DELETE', path, query: query);

  void dispose() {}
}

class ServerBackend extends OfficeBackend {
  ServerBackend(String baseUrl) : base = baseUrl.replaceAll(RegExp(r'/+$'), '');
  final String base;
  final http.Client _client = http.Client();

  @override
  String get kind => 'server';

  @override
  Future<ApiResult> request(String method, String path,
      {Map<String, String>? query,
      Map<String, dynamic>? body,
      Duration? timeout}) async {
    var uri = Uri.parse('$base$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
    try {
      final req = http.Request(method, uri);
      if (body != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(body);
      }
      final streamed = await _client
          .send(req)
          .timeout(timeout ?? const Duration(seconds: 30));
      final text = await streamed.stream.bytesToString();
      return readJson(streamed.statusCode, text);
    } on TimeoutException {
      return ApiResult.fail(0, 'tidak bisa menghubungi server: waktu habis');
    } catch (e) {
      // Network-level failure: the request never got a reply.
      return ApiResult.fail(0, 'tidak bisa menghubungi server: $e');
    }
  }

  @override
  void dispose() => _client.close();
}
