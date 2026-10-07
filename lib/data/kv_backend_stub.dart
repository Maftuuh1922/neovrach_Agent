import 'kv_store.dart';

class _MemoryBackend implements KvBackend {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
}

Future<KvBackend> createKvBackend() async => _MemoryBackend();
