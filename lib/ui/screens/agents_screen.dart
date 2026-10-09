// Agent — spawn / kill / create (AgentSpawnPanel.tsx). In Mandiri mode an
// agent is an on-device profile you can edit (role, persona/SOUL, model).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';

class AgentsScreen extends ConsumerStatefulWidget {
  const AgentsScreen({super.key});
  @override
  ConsumerState<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends ConsumerState<AgentsScreen> {
  List<AgentRow> rows = [];
  bool loading = true;
  String? err;
  String? note;
  String? busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      err = null;
    });
    final res = await ref.read(officeProvider).backend.get('/api/neovarch/agents');
    if (!mounted) return;
    setState(() {
      loading = false;
      if (!res.ok) {
        err = res.error ?? 'gagal memuat daftar agent';
      } else {
        rows = res.list('available').map(AgentRow.fromJson).toList();
      }
    });
  }

  Future<void> _act(String action, String name) async {
    setState(() {
      busy = name;
      err = null;
      note = null;
    });
    final res = await ref.read(officeProvider).backend.post('/api/neovarch/agents', {'action': action, 'name': name});
    if (!mounted) return;
    setState(() {
      busy = null;
      if (!res.ok) {
        err = res.error ?? 'aksi gagal';
      } else if (action == 'kill') {
        final n = (res.map['purged'] as num?)?.toInt() ?? 0;
        note = n > 0 ? '"$name" dihapus permanen bersama $n tugasnya' : '"$name" dihapus permanen';
      }
    });
    await _load();
    ref.read(officeProvider).load();
  }

  Future<void> _kill(AgentRow r) async {
    if (!r.profile) return _act('kill', r.name);
    final ok = await confirmDialog(
      context,
      title: 'Hapus ${r.name} permanen?',
      body: 'Menghapus ${r.name} permanen — profil, sesi, memori, kunci, dan ${r.total} tugasnya. Tidak bisa dipulihkan.',
      confirm: 'Yakin hapus',
      destructive: true,
    );
    if (ok) await _act('kill', r.name);
  }

  @override
  Widget build(BuildContext context) {
    final local = ref.watch(officeProvider).backend.supportsMove;
    final inOffice = rows.where((r) => r.inOffice).toList();
    final out = rows.where((r) => !r.inOffice).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text('Agent', style: context.tt.titleMedium),
        actions: [IconButton(tooltip: 'Segarkan', onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'agent-fab',
        onPressed: () async {
          final created = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ProfileEditor(local: local)));
          if (created == true) {
            await _load();
            ref.read(officeProvider).load();
          }
        },
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Buat profil'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              Expanded(child: _Stat(label: 'di kantor', value: '${inOffice.length}')),
              const SizedBox(width: 10),
              Expanded(child: _Stat(label: 'profil tersedia', value: '${rows.length}')),
            ]),
          ),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 12), child: ErrorBanner(err!, onRetry: _load)),
          if (note != null) Padding(padding: const EdgeInsets.only(top: 12), child: NoteBanner(note!, ok: true)),
          if (loading && rows.isEmpty) const SizedBox(height: 260, child: SkeletonList(count: 4)),
          SectionLabel('Di kantor (${inOffice.length})'),
          if (!loading && inOffice.isEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('kosong', style: context.tt.bodySmall)),
          for (final r in inOffice)
            ListTile(
              leading: AgentAvatar(r.name, size: 36),
              title: Row(children: [
                Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (!r.profile) ...[const SizedBox(width: 8), StatusPill('tanpa profil', color: context.hc.warning)],
              ]),
              subtitle: Text('${r.total} tugas', style: context.tt.bodySmall),
              onTap: local
                  ? () async {
                      final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ProfileEditor(local: true, name: r.name)));
                      if (changed == true) _load();
                    }
                  : null,
              trailing: busy == r.name
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      if (local)
                        IconButton(
                          tooltip: 'Keluarkan dari kantor',
                          icon: const Icon(Icons.logout, size: 20),
                          onPressed: () async {
                            final store = ref.read(storeProvider);
                            final p = store.profile(r.name);
                            if (p != null) store.upsertProfile(p.copyWith(hidden: true));
                            await _load();
                            ref.read(officeProvider).load();
                          },
                        ),
                      r.profile
                          ? TextButton(
                              style: TextButton.styleFrom(foregroundColor: context.hc.destructive),
                              onPressed: () => _kill(r),
                              child: const Text('Kill'),
                            )
                          : TextButton(onPressed: () => _act('kill', r.name), child: const Text('Sembunyikan')),
                    ]),
            ),
          if (out.isNotEmpty) ...[
            SectionLabel('Di luar (${out.length})'),
            for (final r in out)
              ListTile(
                leading: Opacity(opacity: 0.55, child: AgentAvatar(r.name, size: 36)),
                title: Text(r.name),
                subtitle: Text(
                  r.reason == 'killed' ? 'disembunyikan' : (r.reason == 'no_profile' ? 'tanpa profil di disk' : 'tanpa tugas'),
                  style: context.tt.bodySmall,
                ),
                trailing: busy == r.name
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : FilledButton.tonal(onPressed: () => _act('spawn', r.name), child: const Text('Spawn')),
              ),
          ],
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: context.hc.card, borderRadius: BorderRadius.circular(8), border: Border.all(color: context.hc.strokeSoft)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: context.tt.titleLarge),
          Text(label, style: context.tt.bodySmall),
        ]),
      );
}

/// Create a profile (all modes) or edit one (Mandiri).
class ProfileEditor extends ConsumerStatefulWidget {
  const ProfileEditor({super.key, required this.local, this.name});
  final bool local;
  final String? name;
  @override
  ConsumerState<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends ConsumerState<ProfileEditor> {
  late final Profile? existing = widget.name == null ? null : ref.read(storeProvider).profile(widget.name!);
  late final _name = TextEditingController(text: existing?.name ?? '');
  late final _desc = TextEditingController(text: existing?.description ?? '');
  late final _prompt = TextEditingController(text: existing?.systemPrompt ?? '');
  late final _model = TextEditingController(text: existing?.model ?? '');
  late String role = existing?.role ?? 'backend';
  bool busy = false;
  String? err;

  Future<void> _save() async {
    final name = _name.text.trim().toLowerCase();
    setState(() {
      busy = true;
      err = null;
    });
    if (existing != null) {
      ref.read(storeProvider).upsertProfile(existing!.copyWith(
            role: role,
            description: _desc.text.trim(),
            systemPrompt: _prompt.text,
            model: _model.text.trim(),
            clearModel: _model.text.trim().isEmpty,
          ));
      ref.read(officeProvider).load();
      if (mounted) Navigator.pop(context, true);
      return;
    }
    final body = <String, dynamic>{'action': 'create', 'name': name, 'description': _desc.text.trim()};
    if (widget.local) body.addAll({'role': role, 'systemPrompt': _prompt.text});
    final res = await ref.read(officeProvider).backend.post('/api/neovarch/agents', body);
    if (!mounted) return;
    if (!res.ok) {
      setState(() {
        busy = false;
        err = res.error ?? 'gagal membuat profil';
      });
      return;
    }
    if (widget.local && _model.text.trim().isNotEmpty) {
      final p = ref.read(storeProvider).profile(name);
      if (p != null) ref.read(storeProvider).upsertProfile(p.copyWith(model: _model.text.trim()));
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(existing == null ? 'Profil baru' : 'Profil ${existing!.name}', style: context.tt.titleMedium),
        actions: [
          if (existing != null && settings.defaultProfile != existing!.name)
            TextButton(onPressed: () => settings.update((s) => s.defaultProfile = existing!.name), child: const Text('Jadikan default')),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (err != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: ErrorBanner(err!)),
        if (existing != null && settings.defaultProfile == existing!.name)
          const Padding(padding: EdgeInsets.only(bottom: 12), child: NoteBanner('Profil default untuk percakapan baru.', ok: true)),
        TextField(
          controller: _name,
          enabled: existing == null,
          decoration: const InputDecoration(labelText: 'Nama', hintText: 'budi', helperText: 'huruf kecil, angka, - dan _'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(controller: _desc, decoration: const InputDecoration(labelText: 'Deskripsi', hintText: 'Spesialis frontend')),
        if (widget.local) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: role,
            decoration: const InputDecoration(labelText: 'Peran'),
            items: [for (final r in agentRoles) DropdownMenuItem(value: r, child: Text(r))],
            onChanged: (v) => setState(() => role = v ?? role),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _prompt,
            minLines: 5,
            maxLines: 14,
            decoration: const InputDecoration(labelText: 'Persona / system prompt (SOUL)', alignLabelWithHint: true, hintText: 'Kamu insinyur QA yang teliti…'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _model,
            decoration: InputDecoration(
              labelText: 'Model khusus (opsional)',
              hintText: settings.activeProvider?.model ?? 'pakai model default',
              helperText: 'Kosongkan untuk memakai model default penyedia aktif',
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Profil dibuat kosong di server (tanpa --clone), mewarisi lingkungan shell seperti CLI.', style: context.tt.bodySmall),
          ),
        const SizedBox(height: 20),
        FilledButton(onPressed: busy || (existing == null && _name.text.trim().isEmpty) ? null : _save, child: Text(busy ? 'Menyimpan…' : (existing == null ? '+ Buat profil' : 'Simpan'))),
      ]),
    );
  }
}
