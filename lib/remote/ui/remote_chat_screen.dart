// Chat with the agent on the PC: streamed replies, thinking, live tool rows
// and inline approval cards — the same transcript widgets as Desktop.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/platform_caps.dart';
import '../../state/app_controller.dart' show settingsProvider;
import '../../state/voice_service.dart';
import '../../theme/app_theme.dart';
import '../../ui/screens/chat/message_widgets.dart';
import '../../ui/widgets/common.dart';
import '../remote_controller.dart';
import '../remote_gateway.dart';

class RemoteChatScreen extends ConsumerStatefulWidget {
  const RemoteChatScreen({super.key, required this.onOpenApprovals});
  final VoidCallback onOpenApprovals;
  @override
  ConsumerState<RemoteChatScreen> createState() => _RemoteChatScreenState();
}

class _RemoteChatScreenState extends ConsumerState<RemoteChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _dictating = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty) return;
    _input.clear();
    final err = await ref.read(remoteProvider).send(text);
    if (err != null && mounted) toast(context, err);
    _toBottom();
  }

  Future<void> _dictate() async {
    final v = VoiceService.instance;
    if (_dictating) {
      await v.stopDictation();
      setState(() => _dictating = false);
      return;
    }
    setState(() => _dictating = true);
    await v.startDictation(
      locale: ref.read(settingsProvider).sttLocale,
      onText: (t, done) {
        _input.text = t;
        _input.selection = TextSelection.collapsed(offset: t.length);
        if (done && mounted) setState(() => _dictating = false);
      },
    );
    if (v.error != null && mounted) {
      setState(() => _dictating = false);
      toast(context, v.error!);
    }
  }

  void _sessions() => showPaperSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _SessionsSheet(onPick: (id) {
          Navigator.pop(ctx);
          ref.read(remoteProvider).openSession(id).then((_) => _toBottom());
        }),
      );

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(remoteProvider);
    final s = ref.watch(settingsProvider);
    final msgs = r.transcript.messages;
    final mine = r.approvals.where((a) => a.sessionId == r.runtimeId).toList();
    final others = r.approvals.length - mine.length;
    if (r.running) _toBottom();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.title.isNotEmpty ? r.title : (r.storedId == null ? 'Chat baru' : 'Percakapan'),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.titleMedium),
          Row(children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: r.connected ? context.hc.success : context.hc.warning),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text('${r.desktop?.name ?? 'PC'} · ${r.statusLabel}${r.transcript.tokensPerSecond != null ? ' · ${r.transcript.tokensPerSecond!.toStringAsFixed(0)} tok/s' : ''}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall),
            ),
          ]),
        ]),
        actions: [
          IconButton(tooltip: 'Riwayat sesi di PC', icon: const Icon(Icons.history), onPressed: r.connected ? _sessions : null),
          IconButton(tooltip: 'Chat baru', icon: const Icon(Icons.add_comment_outlined), onPressed: r.connected ? r.newChat : null),
        ],
      ),
      body: Column(children: [
        if (others > 0)
          MaterialBanner(
            content: Text('$others persetujuan menunggu di sesi lain'),
            actions: [TextButton(onPressed: widget.onOpenApprovals, child: const Text('Lihat'))],
          ),
        Expanded(
          child: r.opening
              ? const CenterLoader(label: 'membuka sesi di PC…')
              : msgs.isEmpty
                  ? _empty(context, r)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      itemCount: msgs.length,
                      itemBuilder: (context, i) {
                        final m = msgs[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: m.role == 'user'
                              ? UserBubble(msg: m, scale: s.chatScale)
                              : AssistantMessage(
                                  msg: m,
                                  scale: s.chatScale,
                                  showReasoning: s.showReasoning,
                                  isLast: i == msgs.length - 1,
                                  onLink: (u) => launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication),
                                  onOpenFile: (p) => toast(context, 'Berkas ada di PC: $p'),
                                ),
                        );
                      },
                    ),
        ),
        for (final a in mine)
          ApprovalCard(
            command: a.command,
            description: a.description,
            choices: a.choices,
            onChoice: (c) async {
              final err = await r.respond(a, c);
              if (err != null && context.mounted) toast(context, err);
            },
          ),
        if (r.transcript.error != null && !r.running)
          Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 6), child: ErrorBanner(r.transcript.error!, dense: true)),
        _composer(context, r),
      ]),
    );
  }

  Widget _empty(BuildContext context, RemoteController r) => ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 24),
        const Center(child: BrandBadge(height: 64)),
        const SizedBox(height: 14),
        Text('Perintahkan agen di PC', textAlign: TextAlign.center, style: context.tt.titleMedium),
        const SizedBox(height: 6),
        Text(
          r.connected
              ? 'Pesanmu dijalankan oleh agen Neovarch di ${r.desktop?.name ?? 'PC'} — alat, berkas, dan terminal semuanya di sana.'
              : 'Belum terhubung ke PC.',
          textAlign: TextAlign.center,
          style: context.tt.bodySmall,
        ),
        const SizedBox(height: 18),
        if (r.connected)
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            for (final p in const [
              'Apa yang sedang dikerjakan agen sekarang?',
              'Ringkas papan Kanban hari ini',
              'Jalankan tes proyek dan laporkan hasilnya',
            ])
              ActionChip(label: Text(p), onPressed: () => _send(p)),
          ]),
        if (r.sessions.isNotEmpty) ...[
          const SectionLabel('Terakhir di PC', padding: EdgeInsets.fromLTRB(0, 24, 0, 6)),
          for (final s in r.sessions.take(5))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.chat_bubble_outline, size: 20),
              title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(relTime(s.updatedAt), style: context.tt.bodySmall),
              onTap: () => r.openSession(s.id).then((_) => _toBottom()),
            ),
        ],
      ]);

  Widget _composer(BuildContext context, RemoteController r) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 6, 12, (kb > 0 ? kb : bottom) + 8),
      child: PaperScope(
        child: Builder(
          builder: (context) => Container(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
            decoration: BoxDecoration(
              color: context.hc.popover,
              borderRadius: BorderRadius.circular(context.hc.corner + 4),
              border: Border.all(color: context.hc.border),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (canDictate)
                IconButton(
                  tooltip: _dictating ? 'Berhenti dikte' : 'Dikte perintah',
                  icon: Icon(_dictating ? Icons.mic : Icons.mic_none, color: _dictating ? context.cs.primary : null),
                  onPressed: r.connected ? _dictate : null,
                ),
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  enabled: r.connected,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: r.connected ? 'Perintah untuk agen di PC…' : 'Menunggu koneksi ke PC…',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                ),
              ),
              if (r.running)
                IconButton(tooltip: 'Hentikan', icon: const Icon(Icons.stop_circle_outlined), onPressed: r.stop)
              else
                IconButton(
                  tooltip: 'Kirim',
                  icon: Icon(Icons.arrow_upward_rounded, color: context.cs.primary),
                  onPressed: r.connected ? _send : null,
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SessionsSheet extends ConsumerWidget {
  const _SessionsSheet({required this.onPick});
  final void Function(String id) onPick;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(remoteProvider);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
            child: Row(children: [
              Expanded(child: Text('Sesi di ${r.desktop?.name ?? 'PC'}', style: context.tt.titleMedium)),
              IconButton(icon: const Icon(Icons.refresh), onPressed: r.loadSessions),
            ]),
          ),
          Expanded(
            child: r.sessionsLoading && r.sessions.isEmpty
                ? const CenterLoader()
                : r.sessions.isEmpty
                    ? const EmptyState(icon: Icons.forum_outlined, title: 'Belum ada sesi')
                    : ListView(children: [
                        for (final s in r.sessions)
                          ListTile(
                            selected: s.id == r.storedId,
                            title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${relTime(s.updatedAt)} · ${s.messageCount} pesan', style: context.tt.bodySmall),
                            trailing: r.active.any((a) => a.title == s.title && a.status == 'running')
                                ? const TypingDots(size: 4)
                                : null,
                            onTap: () => onPick(s.id),
                          ),
                      ]),
          ),
        ]),
      ),
    );
  }
}

/// Small helper so other tabs can show an approval with its session label.
String approvalOrigin(RemoteController r, RemoteApproval a) => r.sessionTitle(a.sessionId);
