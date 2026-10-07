// Skills — reusable instruction docs the agent loads with `skill_load`.
// List with enable toggles; create / edit / delete with a markdown preview.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/markdown_view.dart';

class SkillsScreen extends ConsumerWidget {
  const SkillsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Skill', style: context.tt.titleMedium)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'skill-fab',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SkillEditor())),
        icon: const Icon(Icons.add),
        label: const Text('Skill baru'),
      ),
      body: store.skills.isEmpty
          ? const EmptyState(icon: Icons.auto_awesome_motion_outlined, title: 'Belum ada skill', body: 'Skill adalah instruksi yang bisa dimuat agent saat dibutuhkan.')
          : ListView(padding: const EdgeInsets.only(bottom: 96, top: 8), children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text('Agent melihat katalog skill aktif di system prompt dan memuat isinya dengan alat skill_load.', style: context.tt.bodySmall),
              ),
              for (final s in store.skills)
                ListTile(
                  leading: Icon(Icons.auto_awesome_motion_outlined, color: s.enabled ? context.cs.primary : null),
                  title: Text(s.name, style: monoStyle(context, size: 13.5, weight: FontWeight.w600)),
                  subtitle: Text(s.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall),
                  trailing: Switch(
                    value: s.enabled,
                    onChanged: (v) => store.upsertSkill(Skill(name: s.name, description: s.description, body: s.body, enabled: v, updatedAt: s.updatedAt)),
                  ),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SkillEditor(skill: s))),
                ),
            ]),
    );
  }
}

class SkillEditor extends ConsumerStatefulWidget {
  const SkillEditor({super.key, this.skill});
  final Skill? skill;
  @override
  ConsumerState<SkillEditor> createState() => _SkillEditorState();
}

class _SkillEditorState extends ConsumerState<SkillEditor> with SingleTickerProviderStateMixin {
  late final _name = TextEditingController(text: widget.skill?.name ?? '');
  late final _desc = TextEditingController(text: widget.skill?.description ?? '');
  late final _body = TextEditingController(text: widget.skill?.body ?? '# Nama skill\n\nLangkah-langkah:\n1. …\n');
  late final _tabs = TabController(length: 2, vsync: this);
  String? err;

  void _save() {
    final name = _name.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]+'), '-');
    if (name.isEmpty) {
      setState(() => err = 'nama wajib diisi');
      return;
    }
    final store = ref.read(storeProvider);
    if (widget.skill == null && store.skills.any((s) => s.name == name)) {
      setState(() => err = 'skill "$name" sudah ada');
      return;
    }
    store.upsertSkill(
      Skill(name: name, description: _desc.text.trim(), body: _body.text, enabled: widget.skill?.enabled ?? true, updatedAt: DateTime.now().toIso8601String()),
      oldName: widget.skill?.name,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.skill == null ? 'Skill baru' : widget.skill!.name, style: context.tt.titleMedium),
        actions: [
          if (widget.skill != null)
            IconButton(
              tooltip: 'Hapus',
              color: context.hc.destructive,
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirmDialog(context, title: 'Hapus skill?', body: widget.skill!.name, confirm: 'Hapus', destructive: true)) {
                  ref.read(storeProvider).deleteSkill(widget.skill!.name);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
          TextButton(onPressed: _save, child: const Text('Simpan')),
        ],
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Sunting'), Tab(text: 'Pratinjau')]),
      ),
      body: TabBarView(controller: _tabs, children: [
        ListView(padding: const EdgeInsets.all(16), children: [
          if (err != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: ErrorBanner(err!)),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nama', hintText: 'ringkas-dokumen')),
          const SizedBox(height: 12),
          TextField(controller: _desc, decoration: const InputDecoration(labelText: 'Deskripsi singkat (tampil di katalog)')),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            minLines: 14,
            maxLines: null,
            style: monoStyle(context, size: 13),
            decoration: const InputDecoration(labelText: 'Instruksi (markdown)', alignLabelWithHint: true),
          ),
        ]),
        AnimatedBuilder(
          animation: _body,
          builder: (_, _) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: MarkdownView(_body.text)),
        ),
      ]),
    );
  }
}
