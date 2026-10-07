// Device tools for the on-device agent: what Android lets an ordinary app do
// for its user. Each tool asks for its runtime permission the first time it
// is used; risky ones (anything private or that leaves the app) also go
// through the chat approval card. Nothing here can tap or read inside other
// apps — that would need root or an Accessibility service.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'agent_runtime.dart';
import 'device_fs_stub.dart' if (dart.library.io) 'device_fs_io.dart';

const _ch = MethodChannel('neovarch/device');

class DeviceUnavailable implements Exception {
  final String message;
  const DeviceUnavailable(this.message);
  @override
  String toString() => message;
}

Future<T?> deviceCall<T>(String method, [Map<String, dynamic>? args]) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    throw const DeviceUnavailable('alat perangkat hanya tersedia di aplikasi Android');
  }
  try {
    return await _ch.invokeMethod<T>(method, args);
  } on MissingPluginException {
    throw const DeviceUnavailable('jembatan perangkat tidak tersedia');
  } on PlatformException catch (e) {
    throw DeviceUnavailable(e.message ?? e.code);
  }
}

/// Request runtime permissions; true when all granted.
Future<bool> ensurePermissions(List<String> perms) async {
  final r = await deviceCall<Map>('requestPermissions', {'permissions': perms});
  return r != null && r.values.every((v) => v == true);
}

/// Camera runtime permission (declared in the manifest, so Android requires
/// it to be granted before any camera intent). No-op off Android.
Future<bool> ensureCameraPermission() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
  try {
    return await ensurePermissions(const ['android.permission.CAMERA']);
  } on DeviceUnavailable {
    return true;
  }
}

/// Read runtime permission state; empty map off Android.
Future<Map<String, bool>> checkPermissions(List<String> perms) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return {};
  final r = await deviceCall<Map>('checkPermissions', {'permissions': perms});
  return {for (final e in (r ?? {}).entries) '${e.key}': e.value == true};
}

const _pNotify = 'android.permission.POST_NOTIFICATIONS';
const _pLoc = ['android.permission.ACCESS_FINE_LOCATION', 'android.permission.ACCESS_COARSE_LOCATION'];
const _pContacts = 'android.permission.READ_CONTACTS';
const _pCalendar = 'android.permission.READ_CALENDAR';

/// Tool name → Android permission(s), for the settings page and the report.
const devicePermissionLabels = {
  'device_info': 'tanpa izin',
  'clipboard_read': 'tanpa izin (aplikasi harus di depan)',
  'clipboard_write': 'tanpa izin',
  'open_intent': 'tanpa izin — membuka aplikasi sistem (browser, telepon, SMS, peta, bagikan, alarm)',
  'notify': 'POST_NOTIFICATIONS (Android 13+)',
  'location_get': 'ACCESS_FINE/COARSE_LOCATION',
  'contacts_search': 'READ_CONTACTS',
  'calendar_events': 'READ_CALENDAR',
  'apps_list': 'QUERY_ALL_PACKAGES (manifest)',
  'storage_list': 'MANAGE_EXTERNAL_STORAGE (Akses semua file) / READ_EXTERNAL_STORAGE ≤ Android 12',
  'storage_read': 'MANAGE_EXTERNAL_STORAGE / READ_EXTERNAL_STORAGE',
  'storage_write': 'MANAGE_EXTERNAL_STORAGE / WRITE_EXTERNAL_STORAGE ≤ Android 10',
  'storage_delete': 'MANAGE_EXTERNAL_STORAGE',
  'document_pick': 'tanpa izin — pemilih dokumen sistem (SAF)',
  'camera_capture': 'CAMERA (kamera) · galeri lewat pemilih sistem',
};

const deviceTools = <ToolSpec>[
  ToolSpec('device_info', 'Info perangkat', 'Phone model, Android version, battery %, charging, network type, free storage, locale, timezone.',
      {'type': 'object', 'properties': {}}, group: 'device'),
  ToolSpec('clipboard_read', 'Baca clipboard', 'Read the current text on the phone clipboard.', {'type': 'object', 'properties': {}},
      group: 'device', risky: true),
  ToolSpec('clipboard_write', 'Salin ke clipboard', 'Put text on the phone clipboard.',
      {'type': 'object', 'properties': {'text': {'type': 'string'}}, 'required': ['text']}, group: 'device'),
  ToolSpec('open_intent', 'Buka aplikasi/URL',
      'Open something on the phone for the user to finish: kind=url (target=https URL), share (text), dial (target=number), '
      'sms (target=number, text=draft), email (target=address, text), maps (target=place query), app (target=package name), '
      'settings (target=optional android.settings.* action), alarm (target=HH:MM, text=label). Never sends anything by itself.',
      {
        'type': 'object',
        'properties': {
          'kind': {'type': 'string', 'enum': ['url', 'share', 'dial', 'sms', 'email', 'maps', 'app', 'settings', 'alarm']},
          'target': {'type': 'string'},
          'text': {'type': 'string'}
        },
        'required': ['kind']
      },
      group: 'device', risky: true),
  ToolSpec('notify', 'Notifikasi lokal', 'Show a local notification on the phone.',
      {'type': 'object', 'properties': {'title': {'type': 'string'}, 'body': {'type': 'string'}}, 'required': ['body']}, group: 'device'),
  ToolSpec('location_get', 'Lokasi', 'Get the phone\'s current approximate location (lat/lng, accuracy).', {'type': 'object', 'properties': {}},
      group: 'device', risky: true),
  ToolSpec('contacts_search', 'Cari kontak', 'Search the phone contacts by name (read-only). Returns names and numbers.',
      {'type': 'object', 'properties': {'query': {'type': 'string'}, 'limit': {'type': 'integer'}}}, group: 'device', risky: true),
  ToolSpec('calendar_events', 'Agenda kalender', 'List upcoming calendar events on the phone (read-only).',
      {'type': 'object', 'properties': {'days': {'type': 'integer', 'description': 'default 7'}}}, group: 'device', risky: true),
  ToolSpec('apps_list', 'Daftar aplikasi', 'List installed launchable apps (label + package). Optional query filter.',
      {'type': 'object', 'properties': {'query': {'type': 'string'}}}, group: 'device'),
  ToolSpec('storage_list', 'Daftar penyimpanan', 'List a folder on the phone\'s shared storage (default: storage root, e.g. Download, DCIM, Documents).',
      {'type': 'object', 'properties': {'path': {'type': 'string', 'description': 'relative to storage root or absolute /storage/...'}}},
      group: 'device'),
  ToolSpec('storage_read', 'Baca penyimpanan', 'Read a text file from the phone\'s shared storage.',
      {'type': 'object', 'properties': {'path': {'type': 'string'}, 'max_bytes': {'type': 'integer'}}, 'required': ['path']},
      group: 'device'),
  ToolSpec('storage_write', 'Tulis penyimpanan', 'Create or overwrite a text file on the phone\'s shared storage (e.g. Documents/notes.md).',
      {'type': 'object', 'properties': {'path': {'type': 'string'}, 'content': {'type': 'string'}}, 'required': ['path', 'content']},
      group: 'device', risky: true),
  ToolSpec('storage_delete', 'Hapus di penyimpanan', 'Delete a file or empty folder on the phone\'s shared storage.',
      {'type': 'object', 'properties': {'path': {'type': 'string'}}, 'required': ['path']}, group: 'device', risky: true),
  ToolSpec('document_pick', 'Pilih dokumen', 'Ask the user to pick a document with the system file picker and read it (text).',
      {'type': 'object', 'properties': {'mime': {'type': 'string', 'description': 'e.g. text/*, application/pdf; default */*'}}},
      group: 'device'),
  ToolSpec('camera_capture', 'Kamera / galeri', 'Ask the user to take a photo (source=camera) or pick one (source=gallery); the image is shown to you next.',
      {'type': 'object', 'properties': {'source': {'type': 'string', 'enum': ['camera', 'gallery']}}}, group: 'device'),
];

String _clip(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}…';

Future<String> _storagePath(String p) async {
  final st = await deviceCall<Map>('storageStatus');
  final root = '${st?['root'] ?? '/storage/emulated/0'}';
  if (st?['allFiles'] != true) {
    await deviceCall('requestAllFiles');
    throw const DeviceUnavailable(
        'izin "Akses semua file" belum diberikan — layar izin sudah dibuka; aktifkan Neovarch Agent lalu minta agen mencoba lagi. '
        'Alternatif: alat document_pick (pemilih dokumen sistem).');
  }
  if (p.trim().isEmpty) return root;
  if (p.startsWith('/')) return p;
  return '$root/${p.replaceAll(RegExp(r'^\./'), '')}';
}

/// Execute a device tool. Returns null when [name] is not a device tool.
Future<ToolResult?> runDeviceTool(String name, Map<String, dynamic> a) async {
  if (!deviceTools.any((t) => t.name == name)) return null;
  try {
    switch (name) {
      case 'device_info':
        final m = await deviceCall<Map>('deviceInfo') ?? {};
        final lines = m.entries.map((e) => '${e.key}: ${e.value is double ? (e.value as double).toStringAsFixed(1) : e.value}').join('\n');
        return ToolResult(lines, '${m['manufacturer']} ${m['model']} · baterai ${m['batteryPercent']}% · ${m['network']}');
      case 'clipboard_read':
        final d = await Clipboard.getData(Clipboard.kTextPlain);
        final t = d?.text ?? '';
        return ToolResult(t.isEmpty ? '(clipboard kosong)' : _clip(t, 8000), t.isEmpty ? 'clipboard kosong' : '${t.length} karakter');
      case 'clipboard_write':
        await Clipboard.setData(ClipboardData(text: '${a['text'] ?? ''}'));
        return ToolResult('disalin', 'Disalin ke clipboard (${'${a['text'] ?? ''}'.length} karakter)');
      case 'open_intent':
        final r = await deviceCall<String>('openIntent', {'kind': '${a['kind'] ?? 'url'}', 'target': '${a['target'] ?? ''}', 'text': '${a['text'] ?? ''}'});
        return ToolResult('$r', 'Membuka ${a['kind']}: ${_clip('${a['target'] ?? a['text'] ?? ''}', 40)}', failed: r != 'dibuka');
      case 'notify':
        await ensurePermissions([_pNotify]);
        final r = await deviceCall<String>('notify', {'title': '${a['title'] ?? 'Neovarch'}', 'body': '${a['body'] ?? ''}'});
        return ToolResult('$r', r == 'terkirim' ? 'Notifikasi dikirim' : '$r', failed: r != 'terkirim');
      case 'location_get':
        if (!await ensurePermissions(_pLoc)) {
          final any = await deviceCall<Map>('checkPermissions', {'permissions': _pLoc});
          if (any?.values.any((v) => v == true) != true) return const ToolResult('error: izin lokasi ditolak', 'izin lokasi ditolak', failed: true);
        }
        final m = await deviceCall<Map>('location');
        if (m == null) return const ToolResult('lokasi belum tersedia (GPS mati?)', 'lokasi tidak tersedia', failed: true);
        return ToolResult(jsonEncode(m), '${(m['lat'] as num).toStringAsFixed(4)}, ${(m['lng'] as num).toStringAsFixed(4)} (±${(m['accuracyM'] as num).round()} m)');
      case 'contacts_search':
        if (!await ensurePermissions([_pContacts])) return const ToolResult('error: izin kontak ditolak', 'izin kontak ditolak', failed: true);
        final l = await deviceCall<List>('contacts', {'query': '${a['query'] ?? ''}', 'limit': (a['limit'] as num?)?.toInt() ?? 20}) ?? [];
        return ToolResult(l.isEmpty ? '(tidak ada kontak cocok)' : l.map((e) => '${e['name']}: ${e['phone']}').join('\n'), '${l.length} kontak');
      case 'calendar_events':
        if (!await ensurePermissions([_pCalendar])) return const ToolResult('error: izin kalender ditolak', 'izin kalender ditolak', failed: true);
        final l = await deviceCall<List>('calendar', {'days': (a['days'] as num?)?.toInt() ?? 7}) ?? [];
        String t(int ms) => DateTime.fromMillisecondsSinceEpoch(ms).toString().substring(0, 16);
        return ToolResult(
            l.isEmpty ? '(tidak ada acara)' : l.map((e) => '${t(e['begin'] as int)}–${t(e['end'] as int).substring(11)} ${e['title']}${(e['location'] ?? '').toString().isNotEmpty ? ' @ ${e['location']}' : ''}').join('\n'),
            '${l.length} acara');
      case 'apps_list':
        final l = await deviceCall<List>('apps', {'query': '${a['query'] ?? ''}'}) ?? [];
        return ToolResult(l.map((e) => '${e['label']} — ${e['package']}').join('\n'), '${l.length} aplikasi');
      case 'storage_list':
        final p = await _storagePath('${a['path'] ?? ''}');
        final l = await fsList(p);
        return ToolResult('$p\n${l.isEmpty ? '(kosong)' : l.join('\n')}', '${l.length} entri di ${p.split('/').last}');
      case 'storage_read':
        final p = await _storagePath('${a['path'] ?? ''}');
        final t = await fsRead(p, ((a['max_bytes'] as num?)?.toInt() ?? 60000).clamp(1000, 400000));
        return ToolResult(t, 'Membaca ${p.split('/').last} (${t.length} karakter)');
      case 'storage_write':
        final p = await _storagePath('${a['path'] ?? ''}');
        final n = await fsWrite(p, '${a['content'] ?? ''}');
        return ToolResult('tertulis: $p ($n karakter)', 'Menulis $p');
      case 'storage_delete':
        final p = await _storagePath('${a['path'] ?? ''}');
        await fsDelete(p);
        return ToolResult('dihapus: $p', 'Menghapus $p');
      case 'document_pick':
        final m = await deviceCall<Map>('pickDocument', {'mime': '${a['mime'] ?? '*/*'}'});
        if (m == null) return const ToolResult('pengguna membatalkan pemilihan', 'dibatalkan', failed: true);
        final bytes = base64Decode('${m['base64']}');
        final mime = '${m['mime']}';
        final texty = mime.startsWith('text/') || mime.contains('json') || mime.contains('xml') || mime.contains('csv') || mime.contains('markdown');
        final body = texty ? utf8.decode(bytes, allowMalformed: true) : '(berkas biner $mime, ${bytes.length} b — isi tidak ditampilkan)';
        return ToolResult('Nama: ${m['name']}\nTipe: $mime\nUkuran: ${m['size']} b\n\n${_clip(body, 60000)}', 'Membaca ${m['name']}');
      case 'camera_capture':
        final src = a['source'] == 'gallery' ? ImageSource.gallery : ImageSource.camera;
        if (src == ImageSource.camera && !await ensureCameraPermission()) {
          return const ToolResult('error: izin kamera ditolak', 'izin kamera ditolak', failed: true);
        }
        final x = await ImagePicker().pickImage(source: src, maxWidth: 1400, maxHeight: 1400, imageQuality: 80);
        if (x == null) return const ToolResult('pengguna membatalkan', 'dibatalkan', failed: true);
        final b = await x.readAsBytes();
        final url = 'data:image/jpeg;base64,${base64Encode(b)}';
        return ToolResult('gambar diambil (${b.length} b); gambar dilampirkan pada pesan berikutnya', 'Gambar ${src == ImageSource.camera ? 'kamera' : 'galeri'} (${(b.length / 1024).round()} KB)',
            images: [url]);
    }
  } on DeviceUnavailable catch (e) {
    return ToolResult('error: ${e.message}', e.message, failed: true);
  } catch (e) {
    return ToolResult('error: $e', 'gagal: ${_clip('$e', 60)}', failed: true);
  }
  return null;
}
