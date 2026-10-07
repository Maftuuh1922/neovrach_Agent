// Tools — which on-device tools the agent may call (Desktop: toolset config).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/agent_runtime.dart';
import '../../../data/device_tools.dart';
import '../../../state/app_controller.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../chat/message_widgets.dart';

class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Alat', style: context.tt.titleMedium)),
      body: ListView(padding: EdgeInsets.only(bottom: 32 + MediaQuery.paddingOf(context).bottom), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(
              'Alat yang boleh dipakai agen di mode Mandiri. Semua aktif secara bawaan. Alat bertanda PERSETUJUAN menunggu izinmu di chat '
              '(atur di panel pengaturan chat → Mode persetujuan); alat perangkat meminta izin Android saat pertama dipakai.',
              style: context.tt.bodySmall),
        ),
        for (final g in const [('app', 'Aplikasi — memori, berkas, papan, web'), ('office', 'Kantor — agen, tugas, rapat, cron'), ('device', 'Perangkat Android')]) ...[
          SectionLabel(g.$2),
          for (final t in allTools.where((t) => t.group == g.$1))
            SwitchListTile(
              secondary: Icon(toolIcon(t.name)),
              title: Row(children: [
                Flexible(child: Text(t.label)),
                if (t.risky) ...[
                  const SizedBox(width: 6),
                  StatusPill('persetujuan', color: context.hc.warning),
                ],
              ]),
              subtitle: Text(
                  '${t.name} — ${t.description}${devicePermissionLabels[t.name] != null ? '\nIzin: ${devicePermissionLabels[t.name]}' : ''}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.bodySmall),
              value: s.enabledTools.contains(t.name),
              onChanged: (v) => s.update((x) => v ? x.enabledTools.add(t.name) : x.enabledTools.remove(t.name)),
            ),
        ],
        const Divider(),
        SwitchListTile(
          title: const Text('Auto-jalankan tugas'),
          subtitle: Text('Tugas yang ditugaskan ke agent langsung dikerjakan lalu pindah ke REVIEW', style: context.tt.bodySmall),
          value: s.autoRunTasks,
          onChanged: (v) => s.update((x) => x.autoRunTasks = v),
        ),
      ]),
    );
  }
}
