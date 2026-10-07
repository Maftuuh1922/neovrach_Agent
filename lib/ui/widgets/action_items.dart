// "Jadikan tugas" — shared by meetings (follow-ups from the minutes) and cron
// (a failing job). Nothing is created until the user confirms; rows whose
// owner did not resolve start OFF (ActionItems.tsx).
import 'package:flutter/material.dart';

import '../../data/office_backend.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import 'common.dart';

class _Row {
  final Candidate c;
  bool on;
  String assignee;
  _Row(this.c) : on = c.suggested != null, assignee = c.suggested ?? '';
}

class ActionItemsPanel extends StatefulWidget {
  const ActionItemsPanel({
    super.key,
    required this.backend,
    required this.candidates,
    required this.roster,
    required this.origin,
    this.label = 'JADIKAN TUGAS',
    this.empty = 'tidak ada item tindak lanjut',
    this.onDone,
  });
  final OfficeBackend backend;
  final List<Candidate> candidates;
  final List<String> roster;
  final TaskOrigin origin;
  final String label;
  final String empty;
  final void Function(int created)? onDone;

  @override
  State<ActionItemsPanel> createState() => _ActionItemsPanelState();
}

class _ActionItemsPanelState extends State<ActionItemsPanel> {
  late List<_Row> rows = widget.candidates.map(_Row.new).toList();
  bool busy = false;
  String? err;
  String? note;

  @override
  void didUpdateWidget(covariant ActionItemsPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.candidates, widget.candidates)) {
      rows = widget.candidates.map(_Row.new).toList();
      err = null;
      note = null;
    }
  }

  Future<void> _create() async {
    final chosen = rows.where((r) => r.on && r.assignee.isNotEmpty).toList();
    if (chosen.isEmpty) {
      setState(() => err = 'pilih minimal satu item dan penanggungnya');
      return;
    }
    setState(() {
      busy = true;
      err = null;
      note = null;
    });
    final res = await widget.backend.post('/api/hermes/tasks', {
      'origin': widget.origin.toJson(),
      'items': [
        for (final r in chosen)
          {
            'title': r.c.text,
            'assignee': r.assignee,
            // The deadline goes in the body, not the narrow card title.
            'body': [if (r.c.due != null) 'Tenggat: ${r.c.due}', if (r.c.body != null) r.c.body!].join('\n\n'),
          }
      ],
    });
    final created = (res.map['created'] as List?)?.length ?? 0;
    final failed = (res.map['failed'] as List?)?.length ?? 0;
    if (!mounted) return;
    setState(() {
      busy = false;
      if (created == 0) {
        err = res.error ?? 'tidak ada tugas yang dibuat';
      } else {
        note = failed > 0 ? '$created tugas dibuat, $failed gagal' : '$created tugas dibuat';
        for (final r in chosen) {
          r.on = false;
        }
      }
    });
    if (created > 0) widget.onDone?.call(created);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.candidates.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionLabel(widget.label, padding: const EdgeInsets.fromLTRB(0, 16, 0, 6)),
        Text(widget.empty, style: context.tt.bodySmall),
      ]);
    }
    final chosen = rows.where((r) => r.on && r.assignee.isNotEmpty).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionLabel('${widget.label} (${rows.length})', padding: const EdgeInsets.fromLTRB(0, 16, 0, 6)),
      for (final r in rows)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(4, 4, 10, 8),
          decoration: BoxDecoration(
            color: r.on ? context.cs.secondaryContainer.withValues(alpha: 0.5) : context.hc.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: r.on ? context.cs.primary.withValues(alpha: 0.5) : context.hc.strokeSoft),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CheckboxListTile(
              value: r.on,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(r.c.text, style: const TextStyle(fontSize: 13.5)),
              onChanged: (v) => setState(() {
                r.on = v ?? false;
                // Turning it on with no owner pre-selects the first roster name.
                if (r.on && r.assignee.isEmpty && widget.roster.isNotEmpty) r.assignee = widget.roster.first;
              }),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                DropdownButton<String>(
                  value: r.assignee.isEmpty ? null : r.assignee,
                  hint: const Text('— pilih penanggung —', style: TextStyle(fontSize: 13)),
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  items: [for (final n in widget.roster) DropdownMenuItem(value: n, child: Text(n, style: const TextStyle(fontSize: 13)))],
                  onChanged: (v) => setState(() => r.assignee = v ?? ''),
                ),
                if (r.c.due != null) StatusPill('tenggat ${r.c.due}'),
                if (r.c.owner.isNotEmpty && r.c.suggested == null) StatusPill('sumber menulis “${r.c.owner}”', color: context.hc.warning),
              ]),
            ),
          ]),
        ),
      FilledButton(onPressed: busy || chosen == 0 ? null : _create, child: Text(busy ? 'Membuat…' : 'Buat $chosen tugas')),
      if (note != null) Padding(padding: const EdgeInsets.only(top: 8), child: NoteBanner(note!, ok: true)),
      if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: ErrorBanner(err!, dense: true)),
    ]);
  }
}
