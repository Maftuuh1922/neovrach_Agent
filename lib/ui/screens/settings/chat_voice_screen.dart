// Chat & voice — thinking (on/off, effort, show), chat text size, resume
// last chat, dictation language, read-aloud and its rate.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/chat_options.dart';
import '../../../state/app_controller.dart';
import '../../../state/voice_service.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../more_screen.dart' show ChatDefaultsScreen;

class ChatVoiceScreen extends ConsumerWidget {
  const ChatVoiceScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Chat, thinking & suara', style: context.tt.titleMedium)),
      body: ListView(padding: EdgeInsets.only(bottom: 32 + MediaQuery.paddingOf(context).bottom), children: [
        const SectionLabel('Thinking / penalaran'),
        SwitchListTile(
          title: const Text('Thinking aktif'),
          subtitle: Text('Model berpikir dulu sebelum menjawab (bila modelnya mendukung)', style: context.tt.bodySmall),
          value: s.chatDefaults.reasoningOn,
          onChanged: (v) => s.update((x) => x.chatDefaults = x.chatDefaults.copyWith(effort: v ? 'medium' : 'off')),
        ),
        ListTile(
          title: const Text('Tingkat usaha (effort)'),
          subtitle: Text('Rendah = cepat & hemat · Maksimum = paling teliti', style: context.tt.bodySmall),
          trailing: DropdownButton<String>(
            value: s.chatDefaults.effort,
            underline: const SizedBox.shrink(),
            items: [for (final l in reasoningLevels) DropdownMenuItem(value: l, child: Text(reasoningLabel(l)))],
            onChanged: (v) => s.update((x) => x.chatDefaults = x.chatDefaults.copyWith(effort: v ?? 'medium')),
          ),
        ),
        SwitchListTile(
          title: const Text('Tampilkan proses berpikir'),
          subtitle: Text('Blok "berpikir" model di transkrip, dengan indikator animasi saat berjalan', style: context.tt.bodySmall),
          value: s.showReasoning && s.chatDefaults.showReasoning,
          onChanged: (v) => s.update((x) {
            x.showReasoning = v;
            x.chatDefaults = x.chatDefaults.copyWith(showReasoning: v);
          }),
        ),
        SwitchListTile(
          title: const Text('Ciutkan setelah selesai'),
          value: s.chatDefaults.autoCollapseReasoning,
          onChanged: (v) => s.update((x) => x.chatDefaults = x.chatDefaults.copyWith(autoCollapseReasoning: v)),
        ),
        ListTile(
          title: const Text('Semua pengaturan chat & thinking…'),
          subtitle: Text('Budget token, model, sampling, persona, alat & persetujuan, memori, streaming', style: context.tt.bodySmall),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatDefaultsScreen())),
        ),
        const SectionLabel('Chat'),
        ListTile(
          title: const Text('Ukuran teks chat'),
          subtitle: Slider(
            value: s.chatScale.clamp(0.85, 1.4),
            min: 0.85,
            max: 1.4,
            divisions: 11,
            label: '${(s.chatScale * 100).round()}%',
            onChanged: (v) => s.update((x) => x.chatScale = v),
          ),
          trailing: Text('${(s.chatScale * 100).round()}%', style: context.tt.bodySmall),
        ),
        SwitchListTile(
          title: const Text('Buka percakapan terakhir saat mulai'),
          value: s.resumeLastSession,
          onChanged: (v) => s.update((x) => x.resumeLastSession = v),
        ),
        const SectionLabel('Suara'),
        SwitchListTile(
          title: const Text('Bacakan balasan'),
          subtitle: Text('Text-to-speech setelah agent selesai menjawab', style: context.tt.bodySmall),
          value: s.readAloud,
          onChanged: (v) => s.update((x) => x.readAloud = v),
        ),
        ListTile(
          title: const Text('Kecepatan baca'),
          subtitle: Slider(value: s.ttsRate, min: 0.2, max: 0.9, divisions: 7, onChanged: (v) => s.update((x) => x.ttsRate = v)),
        ),
        ListTile(
          title: const Text('Bahasa dikte & suara'),
          trailing: DropdownButton<String>(
            value: s.sttLocale,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'id_ID', child: Text('Indonesia')),
              DropdownMenuItem(value: 'en_US', child: Text('English (US)')),
              DropdownMenuItem(value: 'jv_ID', child: Text('Jawa')),
              DropdownMenuItem(value: 'su_ID', child: Text('Sunda')),
            ],
            onChanged: (v) => s.update((x) => x.sttLocale = v ?? 'id_ID'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: () => VoiceService.instance.speak('Halo, aku Neovarch. Suaraku sudah siap.', rate: s.ttsRate, language: s.sttLocale.replaceAll('_', '-')),
            icon: const Icon(Icons.volume_up_outlined, size: 18),
            label: const Text('Uji suara'),
          ),
        ),
      ]),
    );
  }
}
