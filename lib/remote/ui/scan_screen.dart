// Camera QR scanner for the desktop's pairing code (mobile_scanner).
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../theme/neovarch_mobile_theme.dart';
import '../pairing.dart';
import 'nv_widgets.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _ctl = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  String? _hint;

  void _onDetect(BarcodeCapture c) {
    if (_done) return;
    for (final b in c.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      if (GatewayPairing.parse(raw) == null) {
        setState(() => _hint = 'Bukan QR pemasangan Neovarch.');
        continue;
      }
      _done = true;
      Navigator.pop(context, raw);
      return;
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NV.bg,
      body: Stack(children: [
        Positioned.fill(
          child: MobileScanner(
            controller: _ctl,
            onDetect: _onDetect,
            errorBuilder: (context, e) => Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  e.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'Izin kamera ditolak. Izinkan kamera di Pengaturan, atau masukkan alamat & token secara manual.'
                      : 'Kamera tidak tersedia: ${e.errorDetails?.message ?? e.errorCode.name}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: NV.text, fontSize: 14, height: 1.5),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: Container(
            color: NV.bg.withValues(alpha: 0.86),
            child: NvHeader(kicker: 'pemasangan', title: 'Pindai QR dari PC', onBack: () => Navigator.of(context).maybePop()),
          ),
        ),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: NV.red, width: 2),
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 28 + MediaQuery.paddingOf(context).bottom,
          child: NvPanel(
            color: NV.bg.withValues(alpha: 0.92),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_hint != null ? 'QR DITOLAK' : 'LANGKAH', style: NV.monoLabel(color: NV.redInk)),
              const SizedBox(height: 6),
              Text(
                _hint ?? 'Di PC: Neovarch Desktop → Remote / Perangkat → tampilkan QR pemasangan.',
                style: TextStyle(color: NV.text, fontSize: 14, height: 1.45),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
