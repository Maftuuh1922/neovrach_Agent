// First launch of the phone remote: three short slides on the Neovarch dark
// red system (rounded art plates with the dithered red art, serif headlines,
// mono kickers). Replayable from the PC tab. No gradients, no shadows.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_controller.dart' show settingsProvider;
import '../../theme/neovarch_mobile_theme.dart';
import '../../ui/widgets/brand.dart' show Wordmark;
import '../../ui/widgets/motion.dart' show reduceMotion;

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

class RemoteIntroScreen extends ConsumerStatefulWidget {
  const RemoteIntroScreen({super.key, this.replay = false, this.initialPage = 0});
  final bool replay;
  final int initialPage;
  @override
  ConsumerState<RemoteIntroScreen> createState() => _RemoteIntroScreenState();
}

class _RemoteIntroScreenState extends ConsumerState<RemoteIntroScreen> {
  late final PageController _pc = PageController(initialPage: widget.initialPage.clamp(0, _slides.length - 1));
  late int _index = widget.initialPage.clamp(0, _slides.length - 1);

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
    if (_index >= _slides.length - 1) return _done();
    if (reduceMotion(context)) {
      _pc.jumpToPage(_index + 1);
    } else {
      _pc.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final last = _index == _slides.length - 1;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
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
                Text('0${_index + 1} / 0${_slides.length}', style: NV.monoLabel(size: 10, color: NV.muted)),
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
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _SlideView(slide: _slides[i], number: i + 1),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(children: [
                // Progress: rounded segments, the current one red and long.
                for (var i = 0; i < _slides.length; i++)
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
                  onPressed: _next,
                  style: FilledButton.styleFrom(minimumSize: const Size(148, 50)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(last ? (widget.replay ? 'Selesai' : 'Hubungkan PC') : 'Lanjut'),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, size: 18),
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
                  Image.asset(slide.art, fit: BoxFit.cover, alignment: slide.align, filterQuality: FilterQuality.medium),
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
              Text('// ${slide.kicker.toUpperCase()}', style: NV.monoLabel(color: NV.red)),
              const SizedBox(height: 10),
              Text(slide.title, style: NV.display(size: 40)),
              const SizedBox(height: 12),
              Text(slide.body, style: TextStyle(fontSize: 14.5, height: 1.5, color: NV.muted)),
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
                      Text(p, style: TextStyle(fontSize: 12.5, color: NV.text)),
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
