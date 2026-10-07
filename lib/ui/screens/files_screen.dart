// File browser for the app workspace: browse folders, preview files the
// agent writes (markdown / code / text), create, edit and delete.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local_store.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/preview_sheet.dart';

class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key, this.dir = ''});
  final String dir;
  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  late String dir = widget.dir;

  String _join(String a, String b) => a.isEmpty ? b : '$a/$b';

  Future<void> _newFile() async {
    final name = await promptText(context, title: 'Berkas baru', hint: 'catatan.md', confirm: 'Buat');
    if (name == null || name.trim().isEmpty) return;
    final path = _join(dir, name.trim());
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => FileEditor(path: path, initial: '')));
  }

  Future<void> _newFolder() async {
    final name = await promptText(context, title: 'Folder baru', hint: 'proyek-a', confirm: 'Buat');
    if (name == null || name.trim().isEmpty) return;
    ref.read(storeProvider).makeFolder(_join(dir, name.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final (dirs, files) = store.listDir(dir);
    final crumbs = dir.isEmpty ? <String>[] : dir.split('/');
    return Scaffold(
      appBar: AppBar(
        title: Text('Berkas', style: context.tt.titleMedium),
        actions: [IconButton(tooltip: 'Folder baru', onPressed: _newFolder, icon: const Icon(Icons.create_new_folder_outlined))],
      ),
      floatingActionButton: FloatingActionButton.extended(heroTag: 'file-fab', onPressed: _newFile, icon: const Icon(Icons.note_add_outlined), label: const Text('Berkas')),
      body: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.hc.strokeSoft))),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              TextButton.icon(onPressed: () => setState(() => dir = ''), icon: const Icon(Icons.home_outlined, size: 18), label: const Text('workspace')),
              for (var i = 0; i < crumbs.length; i++) ...[
                Icon(Icons.chevron_right, size: 16, color: context.hc.mutedForeground),
                TextButton(onPressed: () => setState(() => dir = crumbs.sublist(0, i + 1).join('/')), child: Text(crumbs[i])),
              ],
            ]),
          ),
        ),
        Expanded(
          child: dirs.isEmpty && files.isEmpty
              ? const EmptyState(icon: Icons.folder_open, title: 'Folder kosong', body: 'Berkas yang ditulis agent dengan file_write muncul di sini.')
              : ListView(padding: const EdgeInsets.only(bottom: 96), children: [
                  for (final d in dirs)
                    ListTile(
                      leading: Icon(Icons.folder, color: context.hc.warning),
                      title: Text(d),
                      onTap: () => setState(() => dir = _join(dir, d)),
                      trailing: IconButton(
                        icon: const Icon(Icons.more_horiz, size: 18),
                        onPressed: () async {
                          if (await confirmDialog(context, title: 'Hapus folder?', body: 'Folder "$d" dan seluruh isinya dihapus.', confirm: 'Hapus', destructive: true)) {
                            store.deleteFile(_join(dir, d));
                          }
                        },
                      ),
                    ),
                  for (final f in files) _fileTile(f, store),
                ]),
        ),
      ]),
    );
  }

  Widget _fileTile(WorkspaceFile f, LocalStore store) {
    final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
    final icon = switch (ext) {
      'md' => Icons.article_outlined,
      'json' || 'yaml' || 'yml' => Icons.data_object,
      'dart' || 'py' || 'js' || 'ts' || 'kt' || 'sh' || 'html' || 'css' => Icons.code,
      _ => Icons.insert_drive_file_outlined,
    };
    return ListTile(
      leading: Icon(icon),
      title: Text(f.name),
      subtitle: Text('${f.size < 1024 ? '${f.size} b' : '${(f.size / 1024).toStringAsFixed(1)} KB'} · ${relTime(f.updatedAt)}', style: context.tt.bodySmall),
      onTap: () => showPreview(context, FilePreview(f.path, f.content)),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'edit') {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => FileEditor(path: f.path, initial: f.content)));
          } else if (v == 'delete') {
            if (await confirmDialog(context, title: 'Hapus berkas?', body: f.path, confirm: 'Hapus', destructive: true)) store.deleteFile(f.path);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Sunting')),
          PopupMenuItem(value: 'delete', child: Text('Hapus')),
        ],
      ),
    );
  }
}

class FileEditor extends ConsumerStatefulWidget {
  const FileEditor({super.key, required this.path, required this.initial});
  final String path;
  final String initial;
  @override
  ConsumerState<FileEditor> createState() => _FileEditorState();
}

class _FileEditorState extends ConsumerState<FileEditor> {
  late final _ctl = TextEditingController(text: widget.initial);
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.path, style: monoStyle(context, size: 13.5)),
          actions: [
            IconButton(
              tooltip: 'Pratinjau',
              icon: const Icon(Icons.visibility_outlined),
              onPressed: () => showPreview(context, FilePreview(widget.path, _ctl.text)),
            ),
            TextButton(
              onPressed: () {
                ref.read(storeProvider).writeFile(widget.path, _ctl.text);
                Navigator.pop(context);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
        body: TextField(
          controller: _ctl,
          expands: true,
          maxLines: null,
          autofocus: widget.initial.isEmpty,
          style: monoStyle(context, size: 13),
          decoration: const InputDecoration(border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, contentPadding: EdgeInsets.all(16)),
        ),
      );
}
