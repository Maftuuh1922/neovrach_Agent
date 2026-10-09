// Kantor: the PC's agents as "pegawai" (name, role, status, current task,
// tool, last activity) plus the live activity feed. Read-only on the phone and
// fully push-driven: the first snapshot comes from `GET /api/office`, every
// change after that arrives as the WebSocket event `office.update`.
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/neovarch_mobile_theme.dart';
import '../../ui/widgets/common.dart' show CenterLoader;
import '../office_models.dart';
import '../remote_controller.dart';
import 'nv_widgets.dart';
import 'remote_vault_screen.dart';

/// "3 mnt lalu" style relative time in Indonesian.
String agoId(DateTime? t, {DateTime? now}) {
  if (t == null) return '';
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inSeconds < 45) return 'baru saja';
  if (d.inMinutes < 60) return '${d.inMinutes} mnt lalu';
  if (d.inHours < 24) return '${d.inHours} jam lalu';
  return '${d.inDays} hari lalu';
}

class RemoteOfficeScreen extends ConsumerWidget {
  const RemoteOfficeScreen({super.key, required this.onOpenChat, required this.onOpenApprovals});
  final VoidCallback onOpenChat;
  final VoidCallback onOpenApprovals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(remoteProvider);
    final o = r.office;
    final pc = r.desktop?.name ?? 'PC';
    final idle = o == null ? 0 : o.agents.length - o.working - o.waiting;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: r.refreshOffice,
        child: ListView(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 16), children: [
          NvHeader(
            kicker: 'kantor · $pc',
            title: 'Kantor',
            status: Row(children: [
              NvDot(r.connected ? NV.red : NV.warn, size: 7),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  r.connected ? (o == null ? 'memuat kantor…' : '${o.agents.length} pegawai · langsung dari PC') : r.statusLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NV.monoLabel(size: 10, color: NV.muted).copyWith(letterSpacing: 0.4),
                ),
              ),
            ]),
          ),
          if (o == null && r.officeError != null)
            Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: NvNotice(r.officeError!))
          else if (o == null)
            const Padding(padding: EdgeInsets.only(top: 80), child: CenterLoader(label: 'membuka kantor di PC…'))
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(children: [
                _Count(key: const ValueKey('office-working'), n: o.working, label: 'bekerja', accent: true),
                const SizedBox(width: 8),
                _Count(n: o.waiting, label: 'menunggu', onTap: o.waiting > 0 ? onOpenApprovals : null),
                const SizedBox(width: 8),
                _Count(n: idle < 0 ? 0 : idle, label: 'santai'),
              ]),
            ),
            NvSection('pegawai', count: o.agents.length),
            if (o.agents.isEmpty)
              const NvEmpty(
                  title: 'Kantor masih sepi', body: 'Pegawai muncul saat agen di PC mengerjakan sesi atau tugas Kanban.')
            else
              for (final a in o.agents)
                AgentDesk(
                  agent: a,
                  onTap: a.sessionId == null
                      ? null
                      : () {
                          r.openSession(a.sessionId!);
                          onOpenChat();
                        },
                  onApprove: a.waiting ? onOpenApprovals : null,
                ),
            const NvSection('memori'),
            NvList(children: [
              NvRow(
                key: const ValueKey('office-vault'),
                icon: CupertinoIcons.circle_grid_hex,
                title: 'Vault Obsidian',
                subtitle: o.vaultConfigured
                    ? '${o.vault['note_count'] ?? 0} catatan · baca saja di HP'
                    : 'Belum dipilih di Pengaturan PC',
                mono: true,
                trailing: Icon(CupertinoIcons.chevron_right, size: 18, color: NV.faint),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RemoteVaultScreen())),
              ),
            ]),
            NvSection('aktivitas', count: o.feed.length),
            if (o.feed.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('Belum ada aktivitas. Kirim perintah dari tab Chat.', style: TextStyle(color: NV.muted, fontSize: 13.5)),
              )
            else
              NvPanel(
                key: const ValueKey('office-feed'),
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(children: [for (final f in o.feed.take(40)) ActivityRow(item: f)]),
              ),
          ],
        ]),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({super.key, required this.n, required this.label, this.accent = false, this.onTap});
  final int n;
  final String label;
  final bool accent;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Expanded(
        child: NvPanel(
          onTap: onTap,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$n', style: NV.display(size: 30, color: accent && n > 0 ? NV.red : NV.text)),
            const SizedBox(height: 4),
            Text(label.toUpperCase(), style: NV.monoLabel(size: 9.5)),
          ]),
        ),
      );
}

/// One pegawai at their desk.
class AgentDesk extends StatelessWidget {
  const AgentDesk({super.key, required this.agent, this.onTap, this.onApprove});
  final OfficeAgent agent;
  final VoidCallback? onTap;
  final VoidCallback? onApprove;

  @override
  Widget build(BuildContext context) {
    final a = agent;
    final c = a.working ? NV.red : (a.waiting ? NV.text : NV.faint);
    return NvPanel(
      key: ValueKey('desk-${a.id}'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: a.working ? NV.redWash : NV.raised,
              shape: BoxShape.circle,
              border: Border.all(color: a.working ? NV.darkRed : NV.border),
            ),
            child: Text(a.name.isEmpty ? '?' : a.name.characters.first.toUpperCase(),
                style: TextStyle(fontFamily: NV.serif, fontSize: 22, color: a.working ? NV.red : NV.text)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: NV.text)),
              const SizedBox(height: 2),
              Text(a.role, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: NV.muted)),
            ]),
          ),
          NvPill(a.statusLabel, color: c, filled: a.working),
        ]),
        if (a.task != null) ...[
          const SizedBox(height: 12),
          Text('TUGAS', style: NV.monoLabel(size: 9)),
          const SizedBox(height: 3),
          Text(a.task!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, height: 1.4, color: NV.text)),
        ],
        if (a.tool != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(CupertinoIcons.wrench, size: 14, color: NV.red),
            const SizedBox(width: 6),
            Expanded(
                child: Text(a.tool!,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: NV.monoLabel(size: 11, color: NV.text).copyWith(letterSpacing: 0.2))),
          ]),
        ],
        if (a.waiting && a.pendingCommand != null) ...[
          const SizedBox(height: 10),
          NvNotice('Menunggu persetujuan: ${a.pendingCommand}',
              icon: CupertinoIcons.checkmark_shield,
              action: onApprove == null ? null : TextButton(onPressed: onApprove, child: const Text('Tinjau'))),
        ],
        if (a.lastActivityText != null || a.lastActivity != null) ...[
          const SizedBox(height: 10),
          Text(
            [if (a.lastActivityText != null) a.lastActivityText!, if (a.lastActivity != null) agoId(a.lastActivity)].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: NV.faint),
          ),
        ],
      ]),
    );
  }
}

/// One line of the activity feed.
class ActivityRow extends StatelessWidget {
  const ActivityRow({super.key, required this.item});
  final OfficeActivity item;

  static IconData iconFor(String kind) => switch (kind) {
        'tool' => CupertinoIcons.wrench,
        'tool.done' => CupertinoIcons.checkmark,
        'message' => CupertinoIcons.chat_bubble,
        'message.user' => CupertinoIcons.doc_checkmark,
        'approval' => CupertinoIcons.checkmark_shield,
        'approval.done' => CupertinoIcons.checkmark_seal,
        'task' => CupertinoIcons.rectangle_grid_2x2,
        'error' => CupertinoIcons.exclamationmark_circle,
        _ => CupertinoIcons.circle,
      };

  @override
  Widget build(BuildContext context) {
    final hot = item.kind == 'error' || item.kind == 'approval';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(iconFor(item.kind), size: 16, color: hot ? NV.red : NV.muted)),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '${item.agent} ', style: TextStyle(fontWeight: FontWeight.w600, color: NV.text)),
              TextSpan(text: item.text, style: TextStyle(color: NV.muted)),
            ]),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ),
        const SizedBox(width: 8),
        Text(agoId(item.at), style: NV.monoLabel(size: 9.5, color: NV.faint).copyWith(letterSpacing: 0.2)),
      ]),
    );
  }
}
