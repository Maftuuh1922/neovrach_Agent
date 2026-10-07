// Projects own a workspace folder and group sessions (Desktop: "Projects own
// workspace cwd"). Agents in a project session save files into its folder.
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import 'files_screen.dart';

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, {Project? p}) async {
    final name = TextEditingController(text: p?.name ?? '');
    final desc = TextEditingController(text: p?.description ?? '');
    final folder = TextEditingController(text: p?.folder ?? '');
    final ok = await showPaperDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p == null ? 'Proyek baru' : 'Ubah proyek', style: ctx.tt.titleMedium),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Nama')),
          const SizedBox(height: 10),
          TextField(controller: desc, maxLines: 3, minLines: 1, decoration: const InputDecoration(labelText: 'Deskripsi / konteks untuk agent')),
          const SizedBox(height: 10),
          TextField(controller: folder, decoration: const InputDecoration(labelText: 'Folder workspace', hintText: 'otomatis dari nama')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final store = ref.read(storeProvider);
    final slug = name.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    store.upsertProject(Project(
      id: p?.id ?? store.uid('p'),
      name: name.text.trim(),
      description: desc.text.trim(),
      folder: folder.text.trim().isEmpty ? 'proyek/$slug' : folder.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final chat = ref.watch(chatProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Proyek', style: context.tt.titleMedium)),
      floatingActionButton: FloatingActionButton.extended(heroTag: 'proj-fab', onPressed: () => _edit(context, ref), icon: const Icon(Icons.add), label: const Text('Proyek')),
      body: store.projects.isEmpty
          ? const EmptyState(icon: Icons.folder_copy_outlined, title: 'Belum ada proyek', body: 'Proyek mengelompokkan sesi chat dan memberi agent folder kerja sendiri.')
          : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
              for (final p in store.projects)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
                  decoration: BoxDecoration(color: context.hc.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: context.hc.strokeSoft)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.folder_copy_outlined, color: context.cs.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(p.name, style: context.tt.titleSmall)),
                      PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'edit') _edit(context, ref, p: p);
                          if (v == 'delete' &&
                              await confirmDialog(context, title: 'Hapus proyek?', body: 'Sesi tetap ada, hanya pengelompokannya yang dilepas. Berkas di folder tidak dihapus.', confirm: 'Hapus', destructive: true)) {
                            store.deleteProject(p.id);
                          }
                        },
                        itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Ubah')), PopupMenuItem(value: 'delete', child: Text('Hapus'))],
                      ),
                    ]),
                    if (p.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4, right: 8), child: Text(p.description, style: context.tt.bodySmall)),
                    const SizedBox(height: 6),
                    Text('${store.sessions.where((s) => s.projectId == p.id).length} sesi · ${p.folder}/', style: monoStyle(context, size: 11.5, color: context.hc.mutedForeground)),
                    Wrap(children: [
                      TextButton.icon(
                        onPressed: () async {
                          await chat.newSession(projectId: p.id);
                          if (context.mounted) {
                            Navigator.pop(context);
                            toast(context, 'Sesi baru di proyek ${p.name} — buka tab Chat');
                          }
                        },
                        icon: const Icon(Icons.chat_bubble_outline, size: 16),
                        label: const Text('Chat di proyek'),
                      ),
                      TextButton.icon(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FilesScreen(dir: p.folder))),
                        icon: const Icon(Icons.folder_open, size: 16),
                        label: const Text('Buka folder'),
                      ),
                    ]),
                  ]),
                ),
            ]),
    );
  }
}
