// Durable key/value JSON store.
//
// On Android/desktop each key is one JSON file under the app documents
// directory (survives restarts, no size limit worth worrying about). On the
// web build (used for screenshots/preview) it falls back to
// shared_preferences. Everything the on-device agent owns — sessions,
// messages, memory, skills, the Kanban board, cron, meetings and the
// workspace files — goes through here.
import 'dart:async';
import 'dart:convert';

import 'kv_backend_stub.dart'
    if (dart.library.io) 'kv_backend_io.dart'
    if (dart.library.js_interop) 'kv_backend_web.dart';

abstract class KvBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class KvStore {
  KvStore._(this._backend);
  final KvBackend _backend;
  final Map<String, dynamic> _cache = {};
  final Map<String, Timer> _pending = {};

  static Future<KvStore> open() async => KvStore._(await createKvBackend());

  /// In-memory store (tests).
  factory KvStore.memory() => KvStore._(_MemKv());

  Future<dynamic> get(String key) async {
    if (_cache.containsKey(key)) return _cache[key];
    final raw = await _backend.read(key);
    dynamic v;
    if (raw != null) {
      try {
        v = jsonDecode(raw);
      } catch (_) {
        v = null; // corrupted file: start empty rather than crash
      }
    }
    _cache[key] = v;
    return v;
  }

  Future<List<Map<String, dynamic>>> getList(String key) async {
    final v = await get(key);
    if (v is List) {
      return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> getMap(String key) async {
    final v = await get(key);
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }

  /// Write-behind: the cache updates now, the disk ~150 ms later, coalesced.
  void put(String key, dynamic value) {
    _cache[key] = value;
    _pending[key]?.cancel();
    _pending[key] = Timer(const Duration(milliseconds: 150), () {
      _pending.remove(key);
      _backend.write(key, jsonEncode(_cache[key]));
    });
  }

  Future<void> remove(String key) async {
    _cache.remove(key);
    _pending.remove(key)?.cancel();
    await _backend.delete(key);
  }

  Future<void> flush() async {
    for (final k in _pending.keys.toList()) {
      _pending.remove(k)?.cancel();
      await _backend.write(k, jsonEncode(_cache[k]));
    }
  }
}

class _MemKv implements KvBackend {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
}
