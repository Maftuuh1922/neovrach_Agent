// Chat with the agent on the PC: streamed replies, thinking, live tool rows
// and inline approval cards — the same transcript widgets as Desktop.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/platform_caps.dart';
import '../../state/app_controller.dart' show settingsProvider;
import '../../state/voice_service.dart';
import '../../theme/neovarch_mobile_theme.dart';
import '../../ui/screens/chat/message_widgets.dart';
import '../../ui/widgets/common.dart';
import '../remote_controller.dart';
import '../remote_gateway.dart';
import 'nv_widgets.dart';

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
    final pc = r.desktop?.name ?? 'PC';
    final tps = r.transcript.tokensPerSecond;

    return Scaffold(
      body: Column(children: [
        NvHeader(
          kicker: 'chat · $pc',
          title: r.title.isNotEmpty ? r.title : (r.storedId == null ? 'Chat baru' : 'Percakapan'),
          status: Row(children: [
            NvDot(r.connected ? NV.ok : NV.warn, size: 7),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${r.statusLabel}${r.running ? ' · agen bekerja' : ''}${tps != null ? ' · ${tps.toStringAsFixed(0)} tok/s' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NV.monoLabel(size: 10, color: NV.muted).copyWith(letterSpacing: 0.4),
              ),
            ),
          ]),
          actions: [
            NvIconButton(tooltip: 'Riwayat sesi di PC', icon: Icons.history_rounded, onPressed: r.connected ? _sessions : null),
            NvIconButton(tooltip: 'Chat baru', icon: Icons.add_rounded, onPressed: r.connected ? r.newChat : null),
          ],
        ),
        const Divider(height: 1, color: NV.border),
        if (others > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: NvNotice(
              '$others persetujuan menunggu di sesi lain',
              color: NV.warn,
              icon: Icons.shield_outlined,
              action: TextButton(onPressed: widget.onOpenApprovals, child: const Text('Lihat')),
            ),
          ),
        Expanded(
          child: r.opening
              ? const CenterLoader(label: 'membuka sesi di PC…')
              : msgs.isEmpty
                  ? _empty(context, r)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      itemCount: msgs.length,
                      itemBuilder: (context, i) {
                        final m = msgs[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: m.role == 'user'
                              ? NvUserMessage(msg: m, scale: s.chatScale)
                              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                  NvAgentLabel('neovarch · $pc', live: m.streaming),
                                  AssistantMessage(
                                    msg: m,
                                    scale: s.chatScale,
                                    showReasoning: s.showReasoning,
                                    isLast: i == msgs.length - 1,
                                    onLink: (u) => launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication),
                                    onOpenFile: (p) => toast(context, 'Berkas ada di PC: $p'),
                                  ),
                                ]),
                        );
                      },
                    ),
        ),
        for (final a in mine)
          NvApprovalCard(
            command: a.command,
            description: a.description,
            choices: a.choices,
            origin: a.toolName,
            onChoice: (c) async {
              final err = await r.respond(a, c);
              if (err != null && context.mounted) toast(context, err);
            },
          ),
        if (r.transcript.error != null && !r.running)
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: NvNotice(r.transcript.error!)),
        _composer(context, r),
      ]),
    );
  }

  Widget _empty(BuildContext context, RemoteController r) => ListView(padding: const EdgeInsets.only(top: 16, bottom: 16), children: [
        NvEmpty(
          art: 'assets/art/portal-banner.webp',
          kicker: r.connected ? 'siap · ${r.desktop?.name ?? 'pc'}' : 'offline',
          title: 'Perintahkan agen di PC',
          body: r.connected
              ? 'Pesanmu dijalankan agen Neovarch di ${r.desktop?.name ?? 'PC'}. Alat, berkas, dan terminal ada di sana; HP ini mengirim perintah dan menampilkan hasilnya.'
              : 'Belum terhubung ke PC. Sambungkan dari tab PC.',
        ),
        if (r.connected) ...[
          const NvSection('coba perintah', padding: EdgeInsets.fromLTRB(20, 4, 20, 10)),
          NvList(children: [
            for (final (i, p) in const [
              'Apa yang sedang dikerjakan agen sekarang?',
              'Ringkas papan Kanban hari ini',
              'Jalankan tes proyek dan laporkan hasilnya',
            ].indexed)
              NvRow(
                icon: [Icons.bolt_rounded, Icons.view_week_outlined, Icons.terminal_rounded][i],
                title: p,
                trailing: const Icon(Icons.north_east_rounded, size: 16, color: NV.faint),
                onTap: () => _send(p),
              ),
          ]),
        ],
        if (r.sessions.isNotEmpty) ...[
          const NvSection('terakhir di pc'),
          NvList(children: [
            for (final s in r.sessions.take(5))
              NvRow(
                icon: Icons.chat_bubble_outline_rounded,
                title: s.title,
                subtitle: '${relTime(s.updatedAt)} · ${s.messageCount} pesan',
                mono: true,
                trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: NV.faint),
                onTap: () => r.openSession(s.id).then((_) => _toBottom()),
              ),
          ]),
        ],
      ]);

  Widget _composer(BuildContext context, RemoteController r) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 6, 16, (kb > 0 ? kb : bottom) + 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        decoration: BoxDecoration(
          color: NV.surface,
          borderRadius: BorderRadius.circular(NV.rCard),
          border: Border.all(color: NV.borderStrong),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (canDictate)
            NvIconButton(
              tooltip: _dictating ? 'Berhenti dikte' : 'Dikte perintah',
              icon: _dictating ? Icons.mic_rounded : Icons.mic_none_rounded,
              accent: _dictating,
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
              style: const TextStyle(fontSize: 15, color: NV.text, height: 1.4),
              decoration: InputDecoration(
                hintText: r.connected ? 'Perintah untuk agen di PC…' : 'Menunggu koneksi ke PC…',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
              ),
            ),
          ),
          if (r.running)
            NvIconButton(tooltip: 'Hentikan', icon: Icons.stop_rounded, accent: true, onPressed: r.stop)
          else
            NvIconButton(tooltip: 'Kirim', icon: Icons.arrow_upward_rounded, accent: true, onPressed: r.connected ? _send : null),
        ]),
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
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
            child: NvSheetTitle(
              kicker: 'riwayat · ${r.desktop?.name ?? 'pc'}',
              title: 'Sesi di PC',
              trailing: NvIconButton(tooltip: 'Segarkan', icon: Icons.refresh_rounded, onPressed: r.loadSessions),
            ),
          ),
          Expanded(
            child: r.sessionsLoading && r.sessions.isEmpty
                ? const CenterLoader()
                : r.sessions.isEmpty
                    ? const NvEmpty(title: 'Belum ada sesi', body: 'Percakapan yang dimulai di PC atau dari HP ini muncul di sini.')
                    : ListView(padding: const EdgeInsets.only(bottom: 16), children: [
                        NvList(children: [
                          for (final s in r.sessions)
                            NvRow(
                              icon: s.id == r.storedId ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
                              accent: s.id == r.storedId,
                              title: s.title,
                              subtitle: '${relTime(s.updatedAt)} · ${s.messageCount} pesan',
                              mono: true,
                              trailing: r.active.any((a) => a.title == s.title && a.status == 'running')
                                  ? const NvPill('jalan', color: NV.red)
                                  : null,
                              onTap: () => onPick(s.id),
                            ),
                        ]),
                      ]),
          ),
        ]),
      ),
    );
  }
}

/// Small helper so other tabs can show an approval with its session label.
String approvalOrigin(RemoteController r, RemoteApproval a) => r.sessionTitle(a.sessionId);
