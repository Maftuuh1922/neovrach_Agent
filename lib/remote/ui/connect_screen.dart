// "Hubungkan ke PC": scan the desktop's pairing QR or type the gateway
// address + token. Also the first screen after the intro on a fresh phone.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/platform_caps.dart';
import '../../theme/app_theme.dart';
import '../../ui/widgets/common.dart';
import '../pairing.dart';
import '../remote_controller.dart';
import 'scan_screen.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key, this.onboarding = false});
  final bool onboarding;
  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final _addr = TextEditingController();
  final _token = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  bool _manual = false;
  bool _showToken = false;
  String? _error;

  @override
  void dispose() {
    _addr.dispose();
    _token.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _pair(GatewayPairing p) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await ref.read(remoteProvider).pair(p);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null) {
      toast(context, 'Terhubung ke ${p.displayName}');
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    }
  }

  Future<void> _scan() async {
    final raw = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (raw == null || !mounted) return;
    final p = GatewayPairing.parse(raw);
    if (p == null) {
      setState(() => _error = 'QR tidak dikenali.');
      return;
    }
    if (p.token.isEmpty) {
      // A QR with only an address: finish by typing the token.
      setState(() {
        _manual = true;
        _addr.text = p.url;
        _error = 'QR ini tidak memuat token. Salin token dari PC lalu tekan Hubungkan.';
      });
      return;
    }
    await _pair(p);
  }

  Future<void> _submitManual() async {
    final p = GatewayPairing.parse(_addr.text);
    if (p == null) {
      setState(() => _error = 'Alamat tidak valid. Contoh: 192.168.1.5:9319');
      return;
    }
    final token = _token.text.trim().isNotEmpty ? _token.text.trim() : p.token;
    await _pair(p.copyWith(token: token, name: _name.text.trim().isEmpty ? null : _name.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final remote = ref.watch(remoteProvider);
    final saved = remote.desktops.items;
    return Scaffold(
      appBar: widget.onboarding ? null : AppBar(title: Text('Tambah PC', style: context.tt.titleMedium)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(padding: const EdgeInsets.fromLTRB(22, 24, 22, 32), children: [
              if (widget.onboarding) ...[
                const Center(child: LogoCard(height: 170)),
                const SizedBox(height: 16),
                const Center(child: Wordmark(height: 34)),
                const SizedBox(height: 18),
              ],
              const MetaLabel('[ remote ]  hp = remote · pc = otak'),
              const SizedBox(height: 6),
              Text('Hubungkan ke PC', style: context.tt.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Agen Neovarch berjalan di aplikasi desktop. HP ini hanya remote: kirim perintah, pantau tugas, dan setujui aksi agen dari mana saja di jaringanmu.',
                style: context.tt.bodyMedium?.copyWith(color: context.hc.mutedForeground),
              ),
              const SizedBox(height: 16),
              PaperScope(
                child: Builder(
                  builder: (context) => Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.hc.popover,
                      borderRadius: BorderRadius.circular(context.hc.corner + 2),
                      border: Border.all(color: context.hc.border),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final (i, t) in [
                        'Buka Neovarch Desktop di PC.',
                        'Masuk ke Pengaturan → Remote / Perangkat, aktifkan akses remote.',
                        'Pindai QR yang muncul, atau ketik alamat dan token-nya di bawah.',
                      ].indexed)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SizedBox(width: 26, child: Text('0${i + 1}', style: monoStyle(context, size: 12, color: context.cs.primary))),
                            Expanded(child: Text(t, style: context.tt.bodyMedium)),
                          ]),
                        ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
              if (canUseCamera)
                FilledButton.icon(
                  onPressed: _busy ? null : _scan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Pindai QR dari PC'),
                ),
              const SizedBox(height: 8),
              if (!_manual)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => setState(() => _manual = true),
                  icon: const Icon(Icons.keyboard_outlined),
                  label: const Text('Masukkan alamat & token'),
                )
              else ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _addr,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Alamat gateway PC',
                    hintText: '192.168.1.5:9319 atau tautan pemasangan',
                    helperText: 'Port bawaan 9319. Tautan neovarch://pair… juga bisa ditempel di sini.',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _token,
                  obscureText: !_showToken,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Token',
                    hintText: 'token dari Remote / Perangkat di PC',
                    suffixIcon: IconButton(
                      tooltip: _showToken ? 'Sembunyikan' : 'Tampilkan',
                      icon: Icon(_showToken ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _showToken = !_showToken),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nama PC (opsional)', hintText: 'PC Kantor')),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _busy ? null : _submitManual,
                  child: Text(_busy ? 'Menghubungkan…' : 'Hubungkan'),
                ),
              ],
              if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: CenterLoader(label: 'menghubungi PC…')),
              if (saved.isNotEmpty) ...[
                const SectionLabel('PC tersimpan', padding: EdgeInsets.fromLTRB(0, 24, 0, 6)),
                for (final d in saved)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.computer_outlined),
                    title: Text(d.name),
                    subtitle: Text(d.url, style: monoStyle(context, size: 11.5)),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () async {
                      await ref.read(remoteProvider).connectTo(d);
                      if (context.mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
                    },
                  ),
              ],
              const SizedBox(height: 20),
              Text(
                'Tip: HP dan PC harus di jaringan yang sama (Wi-Fi rumah/kantor) atau terhubung lewat Tailscale/VPN. Token disimpan terenkripsi di HP.',
                style: context.tt.bodySmall,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
