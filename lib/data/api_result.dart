// Port of src/lib/api.ts: reading a response without blowing up on a body
// that is not JSON, and folding the HTTP status into a user-facing message.
import 'dart:convert';

class ApiResult {
  final bool ok;
  final int status;

  /// Parsed body, or null when the reply was not JSON.
  final dynamic data;

  /// A message safe to show the user.
  final String? error;

  const ApiResult(
      {required this.ok, required this.status, this.data, this.error});

  factory ApiResult.success(dynamic data, [int status = 200]) =>
      ApiResult(ok: true, status: status, data: data);
  factory ApiResult.fail(int status, String error) =>
      ApiResult(ok: false, status: status, error: error);

  Map<String, dynamic> get map =>
      data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};

  List<Map<String, dynamic>> list(String key) {
    final v = map[key];
    if (v is! List) return [];
    return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
}

/// Same rules as readJson(): never throws.
ApiResult readJson(int status, String text) {
  final okStatus = status >= 200 && status < 300;
  if (text.trim().isEmpty) {
    return ApiResult(
        ok: okStatus,
        status: status,
        error: okStatus ? null : 'server membalas kosong (HTTP $status)');
  }
  dynamic parsed;
  try {
    parsed = jsonDecode(text);
  } catch (_) {
    final looksHtml = RegExp(r'^\s*<').hasMatch(text);
    return ApiResult(
      ok: false,
      status: status,
      error: looksHtml
          ? 'server membalas halaman HTML, bukan JSON (HTTP $status) — biasanya proxy atau backend mati'
          : 'balasan server bukan JSON (HTTP $status)',
    );
  }
  String? serverMsg;
  if (parsed is Map && parsed['error'] is Map) {
    final m = (parsed['error'] as Map)['message'];
    if (m is String) serverMsg = m;
  }
  return ApiResult(
    ok: okStatus,
    status: status,
    data: parsed,
    error: okStatus ? null : (serverMsg ?? 'permintaan gagal (HTTP $status)'),
  );
}
