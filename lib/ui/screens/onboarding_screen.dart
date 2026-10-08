// First-run onboarding: welcome → connection → provider/model/key (or
// "pilih penyedia nanti") → first message. Gets to a first answer fast.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../data/device_tools.dart';
import '../widgets/common.dart';
import 'settings/connection_screen.dart';
import 'settings/providers_screen.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int step = 0;
  int _dir = 1;
  final Map<String, bool?> _perm = {};

  void _go(int to) => setState(() {
        _dir = to >= step ? 1 : -1;
        step = to;
      });
  final _first = TextEditingController(text: 'Halo Neovarch! Perkenalkan dirimu dan apa saja yang bisa kamu lakukan di ponsel ini.');

  void _finish({bool send = false}) {
    final s = ref.read(settingsProvider);
    final chat = ref.read(chatProvider);
    s.update((x) => x.onboarded = true);
    if (send && _first.text.trim().isNotEmpty) {
      chat.send(_first.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final steps = [_welcome(context), _connection(context, s.mode), _provider(context), _permissions(context), _firstMessage(context)];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(children: [
                  for (var i = 0; i < steps.length; i++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: motionBase,
                        curve: motionCurve,
                        height: i == step ? 3 : 2,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(color: i <= step ? context.cs.primary : context.hc.border, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                ]),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: reduceMotion(context) ? Duration.zero : motionSlow,
                  switchInCurve: motionCurve,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, a) {
                    final incoming = child.key == ValueKey(step);
                    final dx = (incoming ? 0.18 : -0.18) * _dir;
                    return FadeTransition(
                      opacity: a,
                      child: SlideTransition(position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(a), child: child),
                    );
                  },
                  child: KeyedSubtree(key: ValueKey(step), child: steps[step]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _nav({required VoidCallback? next, String nextLabel = 'Lanjut', Widget? extra}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Row(children: [
          if (step > 0) TextButton(onPressed: () => _go(step - 1), child: const Text('Kembali')),
          const Spacer(),
          ?extra,
          const SizedBox(width: 8),
          FilledButton(onPressed: next, child: Text(nextLabel)),
        ]),
      );

  Widget _welcome(BuildContext context) => Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(children: [
              const SizedBox(height: 12),
              const EntranceFade(child: LogoCard(height: 220)),
              const SizedBox(height: 18),
              EntranceFade(
                delay: const Duration(milliseconds: 120),
                child: Wordmark(height: 42),
              ),
              const SizedBox(height: 10),
              Text('Agen Neovarch yang berjalan langsung di ponselmu — chat dengan alat dan memori, skill, berkas, kantor virtual, Kanban, rapat antar-agent, dan cron.',
                  textAlign: TextAlign.center, style: context.tt.bodyMedium?.copyWith(color: context.hc.mutedForeground)),
              const SizedBox(height: 28),
              for (final (i, t) in [
                (Icons.smartphone, 'Mandiri — tanpa PC, cukup kunci API penyedia model'),
                (Icons.bolt_outlined, 'Balasan streaming dengan aktivitas alat yang terlihat'),
                (Icons.apartment_outlined, 'Kantor isometrik yang menunjukkan siapa sedang bekerja'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(children: [
                    Icon(i, color: context.cs.primary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text(t)),
                  ]),
                ),
            ]),
          ),
        ),
        _nav(next: () => _go(1), nextLabel: 'Mulai'),
      ]);

  Widget _connection(BuildContext context, ConnectionMode mode) => Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Text('Bagaimana Neovarch berjalan?', style: context.tt.titleLarge),
            const SizedBox(height: 6),
            Text('Bisa diubah kapan saja di Lainnya → Koneksi.', style: context.tt.bodySmall),
            const SizedBox(height: 16),
            for (final m in ConnectionMode.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: mode == m ? context.cs.secondaryContainer.withValues(alpha: 0.6) : context.hc.card,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: mode == m ? context.cs.primary : context.hc.strokeSoft)),
                  child: ListTile(
                    leading: Icon(switch (m) {
                      ConnectionMode.local => Icons.smartphone,
                      ConnectionMode.gateway => Icons.cloud_outlined,
                      ConnectionMode.server => Icons.dns_outlined,
                      ConnectionMode.demo => Icons.science_outlined,
                    }),
                    title: Text(m.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(switch (m) {
                      ConnectionMode.local => 'Disarankan. Agent di perangkat + penyedia LLM pilihanmu.',
                      ConnectionMode.gateway => 'Gateway Neovarch milikmu di VPS / PC.',
                      ConnectionMode.server => 'Server kantor virtual (Next.js).',
                      ConnectionMode.demo => 'Coba-coba tanpa jaringan.',
                    }, style: context.tt.bodySmall),
                    onTap: () => ref.read(settingsProvider).update((x) => x.mode = m),
                  ),
                ),
              ),
            if (mode == ConnectionMode.gateway || mode == ConnectionMode.server)
              TextButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectionScreen())),
                icon: const Icon(Icons.settings_ethernet, size: 18),
                label: Text(mode == ConnectionMode.gateway ? 'Atur URL & token gateway' : 'Atur URL server'),
              ),
          ]),
        ),
        _nav(
          next: () => _go(mode == ConnectionMode.local ? 2 : 3),
        ),
      ]);

  Widget _provider(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Pilih penyedia model', style: context.tt.titleLarge),
            const SizedBox(height: 6),
            Text('Nous Portal dan OpenRouter menyediakan banyak model. Kunci disimpan terenkripsi di perangkat.', style: context.tt.bodySmall),
          ]),
        ),
        Expanded(child: ProviderEditor(onSaved: () => _go(3))),
        _nav(
          next: null,
          nextLabel: 'Simpan di atas ↑',
          extra: TextButton(onPressed: () => _go(3), child: const Text('Pilih penyedia nanti')),
        ),
      ]);

  static const _permItems = [
    ('Notifikasi', 'Agen bisa mengirim pengingat & hasil tugas', Icons.notifications_none, ['android.permission.POST_NOTIFICATIONS']),
    ('Kamera & mikrofon', 'Foto untuk chat, dikte suara', Icons.photo_camera_outlined, ['android.permission.CAMERA', 'android.permission.RECORD_AUDIO']),
    ('Foto, video & audio', 'Agen bisa melihat media di penyimpanan', Icons.photo_library_outlined,
        ['android.permission.READ_MEDIA_IMAGES', 'android.permission.READ_MEDIA_VIDEO', 'android.permission.READ_MEDIA_AUDIO', 'android.permission.READ_EXTERNAL_STORAGE']),
    ('Lokasi', 'Untuk pertanyaan "di dekatku", cuaca, rute', Icons.place_outlined, ['android.permission.ACCESS_FINE_LOCATION', 'android.permission.ACCESS_COARSE_LOCATION']),
    ('Kontak', 'Cari nomor saat kamu minta menelepon / SMS', Icons.contacts_outlined, ['android.permission.READ_CONTACTS']),
    ('Kalender', 'Baca agenda untuk merencanakan harimu', Icons.event_outlined, ['android.permission.READ_CALENDAR']),
  ];

  Widget _permissions(BuildContext context) => Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Text('Izin perangkat', style: context.tt.titleLarge),
            const SizedBox(height: 6),
            Text('Opsional. Setiap izin juga diminta otomatis saat agen pertama kali membutuhkannya, dan alatnya bisa dimatikan di Lainnya → Alat. '
                'Aksi sensitif tetap menunggu persetujuanmu di chat.', style: context.tt.bodySmall),
            const SizedBox(height: 14),
            for (final (i, p) in _permItems.indexed)
              EntranceFade(
                delay: Duration(milliseconds: 60 * i),
                child: PaperScope(child: Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(p.$3),
                    title: Text(p.$1),
                    subtitle: Text(p.$2, style: context.tt.bodySmall),
                    trailing: AnimatedSwitcher(
                      duration: motionBase,
                      child: _perm[p.$1] == true
                          ? Icon(Icons.check_circle, key: const ValueKey('ok'), color: context.hc.success)
                          : TextButton(
                              key: const ValueKey('ask'),
                              onPressed: () async {
                                bool ok;
                                try {
                                  ok = await ensurePermissions(p.$4);
                                } catch (e) {
                                  if (context.mounted) toast(context, '$e');
                                  return;
                                }
                                setState(() => _perm[p.$1] = ok);
                              },
                              child: Text(_perm[p.$1] == false ? 'Ditolak' : 'Izinkan'),
                            ),
                    ),
                  ),
                )),
              ),
            EntranceFade(
              delay: const Duration(milliseconds: 260),
              child: PaperScope(child: Card(
                child: ListTile(
                  leading: const Icon(Icons.folder_open_outlined),
                  title: const Text('Akses semua file'),
                  subtitle: Text('Agar agen bisa membaca/menulis Download, Documents, dll. Membuka layar izin Android.', style: context.tt.bodySmall),
                  trailing: TextButton(
                    onPressed: () async {
                      try {
                        await deviceCall('requestAllFiles');
                      } catch (e) {
                        if (context.mounted) toast(context, '$e');
                      }
                    },
                    child: const Text('Buka'),
                  ),
                ),
              )),
            ),
          ]),
        ),
        _nav(next: () => _go(4), nextLabel: 'Lanjut'),
      ]);

  Widget _firstMessage(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final ready = s.mode != ConnectionMode.local || s.llmConfigured;
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text('Pesan pertamamu', style: context.tt.titleLarge),
          const SizedBox(height: 6),
          Text(ready ? 'Kirim untuk mulai — agent menjawab secara streaming.' : 'Penyedia belum diatur; kamu tetap bisa masuk dan mengaturnya nanti.',
              style: context.tt.bodySmall),
          const SizedBox(height: 16),
          TextField(controller: _first, minLines: 3, maxLines: 6, decoration: const InputDecoration(hintText: 'Tanya apa saja…')),
          const SizedBox(height: 16),
          if (s.mode == ConnectionMode.local && s.activeProvider != null)
            NoteBanner('${s.activeProvider!.label} · ${s.activeProvider!.model}', ok: true, icon: Icons.memory),
        ]),
      ),
      _nav(
        next: () => _finish(send: ready),
        nextLabel: ready ? 'Kirim & masuk' : 'Masuk',
        extra: ready ? TextButton(onPressed: () => _finish(), child: const Text('Lewati')) : null,
      ),
    ]);
  }
}
