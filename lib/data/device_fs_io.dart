// Shared-storage file access (needs "All files access" on Android 11+).
import 'dart:convert';
import 'dart:io';

Future<List<String>> fsList(String path) async {
  final d = Directory(path);
  if (!await d.exists()) throw FileSystemException('folder tidak ada', path);
  final out = <String>[];
  await for (final e in d.list(followLinks: false)) {
    final name = e.path.split('/').last;
    if (e is Directory) {
      out.add('$name/');
    } else if (e is File) {
      out.add('$name (${await e.length()} b)');
    }
    if (out.length >= 300) break;
  }
  out.sort();
  return out;
}

Future<String> fsRead(String path, int maxBytes) async {
  final f = File(path);
  final len = await f.length();
  final raf = await f.open();
  try {
    final bytes = await raf.read(len < maxBytes ? len : maxBytes);
    final text = utf8.decode(bytes, allowMalformed: true);
    return len > maxBytes ? '$text\n…(dipotong, total $len b)' : text;
  } finally {
    await raf.close();
  }
}

Future<int> fsWrite(String path, String content) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(content);
  return content.length;
}

Future<void> fsDelete(String path) async {
  final t = await FileSystemEntity.type(path);
  if (t == FileSystemEntityType.notFound) throw FileSystemException('tidak ada', path);
  if (t == FileSystemEntityType.directory) {
    await Directory(path).delete();
  } else {
    await File(path).delete();
  }
}
