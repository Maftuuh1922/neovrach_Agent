// Lainnya — the management hub: agents/profiles, cron, skills, memory,
// files, projects and every settings page.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/nv_themes.dart';
import 'chat/chat_extras.dart';
import '../widgets/common.dart';
import 'agents_screen.dart';
import 'cron_screen.dart';
import 'files_screen.dart';
import 'memory_screen.dart';
import 'projects_screen.dart';
import 'settings/about_screen.dart';
import 'settings/appearance_screen.dart';
import 'settings/chat_voice_screen.dart';
import 'settings/connection_screen.dart';
import 'settings/permissions_screen.dart';
import 'settings/providers_screen.dart';
import 'settings/tools_screen.dart';
import 'skills_screen.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    final settings = ref.watch(settingsProvider);
    final store = ref.watch(storeProvider);
    final office = ref.watch(officeProvider);
    final localish = app.mode == ConnectionMode.local || app.mode == ConnectionMode.gateway;

    void open(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

    Widget tile(IconData icon, String title, String sub, Widget page, {Widget? trailing}) => ListTile(
          leading: Icon(icon),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: Text(sub, style: context.tt.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: trailing ?? const Icon(Icons.chevron_right, size: 18),
          onTap: () => open(page),
        );

    return Scaffold(
      appBar: AppBar(title: Text('Lainnya', style: context.tt.titleMedium)),
      body: ListView(padding: EdgeInsets.only(bottom: 32 + MediaQuery.paddingOf(context).bottom), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(children: [
            const BrandMark(size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Neovarch Agent', style: context.tt.titleMedium),
                Text('${app.mode.label}${localish && settings.activeProvider != null ? ' · ${settings.activeProvider!.label}' : ''}', style: context.tt.bodySmall),
              ]),
            ),
          ]),
        ),
        const SectionLabel('Kerja'),
        tile(Icons.badge_outlined, 'Agent & profil', '${office.agents.length} di kantor', const AgentsScreen()),
        tile(Icons.schedule_outlined, 'Cron', 'Prompt terjadwal', const CronScreen()),
        if (localish) ...[
          tile(Icons.folder_copy_outlined, 'Proyek', '${store.projects.length} proyek · kelompokkan sesi & folder', const ProjectsScreen()),
          tile(Icons.description_outlined, 'Berkas', '${store.files.length} berkas di workspace', const FilesScreen()),
          tile(Icons.auto_awesome_motion_outlined, 'Skill', '${store.skills.length} skill', const SkillsScreen()),
          tile(Icons.bookmark_border, 'Memori', '${store.memory.length} catatan', const MemoryScreen()),
        ],
        const SectionLabel('Pengaturan'),
        tile(Icons.hub_outlined, 'Koneksi', app.mode.label, const ConnectionScreen()),
        tile(Icons.key_outlined, 'Penyedia & model', settings.activeProvider == null ? 'belum diatur' : '${settings.activeProvider!.label} · ${settings.activeProvider!.model}',
            const ProvidersScreen()),
        tile(Icons.build_outlined, 'Alat', '${settings.enabledTools.length} alat aktif', const ToolsScreen()),
        tile(Icons.verified_user_outlined, 'Izin perangkat', 'Kamera, mikrofon, media, notifikasi, lokasi, kontak, kalender, berkas', const PermissionsScreen()),
        tile(Icons.palette_outlined, 'Tampilan', themeByName(settings.themeName).label, const AppearanceScreen()),
        tile(Icons.psychology_alt_outlined, 'Chat & thinking (bawaan)', 'Thinking ${settings.chatDefaults.effort} · persetujuan ${settings.chatDefaults.approval}',
            const ChatDefaultsScreen()),
        tile(Icons.record_voice_over_outlined, 'Chat, thinking & suara', 'Thinking, ukuran teks, dikte, baca balasan', const ChatVoiceScreen()),
        tile(Icons.info_outline, 'Tentang', 'Versi, pembaruan, data', const AboutScreen()),
      ]),
    );
  }
}

class ChatDefaultsScreen extends StatelessWidget {
  const ChatDefaultsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Chat & thinking', style: context.tt.titleMedium)),
        body: const Padding(padding: EdgeInsets.only(top: 12), child: ChatSettingsPanel(defaults: true)),
      );
}
