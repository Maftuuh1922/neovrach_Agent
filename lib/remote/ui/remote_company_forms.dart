// Perusahaan forms on the phone (bottom sheets): hire / edit an agent with its
// monthly budget, company and per-agent budgets, mission, goals, projects and
// routines. Each returns the `company.*` request body (or null when the user
// backs out); the screen sends it and re-reads. A body with `delete: true` /
// `terminate: true` asks the screen for the destructive call instead.
import 'package:flutter/material.dart';

import '../../theme/neovarch_mobile_theme.dart';
import '../company_models.dart';
import 'nv_widgets.dart';

const goalStatusLabel = {'active': 'aktif', 'done': 'tercapai', 'paused': 'ditunda'};
const projectStatusLabel = {'active': 'aktif', 'paused': 'ditunda', 'done': 'selesai'};

Future<bool> _confirm(BuildContext context, String title, String body, String action) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(key: const ValueKey('company-confirm'), onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    ) ==
    true;

/// One sheet scaffold: title, fields, an optional destructive action on the
/// left and the primary action on the right.
Future<T?> _sheet<T>(BuildContext context, Widget Function(BuildContext ctx, StateSetter setSheet) build) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: SingleChildScrollView(child: build(ctx, setSheet)),
        ),
      ),
    );

Widget _actions(BuildContext ctx, {required String primary, required Key primaryKey, required VoidCallback onPrimary, String? danger, Key? dangerKey, VoidCallback? onDanger}) =>
    Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(children: [
        if (danger != null) TextButton(key: dangerKey, onPressed: onDanger, style: TextButton.styleFrom(foregroundColor: NV.red), child: Text(danger)),
        const Spacer(),
        FilledButton(key: primaryKey, onPressed: onPrimary, child: Text(primary)),
      ]),
    );

Widget _field(TextEditingController c, String label, {Key? key, String? hint, int maxLines = 1, TextInputType? type, bool autofocus = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        key: key,
        controller: c,
        autofocus: autofocus,
        maxLines: maxLines,
        minLines: 1,
        keyboardType: type,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );

Widget _dropdown<V>({required Key key, required String label, required V value, required List<(V, String)> items, required ValueChanged<V?> onChanged}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<V>(
            key: key,
            isExpanded: true,
            value: items.any((e) => e.$1 == value) ? value : null,
            items: [for (final (v, l) in items) DropdownMenuItem<V>(value: v, child: Text(l, overflow: TextOverflow.ellipsis))],
            onChanged: onChanged,
          ),
        ),
      ),
    );

const _budgetHint = 'Kosongkan = tanpa batas. Lewat 100% pegawai otomatis dijeda.';

Widget _budgetFields(TextEditingController cents, TextEditingController tokens) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _field(cents, r'Anggaran/bulan ($)', key: const ValueKey('company-budget-cents'), hint: 'mis. 5', type: const TextInputType.numberWithOptions(decimal: true))),
        const SizedBox(width: 10),
        Expanded(child: _field(tokens, 'Batas token/bulan', key: const ValueKey('company-budget-tokens'), hint: 'mis. 200000', type: TextInputType.number)),
      ]),
      Text(_budgetHint, style: TextStyle(fontSize: 11.5, color: NV.faint)),
    ]);

int _tokens(String s) => int.tryParse(s.trim().replaceAll('.', '').replaceAll(',', '').replaceAll(' ', '')) ?? 0;

// ---------------------------------------------------------------- agents --

/// Hire ([agent] null) or edit an agent. Hiring returns `agent.save` without
/// an id (the PC files a hire approval when the company requires it).
Future<Map<String, dynamic>?> showAgentForm(BuildContext context, {required CompanySnapshot snap, CompanyAgent? agent}) {
  final a = agent;
  final name = TextEditingController(text: a?.name ?? '');
  final title = TextEditingController(text: a?.title ?? '');
  final job = TextEditingController(text: a?.jobDescription ?? '');
  final cents = TextEditingController(text: centsToDollars(a?.budgetMonthlyCents ?? 0));
  final tokens = TextEditingController(text: (a?.budgetMonthlyTokens ?? 0) > 0 ? '${a!.budgetMonthlyTokens}' : '');
  int? manager = a?.reportsTo;
  // a manager can't be the agent itself or anyone under it
  final blocked = <int>{};
  if (a != null) {
    blocked.add(a.id);
    var grew = true;
    while (grew) {
      grew = false;
      for (final x in snap.agents) {
        if (x.reportsTo != null && blocked.contains(x.reportsTo) && blocked.add(x.id)) grew = true;
      }
    }
  }
  String? err;
  return _sheet<Map<String, dynamic>>(context, (ctx, setSheet) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      NvSheetTitle(kicker: 'perusahaan', title: a == null ? 'Rekrut pegawai' : 'Ubah ${a.name}'),
      if (a == null && snap.requireHireApproval)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text('Rekrutmen perlu persetujuan: pegawai baru muncul di Setujui dulu.', style: TextStyle(fontSize: 12.5, color: NV.muted)),
        ),
      _field(name, 'Nama', key: const ValueKey('company-agent-name'), autofocus: a == null),
      _field(title, 'Jabatan', key: const ValueKey('company-agent-title'), hint: 'mis. Penulis konten'),
      _dropdown<int?>(
        key: const ValueKey('company-agent-manager'),
        label: 'Atasan',
        value: manager,
        items: [
          (null, 'Tanpa atasan (puncak)'),
          for (final x in snap.agents.where((x) => !blocked.contains(x.id) && x.status != 'pending_approval')) (x.id, '${x.name} · ${x.title}'),
        ],
        onChanged: (v) => setSheet(() => manager = v),
      ),
      _field(job, 'Deskripsi tugas', key: const ValueKey('company-agent-job'), hint: 'Apa tanggung jawabnya?', maxLines: 4),
      _budgetFields(cents, tokens),
      if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: TextStyle(color: NV.red, fontSize: 12.5))),
      _actions(
        ctx,
        primary: a == null ? 'Rekrut' : 'Simpan',
        primaryKey: const ValueKey('company-agent-save'),
        onPrimary: () {
          final n = name.text.trim();
          if (n.isEmpty) return setSheet(() => err = 'Nama pegawai wajib diisi');
          Navigator.pop(ctx, {
            'id': ?a?.id,
            'name': n,
            'title': title.text.trim(),
            'reports_to': manager,
            'job_description': job.text.trim(),
            'budget_monthly_cents': dollarsToCents(cents.text),
            'budget_monthly_tokens': _tokens(tokens.text),
          });
        },
        danger: a == null ? null : 'Berhentikan',
        dangerKey: const ValueKey('company-agent-terminate'),
        onDanger: a == null
            ? null
            : () async {
                final ok = await _confirm(ctx, 'Berhentikan ${a.name}?', 'Tiketnya dilepas dan bawahannya pindah ke atasannya. Tidak bisa dibatalkan.', 'Berhentikan');
                if (ok && ctx.mounted) Navigator.pop(ctx, {'terminate': true});
              },
      ),
    ]);
  });
}

// ---------------------------------------------------------------- budget --

/// Monthly limits for the company (agent null) or one agent.
Future<Map<String, dynamic>?> showBudgetForm(BuildContext context, {required String title, required int cents, required int tokens}) {
  final c = TextEditingController(text: centsToDollars(cents));
  final t = TextEditingController(text: tokens > 0 ? '$tokens' : '');
  return _sheet<Map<String, dynamic>>(context, (ctx, setSheet) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        NvSheetTitle(kicker: 'biaya', title: title),
        _budgetFields(c, t),
        _actions(ctx,
            primary: 'Simpan',
            primaryKey: const ValueKey('company-budget-save'),
            onPrimary: () => Navigator.pop(ctx, {'budget_monthly_cents': dollarsToCents(c.text), 'budget_monthly_tokens': _tokens(t.text)})),
      ]));
}

// --------------------------------------------------------------- mission --

Future<Map<String, dynamic>?> showMissionForm(BuildContext context, {required String name, required String mission}) {
  final n = TextEditingController(text: name);
  final m = TextEditingController(text: mission);
  String? err;
  return _sheet<Map<String, dynamic>>(context, (ctx, setSheet) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const NvSheetTitle(kicker: 'perusahaan', title: 'Nama & misi'),
        _field(n, 'Nama perusahaan', key: const ValueKey('company-name')),
        _field(m, 'Misi', key: const ValueKey('company-mission'), hint: 'Tujuan besar yang dikejar semua pegawai', maxLines: 4),
        if (err != null) Text(err!, style: TextStyle(color: NV.red, fontSize: 12.5)),
        _actions(ctx, primary: 'Simpan', primaryKey: const ValueKey('company-mission-save'), onPrimary: () {
          if (n.text.trim().isEmpty) return setSheet(() => err = 'Nama perusahaan wajib diisi');
          Navigator.pop(ctx, {'name': n.text.trim(), 'mission': m.text.trim()});
        }),
      ]));
}

// ----------------------------------------------------------------- goals --

Future<Map<String, dynamic>?> showGoalForm(BuildContext context, {required CompanySnapshot snap, CompanyGoal? goal}) {
  final g = goal;
  final title = TextEditingController(text: g?.title ?? '');
  final desc = TextEditingController(text: g?.description ?? '');
  int? parent = g?.parentId;
  var status = g?.status ?? 'active';
  final blocked = <int>{};
  if (g != null) {
    blocked.add(g.id);
    var grew = true;
    while (grew) {
      grew = false;
      for (final x in snap.goals) {
        if (x.parentId != null && blocked.contains(x.parentId) && blocked.add(x.id)) grew = true;
      }
    }
  }
  String? err;
  return _sheet<Map<String, dynamic>>(context, (ctx, setSheet) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        NvSheetTitle(kicker: 'rencana', title: g == null ? 'Tujuan baru' : 'Ubah tujuan'),
        _field(title, 'Judul tujuan', key: const ValueKey('company-goal-title'), autofocus: g == null),
        _field(desc, 'Keterangan', key: const ValueKey('company-goal-desc'), maxLines: 3),
        _dropdown<int?>(
          key: const ValueKey('company-goal-parent'),
          label: 'Bagian dari',
          value: parent,
          items: [(null, 'Langsung di bawah misi'), for (final x in snap.goals.where((x) => !blocked.contains(x.id))) (x.id, x.title)],
          onChanged: (v) => setSheet(() => parent = v),
        ),
        if (g != null)
          _dropdown<String>(
            key: const ValueKey('company-goal-status'),
            label: 'Status',
            value: status,
            items: [for (final e in goalStatusLabel.entries) (e.key, e.value), if (!goalStatusLabel.containsKey(status)) (status, status)],
            onChanged: (v) => setSheet(() => status = v ?? status),
          ),
        if (err != null) Text(err!, style: TextStyle(color: NV.red, fontSize: 12.5)),
        _actions(
          ctx,
          primary: g == null ? 'Tambah' : 'Simpan',
          primaryKey: const ValueKey('company-goal-save'),
          onPrimary: () {
            if (title.text.trim().isEmpty) return setSheet(() => err = 'Judul tujuan wajib diisi');
            Navigator.pop(ctx, {
              'id': ?g?.id,
              'title': title.text.trim(),
              'description': desc.text.trim(),
              if (parent != null || g?.parentId != null) 'parent_id': parent,
              if (g != null) 'status': status,
            });
          },
          danger: g == null ? null : 'Hapus',
          dangerKey: const ValueKey('company-goal-delete'),
          onDanger: g == null
              ? null
              : () async {
                  if (await _confirm(ctx, 'Hapus tujuan?', '“${g.title}” dihapus. Proyek dan tiketnya tetap ada.', 'Hapus') && ctx.mounted) {
                    Navigator.pop(ctx, {'delete': true});
                  }
                },
        ),
      ]));
}

// -------------------------------------------------------------- projects --

Future<Map<String, dynamic>?> showProjectForm(BuildContext context, {required CompanySnapshot snap, CompanyProject? project}) {
  final p = project;
  final name = TextEditingController(text: p?.name ?? '');
  final desc = TextEditingController(text: p?.description ?? '');
  final cents = TextEditingController(text: centsToDollars(p?.budgetMonthlyCents ?? 0));
  int? goal = p?.goalId;
  var status = p?.status ?? 'active';
  String? err;
  return _sheet<Map<String, dynamic>>(context, (ctx, setSheet) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        NvSheetTitle(kicker: 'rencana', title: p == null ? 'Proyek baru' : 'Ubah proyek'),
        _field(name, 'Nama proyek', key: const ValueKey('company-project-name'), autofocus: p == null),
        _field(desc, 'Keterangan', key: const ValueKey('company-project-desc'), maxLines: 3),
        _dropdown<int?>(
          key: const ValueKey('company-project-goal'),
          label: 'Tujuan',
          value: goal,
          items: [(null, 'Tanpa tujuan'), for (final x in snap.goals) (x.id, x.title)],
          onChanged: (v) => setSheet(() => goal = v),
        ),
        _field(cents, r'Anggaran/bulan ($)', key: const ValueKey('company-project-budget'), hint: 'kosong = tanpa batas', type: const TextInputType.numberWithOptions(decimal: true)),
        if (p != null)
          _dropdown<String>(
            key: const ValueKey('company-project-status'),
            label: 'Status',
            value: status,
            items: [for (final e in projectStatusLabel.entries) (e.key, e.value), if (!projectStatusLabel.containsKey(status)) (status, status)],
            onChanged: (v) => setSheet(() => status = v ?? status),
          ),
        if (err != null) Text(err!, style: TextStyle(color: NV.red, fontSize: 12.5)),
        _actions(
          ctx,
          primary: p == null ? 'Buat' : 'Simpan',
          primaryKey: const ValueKey('company-project-save'),
          onPrimary: () {
            if (name.text.trim().isEmpty) return setSheet(() => err = 'Nama proyek wajib diisi');
            Navigator.pop(ctx, {
              'id': ?p?.id,
              'name': name.text.trim(),
              'description': desc.text.trim(),
              if (goal != null || p?.goalId != null) 'goal_id': goal,
              'budget_monthly_cents': dollarsToCents(cents.text),
              if (p != null) 'status': status,
            });
          },
          danger: p == null ? null : 'Hapus',
          dangerKey: const ValueKey('company-project-delete'),
          onDanger: p == null
              ? null
              : () async {
                  if (await _confirm(ctx, 'Hapus proyek?', '“${p.name}” dihapus. Tiketnya tetap ada tanpa proyek.', 'Hapus') && ctx.mounted) {
                    Navigator.pop(ctx, {'delete': true});
                  }
                },
        ),
      ]));
}

// -------------------------------------------------------------- routines --

Future<Map<String, dynamic>?> showRoutineForm(BuildContext context, {required CompanySnapshot snap, CompanyRoutine? routine}) {
  final r = routine;
  final name = TextEditingController(text: r?.name ?? '');
  final schedule = TextEditingController(text: r?.schedule ?? '');
  final title = TextEditingController(text: r == null || r.title == r.name ? '' : r.title);
  final desc = TextEditingController(text: r?.description ?? '');
  int? agent = r?.agentId;
  int? project = r?.projectId;
  var enabled = r?.enabled ?? true;
  String? err;
  return _sheet<Map<String, dynamic>>(context, (ctx, setSheet) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        NvSheetTitle(kicker: 'rencana', title: r == null ? 'Rutinitas baru' : 'Ubah rutinitas'),
        _field(name, 'Nama', key: const ValueKey('company-routine-name'), hint: 'mis. Laporan pagi', autofocus: r == null),
        _field(schedule, 'Jadwal', key: const ValueKey('company-routine-schedule'), hint: 'daily 08:00 · every 2h · 0 9 * * 1-5'),
        _field(title, 'Judul tiket (opsional)', key: const ValueKey('company-routine-title'), hint: 'sama dengan nama bila kosong'),
        _field(desc, 'Instruksi', key: const ValueKey('company-routine-desc'), maxLines: 3),
        _dropdown<int?>(
          key: const ValueKey('company-routine-agent'),
          label: 'Dikerjakan oleh',
          value: agent,
          items: [(null, 'Belum ditentukan'), for (final x in snap.agents.where((x) => x.status != 'pending_approval')) (x.id, x.name)],
          onChanged: (v) => setSheet(() => agent = v),
        ),
        _dropdown<int?>(
          key: const ValueKey('company-routine-project'),
          label: 'Proyek',
          value: project,
          items: [(null, 'Tanpa proyek'), for (final x in snap.projects) (x.id, x.name)],
          onChanged: (v) => setSheet(() => project = v),
        ),
        SwitchListTile(
          key: const ValueKey('company-routine-enabled'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Aktif'),
          value: enabled,
          onChanged: (v) => setSheet(() => enabled = v),
        ),
        if (err != null) Text(err!, style: TextStyle(color: NV.red, fontSize: 12.5)),
        _actions(
          ctx,
          primary: r == null ? 'Buat' : 'Simpan',
          primaryKey: const ValueKey('company-routine-save'),
          onPrimary: () {
            final n = name.text.trim();
            final sch = schedule.text.trim();
            if (n.isEmpty) return setSheet(() => err = 'Nama rutinitas wajib diisi');
            if (sch.isEmpty) return setSheet(() => err = 'Jadwal wajib diisi');
            Navigator.pop(ctx, {
              'id': ?r?.id,
              'name': n,
              if (r == null || sch != r.schedule) 'schedule': sch,
              'title': title.text.trim().isEmpty ? n : title.text.trim(),
              'description': desc.text.trim(),
              if (agent != null || r?.agentId != null) 'agent_id': agent,
              if (project != null || r?.projectId != null) 'project_id': project,
              'enabled': enabled,
            });
          },
          danger: r == null ? null : 'Hapus',
          dangerKey: const ValueKey('company-routine-delete'),
          onDanger: r == null
              ? null
              : () async {
                  if (await _confirm(ctx, 'Hapus rutinitas?', '“${r.name}” tidak akan membuat tiket lagi.', 'Hapus') && ctx.mounted) {
                    Navigator.pop(ctx, {'delete': true});
                  }
                },
        ),
      ]));
}
