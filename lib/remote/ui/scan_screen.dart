// Camera QR scanner for the desktop's pairing code (mobile_scanner).
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../theme/app_theme.dart';
import '../../ui/widgets/brand.dart';
import '../pairing.dart';

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
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text('Pindai QR dari PC', style: context.tt.titleMedium)),
      body: Stack(children: [
        Positioned.fill(
          child: MobileScanner(
            controller: _ctl,
            onDetect: _onDetect,
            errorBuilder: (context, e) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  e.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'Izin kamera ditolak. Izinkan kamera di Pengaturan, atau masukkan alamat & token secara manual.'
                      : 'Kamera tidak tersedia: ${e.errorDetails?.message ?? e.errorCode.name}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: brandPaper),
                ),
              ),
            ),
          ),
        ),
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(border: Border.all(color: brandPaper, width: 2)),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 40,
          child: Text(
            _hint ?? 'Di PC: Neovarch Desktop → Remote / Perangkat → tampilkan QR pemasangan.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: brandPaper, fontSize: 14),
          ),
        ),
      ]),
    );
  }
}
