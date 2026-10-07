// Web / tests: no shared storage.
Future<List<String>> fsList(String path) async => throw UnsupportedError('penyimpanan perangkat hanya ada di Android');
Future<String> fsRead(String path, int maxBytes) async => throw UnsupportedError('penyimpanan perangkat hanya ada di Android');
Future<int> fsWrite(String path, String content) async => throw UnsupportedError('penyimpanan perangkat hanya ada di Android');
Future<void> fsDelete(String path) async => throw UnsupportedError('penyimpanan perangkat hanya ada di Android');
