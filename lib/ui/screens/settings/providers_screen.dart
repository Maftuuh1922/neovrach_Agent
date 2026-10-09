// Providers & models — Accounts/API-keys UX: presets (OpenRouter, Nous
// Portal, OpenAI, Ollama, LM Studio, custom), per-provider keys in secure
// storage, model list fetched from /models with favourites, and a Test that
// exercises the route actually used (/chat/completions).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/llm_client.dart';
import '../../../models/models.dart';
import '../../../state/app_controller.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/common.dart';

class ProvidersScreen extends ConsumerWidget {
  const ProvidersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Penyedia & model', style: context.tt.titleMedium)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'prov-fab',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProviderEditor())),
        icon: const Icon(Icons.add),
        label: const Text('Tambah penyedia'),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text('Dipakai mode Mandiri: agent di ponsel memanggil penyedia OpenAI-compatible langsung. Kunci API disimpan terenkripsi di keystore perangkat.',
              style: context.tt.bodySmall),
        ),
        if (s.providers.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: EmptyState(icon: Icons.key_outlined, title: 'Belum ada penyedia', body: 'Tambahkan OpenRouter, Nous Portal, OpenAI, atau server lokal.'),
          ),
        for (final p in s.providers)
          RadioListTile<String>(
            value: p.id,
            // ignore: deprecated_member_use
            groupValue: s.activeProviderId,
            // ignore: deprecated_member_use
            onChanged: (v) => s.update((x) => x.activeProviderId = v ?? x.activeProviderId),
            title: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.model.isEmpty ? '(model belum dipilih)' : p.model, style: monoStyle(context, size: 12)),
              Text(p.baseUrl, style: context.tt.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Row(children: [
                StatusPill(s.hasKey(p.id) ? 'kunci tersimpan' : 'tanpa kunci', color: s.hasKey(p.id) ? context.hc.success : context.hc.mutedForeground),
                if (p.id == s.activeProviderId) ...[const SizedBox(width: 6), StatusPill('aktif', color: context.cs.primary)],
              ]),
            ]),
            secondary: IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProviderEditor(existing: p))),
            ),
          ),
      ]),
    );
  }
}

class ProviderEditor extends ConsumerStatefulWidget {
  const ProviderEditor({super.key, this.existing, this.onSaved});
  final ProviderConfig? existing;
  final VoidCallback? onSaved;
  @override
  ConsumerState<ProviderEditor> createState() => _ProviderEditorState();
}

class _ProviderEditorState extends ConsumerState<ProviderEditor> {
  late String presetId = widget.existing?.id.split('#').first ?? 'openrouter';
  late final _url = TextEditingController(text: widget.existing?.baseUrl ?? providerPresets.first.baseUrl);
  late final _model = TextEditingController(text: widget.existing?.model ?? providerPresets.first.defaultModel);
  late final _key = TextEditingController(text: widget.existing == null ? '' : ref.read(settingsProvider).keyFor(widget.existing!.id));
  late final _label = TextEditingController(text: widget.existing?.label ?? providerPresets.first.label);
  late List<String> favorites = List.of(widget.existing?.favoriteModels ?? const []);
  List<String> models = [];
  String modelQuery = '';
  bool busy = false;
  bool obscure = true;
  String? result;
  bool resultOk = false;

  ProviderPreset get preset => providerPresets.firstWhere((p) => p.id == presetId, orElse: () => providerPresets.last);

  void _pickPreset(String id) {
    setState(() {
      presetId = id;
      final p = preset;
      _url.text = p.baseUrl;
      _model.text = p.defaultModel;
      _label.text = p.label;
      models = [];
      result = null;
    });
  }

  LlmClient get _client => LlmClient(baseUrl: _url.text, apiKey: _key.text.trim(), model: _model.text.trim());

  Future<void> _fetchModels() async {
    setState(() {
      busy = true;
      result = null;
    });
    try {
      final m = await _client.listModels();
      setState(() {
        models = m;
        resultOk = true;
        result = '${m.length} model tersedia';
      });
    } catch (e) {
      setState(() {
        resultOk = false;
        result = 'Gagal mengambil daftar model: $e';
      });
    }
    setState(() => busy = false);
  }

  Future<void> _test() async {
    setState(() {
      busy = true;
      result = null;
    });
    try {
      final r = await _client.test();
      setState(() {
        resultOk = true;
        result = 'Terhubung — model menjawab: "${r.isEmpty ? '(kosong)' : r}"';
      });
    } catch (e) {
      setState(() {
        resultOk = false;
        result = 'Uji gagal (/chat/completions): $e';
      });
    }
    setState(() => busy = false);
  }

  Future<void> _save() async {
    final s = ref.read(settingsProvider);
    final id = widget.existing?.id ?? (s.providers.any((p) => p.id == presetId) ? '$presetId#${DateTime.now().millisecondsSinceEpoch}' : presetId);
    await s.upsertProvider(
      ProviderConfig(id: id, label: _label.text.trim().isEmpty ? preset.label : _label.text.trim(), baseUrl: _url.text.trim(), model: _model.text.trim(), favoriteModels: favorites),
      key: _key.text.trim(),
      activate: true,
    );
    widget.onSaved?.call();
    if (mounted && widget.onSaved == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = models.where((m) {
      if (modelQuery.isEmpty) return true;
      String norm(String x) => x.toLowerCase().replaceAll(RegExp(r'[-._\s]'), '');
      return norm(m).contains(norm(modelQuery));
    }).toList();
    final favs = favorites.where((f) => models.isEmpty || models.contains(f)).toList();
    final body = ListView(padding: const EdgeInsets.all(16), children: [
      if (widget.existing == null) ...[
        Text('PENYEDIA', style: context.tt.labelSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in providerPresets) ChoiceChip(label: Text(p.label), selected: presetId == p.id, onSelected: (_) => _pickPreset(p.id)),
        ]),
        if (preset.hint.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(preset.hint, style: context.tt.bodySmall)),
        const SizedBox(height: 16),
      ],
      TextField(controller: _label, decoration: const InputDecoration(labelText: 'Nama tampilan')),
      const SizedBox(height: 12),
      TextField(controller: _url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Base URL', hintText: 'https://…/v1')),
      const SizedBox(height: 12),
      TextField(
        controller: _key,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: preset.needsKey ? 'Kunci API' : 'Kunci API (opsional)',
          suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => obscure = !obscure)),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _model,
        style: monoStyle(context, size: 13.5),
        decoration: const InputDecoration(labelText: 'Model default', hintText: 'qwen/qwen3-coder'),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: busy ? null : _fetchModels, icon: const Icon(Icons.list, size: 18), label: const Text('Ambil daftar model')),
        OutlinedButton.icon(onPressed: busy ? null : _test, icon: const Icon(Icons.network_check, size: 18), label: const Text('Uji koneksi')),
      ]),
      if (busy) const Padding(padding: EdgeInsets.only(top: 12), child: NvLoader(size: 18)),
      if (result != null) Padding(padding: const EdgeInsets.only(top: 12), child: resultOk ? NoteBanner(result!, ok: true) : ErrorBanner(result!)),
      if (favs.isNotEmpty) ...[
        const SectionLabel('Favorit', padding: EdgeInsets.fromLTRB(0, 18, 0, 6)),
        for (final m in favs) _modelRow(m),
      ],
      if (models.isNotEmpty) ...[
        const SectionLabel('Semua model', padding: EdgeInsets.fromLTRB(0, 18, 0, 6)),
        TextField(
          onChanged: (v) => setState(() => modelQuery = v),
          decoration: const InputDecoration(hintText: 'Cari model (tanda - . _ dianggap sama)', prefixIcon: Icon(Icons.search, size: 18)),
        ),
        const SizedBox(height: 6),
        for (final m in filtered.take(200)) _modelRow(m),
      ],
      const SizedBox(height: 20),
      FilledButton(onPressed: _url.text.trim().isEmpty ? null : _save, child: const Text('Simpan & aktifkan')),
      if (widget.existing != null) ...[
        const SizedBox(height: 8),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: context.hc.destructive),
          onPressed: () async {
            if (await confirmDialog(context, title: 'Hapus penyedia?', body: 'Kunci API-nya ikut dihapus dari perangkat.', confirm: 'Hapus', destructive: true)) {
              await ref.read(settingsProvider).removeProvider(widget.existing!.id);
              if (context.mounted) Navigator.pop(context);
            }
          },
          child: const Text('Hapus penyedia'),
        ),
      ],
    ]);
    if (widget.onSaved != null) return body; // embedded in onboarding
    return Scaffold(appBar: AppBar(title: Text(widget.existing == null ? 'Tambah penyedia' : widget.existing!.label, style: context.tt.titleMedium)), body: body);
  }

  Widget _modelRow(String m) {
    final fav = favorites.contains(m);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: IconButton(
        icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? context.hc.warning : null, size: 20),
        onPressed: () => setState(() => fav ? favorites.remove(m) : favorites.add(m)),
      ),
      title: Text(m, style: monoStyle(context, size: 12.5)),
      trailing: _model.text == m ? Icon(Icons.check, color: context.cs.primary, size: 18) : null,
      onTap: () => setState(() => _model.text = m),
    );
  }
}
