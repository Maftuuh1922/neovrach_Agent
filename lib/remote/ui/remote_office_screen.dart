// Kantor: the PC's agents as "pegawai" (name, role, status, current task,
// tool, last activity) plus the live activity feed, as the 3D room (default)
// or a list. Fully push-driven: the first snapshot comes from `GET /api/office`,
// every change after that arrives as the WebSocket event `office.update`; the
// only write is "Kasih tugas" (a Kanban task assigned to the pegawai).
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/neovarch_mobile_theme.dart';
import '../../ui/widgets/common.dart' show CenterLoader, toast;
import '../../ui/widgets/motion.dart' show reduceMotion;
import '../agent_identity.dart';
import '../office_models.dart';
import '../office_scene_state.dart';
import '../remote_controller.dart';
import 'nv_widgets.dart';
import 'remote_office_3d.dart';
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

/// Web preview / tests: open the Kantor segment on the list instead of the
/// 3D office.
bool previewOfficeList = false;

class RemoteOfficeScreen extends ConsumerStatefulWidget {
  const RemoteOfficeScreen({super.key, required this.onOpenChat, required this.onOpenApprovals});
  final VoidCallback onOpenChat;
  final VoidCallback onOpenApprovals;

  @override
  ConsumerState<RemoteOfficeScreen> createState() => _RemoteOfficeScreenState();
}

class _RemoteOfficeScreenState extends ConsumerState<RemoteOfficeScreen> {
  late bool _visual = !previewOfficeList;
  String? _sceneUnavailable;
  final _desks = OfficeDeskAssigner();

  void _openAgent(OfficeAgent a) => showAgentSheet(context, a, onOpenChat: widget.onOpenChat, onOpenApprovals: widget.onOpenApprovals);

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(remoteProvider);
    final o = r.office;
    final pc = r.desktop?.name ?? 'PC';
    final idle = o == null ? 0 : o.agents.length - o.working - o.waiting;
    final visual = _visual && _sceneUnavailable == null;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: r.refreshOffice,
        child: ListView(
            key: const ValueKey('office-list'),
            padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 16),
            children: [
          NvHeader(
            kicker: 'kantor · $pc',
            title: 'Kantor',
            actions: [
              _ViewToggle(
                visual: _visual,
                onChanged: (v) => setState(() {
                  _visual = v;
                  if (v) _sceneUnavailable = null; // retry the 3D view
                }),
              ),
            ],
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
                _Count(n: o.waiting, label: 'menunggu', onTap: o.waiting > 0 ? widget.onOpenApprovals : null),
                const SizedBox(width: 8),
                _Count(n: idle < 0 ? 0 : idle, label: 'santai'),
              ]),
            ),
            if (_visual && _sceneUnavailable != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: NvNotice('Kantor 3D tidak bisa dibuka di HP ini, jadi tampil sebagai daftar.',
                    key: const ValueKey('office-3d-fallback'), icon: CupertinoIcons.cube_box),
              ),
            if (visual) ...[
              const SizedBox(height: 12),
              _ScenePanel(
                child: RemoteOffice3D(
                  key: const ValueKey('office-3d'),
                  state: officeSceneState(o, desks: _desks, accentArgb: NV.red.toARGB32(), dark: NV.palette.dark, motion: !reduceMotion(context)),
                  onAgentTap: (id) {
                    final a = ref.read(remoteProvider).office?.agents.where((x) => x.id == id).firstOrNull;
                    if (a != null) _openAgent(a);
                  },
                  onUnavailable: (why) {
                    if (mounted) setState(() => _sceneUnavailable = why);
                  },
                ),
              ),
            ],
            NvSection('pegawai', count: o.agents.length),
            if (o.agents.isEmpty)
              const NvEmpty(
                  title: 'Kantor masih sepi', body: 'Pegawai muncul saat agen di PC mengerjakan sesi atau tugas Kanban.')
            else if (visual)
              NvList(children: [for (final a in o.agents) AgentRosterRow(agent: a, onTap: () => _openAgent(a))])
            else
              for (final a in o.agents)
                AgentDesk(
                  agent: a,
                  onTap: a.sessionId == null
                      ? null
                      : () {
                          r.openSession(a.sessionId!);
                          widget.onOpenChat();
                        },
                  onApprove: a.waiting ? widget.onOpenApprovals : null,
                  onAssign: () => _openAgent(a),
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

/// "3D | Daftar" switch in the Kantor header (glass, icon + label).
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.visual, required this.onChanged});
  final bool visual;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(bool v, IconData icon, String label, String key) {
      final on = visual == v;
      return Semantics(
        button: true,
        selected: on,
        label: v ? 'Kantor 3D' : 'Daftar pegawai',
        child: GestureDetector(
          key: ValueKey(key),
          behavior: HitTestBehavior.opaque,
          onTap: on ? null : () => onChanged(v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(color: on ? NV.red : Colors.transparent, borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 15, color: on ? NV.onRed : NV.muted),
              const SizedBox(width: 5),
              Text(label, style: NV.monoLabel(size: 9.5, color: on ? NV.onRed : NV.muted)),
            ]),
          ),
        ),
      );
    }

    return NvGlass(
      key: const ValueKey('office-view-toggle'),
      radius: 999,
      padding: const EdgeInsets.all(3),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg(true, CupertinoIcons.cube, '3D', 'office-view-visual'),
        seg(false, CupertinoIcons.list_bullet, 'DAFTAR', 'office-view-list'),
      ]),
    );
  }
}

/// The glass frame the 3D room floats in (wallpaper shows through the clear
/// WebView background).
class _ScenePanel extends StatelessWidget {
  const _ScenePanel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = (w * 0.95).clamp(300.0, 460.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        key: const ValueKey('office-scene-panel'),
        height: h,
        child: NvGlass(
          child: Stack(children: [
            Positioned.fill(child: child),
            Positioned(
              left: 12,
              top: 12,
              child: IgnorePointer(
                child: NvGlass(
                  radius: 999,
                  backdrop: false,
                  padding: const EdgeInsets.fromLTRB(9, 5, 11, 5),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    NvDot(NV.red, size: 6),
                    const SizedBox(width: 6),
                    Text('LANGSUNG · KETUK PEGAWAI', style: NV.monoLabel(size: 9, color: NV.text)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// One compact roster line under the 3D room: status, name, current task.
class AgentRosterRow extends StatelessWidget {
  const AgentRosterRow({super.key, required this.agent, required this.onTap});
  final OfficeAgent agent;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final a = agent;
    return InkWell(
      key: ValueKey('roster-${a.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(children: [
          NvAgentAvatar.of(a, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: NV.text)),
              const SizedBox(height: 2),
              Text(a.task ?? a.role, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: NV.muted)),
            ]),
          ),
          const SizedBox(width: 8),
          NvPill(a.statusLabel, color: a.working ? NV.red : (a.waiting ? NV.text : NV.muted), filled: a.working),
        ]),
      ),
    );
  }
}

/// Agent sheet: status, current task, and "Kasih tugas" (a Kanban task
/// assigned to this pegawai, created on the PC through `POST /api/plugins/kanban/tasks`).
Future<void> showAgentSheet(BuildContext context, OfficeAgent agent, {VoidCallback? onOpenChat, VoidCallback? onOpenApprovals}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AgentSheet(agentId: agent.id, initial: agent, onOpenChat: onOpenChat, onOpenApprovals: onOpenApprovals),
    );

class AgentSheet extends ConsumerStatefulWidget {
  const AgentSheet({super.key, required this.agentId, required this.initial, this.onOpenChat, this.onOpenApprovals});
  final String agentId;
  final OfficeAgent initial;
  final VoidCallback? onOpenChat;
  final VoidCallback? onOpenApprovals;
  @override
  ConsumerState<AgentSheet> createState() => _AgentSheetState();
}

class _AgentSheetState extends ConsumerState<AgentSheet> {
  final _task = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    _task.dispose();
    super.dispose();
  }

  Future<void> _send(OfficeAgent a) async {
    final text = _task.text.trim();
    if (text.isEmpty || busy) return;
    final lines = text.split('\n');
    final title = lines.first.trim();
    final body = lines.skip(1).join('\n').trim();
    setState(() => busy = true);
    final err = await ref.read(remoteProvider).createTask(title: title, body: body.isEmpty ? null : body, assignee: a.name);
    if (!mounted) return;
    setState(() => busy = false);
    toast(context, err ?? 'Tugas dikirim ke ${a.name}');
    if (err == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(remoteProvider);
    // live: the sheet follows office.update pushes while it is open
    final a = r.office?.agents.where((x) => x.id == widget.agentId).firstOrNull ?? widget.initial;
    return Padding(
      key: const ValueKey('agent-sheet'),
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          NvAgentAvatar.of(a, size: 44),
          const SizedBox(width: 12),
          Expanded(child: NvSheetTitle(kicker: a.role, title: a.name)),
          NvPill(a.statusLabel, color: a.working ? NV.red : (a.waiting ? NV.text : NV.muted), filled: a.working),
        ]),
        const SizedBox(height: 14),
        Text('TUGAS SEKARANG', style: NV.monoLabel(size: 9)),
        const SizedBox(height: 4),
        Text(a.task ?? 'Belum ada tugas', key: const ValueKey('agent-sheet-task'), maxLines: 3, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14.5, height: 1.4, color: a.task == null ? NV.muted : NV.text)),
        if (a.tool != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(CupertinoIcons.wrench, size: 14, color: NV.red),
            const SizedBox(width: 6),
            Expanded(child: Text(a.tool!, maxLines: 1, overflow: TextOverflow.ellipsis, style: NV.monoLabel(size: 11, color: NV.text).copyWith(letterSpacing: 0.2))),
          ]),
        ],
        if (a.waiting && a.pendingCommand != null) ...[
          const SizedBox(height: 10),
          NvNotice('Menunggu persetujuan: ${a.pendingCommand}',
              icon: CupertinoIcons.checkmark_shield,
              action: widget.onOpenApprovals == null
                  ? null
                  : TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onOpenApprovals!();
                      },
                      child: const Text('Tinjau'))),
        ],
        if (a.sessionId != null && widget.onOpenChat != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('agent-sheet-chat'),
              onPressed: () {
                Navigator.pop(context);
                r.openSession(a.sessionId!);
                widget.onOpenChat!();
              },
              icon: const Icon(CupertinoIcons.chat_bubble, size: 16),
              label: const Text('Buka chat-nya'),
            ),
          ),
        const SizedBox(height: 12),
        Text('KASIH TUGAS', style: NV.monoLabel(size: 9)),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('assign-task-field'),
          controller: _task,
          minLines: 1,
          maxLines: 4,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(hintText: 'Tugas untuk ${a.name}… (baris pertama = judul)'),
        ),
        const SizedBox(height: 6),
        Text('Jadi tugas Kanban di PC dengan penanggung ${a.name}.', style: TextStyle(fontSize: 12.5, color: NV.muted)),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('assign-task-send'),
          onPressed: busy ? null : () => _send(a),
          icon: const Icon(CupertinoIcons.paperplane_fill, size: 16),
          label: Text(busy ? 'Mengirim…' : 'Kasih tugas'),
        ),
      ]),
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
            Text('$n', style: NV.display(size: 30, color: accent && n > 0 ? NV.redInk : NV.text)),
            const SizedBox(height: 4),
            Text(label.toUpperCase(), style: NV.monoLabel(size: 9.5)),
          ]),
        ),
      );
}

/// One pegawai at their desk.
class AgentDesk extends StatelessWidget {
  const AgentDesk({super.key, required this.agent, this.onTap, this.onApprove, this.onAssign});
  final OfficeAgent agent;
  final VoidCallback? onTap;
  final VoidCallback? onApprove;
  /// "Kasih tugas": opens the agent sheet with the task field.
  final VoidCallback? onAssign;

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
          NvAgentAvatar.of(a, size: 40),
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
        if (onAssign != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: ValueKey('assign-${a.id}'),
              onPressed: onAssign,
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), visualDensity: VisualDensity.compact),
              icon: const Icon(CupertinoIcons.paperplane, size: 15),
              label: const Text('Kasih tugas'),
            ),
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
