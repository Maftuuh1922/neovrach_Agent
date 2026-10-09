// Profil → Hey Neo: the opt-in switch for the wake word (lib/remote/wake_word.dart).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/neovarch_mobile_theme.dart';
import '../wake_word.dart';

class WakeWordPanel extends ConsumerStatefulWidget {
  const WakeWordPanel({super.key});
  @override
  ConsumerState<WakeWordPanel> createState() => _WakeWordPanelState();
}

class _WakeWordPanelState extends ConsumerState<WakeWordPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(wakeWordProvider).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = ref.watch(wakeWordProvider);
    final s = w.status;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Panggil dengan "Hey Neo"', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: NV.text)),
            const SizedBox(height: 2),
            Text(s.label, key: const ValueKey('wake-state'), style: TextStyle(fontSize: 12.5, color: NV.muted)),
          ]),
        ),
        Switch.adaptive(
          key: const ValueKey('wake-switch'),
          value: s.enabled,
          activeTrackColor: NV.red,
          onChanged: w.busy ? null : (v) => w.setEnabled(v),
        ),
      ]),
      const SizedBox(height: 8),
      Text(
        'Opsional. Mikrofon didengarkan di HP (tanpa internet) hanya untuk kata "Hey Neo", lalu dikte Chat terbuka. '
        'Model suara ±40 MB diunduh saat pertama dinyalakan. Ada notifikasi tetap selama aktif dan baterai sedikit lebih boros. '
        'Setelah HP dinyalakan ulang, ketuk notifikasinya untuk menyalakan lagi.',
        style: TextStyle(fontSize: 12.5, height: 1.35, color: NV.muted),
      ),
      if (w.error != null) ...[
        const SizedBox(height: 8),
        Text(w.error!, key: const ValueKey('wake-error'), style: TextStyle(fontSize: 12.5, color: NV.redInk)),
      ],
    ]);
  }
}
