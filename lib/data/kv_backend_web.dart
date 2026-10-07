import 'package:shared_preferences/shared_preferences.dart';

import 'kv_store.dart';

class _PrefsBackend implements KvBackend {
  _PrefsBackend(this.p);
  final SharedPreferences p;
  @override
  Future<String?> read(String key) async => p.getString('kv.$key');
  @override
  Future<void> write(String key, String value) async =>
      p.setString('kv.$key', value);
  @override
  Future<void> delete(String key) async => p.remove('kv.$key');
}

Future<KvBackend> createKvBackend() async =>
    _PrefsBackend(await SharedPreferences.getInstance());
