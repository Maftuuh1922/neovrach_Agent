// Chat controls as on the desktop app / CLI: per-session settings panel
// (model, thinking, sampling, persona, toolsets, approval, memory, stream),
// the thinking quick-switch in the composer, slash commands with
// autocomplete, and the /usage, /help and search sheets.
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/chat_options.dart';
import '../../../state/app_controller.dart';
import '../../../state/settings_controller.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/markdown_view.dart';

/// The model a session will actually use.
String effectiveModel(WidgetRef ref, [String? sessionId]) {
  final s = ref.read(settingsProvider);
  final store = ref.read(storeProvider);
  final chat = ref.read(chatProvider);
  final sid = sessionId ?? chat.current?.id;
  final o = sid == null ? s.chatDefaults : s.optionsFor(sid);
  if (o.model?.isNotEmpty == true) return o.model!;
  final p = store.profile(chat.current?.profile ?? s.defaultProfile);
  if (p?.model?.isNotEmpty == true) return p!.model!;
  final prov = o.providerId != null ? s.providers.where((x) => x.id == o.providerId).firstOrNull : null;
  return (prov ?? s.activeProvider)?.model ?? '';
}

ChatOptions currentOptions(WidgetRef ref) {
  final s = ref.read(settingsProvider);
  final id = ref.read(chatProvider).current?.id;
  return id == null ? s.chatDefaults : s.optionsFor(id);
}

void updateOptions(WidgetRef ref, ChatOptions Function(ChatOptions o) f, {bool defaults = false}) {
  final s = ref.read(settingsProvider);
  final id = ref.read(chatProvider).current?.id;
  if (defaults || id == null) {
    s.update((x) => x.chatDefaults = f(x.chatDefaults));
  } else {
    s.setSessionOptions(id, f(s.optionsFor(id)));
  }
}

// ------------------------------------------------------------ thinking chip --
class ThinkingButton extends ConsumerWidget {
  const ThinkingButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(settingsProvider);
    ref.watch(chatProvider);
    final o = currentOptions(ref);
    final model = effectiveModel(ref);
    final supported = modelSupportsReasoning(model);
    final on = supported && o.reasoningOn;
    return PopupMenuButton<String>(
      tooltip: 'Thinking / penalaran',
      position: PopupMenuPosition.over,
      onSelected: (v) {
        if (v == 'settings') {
          showChatSettingsSheet(context);
        } else {
          updateOptions(ref, (x) => x.copyWith(effort: v));
        }
      },
      itemBuilder: (_) => [
        if (supported)
          for (final l in reasoningLevels)
            CheckedPopupMenuItem(value: l, checked: o.effort == l, child: Text('Thinking: ${reasoningLabel(l)}'))
        else
          PopupMenuItem(enabled: false, child: Text('Model "$model" tidak mendukung thinking', style: context.tt.bodySmall)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'settings', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.tune, size: 18), title: Text('Pengaturan chat…'))),
      ],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: on ? context.cs.primary.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(context.hc.corner < 6 ? context.hc.corner : 20),
          border: Border.all(color: on ? context.cs.primary.withValues(alpha: 0.6) : context.hc.strokeSoft),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(on ? Icons.psychology_alt : Icons.psychology_alt_outlined, size: 16, color: on ? context.cs.primary : context.hc.mutedForeground),
          const SizedBox(width: 4),
          Text(supported ? (on ? reasoningLabel(o.effort) : 'Mati') : '—',
              style: monoStyle(context, size: 10.5, color: on ? context.cs.primary : context.hc.mutedForeground, weight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// --------------------------------------------------------- settings sheet --
Future<void> showChatSettingsSheet(BuildContext context, {bool defaults = false}) => showPaperSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.86,
        maxChildSize: 0.96,
        builder: (ctx, sc) => ChatSettingsPanel(scroll: sc, defaults: defaults),
      ),
    );

class ChatSettingsPanel extends ConsumerStatefulWidget {
  const ChatSettingsPanel({super.key, this.scroll, this.defaults = false});
  final ScrollController? scroll;
  /// Edit the defaults (Pengaturan) instead of the open session.
  final bool defaults;
  @override
  ConsumerState<ChatSettingsPanel> createState() => _ChatSettingsPanelState();
}

class _ChatSettingsPanelState extends ConsumerState<ChatSettingsPanel> {
  late bool _defaults = widget.defaults || ref.read(chatProvider).current == null;
  late final _persona = TextEditingController(text: _opts.persona);
  late final _model = TextEditingController(text: _opts.model ?? '');
  late final _maxTok = TextEditingController(text: _opts.maxTokens?.toString() ?? '');

  ChatOptions get _opts {
    final s = ref.read(settingsProvider);
    final id = ref.read(chatProvider).current?.id;
    return _defaults || id == null ? s.chatDefaults : s.optionsFor(id);
  }

  void _set(ChatOptions Function(ChatOptions o) f) => updateOptions(ref, f, defaults: _defaults);

  void _reload() {
    _persona.text = _opts.persona;
    _model.text = _opts.model ?? '';
    _maxTok.text = _opts.maxTokens?.toString() ?? '';
  }

  @override
  void dispose() {
    _persona.dispose();
    _model.dispose();
    _maxTok.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final chat = ref.watch(chatProvider);
    final o = _opts;
    final model = _defaults ? (o.model ?? s.activeProvider?.model ?? '') : effectiveModel(ref);
    final supported = modelSupportsReasoning(model);
    final providers = s.providers;
    final hasSession = chat.current != null && !widget.defaults;
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(18, 0, 18, 28), children: [
      Row(children: [
        Expanded(child: Text(_defaults ? 'PENGATURAN CHAT · BAWAAN' : 'PENGATURAN CHAT · SESI INI', style: context.tt.labelSmall)),
        if (!_defaults && s.hasSessionOptions(chat.current!.id))
          TextButton(
            onPressed: () {
              s.setSessionOptions(chat.current!.id, null);
              setState(_reload);
            },
            child: const Text('Reset ke bawaan'),
          ),
      ]),
      if (hasSession)
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Sesi ini'), icon: Icon(Icons.chat_bubble_outline, size: 16)),
              ButtonSegment(value: true, label: Text('Bawaan'), icon: Icon(Icons.settings_outlined, size: 16)),
            ],
            selected: {_defaults},
            onSelectionChanged: (v) => setState(() {
              _defaults = v.first;
              _reload();
            }),
          ),
        ),
      // ---- model
      const SectionLabel('Model', padding: EdgeInsets.fromLTRB(0, 16, 0, 6)),
      DropdownButtonFormField<String>(
        initialValue: providers.any((p) => p.id == o.providerId) ? o.providerId : '',
        decoration: const InputDecoration(labelText: 'Penyedia'),
        items: [
          DropdownMenuItem(value: '', child: Text('Aktif (${s.activeProvider?.label ?? '-'})')),
          for (final p in providers) DropdownMenuItem(value: p.id, child: Text(p.label)),
        ],
        onChanged: (v) => _set((x) => (v == null || v.isEmpty)
            ? ChatOptions.fromJson({...x.toJson(), 'providerId': null})
            : x.copyWith(providerId: v)),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _model,
        decoration: InputDecoration(labelText: 'Model (kosong = bawaan profil/penyedia)', hintText: model.isEmpty ? 'mis. qwen/qwen3-coder' : model),
        onSubmitted: (v) => _set((x) => v.trim().isEmpty ? ChatOptions.fromJson({...x.toJson(), 'model': null}) : x.copyWith(model: v.trim())),
        onTapOutside: (_) {
          final v = _model.text.trim();
          if (v != (o.model ?? '')) _set((x) => v.isEmpty ? ChatOptions.fromJson({...x.toJson(), 'model': null}) : x.copyWith(model: v));
        },
      ),
      Builder(builder: (context) {
        final favs = {for (final p in providers) ...p.favoriteModels, for (final p in providers) if (p.model.isNotEmpty) p.model}.toList();
        if (favs.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final f in favs.take(10))
              ChoiceChip(
                label: Text(f, style: monoStyle(context, size: 11)),
                selected: model == f,
                onSelected: (_) {
                  _model.text = f;
                  _set((x) => x.copyWith(model: f));
                },
              ),
          ]),
        );
      }),
      // ---- thinking
      const SectionLabel('Thinking / penalaran', padding: EdgeInsets.fromLTRB(0, 20, 0, 6)),
      if (!supported)
        NoteBanner('Model "${model.isEmpty ? '-' : model}" tampaknya tidak mendukung mode thinking — opsi disembunyikan. '
            'Pilih model reasoning (mis. DeepSeek R1, o4-mini, Claude Sonnet 4, Qwen3).')
      else ...[
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [for (final l in reasoningLevels) ButtonSegment(value: l, label: Text(reasoningLabel(l), style: const TextStyle(fontSize: 12)))],
          selected: {o.effort},
          onSelectionChanged: (v) => _set((x) => x.copyWith(effort: v.first)),
        ),
        const SizedBox(height: 10),
        Text('Budget token penalaran · ${o.reasoningBudget ?? 'otomatis'}', style: context.tt.bodySmall),
        Slider(
          value: (o.reasoningBudget ?? 0).toDouble().clamp(0, 32768),
          min: 0,
          max: 32768,
          divisions: 32,
          label: o.reasoningBudget == null ? 'otomatis' : '${o.reasoningBudget}',
          onChanged: o.reasoningOn ? (v) => _set((x) => v < 512 ? x.copyWith(clearBudget: true) : x.copyWith(reasoningBudget: (v / 1024).round() * 1024)) : null,
        ),
        Text(_wireNote(s, o), style: context.tt.bodySmall?.copyWith(fontSize: 11.5)),
      ],
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Tampilkan blok penalaran'),
        value: o.showReasoning,
        onChanged: (v) => _set((x) => x.copyWith(showReasoning: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Ciutkan otomatis setelah selesai'),
        value: o.autoCollapseReasoning,
        onChanged: (v) => _set((x) => x.copyWith(autoCollapseReasoning: v)),
      ),
      // ---- sampling
      const SectionLabel('Sampling', padding: EdgeInsets.fromLTRB(0, 16, 0, 6)),
      _OptionalSlider(
        label: 'Temperature',
        value: o.temperature,
        min: 0,
        max: 2,
        divisions: 40,
        onChanged: (v) => _set((x) => v == null ? x.copyWith(clearTemperature: true) : x.copyWith(temperature: v)),
      ),
      _OptionalSlider(
        label: 'Top-p',
        value: o.topP,
        min: 0.05,
        max: 1,
        divisions: 19,
        onChanged: (v) => _set((x) => v == null ? x.copyWith(clearTopP: true) : x.copyWith(topP: v)),
      ),
      TextField(
        controller: _maxTok,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Max tokens jawaban (kosong = bawaan penyedia)'),
        onChanged: (v) {
          final n = int.tryParse(v.trim());
          _set((x) => n == null || n <= 0 ? x.copyWith(clearMaxTokens: true) : x.copyWith(maxTokens: n));
        },
      ),
      // ---- persona
      const SectionLabel('Persona / system prompt', padding: EdgeInsets.fromLTRB(0, 20, 0, 6)),
      TextField(
        controller: _persona,
        minLines: 2,
        maxLines: 6,
        decoration: const InputDecoration(hintText: 'Instruksi tambahan untuk sesi ini (mis. "jawab singkat, gaya santai")'),
        onChanged: (v) => _set((x) => x.copyWith(persona: v)),
      ),
      Wrap(spacing: 6, children: [
        for (final p in personalities.entries)
          ActionChip(
            label: Text(p.key),
            onPressed: () {
              _persona.text = p.value;
              _set((x) => x.copyWith(persona: p.value));
            },
          ),
      ]),
      // ---- tools & safety
      const SectionLabel('Alat & keamanan', padding: EdgeInsets.fromLTRB(0, 20, 0, 6)),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Alat aktif'),
        subtitle: Text('Matikan untuk chat murni tanpa alat', style: context.tt.bodySmall),
        value: o.tools,
        onChanged: (v) => _set((x) => x.copyWith(tools: v)),
      ),
      Wrap(spacing: 6, children: [
        for (final g in const [('app', 'Aplikasi'), ('office', 'Kantor'), ('device', 'Perangkat')])
          FilterChip(
            label: Text(g.$2),
            selected: o.toolGroups.contains(g.$1),
            onSelected: o.tools
                ? (v) => _set((x) => x.copyWith(toolGroups: v ? {...x.toolGroups, g.$1} : (x.toolGroups.toSet()..remove(g.$1))))
                : null,
          ),
      ]),
      const SizedBox(height: 12),
      Text('Mode persetujuan alat sensitif', style: context.tt.bodySmall),
      const SizedBox(height: 6),
      SegmentedButton<String>(
        showSelectedIcon: false,
        segments: [for (final m in approvalModes) ButtonSegment(value: m, label: Text(approvalLabel(m), style: const TextStyle(fontSize: 12)))],
        selected: {o.approval},
        onSelectionChanged: (v) => _set((x) => x.copyWith(approval: v.first)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Memori & konteks jangka panjang'),
        subtitle: Text('Sertakan catatan memori di prompt dan izinkan alat memory_*', style: context.tt.bodySmall),
        value: o.memory,
        onChanged: (v) => _set((x) => x.copyWith(memory: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Streaming'),
        subtitle: Text('Matikan bila penyedia/jaringan bermasalah dengan SSE', style: context.tt.bodySmall),
        value: o.streaming,
        onChanged: (v) => _set((x) => x.copyWith(streaming: v)),
      ),
    ]);
  }

  String _wireNote(SettingsController s, ChatOptions o) {
    final prov = (o.providerId != null ? s.providers.where((p) => p.id == o.providerId).firstOrNull : null) ?? s.activeProvider;
    final wire = reasoningWireFor(prov?.baseUrl ?? '');
    return switch (wire) {
      ReasoningWire.openRouter => 'Dikirim ke OpenRouter sebagai reasoning: {effort | max_tokens}.',
      ReasoningWire.openAi => 'Dikirim ke OpenAI sebagai reasoning_effort (Maksimum = high, Mati = minimal).',
      ReasoningWire.ollama => 'Dikirim ke Ollama sebagai think + reasoning_effort.',
      ReasoningWire.nous => 'Nous Portal: reasoning_effort (OpenAI-compatible).',
      ReasoningWire.generic => 'Dikirim sebagai reasoning_effort (standar OpenAI-kompatibel); budget hanya untuk OpenRouter.',
    };
  }
}

const personalities = {
  'Ringkas': 'Jawab sesingkat mungkin: poin-poin, tanpa basa-basi.',
  'Guru': 'Jelaskan langkah demi langkah dengan contoh sederhana, cek pemahaman di akhir.',
  'Kreatif': 'Berani bereksperimen, beri beberapa alternatif ide yang tidak biasa.',
  'Teknis': 'Fokus pada detail teknis yang presisi, sertakan kode dan perintah yang bisa dijalankan.',
  'Santai': 'Gaya bahasa santai seperti teman, tetap akurat.',
};

class _OptionalSlider extends StatelessWidget {
  const _OptionalSlider({required this.label, required this.value, required this.min, required this.max, required this.divisions, required this.onChanged});
  final String label;
  final double? value;
  final double min, max;
  final int divisions;
  final ValueChanged<double?> onChanged;
  @override
  Widget build(BuildContext context) => Row(children: [
        SizedBox(width: 92, child: Text('$label\n${value == null ? 'otomatis' : value!.toStringAsFixed(2)}', style: context.tt.bodySmall)),
        Expanded(
          child: Slider(
            value: (value ?? (min + max) / 2).clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: value == null ? null : (v) => onChanged(v),
          ),
        ),
        Switch(value: value != null, onChanged: (v) => onChanged(v ? (label == 'Top-p' ? 1.0 : 0.7) : null)),
      ]);
}

// ---------------------------------------------------------- slash commands --
class SlashCommand {
  final String name;
  final String args;
  final String help;
  const SlashCommand(this.name, this.help, [this.args = '']);
}

const slashCommands = [
  SlashCommand('new', 'Percakapan baru', ''),
  SlashCommand('reset', 'Sama dengan /new', ''),
  SlashCommand('model', 'Ganti model sesi ini', '[nama-model]'),
  SlashCommand('reasoning', 'Atur thinking', '[off|low|medium|high|max]'),
  SlashCommand('think', 'Nyalakan/matikan thinking', ''),
  SlashCommand('tools', 'Alat aktif/nonaktif untuk sesi ini', '[on|off]'),
  SlashCommand('approval', 'Mode persetujuan alat sensitif', '[ask|auto|deny]'),
  SlashCommand('personality', 'Persona sesi', '[nama|teks|reset]'),
  SlashCommand('skills', 'Daftar skill; /<nama-skill> untuk memakainya', ''),
  SlashCommand('retry', 'Ulangi jawaban terakhir', ''),
  SlashCommand('undo', 'Batalkan giliran terakhir', ''),
  SlashCommand('compress', 'Ringkas konteks lama', ''),
  SlashCommand('usage', 'Statistik token & biaya sesi', ''),
  SlashCommand('export', 'Ekspor sesi ke Markdown (Berkas → exports/)', ''),
  SlashCommand('search', 'Cari di percakapan', '[teks]'),
  SlashCommand('title', 'Ganti judul sesi', '<judul>'),
  SlashCommand('stop', 'Hentikan jawaban', ''),
  SlashCommand('settings', 'Panel pengaturan chat', ''),
  SlashCommand('memory', 'Tampilkan memori yang dipakai', ''),
  SlashCommand('status', 'Status kantor & perangkat', ''),
  SlashCommand('help', 'Daftar perintah', ''),
];

/// Autocomplete rows above the composer while typing "/…".
class SlashSuggestions extends ConsumerWidget {
  const SlashSuggestions({super.key, required this.query, required this.onPick});
  final String query; // text after "/"
  final ValueChanged<String> onPick;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final q = query.toLowerCase();
    final cmds = slashCommands.where((c) => c.name.startsWith(q)).toList();
    final skills = store.skills.where((sk) => sk.enabled && sk.name.toLowerCase().startsWith(q)).take(6).toList();
    if (cmds.isEmpty && skills.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: context.hc.popover,
        borderRadius: BorderRadius.circular(context.hc.corner),
        border: Border.all(color: context.hc.border),
      ),
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 4), children: [
        for (final c in cmds)
          InkWell(
            onTap: () => onPick('/${c.name}${c.args.isNotEmpty ? ' ' : ''}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(children: [
                Text('/${c.name}', style: monoStyle(context, size: 12.5, color: context.cs.primary, weight: FontWeight.w600)),
                if (c.args.isNotEmpty) Text(' ${c.args}', style: monoStyle(context, size: 11.5, color: context.hc.mutedForeground)),
                const SizedBox(width: 10),
                Expanded(child: Text(c.help, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall)),
              ]),
            ),
          ),
        for (final sk in skills)
          InkWell(
            onTap: () => onPick('/${sk.name} '),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(children: [
                Icon(Icons.auto_awesome_motion_outlined, size: 14, color: context.hc.mutedForeground),
                const SizedBox(width: 6),
                Text('/${sk.name}', style: monoStyle(context, size: 12.5, color: context.cs.primary, weight: FontWeight.w600)),
                const SizedBox(width: 10),
                Expanded(child: Text(sk.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Markdown info sheet (/help, /usage, /status, /memory).
Future<void> showInfoSheet(BuildContext context, String title, String markdown) => showPaperSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (ctx, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(18, 0, 18, 24), children: [
          Text(title.toUpperCase(), style: ctx.tt.labelSmall),
          const SizedBox(height: 10),
          MarkdownView(markdown, onLink: (_) {}),
        ]),
      ),
    );

String helpMarkdown() => [
      '| Perintah | Fungsi |',
      '|---|---|',
      for (final c in slashCommands) '| `/${c.name}${c.args.isNotEmpty ? ' ${c.args}' : ''}` | ${c.help} |',
      '| `/<nama-skill> [tugas]` | Jalankan skill |',
      '',
      'Tekan lama pesan untuk **salin, sunting, buat ulang, cabangkan**.',
    ].join('\n');

/// In-chat search sheet; returns the picked message index.
Future<int?> showSearchSheet(BuildContext context, WidgetRef ref, {String initial = ''}) => showPaperSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _SearchSheet(initial: initial),
    );

class _SearchSheet extends ConsumerStatefulWidget {
  const _SearchSheet({required this.initial});
  final String initial;
  @override
  ConsumerState<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends ConsumerState<_SearchSheet> {
  late final _q = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hits = ref.read(chatProvider).search(_q.text);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _q,
          autofocus: true,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cari di percakapan ini'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
          child: hits.isEmpty
              ? Padding(padding: const EdgeInsets.all(16), child: Text(_q.text.isEmpty ? 'Ketik untuk mencari' : 'Tidak ada hasil', style: context.tt.bodySmall))
              : ListView(shrinkWrap: true, children: [
                  for (final h in hits)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.subdirectory_arrow_right, size: 18),
                      title: Text(h.$2, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, h.$1),
                    ),
                ]),
        ),
      ]),
    );
  }
}

/// Run a slash command typed in the composer. Returns (handled, refill text).
Future<(bool, String?)> handleSlash(BuildContext context, WidgetRef ref, String raw) async {
  final text = raw.trim();
  if (!text.startsWith('/') || text.startsWith('//')) return (false, null);
  final sp = text.indexOf(' ');
  final cmd = (sp < 0 ? text.substring(1) : text.substring(1, sp)).toLowerCase();
  final arg = sp < 0 ? '' : text.substring(sp + 1).trim();
  final chat = ref.read(chatProvider);
  final s = ref.read(settingsProvider);
  final store = ref.read(storeProvider);
  void say(String m) => toast(context, m);
  switch (cmd) {
    case 'new' || 'reset' || 'clear':
      await chat.newSession();
      say('Percakapan baru');
    case 'model':
      if (arg.isEmpty) {
        await showChatSettingsSheet(context);
      } else {
        if (chat.current == null) await chat.newSession();
        final p = arg.contains(':') ? arg.split(':') : null;
        final prov = p != null ? s.providers.where((x) => x.id == p[0] || x.label.toLowerCase() == p[0].toLowerCase()).firstOrNull : null;
        updateOptions(ref, (o) => prov != null ? o.copyWith(providerId: prov.id, model: p!.sublist(1).join(':')) : o.copyWith(model: arg));
        say('Model sesi: $arg');
      }
    case 'reasoning' || 'think':
      final o = currentOptions(ref);
      final lv = cmd == 'think' && arg.isEmpty ? (o.reasoningOn ? 'off' : 'medium') : arg.toLowerCase();
      if (!reasoningLevels.contains(lv)) {
        await showChatSettingsSheet(context);
      } else {
        updateOptions(ref, (x) => x.copyWith(effort: lv));
        final m = effectiveModel(ref);
        say(modelSupportsReasoning(m) ? 'Thinking: ${reasoningLabel(lv)}' : 'Thinking diset ${reasoningLabel(lv)} (model $m mungkin tidak mendukung)');
      }
    case 'tools':
      final on = arg.isEmpty ? !currentOptions(ref).tools : arg != 'off';
      updateOptions(ref, (x) => x.copyWith(tools: on));
      say(on ? 'Alat aktif' : 'Alat dimatikan untuk sesi ini');
    case 'approval':
      if (approvalModes.contains(arg)) {
        updateOptions(ref, (x) => x.copyWith(approval: arg));
        say('Persetujuan: ${approvalLabel(arg)}');
      } else {
        await showChatSettingsSheet(context);
      }
    case 'personality':
      if (arg.isEmpty) {
        await showInfoSheet(context, 'Persona', [
          'Pakai `/personality <nama>` atau `/personality <teks bebas>`; `/personality reset` untuk menghapus.',
          '',
          for (final p in personalities.entries) '- **${p.key}** — ${p.value}',
          '',
          'Aktif: ${currentOptions(ref).persona.isEmpty ? '_(tidak ada)_' : currentOptions(ref).persona}',
        ].join('\n'));
      } else {
        final preset = personalities.entries.where((e) => e.key.toLowerCase() == arg.toLowerCase()).firstOrNull;
        final v = arg == 'reset' ? '' : (preset?.value ?? arg);
        updateOptions(ref, (x) => x.copyWith(persona: v));
        say(v.isEmpty ? 'Persona dihapus' : 'Persona diterapkan');
      }
    case 'skills':
      final sk = store.skills.where((x) => x.enabled).toList();
      await showInfoSheet(context, 'Skill', sk.isEmpty ? 'Belum ada skill. Buat di Lainnya → Skill.' : [for (final x in sk) '- `/${x.name}` — ${x.description}'].join('\n'));
    case 'retry':
      await chat.retry();
    case 'undo':
      final t = chat.undo();
      say(t == null ? 'Tidak ada yang bisa dibatalkan' : 'Giliran terakhir dibatalkan');
      return (true, t);
    case 'compress':
      say('Mengompres konteks…');
      final r = await chat.compress();
      if (context.mounted) say(r);
    case 'usage':
      final m = effectiveModel(ref);
      await showInfoSheet(context, 'Pemakaian sesi', [
        '| | |', '|---|---|',
        '| Model | `$m` |',
        '| Giliran model | ${chat.usageTurns} |',
        '| Token prompt | ${chat.usagePrompt} |',
        '| Token jawaban | ${chat.usageCompletion} |',
        '| Total | ${chat.usagePrompt + chat.usageCompletion} |',
        '| Konteks terakhir | ${chat.contextTokens} |',
        '| Kecepatan | ${chat.tokensPerSecond?.toStringAsFixed(1) ?? '-'} tok/s |',
        '| Biaya | ${chat.usageCost > 0 ? '\$${chat.usageCost.toStringAsFixed(5)}' : 'tidak dilaporkan penyedia (OpenRouter melaporkannya)'} |',
        '', '_Dihitung sejak sesi dibuka di aplikasi ini. Bila penyedia tidak mengirim usage, token diperkirakan (≈4 karakter/token)._',
      ].join('\n'));
    case 'export':
      if (chat.messages.isEmpty) {
        say('Belum ada pesan');
      } else {
        final path = chat.exportToWorkspace();
        say('Diekspor ke $path (Lainnya → Berkas)');
      }
    case 'search':
      await showSearchSheet(context, ref, initial: arg);
    case 'title':
      if (arg.isNotEmpty && chat.current != null) {
        await chat.rename(chat.current!, arg);
        say('Judul diganti');
      }
    case 'stop':
      await chat.stop();
    case 'settings':
      await showChatSettingsSheet(context);
    case 'memory':
      final mem = store.memoryFor(chat.current?.profile ?? s.defaultProfile);
      await showInfoSheet(context, 'Memori', mem.isEmpty ? 'Belum ada memori.' : [for (final m in mem) '- ${m.text}'].join('\n'));
    case 'status':
      final app = ref.read(appProvider);
      await showInfoSheet(context, 'Status', '```\n${app.runtime.officeSummary()}\n```');
    case 'help' || '?':
      await showInfoSheet(context, 'Perintah', helpMarkdown());
    default:
      final sk = store.skills.where((x) => x.enabled && x.name.toLowerCase() == cmd).firstOrNull;
      if (sk == null) {
        say('Perintah /$cmd tidak dikenal — ketik /help');
        return (true, text);
      }
      await chat.send('Gunakan skill "${sk.name}" (muat dulu dengan skill_load). ${arg.isEmpty ? '' : 'Tugas: $arg'}'.trim());
  }
  return (true, null);
}
