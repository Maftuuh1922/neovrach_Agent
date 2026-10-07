// Memory viewer/editor: what agents remember (memory_write), shared or per
// agent. Add, edit, move between scopes, delete.
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';

class MemoryScreen extends ConsumerStatefulWidget {
  const MemoryScreen({super.key});
  @override
  ConsumerState<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends ConsumerState<MemoryScreen> {
  String scope = 'all';
  String query = '';

  Future<void> _edit({MemoryNote? note}) async {
    final store = ref.read(storeProvider);
    final ctl = TextEditingController(text: note?.text ?? '');
    var sc = note?.scope ?? '*';
    final ok = await showPaperDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(note == null ? 'Catatan memori baru' : 'Ubah catatan', style: ctx.tt.titleMedium),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: ctl, autofocus: true, minLines: 2, maxLines: 6, decoration: const InputDecoration(hintText: 'Pengguna lebih suka jawaban singkat')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: sc,
              decoration: const InputDecoration(labelText: 'Cakupan'),
              items: [
                const DropdownMenuItem(value: '*', child: Text('Bersama (semua agent)')),
                for (final p in store.profiles) DropdownMenuItem(value: p.name, child: Text('Hanya ${p.name}')),
              ],
              onChanged: (v) => set(() => sc = v ?? '*'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (ok != true || ctl.text.trim().isEmpty) return;
    if (note == null) {
      store.addMemory(sc, ctl.text);
    } else {
      store.updateMemory(MemoryNote(id: note.id, scope: sc, text: ctl.text.trim(), createdAt: note.createdAt));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final list = store.memory.where((m) {
      if (scope != 'all' && m.scope != scope) return false;
      return query.isEmpty || m.text.toLowerCase().contains(query.toLowerCase());
    }).toList();
    return Scaffold(
      appBar: AppBar(title: Text('Memori', style: context.tt.titleMedium)),
      floatingActionButton: FloatingActionButton.extended(heroTag: 'mem-fab', onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Catatan')),
      body: Column(children: [
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), children: [
            for (final s in ['all', '*', ...store.profiles.map((p) => p.name)])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(s == 'all' ? 'Semua' : (s == '*' ? 'Bersama' : s)),
                  selected: scope == s,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => scope = s),
                ),
              ),
          ]),
        ),
        if (store.memory.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (v) => setState(() => query = v),
              decoration: const InputDecoration(hintText: 'Cari memori', prefixIcon: Icon(Icons.search, size: 18), filled: false, border: InputBorder.none, enabledBorder: InputBorder.none),
            ),
          ),
        Expanded(
          child: list.isEmpty
              ? const EmptyState(icon: Icons.bookmark_border, title: 'Memori kosong', body: 'Agent menyimpan fakta penting di sini dengan memory_write — atau tambahkan sendiri.')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => Divider(color: context.hc.strokeSoft, height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (_, i) {
                    final m = list[i];
                    return ListTile(
                      title: Text(m.text, style: const TextStyle(fontSize: 14)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(children: [
                          StatusPill(m.scope == '*' ? 'bersama' : m.scope, color: m.scope == '*' ? context.hc.info : null),
                          const SizedBox(width: 8),
                          Text(relTime(m.createdAt), style: context.tt.bodySmall),
                          const SizedBox(width: 8),
                          Text(m.id, style: monoStyle(context, size: 10, color: context.hc.mutedForeground)),
                        ]),
                      ),
                      onTap: () => _edit(note: m),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () async {
                          if (await confirmDialog(context, title: 'Lupakan catatan ini?', body: m.text, confirm: 'Hapus', destructive: true)) {
                            store.deleteMemory(m.id);
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
