// Connection mode: Mandiri (on-device, default), Remote gateway (hermes
// serve, JSON-RPC over WebSocket), the Next.js office server, or Demo.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api_result.dart';
import '../../../data/gateway_client.dart';
import '../../../data/office_backend.dart';
import '../../../models/models.dart';
import '../../../state/app_controller.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/common.dart';

class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});
  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  late final s = ref.read(settingsProvider);
  late ConnectionMode mode = s.mode;
  late final _server = TextEditingController(text: s.serverUrl);
  late final _gw = TextEditingController(text: s.gatewayUrl);
  late final _token = TextEditingController(text: s.gatewayToken);
  late final _profile = TextEditingController(text: s.gatewayProfile);
  late final _headers = TextEditingController(text: s.gatewayHeaders.entries.map((e) => '${e.key}: ${e.value}').join('\n'));
  late final _poll = TextEditingController(text: '${s.pollMs}');
  bool busy = false;
  String? result;
  bool ok = false;

  Map<String, String> _parseHeaders() {
    final out = <String, String>{};
    for (final line in _headers.text.split('\n')) {
      final i = line.indexOf(':');
      if (i > 0) out[line.substring(0, i).trim()] = line.substring(i + 1).trim();
    }
    return out;
  }

  Future<void> _test() async {
    setState(() {
      busy = true;
      result = null;
    });
    try {
      if (mode == ConnectionMode.server) {
        final b = ServerBackend(_server.text.trim());
        final ApiResult r = await b.get('/api/hermes/tasks');
        b.dispose();
        ok = r.ok;
        result = r.ok ? 'Server menjawab: ${r.list('tasks').length} tugas, ${r.list('agents').length} agent' : r.error;
      } else if (mode == ConnectionMode.gateway) {
        final c = GatewayClient(baseUrl: _gw.text.trim(), token: _token.text.trim(), headers: _parseHeaders());
        try {
          final r = await c.call('session.list', {'limit': 5, if (_profile.text.trim().isNotEmpty) 'profile': _profile.text.trim()}, const Duration(seconds: 15));
          final n = (r is Map && r['sessions'] is List) ? (r['sessions'] as List).length : 0;
          ok = true;
          result = 'Gateway terhubung (WebSocket /api/ws) — $n sesi terbaru terbaca';
        } finally {
          c.close();
        }
      } else {
        ok = true;
        result = 'Tidak perlu jaringan untuk mode ini.';
      }
    } catch (e) {
      ok = false;
      result = '$e';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _save() async {
    await s.setGatewayToken(_token.text.trim());
    s.update((x) {
      x.mode = mode;
      x.serverUrl = _server.text.trim();
      x.gatewayUrl = _gw.text.trim();
      x.gatewayProfile = _profile.text.trim();
      x.gatewayHeaders = _parseHeaders();
      x.pollMs = int.tryParse(_poll.text.trim())?.clamp(1500, 60000) ?? 4000;
    });
    if (mounted) {
      toast(context, 'Koneksi disimpan — ${mode.label}');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final desc = {
      ConnectionMode.local: 'Agent berjalan di ponsel: chat, memori, skill, berkas, Kanban, rapat, dan cron — memanggil penyedia LLM langsung. Tanpa PC.',
      ConnectionMode.gateway: 'Sambungkan ke backend `hermes serve` (tui_gateway) di VPS/PC lewat WebSocket. Sesi, alat, dan memori milik Hermes di sana. Kantor/Kanban tetap memakai agent di perangkat.',
      ConnectionMode.server: 'Sambungkan ke server Hermes Virtual Office (Next.js) yang menjalankan CLI hermes. Papan, rapat, cron, dan chat per-agent milik server.',
      ConnectionMode.demo: 'Papan contoh tanpa jaringan — untuk mencoba alur. Balasan chat adalah simulasi berlabel demo.',
    };
    return Scaffold(
      appBar: AppBar(title: Text('Koneksi', style: context.tt.titleMedium)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (final m in ConnectionMode.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: mode == m ? context.cs.secondaryContainer.withValues(alpha: 0.6) : context.hc.card,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: mode == m ? context.cs.primary : context.hc.strokeSoft)),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() {
                  mode = m;
                  result = null;
                }),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(switch (m) {
                      ConnectionMode.local => Icons.smartphone,
                      ConnectionMode.gateway => Icons.cloud_outlined,
                      ConnectionMode.server => Icons.dns_outlined,
                      ConnectionMode.demo => Icons.science_outlined,
                    }, color: mode == m ? context.cs.primary : context.hc.mutedForeground),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.label, style: context.tt.titleSmall),
                        const SizedBox(height: 4),
                        Text(desc[m]!, style: context.tt.bodySmall),
                      ]),
                    ),
                    if (mode == m) Icon(Icons.check_circle, color: context.cs.primary, size: 20),
                  ]),
                ),
              ),
            ),
          ),
        if (mode == ConnectionMode.server) ...[
          const SectionLabel('Server kantor', padding: EdgeInsets.fromLTRB(0, 12, 0, 8)),
          TextField(controller: _server, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'URL server', hintText: 'http://192.168.1.10:3000')),
          const SizedBox(height: 6),
          Text('Jalankan backend dengan `npm run dev -- -H 0.0.0.0`. Emulator Android: http://10.0.2.2:3000.', style: context.tt.bodySmall),
          const SizedBox(height: 12),
          TextField(controller: _poll, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Interval polling (ms)', helperText: 'default 4000, seperti NEXT_PUBLIC_POLL_MS')),
        ],
        if (mode == ConnectionMode.gateway) ...[
          const SectionLabel('Gateway jarak jauh', padding: EdgeInsets.fromLTRB(0, 12, 0, 8)),
          TextField(controller: _gw, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'URL backend', hintText: 'http://100.x.y.z:9319')),
          const SizedBox(height: 12),
          TextField(controller: _token, obscureText: true, decoration: const InputDecoration(labelText: 'Token sesi', helperText: 'dikirim sebagai ?token= dan Authorization: Bearer')),
          const SizedBox(height: 12),
          TextField(controller: _profile, decoration: const InputDecoration(labelText: 'Profil (opsional)', hintText: 'default')),
          const SizedBox(height: 12),
          TextField(
            controller: _headers,
            minLines: 2,
            maxLines: 5,
            style: monoStyle(context, size: 12.5),
            decoration: const InputDecoration(labelText: 'Header tambahan', hintText: 'CF-Access-Client-Id: …\nX-Proxy-Token: …', alignLabelWithHint: true),
          ),
          const SizedBox(height: 6),
          Text('Di server: `neovarch serve --host 0.0.0.0 --port 9319` di jaringan tepercaya (mis. Tailscale).', style: context.tt.bodySmall),
        ],
        const SizedBox(height: 16),
        Row(children: [
          if (mode == ConnectionMode.server || mode == ConnectionMode.gateway)
            Expanded(child: OutlinedButton.icon(onPressed: busy ? null : _test, icon: const Icon(Icons.network_check, size: 18), label: const Text('Uji'))),
          if (mode == ConnectionMode.server || mode == ConnectionMode.gateway) const SizedBox(width: 10),
          Expanded(child: FilledButton(onPressed: busy ? null : _save, child: const Text('Simpan & sambungkan ulang'))),
        ]),
        if (busy) const Padding(padding: EdgeInsets.only(top: 12), child: HermesLoader(size: 18)),
        if (result != null) Padding(padding: const EdgeInsets.only(top: 12), child: ok ? NoteBanner(result!, ok: true) : ErrorBanner(result!)),
      ]),
    );
  }
}
