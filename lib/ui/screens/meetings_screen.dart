// Ruang rapat — list of meeting cards (live and archived), the create form,
// and an opened meeting: live transcript, minutes, download/copy, and the
// follow-ups → tasks link (MeetingPanel.tsx).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/action_items.dart';
import '../widgets/common.dart';
import '../widgets/markdown_view.dart';
import 'settings/providers_screen.dart';

class MeetingsScreen extends ConsumerWidget {
  const MeetingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final office = ref.watch(officeProvider);
    final app = ref.watch(appProvider);
    final m = office.meeting;
    return Scaffold(
      appBar: AppBar(
        title: Text('Ruang rapat', style: context.tt.titleMedium),
        actions: [IconButton(tooltip: 'Segarkan', onPressed: office.refreshMeeting, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'meet-fab',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewMeetingScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Rapat baru'),
      ),
      body: RefreshIndicator(
        onRefresh: office.refreshMeeting,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
          if (!office.meetingConfigured && !office.loading)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: app.mode == ConnectionMode.server
                  ? const NoteBanner('LLM belum dikonfigurasi di server — rapat tidak bisa dimulai. Isi AI_BASE_URL dan AI_API_KEY di .env.local.')
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const NoteBanner('Penyedia LLM belum diatur — rapat butuh model untuk tiap peserta.'),
                      TextButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProvidersScreen())),
                        child: const Text('Atur penyedia'),
                      ),
                    ]),
            ),
          if (m != null) ...[
            SectionLabel('Rapat aktif', padding: const EdgeInsets.fromLTRB(0, 12, 0, 8), trailing: m.live ? StatusPill('LANGSUNG', color: context.hc.warning) : null),
            _MeetingCard(
              title: m.topic.isEmpty ? '(tanpa topik)' : m.topic,
              meta: '${m.state} · ${m.participants.length} peserta · ${m.turns.length} giliran',
              participants: m.participants,
              highlight: m.live,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MeetingDetailScreen(liveId: m.id))),
            ),
          ],
          for (final x in office.liveMeetings.where((x) => x.id != m?.id))
            _MeetingCard(
              title: x.topic,
              meta: '${x.state} · ${x.participants.length} peserta',
              participants: x.participants,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MeetingDetailScreen(liveId: x.id))),
            ),
          SectionLabel('Rapat terdahulu (${office.meetingHistory.length})', padding: const EdgeInsets.fromLTRB(0, 18, 0, 8)),
          if (office.meetingHistory.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: EmptyState(icon: Icons.groups_2_outlined, title: 'Belum ada rapat tersimpan', body: 'Kumpulkan 2–4 agent untuk membahas satu topik; notulen dan tindak lanjutnya tersimpan di sini.'),
            ),
          for (final h in office.meetingHistory)
            _MeetingCard(
              title: h.topic,
              meta: '${h.startedAt} · ${h.participants.isEmpty ? '?' : h.participants.length} peserta · ${h.turnCount} giliran',
              participants: h.participants,
              preview: h.preview,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MeetingDetailScreen(archiveId: h.id, title: h.topic))),
            ),
        ]),
      ),
    );
  }
}

class _MeetingCard extends StatelessWidget {
  const _MeetingCard({required this.title, required this.meta, required this.participants, required this.onTap, this.highlight = false, this.preview});
  final String title;
  final String meta;
  final List<String> participants;
  final VoidCallback onTap;
  final bool highlight;
  final String? preview;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: highlight ? context.hc.warning.withValues(alpha: 0.08) : context.hc.card,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10), side: BorderSide(color: highlight ? context.hc.warning.withValues(alpha: 0.6) : context.hc.strokeSoft)),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: context.tt.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(meta, style: context.tt.bodySmall),
                if (preview != null && preview!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(preview!.replaceAll('**', ''), maxLines: 2, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                ],
                if (participants.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    for (final p in participants.take(5))
                      Padding(padding: const EdgeInsets.only(right: 4), child: AgentAvatar(p, size: 22)),
                  ]),
                ],
              ]),
            ),
          ),
        ),
      );
}

class NewMeetingScreen extends ConsumerStatefulWidget {
  const NewMeetingScreen({super.key});
  @override
  ConsumerState<NewMeetingScreen> createState() => _NewMeetingScreenState();
}

class _NewMeetingScreenState extends ConsumerState<NewMeetingScreen> {
  final _topic = TextEditingController();
  final List<String> picked = [];
  String moderator = '';
  String mode = 'auto';
  bool busy = false;
  String? err;

  void _toggle(String name) => setState(() {
        if (picked.contains(name)) {
          picked.remove(name);
          if (moderator == name) moderator = picked.isNotEmpty ? picked.first : '';
        } else if (picked.length < 4) {
          picked.add(name);
          if (moderator.isEmpty) moderator = name;
        }
      });

  Future<void> _start() async {
    setState(() {
      busy = true;
      err = null;
    });
    final office = ref.read(officeProvider);
    final res = await office.backend.post('/api/neovarch/meeting', {'topic': _topic.text.trim(), 'participants': picked, 'moderator': moderator, 'mode': mode});
    if (!mounted) return;
    if (!res.ok) {
      setState(() {
        busy = false;
        err = res.error ?? 'gagal memulai rapat';
      });
      return;
    }
    await office.refreshMeeting();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final office = ref.watch(officeProvider);
    final agents = office.agents;
    return Scaffold(
      appBar: AppBar(title: Text('Rapat baru', style: context.tt.titleMedium)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (err != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: ErrorBanner(err!)),
        TextField(
          controller: _topic,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Topik', hintText: 'Rencana rilis endpoint refund', alignLabelWithHint: true),
          onChanged: (_) => setState(() {}),
        ),
        SectionLabel('Peserta (2–4) · ${agents.length} agent aktif', padding: const EdgeInsets.fromLTRB(0, 18, 0, 8)),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final a in agents)
            FilterChip(
              avatar: AgentAvatar(a.name, size: 20),
              label: Text('${a.displayName} · ${agentStatusLabel[a.status] ?? a.status}'),
              selected: picked.contains(a.name),
              onSelected: (_) => _toggle(a.name),
            ),
          if (agents.isEmpty) Text('belum ada agent aktif', style: context.tt.bodySmall),
        ]),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          initialValue: picked.contains(moderator) ? moderator : null,
          decoration: const InputDecoration(labelText: 'Pembawa acara'),
          items: [for (final p in picked) DropdownMenuItem(value: p, child: Text(p))],
          onChanged: (v) => setState(() => moderator = v ?? ''),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: mode,
          decoration: const InputDecoration(labelText: 'Mode'),
          items: const [
            DropdownMenuItem(value: 'auto', child: Text('auto — semua bicara bergiliran')),
            DropdownMenuItem(value: 'directed', child: Text('directed — hanya yang ditunjuk')),
            DropdownMenuItem(value: 'manual', child: Text('manual — hanya yang disebut namanya')),
          ],
          onChanged: (v) => setState(() => mode = v ?? 'auto'),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy || _topic.text.trim().isEmpty || picked.length < 2 || !office.meetingConfigured ? null : _start,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(busy ? 'Memulai…' : 'Mulai rapat'),
        ),
        if (picked.length < 2) Padding(padding: const EdgeInsets.only(top: 8), child: Text('pilih minimal 2 peserta', style: context.tt.bodySmall)),
        if (!office.meetingConfigured) Padding(padding: const EdgeInsets.only(top: 8), child: Text('LLM belum dikonfigurasi — rapat tidak bisa dimulai.', style: context.tt.bodySmall)),
      ]),
    );
  }
}

class MeetingDetailScreen extends ConsumerStatefulWidget {
  const MeetingDetailScreen({super.key, this.liveId, this.archiveId, this.title});
  final String? liveId;
  final String? archiveId;
  final String? title;
  @override
  ConsumerState<MeetingDetailScreen> createState() => _MeetingDetailScreenState();
}

class _MeetingDetailScreenState extends ConsumerState<MeetingDetailScreen> {
  String? body;
  String? err;
  List<Candidate> items = [];
  List<String> roster = [];
  bool itemsLoaded = false;
  bool itemsBusy = false;

  @override
  void initState() {
    super.initState();
    if (widget.archiveId != null) _loadArchive();
  }

  Future<void> _loadArchive() async {
    final res = await ref.read(officeProvider).backend.get('/api/neovarch/meeting', {'id': widget.archiveId!});
    if (!mounted) return;
    setState(() {
      if (!res.ok || res.data == null) {
        err = res.error ?? 'gagal membuka transkrip';
      } else {
        body = '${res.map['body'] ?? ''}';
      }
    });
    _loadItems(widget.archiveId!);
  }

  Future<void> _loadItems(String id) async {
    if (itemsBusy) return;
    itemsBusy = true;
    final res = await ref.read(officeProvider).backend.get('/api/neovarch/meeting/actions', {'from': id});
    if (!mounted) return;
    setState(() {
      itemsBusy = false;
      itemsLoaded = true;
      // No follow-ups is a normal outcome, not an error.
      items = res.ok ? res.list('items').map(Candidate.fromJson).toList() : [];
      roster = ((res.map['roster'] as List?) ?? []).map((e) => '$e').toList();
    });
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    toast(context, '$what disalin (markdown)');
  }

  @override
  Widget build(BuildContext context) {
    final office = ref.watch(officeProvider);
    final m = widget.liveId == null ? null : office.liveMeetings.where((x) => x.id == widget.liveId).firstOrNull;
    if (m != null && m.minutes.isNotEmpty && !itemsLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadItems(m.id));
    }
    final title = m?.topic ?? widget.title ?? 'Rapat';
    return Scaffold(
      appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.titleMedium)),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
        if (err != null) ErrorBanner(err!),
        if (widget.archiveId != null) ...[
          if (body == null && err == null) const Padding(padding: EdgeInsets.all(30), child: CenterLoader(label: 'memuat transkrip')),
          if (body != null) ...[
            Row(children: [
              Text('Transkrip · ${widget.archiveId}', style: context.tt.labelSmall),
              const Spacer(),
              TextButton.icon(onPressed: () => _copy(body!, 'Transkrip'), icon: const Icon(Icons.download_outlined, size: 18), label: const Text('Unduh')),
            ]),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: context.hc.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: context.hc.strokeSoft)),
              child: MarkdownView(body!, scale: 0.95),
            ),
          ],
        ],
        if (widget.liveId != null && m == null) Text('rapat ini sudah tidak ada di memori', style: context.tt.bodySmall),
        if (m != null) ...[
          Wrap(spacing: 6, runSpacing: 6, children: [
            StatusPill('${m.state} · ${m.phase}', color: m.live ? context.hc.warning : context.hc.success),
            StatusPill('mode ${m.mode}'),
            StatusPill('moderator ${m.moderator}'),
          ]),
          const SizedBox(height: 10),
          KeyValue('peserta', m.participants.join(', ')),
          KeyValue('giliran', m.currentSpeaker ?? '—'),
          SectionLabel('Transkrip (${m.turns.where((t) => t.kind != 'minutes').length})', padding: const EdgeInsets.fromLTRB(0, 14, 0, 8)),
          if (m.turns.isEmpty) Padding(padding: const EdgeInsets.all(8), child: Row(children: [const NvLoader(size: 16), const SizedBox(width: 10), Text('menunggu giliran pertama…', style: context.tt.bodySmall)])),
          for (final t in m.turns.where((t) => t.kind != 'minutes'))
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.speaker == m.currentSpeaker && m.live ? context.hc.warning.withValues(alpha: 0.08) : context.hc.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.hc.strokeSoft),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AgentAvatar(t.speaker, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(t.speaker, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(width: 8),
                      Text('${t.kind}${t.round > 0 ? ' · r${t.round}' : ''}', style: context.tt.bodySmall?.copyWith(fontSize: 11)),
                    ]),
                    const SizedBox(height: 4),
                    MarkdownView(t.text, scale: 0.92),
                  ]),
                ),
              ]),
            ),
          if (m.live && m.currentSpeaker != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [const NvLoader(size: 14), const SizedBox(width: 10), Text('${m.currentSpeaker} sedang bicara…', style: context.tt.bodySmall)]),
            ),
          if (m.minutes.isNotEmpty) ...[
            SectionLabel('Notulen',
                padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
                trailing: TextButton.icon(onPressed: () => _copy(m.minutes, 'Notulen'), icon: const Icon(Icons.download_outlined, size: 18), label: const Text('Unduh notulen'))),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: context.hc.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: context.hc.strokeSoft)),
              child: MarkdownView(m.minutes, scale: 0.95),
            ),
          ],
        ],
        // The cross-menu link: what this meeting asked for, as tasks.
        if (itemsBusy) Padding(padding: const EdgeInsets.all(12), child: Text('membaca tindak lanjut…', style: context.tt.bodySmall)),
        if (itemsLoaded)
          ActionItemsPanel(
            backend: office.backend,
            candidates: items,
            roster: roster,
            origin: TaskOrigin(kind: 'meeting', ref: widget.archiveId ?? widget.liveId),
            label: 'TINDAK LANJUT → TUGAS',
            onDone: (_) => office.load(),
          ),
      ]),
    );
  }
}
