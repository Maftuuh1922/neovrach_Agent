// Izin perangkat — one place to see and grant every Android runtime
// permission the agent's device tools use (Android asks again at first use
// if something is still off). iOS asks per feature at first use, with the
// usage texts from Info.plist.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../data/device_tools.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/common.dart';

class _Perm {
  final IconData icon;
  final String title, why;
  final List<String> perms;
  /// Special access granted from a system screen (not a runtime dialog).
  final String? special;
  const _Perm(this.icon, this.title, this.why, this.perms, {this.special});
}

const _a = 'android.permission.';
const _perms = [
  _Perm(Icons.notifications_outlined, 'Notifikasi', 'Agen mengabari saat tugas, cron, atau rapat selesai (alat notify).', ['${_a}POST_NOTIFICATIONS']),
  _Perm(Icons.photo_camera_outlined, 'Kamera', 'Ambil foto untuk dilampirkan ke chat atau saat agen memintanya (camera_capture).', ['${_a}CAMERA']),
  _Perm(Icons.mic_none_outlined, 'Mikrofon', 'Dikte pesan ke agen dengan suara.', ['${_a}RECORD_AUDIO']),
  _Perm(Icons.photo_library_outlined, 'Foto & video', 'Agen bisa melihat foto/video di penyimpanan bersama.',
      ['${_a}READ_MEDIA_IMAGES', '${_a}READ_MEDIA_VIDEO', '${_a}READ_EXTERNAL_STORAGE']),
  _Perm(Icons.library_music_outlined, 'Audio', 'Berkas audio di penyimpanan bersama.', ['${_a}READ_MEDIA_AUDIO']),
  _Perm(Icons.place_outlined, 'Lokasi', 'Untuk permintaan berbasis lokasi: sekitar, rute, cuaca (location_get).',
      ['${_a}ACCESS_FINE_LOCATION', '${_a}ACCESS_COARSE_LOCATION']),
  _Perm(Icons.contacts_outlined, 'Kontak', 'Cari kontak (hanya baca) saat kamu minta menelepon / SMS seseorang.', ['${_a}READ_CONTACTS']),
  _Perm(Icons.event_outlined, 'Kalender', 'Baca agenda untuk membantu merencanakan hari (hanya baca).', ['${_a}READ_CALENDAR']),
  _Perm(Icons.folder_open_outlined, 'Akses semua file', 'Agen membaca/menulis berkas di Download, Documents, dll (storage_*). Diatur di layar sistem.', [],
      special: 'allFiles'),
];

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});
  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> with WidgetsBindingObserver {
  Map<String, bool> _state = {};
  bool _allFiles = false;
  bool _busy = false;
  final bool _android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // back from the system settings screen → re-read
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (!_android) return;
    try {
      final st = await checkPermissions([for (final p in _perms) ...p.perms]);
      final fs = await deviceCall<Map>('storageStatus');
      if (mounted) {
        setState(() {
          _state = st;
          _allFiles = fs?['allFiles'] == true;
        });
      }
    } catch (_) {}
  }

  bool _granted(_Perm p) {
    if (p.special == 'allFiles') return _allFiles;
    if (p.perms.isEmpty) return true;
    // location: either precision is enough
    if (p.title == 'Lokasi') return p.perms.any((x) => _state[x] == true);
    return p.perms.every((x) => _state[x] == true);
  }

  Future<void> _request(_Perm p) async {
    if (!_android) return;
    setState(() => _busy = true);
    try {
      if (p.special == 'allFiles') {
        await deviceCall('requestAllFiles');
      } else {
        await ensurePermissions(p.perms);
      }
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _requestAll() async {
    if (!_android) return;
    setState(() => _busy = true);
    try {
      await ensurePermissions([for (final p in _perms) if (p.special == null) ...p.perms]);
    } catch (_) {}
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final granted = _perms.where(_granted).length;
    return Scaffold(
      appBar: AppBar(title: Text('Izin perangkat', style: context.tt.titleMedium)),
      body: ListView(padding: EdgeInsets.only(bottom: 32 + MediaQuery.paddingOf(context).bottom), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(
            _android
                ? 'Akses yang dipakai alat perangkat agen. Semua bisa dicabut kapan saja di sini atau di Pengaturan Android; '
                    'alat yang berisiko tetap meminta persetujuanmu di chat.'
                : 'Di iPhone, sistem menanyakan setiap izin saat fitur pertama kali dipakai (kamera, mikrofon, foto, lokasi, kontak, kalender).',
            style: context.tt.bodySmall,
          ),
        ),
        if (_android)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(children: [
              MetaLabel('$granted / ${_perms.length} diizinkan'),
              const Spacer(),
              FilledButton(onPressed: _busy ? null : _requestAll, child: const Text('Izinkan semua')),
            ]),
          ),
        const SectionLabel('Akses'),
        for (final p in _perms)
          ListTile(
            leading: Icon(p.icon),
            title: Text(p.title),
            subtitle: Text(p.why, style: context.tt.bodySmall),
            trailing: !_android
                ? null
                : _granted(p)
                    ? StatusPill('aktif', color: context.hc.success)
                    : OutlinedButton(onPressed: _busy ? null : () => _request(p), child: const Text('Izinkan')),
          ),
        const SectionLabel('Lainnya'),
        ListTile(
          leading: const Icon(Icons.apps_outlined),
          title: const Text('Daftar aplikasi'),
          subtitle: Text('Melihat aplikasi terpasang (apps_list) — sudah dideklarasikan, tanpa dialog.', style: context.tt.bodySmall),
        ),
        ListTile(
          leading: const Icon(Icons.apartment_outlined),
          title: const Text('Tampilan kantor'),
          subtitle: Text('Agen bisa "melihat" kantor lewat alat office_view (gambar) dan office_status — tanpa izin sistem.', style: context.tt.bodySmall),
        ),
        if (_android)
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              onPressed: () => deviceCall('openAppSettings'),
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('Buka pengaturan aplikasi Android'),
            ),
          ),
      ]),
    );
  }
}
