// Every approval the PC's agent is waiting on (tool calls that need a yes).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/neovarch_mobile_theme.dart';
import '../../ui/widgets/common.dart';
import '../remote_controller.dart';
import 'nv_widgets.dart';

class RemoteApprovalsScreen extends ConsumerWidget {
  const RemoteApprovalsScreen({super.key, required this.onOpenChat});
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(remoteProvider);
    final list = r.approvals;
    return Scaffold(
      body: Column(children: [
        NvHeader(
          kicker: 'izin · ${r.desktop?.name ?? 'pc'}',
          title: 'Persetujuan',
          status: Text(list.isEmpty ? 'tidak ada yang menunggu' : '${list.length} aksi menunggu keputusanmu',
              style: NV.monoLabel(size: 10, color: list.isEmpty ? NV.muted : NV.red).copyWith(letterSpacing: 0.4)),
        ),
        Expanded(
          child: list.isEmpty
              ? ListView(padding: const EdgeInsets.only(top: 4), children: const [
                  NvEmpty(
                    kicker: 'aman',
                    title: 'Tidak ada yang menunggu',
                    body: 'Saat agen di PC ingin menjalankan aksi berisiko (perintah terminal, hapus berkas, dan sejenisnya), permintaannya muncul di sini dan sebagai notifikasi.',
                  ),
                ])
              : ListView(padding: EdgeInsets.only(top: 4, bottom: 16 + MediaQuery.paddingOf(context).bottom), children: [
                  for (final a in list) ...[
                    NvSection('${a.toolName ?? 'alat'} · ${relTime(a.receivedAt.toIso8601String())}',
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10)),
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
                            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
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
        ),
      ]),
    );
  }
}
