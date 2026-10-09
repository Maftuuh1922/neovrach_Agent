// Cron (CronPanel.tsx): jobs are created PAUSED by default, and every
// action that changes a schedule needs a confirmation.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cron_schedule.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/action_items.dart';
import '../widgets/common.dart';
import '../widgets/markdown_view.dart';

class CronScreen extends ConsumerStatefulWidget {
  const CronScreen({super.key});
  @override
  ConsumerState<CronScreen> createState() => _CronScreenState();
}

class _CronScreenState extends ConsumerState<CronScreen> {
  List<CronJob> jobs = [];
  List<CronRun> runs = [];
  bool loading = true;
  String? err;
  String? note;
  String? busy;
  final Map<String, List<Candidate>> items = {};
  List<String> roster = [];

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
    final res = await ref.read(officeProvider).backend.get('/api/neovarch/cron');
    if (!mounted) return;
    setState(() {
      loading = false;
      if (!res.ok) {
        err = res.error ?? 'gagal memuat cron';
      } else {
        jobs = res.list('jobs').map(CronJob.fromJson).toList();
        runs = res.list('runs').map(CronRun.fromJson).toList();
      }
    });
  }

  Future<void> _act(CronJob j, String action) async {
    const confirmText = {'pause': 'Yakin jeda?', 'resume': 'Yakin aktifkan?', 'run': 'Yakin jalankan?', 'remove': 'Yakin hapus?'};
    final ok = await confirmDialog(
      context,
      title: confirmText[action]!,
      body: '${j.name} · ${j.schedule}',
      confirm: switch (action) { 'pause' => 'Jeda', 'resume' => 'Aktifkan', 'run' => 'Jalankan', _ => 'Hapus' },
      destructive: action == 'remove',
    );
    if (!ok) return;
    setState(() {
      busy = j.id + action;
      err = null;
      note = null;
    });
    final res = await ref.read(officeProvider).backend.post('/api/neovarch/cron', {'action': action, 'id': j.id});
    if (!mounted) return;
    setState(() {
      busy = null;
      if (!res.ok) {
        err = res.error ?? 'aksi gagal';
      } else {
        note = switch (action) {
          'remove' => 'job dihapus',
          'run' => 'job akan jalan pada tick berikutnya',
          'pause' => 'job dipause',
          _ => 'job diaktifkan',
        };
      }
    });
    await _load();
  }

  Future<void> _loadItems(String jobId) async {
    setState(() => busy = 'items$jobId');
    final res = await ref.read(officeProvider).backend.get('/api/neovarch/cron/actions', {'from': jobId});
    if (!mounted) return;
    setState(() {
      busy = null;
      if (!res.ok) {
        err = res.error ?? 'gagal membaca tindak lanjut';
      } else {
        items[jobId] = res.list('items').map(Candidate.fromJson).toList();
        roster = ((res.map['roster'] as List?) ?? []).map((e) => '$e').toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final office = ref.watch(officeProvider);
    final local = office.backend.supportsMove;
    return Scaffold(
      appBar: AppBar(
        title: Text('Cron', style: context.tt.titleMedium),
        actions: [IconButton(tooltip: 'Segarkan', onPressed: loading ? null : _load, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'cron-fab',
        onPressed: () async {
          final r = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const NewCronScreen()));
          if (r != null) {
            setState(() => note = r);
            _load();
          }
        },
        icon: const Icon(Icons.add_alarm),
        label: const Text('Buat job'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
          if (err != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: ErrorBanner(err!, onRetry: _load)),
          if (note != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: NoteBanner(note!, ok: true)),
          if (local)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Mode Mandiri: job berjalan selama aplikasi terbuka (Android membatasi kerja latar). Hasilnya disimpan ke Berkas › cron/.',
                  style: context.tt.bodySmall),
            ),
          SectionLabel('Job (${jobs.length})', padding: const EdgeInsets.fromLTRB(0, 8, 0, 8)),
          if (loading && jobs.isEmpty) const SizedBox(height: 200, child: SkeletonList(count: 3)),
          if (!loading && jobs.isEmpty) const EmptyState(icon: Icons.schedule, title: 'Belum ada job terjadwal', body: 'Contoh: setiap pagi rangkum berita, tiap 2 jam cek status layanan.'),
          for (final j in jobs) _jobCard(j, local),
          if (runs.isNotEmpty) ...[
            SectionLabel('Eksekusi terakhir (${runs.length})', padding: const EdgeInsets.fromLTRB(0, 18, 0, 8)),
            for (final r in runs.take(12))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  StatusPill(r.status, color: statusColor(context, r.status == 'success' ? 'success' : 'error')),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(jobs.where((j) => j.id == r.jobId).firstOrNull?.name ?? r.jobId,
                        style: monoStyle(context, size: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Text(relTime(r.startedAt ?? ''), style: context.tt.bodySmall),
                ]),
              ),
          ],
        ]),
      ),
    );
  }

  Widget _jobCard(CronJob j, bool local) {
    final b = busy;
    Widget guarded(String action, String label, {bool danger = false}) => TextButton(
          style: danger ? TextButton.styleFrom(foregroundColor: context.hc.destructive) : null,
          onPressed: b == j.id + action ? null : () => _act(j, action),
          child: Text(b == j.id + action ? '…' : label),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
      decoration: BoxDecoration(
        color: context.hc.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: j.enabled ? context.cs.primary.withValues(alpha: 0.45) : context.hc.strokeSoft),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(j.name, style: context.tt.titleSmall)),
          StatusPill(j.state, color: j.enabled ? context.hc.success : context.hc.mutedForeground),
          const SizedBox(width: 8),
        ]),
        const SizedBox(height: 4),
        Text(j.schedule, style: monoStyle(context, size: 12, color: context.hc.mutedForeground)),
        const SizedBox(height: 6),
        Wrap(spacing: 10, runSpacing: 4, children: [
          Text(j.enabled ? 'jalan ${relTime(j.nextRunAt ?? '', future: true)}' : 'dijeda', style: context.tt.bodySmall),
          if (j.lastRunAt != null) Text('terakhir ${relTime(j.lastRunAt!)}', style: context.tt.bodySmall),
          if (j.agent != null) Text('agent ${j.agent}', style: context.tt.bodySmall),
          if (j.failureStreak > 0) StatusPill('gagal ${j.failureStreak}×', color: context.hc.destructive),
        ]),
        if (j.prompt.isNotEmpty) Collapsible(label: 'Prompt', text: j.prompt),
        if (j.lastOutput != null && j.lastOutput!.isNotEmpty)
          Collapsible(label: 'Hasil terakhir', child: Padding(padding: const EdgeInsets.only(right: 8), child: MarkdownView(j.lastOutput!, scale: 0.9))),
        if (j.lastError != null) Padding(padding: const EdgeInsets.only(right: 8, bottom: 4), child: ErrorBanner(j.lastError!, dense: true)),
        // A failing job becomes a task — offered only when there is something to fix.
        if (j.failureStreak > 0)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: items[j.id] != null
                ? ActionItemsPanel(
                    backend: ref.read(officeProvider).backend,
                    candidates: items[j.id]!,
                    roster: roster,
                    origin: TaskOrigin(kind: 'cron', ref: j.id),
                    label: 'TINDAK LANJUT → TUGAS',
                  )
                : OutlinedButton(
                    onPressed: busy == 'items${j.id}' ? null : () => _loadItems(j.id),
                    child: Text(busy == 'items${j.id}' ? '…' : 'Buat tugas dari kegagalan ini'),
                  ),
          ),
        Wrap(children: [
          j.enabled ? guarded('pause', 'Pause') : guarded('resume', 'Aktifkan'),
          guarded('run', 'Jalankan'),
          guarded('remove', 'Hapus', danger: true),
        ]),
      ]),
    );
  }
}

class NewCronScreen extends ConsumerStatefulWidget {
  const NewCronScreen({super.key});
  @override
  ConsumerState<NewCronScreen> createState() => _NewCronScreenState();
}

class _NewCronScreenState extends ConsumerState<NewCronScreen> {
  final _schedule = TextEditingController();
  final _prompt = TextEditingController();
  final _name = TextEditingController();
  bool liveNow = false;
  String? agent;
  bool busy = false;
  String? err;

  Future<void> _create() async {
    setState(() {
      busy = true;
      err = null;
    });
    final res = await ref.read(officeProvider).backend.post('/api/neovarch/cron', {
      'action': 'create',
      'schedule': _schedule.text.trim(),
      'prompt': _prompt.text.trim(),
      'name': _name.text.trim(),
      'paused': !liveNow,
      'agent': ?agent,
    });
    if (!mounted) return;
    if (!res.ok || res.data == null) {
      setState(() {
        busy = false;
        err = res.error ?? 'gagal membuat job';
      });
      return;
    }
    final id = res.map['id'];
    Navigator.pop(context, liveNow ? 'job dibuat dan langsung aktif ($id)' : 'job dibuat dalam keadaan pause ($id) — aktifkan kalau sudah benar');
  }

  @override
  Widget build(BuildContext context) {
    final office = ref.watch(officeProvider);
    final local = office.backend.supportsMove;
    final schedErr = _schedule.text.trim().isEmpty ? null : validateSchedule(_schedule.text.trim());
    return Scaffold(
      appBar: AppBar(title: Text('Job baru', style: context.tt.titleMedium)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (err != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: ErrorBanner(err!)),
        TextField(
          controller: _schedule,
          decoration: InputDecoration(labelText: 'Jadwal', hintText: '30m  ·  every 2h  ·  0 9 * * *', errorText: local ? schedErr : null),
          style: monoStyle(context, size: 14),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [
          for (final s in ['30m', 'every 2h', '0 9 * * *', '0 8 * * 1-5'])
            ActionChip(label: Text(s, style: monoStyle(context, size: 12)), onPressed: () => setState(() => _schedule.text = s)),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _prompt,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(labelText: 'Prompt', hintText: 'perintah', alignLabelWithHint: true),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nama (opsional)', hintText: 'cek rilis harian')),
        if (local) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: agent,
            decoration: const InputDecoration(labelText: 'Agent yang menjalankan'),
            items: [for (final a in office.agents) DropdownMenuItem(value: a.name, child: Text(a.name))],
            onChanged: (v) => setState(() => agent = v),
          ),
        ],
        const SizedBox(height: 8),
        CheckboxListTile(
          value: liveNow,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('langsung aktif'),
          subtitle: const Text('kalau tidak dicentang, job dibuat pause dulu'),
          onChanged: (v) => setState(() => liveNow = v ?? false),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: busy || _schedule.text.trim().isEmpty || _prompt.text.trim().isEmpty || (local && schedErr != null) ? null : _create,
          child: Text(busy ? 'Membuat…' : 'Buat job'),
        ),
      ]),
    );
  }
}
