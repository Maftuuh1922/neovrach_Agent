// "Tugas baru" — dispatch a task straight into the board (NewTaskDialog.tsx).
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';

Future<void> showNewTaskSheet(BuildContext context) => showPaperSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: const NewTaskSheet(),
      ),
    );

class NewTaskSheet extends ConsumerStatefulWidget {
  const NewTaskSheet({super.key});
  @override
  ConsumerState<NewTaskSheet> createState() => _NewTaskSheetState();
}

class _NewTaskSheetState extends ConsumerState<NewTaskSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String? assignee;
  int priority = 0;
  bool busy = false;
  String? note;
  bool ok = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      busy = true;
      note = null;
    });
    final office = ref.read(officeProvider);
    final err = await office.createTask(
      title: _title.text.trim(),
      assignee: assignee ?? (office.agents.isNotEmpty ? office.agents.first.name : ''),
      body: _body.text,
      priority: priority,
    );
    if (!mounted) return;
    setState(() {
      busy = false;
      ok = err == null;
      note = err == null ? 'Dikirim ke antrean' : 'Gagal: $err';
    });
    if (err == null) {
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final office = ref.watch(officeProvider);
    final settings = ref.watch(settingsProvider);
    final names = office.agents.map((a) => a.name).toList();
    assignee ??= names.isNotEmpty ? names.first : null;
    final local = office.backend.supportsMove;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text('Tugas baru', style: context.tt.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _title,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Judul', hintText: 'Tambah test idempotensi refund'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: names.contains(assignee) ? assignee : null,
          decoration: const InputDecoration(labelText: 'Penanggung jawab'),
          items: [for (final n in names) DropdownMenuItem(value: n, child: Text(n))],
          onChanged: (v) => setState(() => assignee = v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _body,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'Detail (opsional)', hintText: 'Konteks, kriteria penerimaan', alignLabelWithHint: true),
        ),
        const SizedBox(height: 14),
        Text('PRIORITAS', style: context.tt.labelSmall),
        const SizedBox(height: 6),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('P0')),
            ButtonSegment(value: 1, label: Text('P1')),
            ButtonSegment(value: 2, label: Text('P2')),
            ButtonSegment(value: 3, label: Text('P3')),
          ],
          selected: {priority.clamp(0, 3)},
          onSelectionChanged: (s) => setState(() => priority = s.first),
        ),
        if (local)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              settings.autoRunTasks
                  ? (settings.llmConfigured ? 'Agent langsung mengerjakannya lalu memindahkan ke REVIEW.' : 'Atur penyedia LLM agar agent bisa mengerjakan tugas.')
                  : 'Auto-jalan nonaktif — jalankan dari detail tugas.',
              style: context.tt.bodySmall,
            ),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy || _title.text.trim().isEmpty || names.isEmpty ? null : _submit,
          child: Text(busy ? 'Mengirim…' : 'Kirim ke antrean'),
        ),
        if (names.isEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Belum ada agent untuk ditugasi.', style: context.tt.bodySmall)),
        if (note != null) Padding(padding: const EdgeInsets.only(top: 10), child: NoteBanner(note!, ok: ok)),
      ]),
    );
  }
}
