// "Intip layar": whoever occupies a desk — live log (polled every 5 s),
// recent runs, and steer / stop controls (PeekPanel.tsx), plus a shortcut
// into a chat with that agent.
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/chat_engine.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import 'task_detail_sheet.dart';

Future<void> showPeekSheet(BuildContext context, {String? agentName, int? desk}) => showPaperSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (ctx, scroll) => PeekSheet(agentName: agentName, desk: desk, scroll: scroll),
      ),
    );

class PeekSheet extends ConsumerStatefulWidget {
  const PeekSheet({super.key, this.agentName, this.desk, required this.scroll});
  final String? agentName;
  final int? desk;
  final ScrollController scroll;
  @override
  ConsumerState<PeekSheet> createState() => _PeekSheetState();
}

class _PeekSheetState extends ConsumerState<PeekSheet> {
  String log = '';
  List<RunInfo> runs = [];
  final _msg = TextEditingController();
  bool busy = false;
  String? note;
  bool noteOk = true;
  Timer? _timer;
  String? _taskId;

  @override
  void dispose() {
    _timer?.cancel();
    _msg.dispose();
    super.dispose();
  }

  void _watch(String? taskId) {
    if (taskId == _taskId) return;
    _taskId = taskId;
    _timer?.cancel();
    log = '';
    runs = [];
    if (taskId == null) return;
    _pull();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _pull());
  }

  Future<void> _pull() async {
    final id = _taskId;
    if (id == null) return;
    final res = await ref.read(officeProvider).backend.get('/api/hermes/tasks/${Uri.encodeComponent(id)}');
    // A dropped packet leaves the last known log on screen.
    if (!mounted || !res.ok || res.data == null || id != _taskId) return;
    setState(() {
      log = '${res.map['log'] ?? ''}';
      runs = res.list('runs').map(RunInfo.fromJson).toList();
    });
  }

  Future<void> _act(String action, String taskId) async {
    setState(() {
      busy = true;
      note = null;
    });
    final err = await ref.read(officeProvider).taskAction(taskId, {'action': action, 'message': _msg.text});
    if (!mounted) return;
    setState(() {
      busy = false;
      noteOk = err == null;
      note = err == null ? (action == 'steer' ? 'Arahan terkirim ke worker.' : 'Claim worker dilepas.') : 'Gagal: $err';
      if (err == null && action == 'steer') _msg.clear();
    });
    _pull();
  }

  Future<void> _openChat(String agent) async {
    final chat = ref.read(chatProvider);
    Navigator.pop(context);
    if (chat.engine.perAgentThreads) {
      final s = chat.sessions.where((x) => x.profile == agent).firstOrNull ?? ChatSessionInfo(id: agent, title: agent, profile: agent);
      await chat.open(s);
    } else if (chat.engine is LocalChatEngine) {
      final s = chat.sessions.where((x) => x.profile == agent).firstOrNull;
      if (s != null) {
        await chat.open(s);
      } else {
        await chat.newSession(profile: agent);
      }
    }
    if (mounted) toast(context, 'Buka tab Chat untuk melanjutkan percakapan dengan $agent');
  }

  @override
  Widget build(BuildContext context) {
    final office = ref.watch(officeProvider);
    final agent = widget.agentName != null
        ? office.agent(widget.agentName)
        : (widget.desk != null ? office.agentAtDesk(widget.desk!) : null);
    final task = office.task(agent?.currentTaskId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _watch(task?.id));
    });
    final deskLabel = (agent?.deskIndex ?? widget.desk) != null ? 'Meja ${(agent?.deskIndex ?? widget.desk)! + 1}' : 'Tanpa meja';

    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
      Row(children: [
        if (agent != null) AgentAvatar(agent.name, size: 44, status: agent.status) else const Icon(Icons.desk_outlined, size: 36),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$deskLabel · ${agent?.displayName ?? 'kosong'}', style: context.tt.titleMedium),
            if (agent != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  StatusPill(agentStatusLabel[agent.status] ?? agent.status, color: statusColor(context, agent.status)),
                  const SizedBox(width: 6),
                  StatusPill(agent.role),
                ]),
              ),
          ]),
        ),
        if (agent != null)
          IconButton(tooltip: 'Chat dengan ${agent.name}', onPressed: () => _openChat(agent.name), icon: const Icon(Icons.chat_bubble_outline)),
      ]),
      const SizedBox(height: 14),
      if (agent == null) Text('Tidak ada agent di meja ini.', style: context.tt.bodySmall),
      if (agent != null) ...[
        KeyValue('tugas', task?.title ?? '— tidak ada tugas aktif —'),
        if (task != null) ...[
          KeyValue('id', task.id, mono: true),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                showTaskDetail(context, task.id);
              },
              icon: const Icon(Icons.open_in_full, size: 16),
              label: const Text('Detail tugas'),
            ),
          ),
          const SizedBox(height: 4),
          Collapsible(
            label: 'Log terakhir',
            count: log.trim().isEmpty ? null : log.trim().split('\n').length,
            initiallyOpen: true,
            child: LogView(log, maxHeight: 280),
          ),
          Collapsible(
            label: 'Riwayat run',
            count: runs.length,
            child: runs.isEmpty
                ? Text('belum ada run', style: context.tt.bodySmall)
                : Column(children: [for (final r in runs.reversed.take(4)) RunTile(run: r)]),
          ),
          const SectionLabel('Arahkan / hentikan', padding: EdgeInsets.fromLTRB(0, 14, 0, 8)),
          TextField(
            controller: _msg,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'fokus ke test postgres saja'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: busy || _msg.text.trim().isEmpty ? null : () => _act('steer', task.id),
                icon: const Icon(Icons.near_me_outlined, size: 18),
                label: const Text('Steer'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: context.hc.destructive),
                onPressed: busy ? null : () => _act('cancel', task.id),
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: const Text('Hentikan'),
              ),
            ),
          ]),
          if (note != null) Padding(padding: const EdgeInsets.only(top: 10), child: NoteBanner(note!, ok: noteOk)),
        ],
      ],
    ]);
  }
}

class RunTile extends StatelessWidget {
  const RunTile({super.key, required this.run});
  final RunInfo run;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(border: Border.all(color: context.hc.strokeSoft), borderRadius: BorderRadius.circular(6)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            StatusPill(run.status, color: statusColor(context, run.status)),
            if (run.outcome != null) ...[const SizedBox(width: 6), Text(run.outcome!, style: context.tt.bodySmall)],
            const Spacer(),
            if (run.profile != null) Text(run.profile!, style: context.tt.bodySmall),
          ]),
          if (run.summary != null && run.summary!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(run.summary!, style: context.tt.bodySmall)),
          if (run.error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(run.error!, style: TextStyle(color: context.hc.destructive, fontSize: 12.5))),
        ]),
      );
}
