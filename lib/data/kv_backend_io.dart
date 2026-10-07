import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'kv_store.dart';

class _FileBackend implements KvBackend {
  _FileBackend(this.dir);
  final Directory dir;

  File _f(String key) =>
      File('${dir.path}/${key.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_')}.json');

  @override
  Future<String?> read(String key) async {
    final f = _f(key);
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> write(String key, String value) async {
    final f = _f(key);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(value, flush: true);
    await tmp.rename(f.path); // atomic replace: no half-written board
  }

  @override
  Future<void> delete(String key) async {
    final f = _f(key);
    if (await f.exists()) await f.delete();
  }
}

Future<KvBackend> createKvBackend() async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/neovarch_agent');
  await dir.create(recursive: true);
  return _FileBackend(dir);
}
