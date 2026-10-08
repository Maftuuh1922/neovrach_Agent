// First launch of the phone remote: three short slides plus a "Pilih tema"
// step (accent presets / hue / hex, Gelap·Terang·Sistem, applied live).
// Everything follows the current accent and brightness; the red slide art is
// recoloured to the accent (unchanged in Merah). Replayable from the PC tab.
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_controller.dart' show settingsProvider;
import '../../theme/neovarch_mobile_theme.dart';
import '../../ui/widgets/brand.dart' show Wordmark;
import '../../ui/widgets/motion.dart' show reduceMotion;
import '../appearance.dart' show appearanceProvider;
import 'remote_background.dart' show NvAccentArt;
import 'remote_pc_screen.dart' show AppearancePanel;

class _Slide {
  const _Slide(this.art, this.align, this.kicker, this.title, this.body, this.points);
  final String art;
  final Alignment align;
  final String kicker;
  final String title;
  final String body;
  final List<String> points;
}

const _slides = [
  _Slide('assets/art/feat-remote.webp', Alignment(0.35, 0), 'pc = otak · hp = remote', 'Agen di PC,\nremote di saku.',
      'Neovarch berjalan di aplikasi desktop. HP ini hanya remote: kirim perintah dan lihat hasilnya.',
      ['Tanpa kunci API di HP', 'Satu PC atau beberapa']),
  _Slide('assets/art/feat-automation.webp', Alignment(0.2, 0), 'tugas · kanban', 'Pantau kerja\npara agen.',
      'Papan tugas di PC tampil di sini: siapa mengerjakan apa, sampai mana, dan apa yang menunggu review.',
      ['Pindahkan tugas', 'Kirim arahan']),
  _Slide('assets/art/portal-banner.webp', Alignment(0.6, 0), 'persetujuan · aman', 'Kamu yang\nmemutuskan.',
      'Perintah berisiko berhenti dulu sampai kamu setujui dari HP. Token pemasangan disimpan terenkripsi.',
      ['Izinkan sekali', 'Tolak kapan saja']),
];

/// Slides plus the theme step (last page).
const introPageCount = 4;
const introThemePage = 3;

class RemoteIntroScreen extends ConsumerStatefulWidget {
  const RemoteIntroScreen({super.key, this.replay = false, this.initialPage = 0});
  final bool replay;
  final int initialPage;
  @override
  ConsumerState<RemoteIntroScreen> createState() => _RemoteIntroScreenState();
}

class _RemoteIntroScreenState extends ConsumerState<RemoteIntroScreen> {
  late final PageController _pc = PageController(initialPage: widget.initialPage.clamp(0, introPageCount - 1));
  late int _index = widget.initialPage.clamp(0, introPageCount - 1);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final s in _slides) {
      precacheImage(AssetImage(s.art), context);
    }
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _done() {
    final s = ref.read(settingsProvider);
    if (!s.introSeen) s.update((x) => x.introSeen = true);
    if (widget.replay && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  void _next() {
    if (_index >= introPageCount - 1) return _done();
    if (reduceMotion(context)) {
      _pc.jumpToPage(_index + 1);
    } else {
      _pc.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final last = _index == introPageCount - 1;
    ref.watch(appearanceProvider); // repaint on theme changes (live preview)
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (NV.palette.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: NV.bg,
        systemNavigationBarDividerColor: NV.bg,
      ),
      child: Scaffold(
        backgroundColor: NV.bg,
        body: Padding(
          padding: EdgeInsets.fromLTRB(0, pad.top + 10, 0, pad.bottom + 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Top rail: wordmark, slide counter, skip.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 6),
              child: Row(children: [
                Wordmark(height: 22, color: NV.text, haloColor: NV.red),
                const Spacer(),
                Text('${_index + 1} / $introPageCount', style: NV.monoLabel(size: 10, color: NV.muted)),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: _done,
                  style: TextButton.styleFrom(foregroundColor: NV.muted),
                  child: Text(widget.replay ? 'Tutup' : 'Lewati'),
                ),
              ]),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pc,
                itemCount: introPageCount,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => i == introThemePage ? const _ThemeStep() : _SlideView(slide: _slides[i], number: i + 1),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(children: [
                // Progress: rounded segments, the current one in the accent and long.
                for (var i = 0; i < introPageCount; i++)
                  AnimatedContainer(
                    duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 220),
                    margin: const EdgeInsets.only(right: 6),
                    width: i == _index ? 28 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index ? NV.red : NV.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                const Spacer(),
                FilledButton(
                  key: const ValueKey('intro-next'),
                  onPressed: _next,
                  style: FilledButton.styleFrom(minimumSize: const Size(148, 50)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(last ? (widget.replay ? 'Selesai' : 'Hubungkan PC') : 'Lanjut'),
                    const SizedBox(width: 8),
                    const Icon(CupertinoIcons.arrow_right, size: 18),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide, required this.number});
  final _Slide slide;
  final int number;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      // The plate takes what is left after the copy; never below 160px.
      final plateH = (c.maxHeight - 300).clamp(160.0, 420.0);
      return SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          SizedBox(
            height: plateH,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(NV.rCard),
              child: Container(
                foregroundDecoration: BoxDecoration(borderRadius: BorderRadius.circular(NV.rCard), border: Border.all(color: NV.border)),
                child: Stack(fit: StackFit.expand, children: [
                  NvAccentArt(slide.art, alignment: slide.align),
                  // Big outlined plate number, bottom-left, print style.
                  Positioned(
                    left: 14,
                    bottom: 6,
                    child: Text('0$number', style: NV.display(size: 64, color: NV.text)),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(slide.kicker.toUpperCase(), style: NV.monoLabel(color: NV.red)),
              const SizedBox(height: 10),
              Text(slide.title, style: NV.display(size: 34)),
              const SizedBox(height: 12),
              Text(slide.body, style: TextStyle(fontSize: 17, height: 1.4, letterSpacing: NV.tracking(17), color: NV.muted)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in slide.points)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: NV.surface,
                      borderRadius: BorderRadius.circular(NV.rCtl),
                      border: Border.all(color: NV.border),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: NV.red, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text(p, style: TextStyle(fontSize: 13, color: NV.text)),
                    ]),
                  ),
              ]),
            ]),
          ),
        ]),
      );
    });
  }
}

/// "Pilih tema": the same picker as PC → Tampilan, without "Ikuti tema PC"
/// (no PC yet). Any pick is a local override; untouched, the phone keeps
/// following the PC's theme once paired.
class _ThemeStep extends ConsumerWidget {
  const _ThemeStep();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = ref.watch(appearanceProvider);
    return ListView(
      key: const ValueKey('intro-theme-step'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TAMPILAN · TEMA', style: NV.monoLabel(color: NV.red)),
            const SizedBox(height: 10),
            Text('Pilih temamu.', style: NV.display(size: 34)),
            const SizedBox(height: 10),
            Text(
              look.followPc
                  ? 'Pilih warna dan mode. Kalau dilewati, HP mengikuti tema PC setelah terhubung.'
                  : 'Tema khusus HP ini dipakai, juga setelah terhubung. Ubah kapan saja di PC → Tampilan.',
              key: const ValueKey('intro-theme-note'),
              style: TextStyle(fontSize: 15, height: 1.4, letterSpacing: NV.tracking(15), color: NV.muted),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        const AppearancePanel(showFollowPc: false, showBackground: false, margin: EdgeInsets.zero),
      ],
    );
  }
}
