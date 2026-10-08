// Every approval the PC's agent is waiting on (tool calls that need a yes).
// 1.4.2: no longer a tab — Chat shows a pinned "N menunggu persetujuan" chip
// that opens this list as a sheet ([showApprovalsSheet]); approvals of the
// open session also sit inline in the chat above the composer.
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/neovarch_mobile_theme.dart';
import '../../ui/widgets/common.dart';
import '../remote_controller.dart';
import 'nv_widgets.dart';

/// Opens the full pending-approvals list (the old Setujui tab) as a sheet.
/// [onOpenChat] runs after "Lihat percakapan" switched the chat session.
Future<void> showApprovalsSheet(BuildContext context, {VoidCallback? onOpenChat}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.35,
        builder: (ctx, sc) => ApprovalsList(
          key: const ValueKey('approvals-sheet'),
          controller: sc,
          onOpenChat: () {
            Navigator.pop(ctx);
            onOpenChat?.call();
          },
        ),
      ),
    );

class ApprovalsList extends ConsumerWidget {
  const ApprovalsList({super.key, required this.onOpenChat, this.controller});
  final VoidCallback onOpenChat;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(remoteProvider);
    final list = r.approvals;
    return ListView(controller: controller, padding: EdgeInsets.only(bottom: 16 + MediaQuery.paddingOf(context).bottom), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
        child: NvSheetTitle(kicker: 'izin · ${r.desktop?.name ?? 'pc'}', title: 'Persetujuan'),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Text(list.isEmpty ? 'tidak ada yang menunggu' : '${list.length} aksi menunggu keputusanmu',
            style: NV.monoLabel(size: 10, color: list.isEmpty ? NV.muted : NV.red).copyWith(letterSpacing: 0.4)),
      ),
      if (list.isEmpty)
        const NvEmpty(
          kicker: 'aman',
          title: 'Tidak ada yang menunggu',
          body: 'Saat agen di PC ingin menjalankan aksi berisiko (perintah terminal, hapus berkas, dan sejenisnya), permintaannya muncul di chat dan sebagai notifikasi.',
        )
      else
        for (final a in list) ...[
          NvSection('${a.toolName ?? 'alat'} · ${relTime(a.receivedAt.toIso8601String())}', padding: const EdgeInsets.fromLTRB(20, 10, 20, 10)),
          NvApprovalCard(
            command: a.command,
            description: a.description,
            choices: a.choices,
            origin: r.sessionTitle(a.sessionId),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            onChoice: (c) async {
              final err = await r.respond(a, c);
              if (context.mounted) toast(context, err ?? (c == 'deny' ? 'Ditolak' : 'Disetujui'));
            },
          ),
          if (a.sessionId.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: TextButton.icon(
                  icon: const Icon(CupertinoIcons.chat_bubble, size: 16),
                  label: const Text('Lihat percakapan'),
                  onPressed: () async {
                    if (a.sessionId != r.runtimeId) {
                      final s = r.sessions.where((s) => s.title == r.sessionTitle(a.sessionId)).firstOrNull;
                      if (s != null) await r.openSession(s.id);
                    }
                    onOpenChat();
                  },
                ),
              ),
            ),
        ],
    ]);
  }
}
