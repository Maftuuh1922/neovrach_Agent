// Every approval the PC's agent is waiting on (tool calls that need a yes).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../ui/screens/chat/message_widgets.dart';
import '../../ui/widgets/common.dart';
import '../remote_controller.dart';

class RemoteApprovalsScreen extends ConsumerWidget {
  const RemoteApprovalsScreen({super.key, required this.onOpenChat});
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(remoteProvider);
    final list = r.approvals;
    return Scaffold(
      appBar: AppBar(title: Text('Persetujuan', style: context.tt.titleMedium)),
      body: list.isEmpty
          ? const EmptyState(
              icon: Icons.verified_user_outlined,
              title: 'Tidak ada yang menunggu',
              body: 'Saat agen di PC ingin menjalankan aksi berisiko (perintah terminal, hapus berkas, dsb.), permintaannya muncul di sini dan sebagai notifikasi.',
            )
          : ListView(padding: const EdgeInsets.only(top: 8, bottom: 24), children: [
              for (final a in list) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Row(children: [
                    Expanded(child: MetaLabel('${a.toolName ?? 'alat'} · ${r.sessionTitle(a.sessionId)}')),
                    Text(relTime(a.receivedAt.toIso8601String()), style: context.tt.bodySmall),
                  ]),
                ),
                ApprovalCard(
                  command: a.command,
                  description: a.description,
                  choices: a.choices,
                  onChoice: (c) async {
                    final err = await r.respond(a, c);
                    if (context.mounted) toast(context, err ?? (c == 'deny' ? 'Ditolak' : 'Disetujui'));
                  },
                ),
                if (a.sessionId.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: TextButton.icon(
                        icon: const Icon(Icons.forum_outlined, size: 16),
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
            ]),
    );
  }
}
