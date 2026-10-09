// Chat with the agent on the PC: streamed replies, thinking, live tool rows
// and inline approval cards — the same transcript widgets as Desktop.
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/platform_caps.dart';
import '../../state/app_controller.dart' show settingsProvider;
import '../../state/voice_service.dart';
import '../../theme/neovarch_mobile_theme.dart';
import '../../ui/screens/chat/message_widgets.dart';
import '../../ui/widgets/common.dart';
import '../composer.dart';
import '../remote_controller.dart';
import '../remote_gateway.dart';
import 'nv_glass_text.dart';
import 'glass/backdrop_luminance.dart';
import 'glass/glass_chat.dart';
import 'glass/liquid_glass.dart';
import 'nv_widgets.dart';
import 'remote_attachments.dart';
import 'remote_composer.dart';

class RemoteChatScreen extends ConsumerStatefulWidget {
  const RemoteChatScreen({super.key, required this.onOpenApprovals});
  final VoidCallback onOpenApprovals;
  @override
  ConsumerState<RemoteChatScreen> createState() => _RemoteChatScreenState();
}

class _RemoteChatScreenState extends ConsumerState<RemoteChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  /// Height of the floating dock (approvals + composer) over the messages.
  double _dockH = 0;
  double _lastKb = 0;
  bool _dictating = false;
  /// Message ids already on screen; ids that arrive later play the glass
  /// "materialize" entrance once ([_fresh]).
  final _known = <String>{};
  final _fresh = <String>{};
  String? _knownSession;

  void _track(RemoteController r) {
    final session = '${r.storedId}|${r.runtimeId}';
    final msgs = r.transcript.messages;
    if (session != _knownSession || r.opening) {
      // a (re)opened session shows its history without animation
      _knownSession = session;
      _known
        ..clear()
        ..addAll(msgs.map((m) => m.id));
      _fresh.clear();
      return;
    }
    for (final m in msgs) {
      if (_known.add(m.id)) _fresh.add(m.id);
    }
  }

  final _focus = FocusNode();

  // "/" and "@" suggestions (only when the PC serves the composer catalog)
  ComposerTrigger? _trigger;
  List<ComposerSuggestion> _suggestions = const [];
  bool _sugLoading = false;
  int _sugSeq = 0;
  bool _menuOpen = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(_onInput);
  }

  @override
  void dispose() {
    _input.removeListener(_onInput);
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onInput() {
    final r = ref.read(remoteProvider);
    final c = r.composer;
    final sel = _input.selection;
    final t = c == null || !sel.isValid || !sel.isCollapsed ? null : detectTrigger(_input.text, sel.baseOffset);
    if (t == _trigger) return;
    if (t == null) {
      if (_trigger != null) setState(() => _trigger = null);
      return;
    }
    final seq = ++_sugSeq;
    if (t.kind == '/') {
      setState(() {
        _trigger = t;
        _suggestions = slashSuggestions(c!, t.query);
        _sugLoading = false;
      });
      return;
    }
    setState(() {
      _trigger = t;
      _sugLoading = true;
    });
    Future<void>.delayed(const Duration(milliseconds: 140), () async {
      if (seq != _sugSeq || !mounted) return;
      final items = await r.completeMentions(t.query);
      if (seq != _sugSeq || !mounted) return;
      setState(() {
        _suggestions = items;
        _sugLoading = false;
      });
    });
  }

  void _setText(String text, int cursor) {
    _input.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: cursor));
  }

  void _pick(ComposerSuggestion s) {
    final t = _trigger;
    if (t == null) return;
    final r = ref.read(remoteProvider);
    if (s.kind == 'skill' || s.kind == 'command') {
      // The token becomes a chip (skill) or an action (command), not text.
      final text = _input.text.replaceRange(t.start, t.end, '').replaceFirst(RegExp(r'^ '), '');
      _sugSeq++;
      setState(() => _trigger = null);
      _setText(text, math.min(t.start, text.length));
      if (s.kind == 'skill') {
        final name = s.text.substring(1);
        if (!r.selectedSkills.contains(name)) r.toggleSkill(name);
      } else if (s.text == '/new') {
        r.newChat();
      } else if (s.text == '/model') {
        showModelSheet(context, r);
      }
      return;
    }
    final next = applySuggestion(_input.text, t, s.text);
    _setText(next.text, next.cursor);
    _focus.requestFocus();
  }

  /// Insert at the cursor with a separating space.
  void _insertText(String text) {
    final v = _input.value;
    final at = v.selection.isValid ? v.selection.baseOffset : v.text.length;
    final before = v.text.substring(0, at);
    final sep = before.isEmpty || before.endsWith(' ') || before.endsWith('\n') ? '' : ' ';
    final next = '$before$sep$text${v.text.substring(at)}';
    _setText(next, at + sep.length + text.length);
    _focus.requestFocus();
  }

  void _startMention() => _insertText('@');

  Future<void> _openMenu(RemoteController r) async {
    setState(() => _menuOpen = true);
    await showComposerMenu(context, r, ComposerActions(insertText: _insertText, startMention: _startMention));
    if (mounted) setState(() => _menuOpen = false);
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    final r = ref.read(remoteProvider);
    if (text.isEmpty && preset == null && r.pendingAttachments.isEmpty) return;
    if (text.isEmpty && preset != null) return;
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

    _track(r);
    final empty = msgs.isEmpty && !r.opening;
    // Keyboard: the shell hides the nav pill and this screen does NOT let the
    // Scaffold shrink for it (the composer adds the keyboard inset itself);
    // both at once double-counted it and left the composer half a screen
    // above the keyboard (1.4.1 bug). Keep the newest message in view.
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    if ((kb > 0) != (_lastKb > 0)) WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
    _lastKb = kb;
    return GlassBackdrop(child: Scaffold(
      resizeToAvoidBottomInset: false,
      body: Column(children: [
        if (empty)
          _MinimalTopBar(
            onHistory: r.connected ? _sessions : null,
            onNew: r.connected ? r.newChat : null,
          )
        else ...[
        GlassChatHeader(
          kicker: 'chat · $pc',
          title: r.title.isNotEmpty ? r.title : (r.storedId == null ? 'Sesi baru' : 'Percakapan'),
          online: r.connected,
          status: '${r.statusLabel}${r.running ? ' · agen bekerja' : ''}${tps != null ? ' · ${tps.toStringAsFixed(0)} tok/s' : ''}',
          actions: [
            GlassHeaderAction(tooltip: 'Riwayat sesi di PC', icon: CupertinoIcons.clock, onPressed: r.connected ? _sessions : null),
            GlassHeaderAction(tooltip: 'Sesi baru', icon: CupertinoIcons.add, onPressed: r.connected ? r.newChat : null),
          ],
        ),
        ],
        // 1.4.2: approvals live in Chat. Inline cards for this session sit
        // above the composer; this pinned glass chip opens the full list.
        if (r.approvals.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(16, empty ? 8 : 10, 16, 0),
            child: Center(
              child: NvGlassChip(
                key: const ValueKey('chat-approvals-chip'),
                icon: CupertinoIcons.checkmark_shield_fill,
                label: '${r.approvals.length} menunggu persetujuan${others > 0 && mine.isNotEmpty ? ' · $others di sesi lain' : ''}',
                color: NV.red,
                onTap: widget.onOpenApprovals,
              ),
            ),
          ),
        // Messages run under the composer and the glass nav bar (both are
        // liquid glass), padded so the last message clears them at rest.
        Expanded(
          child: Stack(children: [
            Positioned.fill(
              child: r.opening
              ? const CenterLoader(label: 'membuka sesi di PC…')
              : msgs.isEmpty
                  ? _empty(context, r)
                  : BackdropGroup(child: ListView.builder(
                      controller: _scroll,
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 12 + _dockH),
                      itemCount: msgs.length,
                      itemBuilder: (context, i) {
                        final m = msgs[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: m.role == 'user'
                              ? (m.attachments.isEmpty
                                  ? GlassUserMessage(msg: m, scale: s.chatScale, appear: _fresh.remove(m.id))
                                  : Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                      MessageAttachments(attachments: m.attachments, gateway: r.gateway),
                                      if (m.content.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        GlassUserMessage(msg: m, scale: s.chatScale, appear: _fresh.remove(m.id)),
                                      ],
                                    ]))
                              : GlassAgentTurn(
                                  label: 'neovarch · $pc',
                                  live: m.streaming,
                                  appear: _fresh.remove(m.id),
                                  child: AssistantMessage(
                                    msg: m,
                                    scale: s.chatScale,
                                    showReasoning: s.showReasoning,
                                    isLast: i == msgs.length - 1,
                                    onLink: (u) => launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication),
                                    onOpenFile: (p) => toast(context, 'Berkas ada di PC: $p'),
                                  ),
                                ),
                        );
                      },
                    )),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: NvSizeReporter(
                onHeight: (h) {
                  if ((h - _dockH).abs() > 0.5) {
                    setState(() => _dockH = h);
                    if (_lastKb > 0) _toBottom();
                  }
                },
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final a in mine)
          NvApprovalCard(
            command: a.command,
            description: a.description,
            choices: a.choices,
            origin: a.toolName,
            color: NV.surface,
            onChoice: (c) async {
              final err = await r.respond(a, c);
              if (err != null && context.mounted) toast(context, err);
            },
          ),
        if (r.transcript.error != null && !r.running)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: GlassNotice(r.transcript.error!),
          ),
                  _composer(context, r),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    ));
  }

  /// Minimal start: only a time-based greeting (the composer sits below).
  Widget _empty(BuildContext context, RemoteController r) => LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: Center(
              child: Padding(
                padding: EdgeInsets.fromLTRB(28, 0, 28, _dockH),
                child: NvGlassText(greetingFor(DateTime.now()),
                    key: const ValueKey('chat-greeting'), textAlign: TextAlign.center, style: NV.display(size: 40)),
              ),
            ),
          ),
        ),
      );

  Widget _composer(BuildContext context, RemoteController r) {
    // At rest: above the nav pill (the shell reserves it in padding.bottom).
    // Keyboard open: 8px above the keyboard top (pill hidden).
    final bottom = MediaQuery.paddingOf(context).bottom;
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      key: const ValueKey('chat-composer-dock'),
      padding: EdgeInsets.fromLTRB(16, 6, 16, (kb > 0 ? kb : bottom) + 8),
      // themed liquid glass: the field's text / hint follow the glass tone
      child: LiquidGlass(
        key: const ValueKey('chat-composer'),
        themed: true,
        borderRadius: BorderRadius.circular(NV.rCard),
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AttachmentStrip(items: r.pendingAttachments, onRemove: r.removeAttachment),
        ComposerChipsRow(
          r: r,
          onModel: () => showModelSheet(context, r),
          onReasoning: () => showReasoningSheet(context, r),
          onSkills: () => showSkillPicker(context, r),
        ),
        if (_trigger != null && r.composer != null)
          ComposerSuggestionList(items: _suggestions, kind: _trigger!.kind, loading: _sugLoading, onPick: _pick),
        if (r.attachNotice != null && r.attachNotice!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
            child: Text(r.attachNotice!, key: const ValueKey('attach-notice'), style: TextStyle(fontSize: 12, color: NV.muted, height: 1.35)),
          ),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          // "+": uploads, and on a PC with the composer catalog also skills,
          // model, reasoning, mentions, URL and snippets (desktop parity).
          ComposerPlusButton(
            key: const ValueKey('attach-button'),
            open: _menuOpen,
            onPressed: r.connected ? () => _openMenu(r) : null,
          ),
          const SizedBox(width: 4),
          if (canDictate)
            NvIconButton(
              tooltip: _dictating ? 'Berhenti dikte' : 'Dikte perintah',
              icon: _dictating ? CupertinoIcons.mic_fill : CupertinoIcons.mic,
              accent: _dictating,
              onPressed: r.connected ? _dictate : null,
            ),
          Expanded(
            child: TextField(
              controller: _input,
              focusNode: _focus,
              minLines: 1,
              maxLines: 5,
              enabled: r.connected,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              // Keyboard image insertion (Gboard paste of a screenshot / GIF).
              contentInsertionConfiguration: ContentInsertionConfiguration(
                allowedMimeTypes: kInsertableImageMimes,
                onContentInserted: (c) => attachInserted(context, r, c),
              ),
              // Long-press menu: "Tempel gambar" next to the usual paste.
              contextMenuBuilder: (context, editable) => AdaptiveTextSelectionToolbar.buttonItems(
                anchors: editable.contextMenuAnchors,
                buttonItems: [
                  ...editable.contextMenuButtonItems,
                  ContextMenuButtonItem(
                    label: 'Tempel gambar',
                    onPressed: () {
                      ContextMenuController.removeAny();
                      pasteClipboardImage(context, r);
                    },
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 15, height: 1.4),
              decoration: InputDecoration(
                hintText: r.connected ? 'Ketik perintah untuk agen di PC…' : 'Menunggu koneksi ke PC…',
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
            ComposerSendButton(key: const ValueKey('composer-stop'), stop: true, onPressed: r.stop)
          else
            ComposerSendButton(key: const ValueKey('composer-send'), onPressed: r.connected ? _send : null),
        ]),
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
              trailing: NvIconButton(tooltip: 'Segarkan', icon: CupertinoIcons.arrow_clockwise, onPressed: r.loadSessions),
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
                              icon: s.id == r.storedId ? CupertinoIcons.chat_bubble_fill : CupertinoIcons.chat_bubble,
                              accent: s.id == r.storedId,
                              title: s.title,
                              subtitle: '${relTime(s.updatedAt)} · ${s.messageCount} pesan',
                              mono: true,
                              trailing: r.active.any((a) => a.title == s.title && a.status == 'running')
                                  ? NvPill('jalan', color: NV.red)
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

/// "Selamat pagi/siang/sore/malam" by the phone's local hour.
String greetingFor(DateTime t) {
  final h = t.hour;
  if (h >= 4 && h < 11) return 'Selamat pagi';
  if (h >= 11 && h < 15) return 'Selamat siang';
  if (h >= 15 && h < 18) return 'Selamat sore';
  return 'Selamat malam';
}

class _MinimalTopBar extends StatelessWidget {
  const _MinimalTopBar({required this.onHistory, required this.onNew});
  final VoidCallback? onHistory;
  final VoidCallback? onNew;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 10, 12, 0),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          NvIconButton(tooltip: 'Riwayat sesi di PC', icon: CupertinoIcons.clock, onPressed: onHistory),
          const SizedBox(width: 6),
          NvIconButton(tooltip: 'Sesi baru', icon: CupertinoIcons.add, onPressed: onNew),
        ]),
      );
}
