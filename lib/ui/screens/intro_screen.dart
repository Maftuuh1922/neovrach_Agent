// First-launch intro carousel, flat print style: a solid red #C8101A page,
// a framed plate of duotone red/bone halftone art (original), huge thin
// condensed bone headlines, mono meta captions and a star-grid frame. No
// gradients, scrims or glows. Shown once before the connection/provider
// onboarding; can be replayed from Lainnya → Tentang.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_controller.dart';
import '../widgets/brand.dart';
import '../widgets/motion.dart';

class _Slide {
  final String art, meta, headline, caption;
  const _Slide(this.art, this.meta, this.headline, this.caption);
}

const _slides = [
  _Slide('assets/intro/eva_hero.webp', '[ 01 ]  pembuka · neovarch', 'NEOVARCH\nAGENT',
      'Agen AI milikmu sendiri — mandiri, terbuka, dan berjalan langsung di ponsel. Dibangun di atas Hermes Agent.'),
  _Slide('assets/intro/eva_office.webp', '[ 02 ]  kantor agen', 'KANTOR\nAGEN',
      'Tim agen bekerja di kantor isometrik: Kanban, rapat antar-agen, cron — kamu tinggal memantau dan menyetujui.'),
  _Slide('assets/intro/eva_remote.webp', '[ 03 ]  pc = otak · hp = remote', 'OTAK DI PC,\nREMOTE\nDI SAKU',
      'Jalankan agen langsung di ponsel, atau sambungkan ke gateway hermes serve di PC/VPS dan kendalikan dari sini.'),
  _Slide('assets/intro/eva_pairing.webp', '[ 04 ]  pairing · mulai', 'MULAI',
      'Pasangkan gateway atau pilih penyedia model, lalu beri izin perangkat. Semua kunci tersimpan terenkripsi di perangkat.'),
];

class IntroScreen extends ConsumerStatefulWidget {
  const IntroScreen({super.key, this.replay = false, this.initialPage = 0});
  /// Opened again from Settings: pop instead of continuing to onboarding.
  final bool replay;
  final int initialPage;
  @override
  ConsumerState<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends ConsumerState<IntroScreen> with TickerProviderStateMixin {
  /// Opening sequence: ink-reveal of the logo card, halo, typed wordmark.
  late final AnimationController _boot = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400));
  late final AnimationController _halo = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
  bool _bootStarted = false;
  late final PageController _pc = PageController(initialPage: widget.initialPage.clamp(0, _slides.length - 1));
  late int _index = widget.initialPage.clamp(0, _slides.length - 1);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final s in _slides) {
      precacheImage(AssetImage(s.art), context);
    }
    precacheImage(const AssetImage('assets/brand/logo_card.png'), context);
    if (!_bootStarted) {
      _bootStarted = true;
      if (reduceMotion(context) || widget.initialPage > 0) {
        _boot.value = 1;
        _halo.stop();
      } else {
        _boot.forward();
      }
    }
  }

  @override
  void dispose() {
    _boot.dispose();
    _halo.dispose();
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
    _pc.nextPage(duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _slides.length - 1;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: brandRed,
        systemNavigationBarColor: brandRed,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: brandBg,
        body: AnimatedBuilder(
          animation: _boot,
          builder: (context, carousel) {
            final b = _boot.value;
            final show = Curves.easeOut.transform(((b - 0.78) / 0.22).clamp(0.0, 1.0));
            return Stack(children: [
              Opacity(opacity: show, child: carousel),
              if (b < 1)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => _boot.value = 1,
                    child: Opacity(opacity: 1 - show, child: _BootSequence(t: b, halo: _halo)),
                  ),
                ),
            ]);
          },
          child: Stack(children: [
          PageView.builder(
            controller: _pc,
            itemCount: _slides.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => AnimatedBuilder(
              animation: _pc,
              builder: (context, _) {
                final page = _pc.hasClients && _pc.position.haveDimensions ? (_pc.page ?? _index.toDouble()) : _index.toDouble();
                return _SlideView(slide: _slides[i], offset: page - i);
              },
            ),
          ),
          // thin plate frame with star-grid strip
          Positioned.fill(
            child: IgnorePointer(
              child: SafeArea(
                child: AnimatedBuilder(
                  animation: _boot,
                  builder: (context, _) => CustomPaint(
                    painter: StarFramePainter(
                      color: brandPaper.withValues(alpha: 0.8),
                      inset: 10,
                      cell: 34,
                      progress: ((_boot.value - 0.7) / 0.3).clamp(0.0, 1.0),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // top meta bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 58, 14, 0),
              child: Row(children: [
                const BrandBadge(height: 34, color: brandPaper),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    MetaLabel('Neovarch Agent', color: brandPaper, size: 10.5),
                    MetaLabel('NeovarchLabs · v1.1', color: Color(0xFFF0CFC9), size: 9.5),
                  ]),
                ),
                MetaLabel('${(_index + 1).toString().padLeft(2, '0')} / ${_slides.length.toString().padLeft(2, '0')}', color: brandPaper, size: 10.5),
                const SizedBox(width: 4),
                if (!last)
                  TextButton(
                    onPressed: _done,
                    style: TextButton.styleFrom(foregroundColor: brandPaper, shape: const RoundedRectangleBorder()),
                    child: const MetaLabel('Lewati', color: brandPaper, size: 11),
                  )
                else
                  const SizedBox(width: 12),
              ]),
            ),
          ),
          // bottom controls
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 0, 22, 26),
                child: Row(children: [
                  for (var i = 0; i < _slides.length; i++)
                    GestureDetector(
                      onTap: () => _pc.animateToPage(i, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.only(right: 6),
                        width: i == _index ? 28 : 12,
                        height: i == _index ? 3 : 1.5,
                        color: i == _index ? brandPaper : brandPaper.withValues(alpha: 0.45),
                      ),
                    ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: _next,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: last ? brandRed : brandPaper,
                      backgroundColor: last ? brandPaper : brandRed,
                      side: const BorderSide(color: brandPaper),
                      shape: const RoundedRectangleBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                    ),
                    child: Text(last ? 'MULAI  →' : 'LANJUT  →',
                        style: const TextStyle(fontFamily: 'IBMPlexMono', fontWeight: FontWeight.w500, letterSpacing: 1.4, fontSize: 13)),
                  ),
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

/// The opening: the Neovarch card is inked in from top to bottom, the halo
/// lights up and orbits, the wordmark types itself, then everything hands
/// over to the carousel.
class _BootSequence extends StatelessWidget {
  const _BootSequence({required this.t, required this.halo});
  final double t;
  final Animation<double> halo;
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final cardH = math.min(size.height * 0.56, size.width * 1.25);
    final cardW = cardH * LogoCard.ratio;
    double seg(double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
    final ink = Curves.easeInOutCubic.transform(seg(0.05, 0.5));
    final haloIn = Curves.easeOutBack.transform(seg(0.42, 0.62));
    const word = 'NEOVARCHAGENT';
    final typed = (word.length * seg(0.5, 0.74)).floor();
    final lift = Curves.easeInCubic.transform(seg(0.78, 1.0));
    return ColoredBox(
      color: brandBg,
      child: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: StarFramePainter(color: brandPaper.withValues(alpha: 0.8), inset: 18, cell: 34, progress: seg(0.0, 0.45)))),
        Positioned.fill(child: CustomPaint(painter: HalftonePainter(color: brandPaper.withValues(alpha: 0.16 * ink), focus: const Offset(0.5, 0.42), reach: 0.62, cell: 9))),
        Center(
          child: Transform.translate(
            offset: Offset(0, -lift * 40),
            child: Transform.scale(
              scale: 0.92 + 0.08 * ink - 0.1 * lift,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: cardW,
                  height: cardH,
                  child: Stack(clipBehavior: Clip.none, children: [
                    // print reveal: the card is "pulled" top-down behind a hard edge
                    ClipRect(clipper: _TopReveal(ink.clamp(0.0, 1.0)), child: LogoCard(height: cardH)),
                    if (ink > 0 && ink < 1)
                      Positioned(left: 0, right: 0, top: cardH * ink - 1, child: Container(height: 2, color: brandPaper)),
                    // halo over the N of the wordmark
                    if (haloIn > 0)
                      Positioned(
                        left: cardW * 0.035,
                        top: cardH * 0.205,
                        width: cardW * 0.3,
                        height: cardW * 0.075,
                        child: Opacity(
                          opacity: haloIn.clamp(0.0, 1.0),
                          child: AnimatedBuilder(
                            animation: halo,
                            builder: (context, _) => CustomPaint(painter: HaloPainter(t: halo.value, color: brandInk, glow: haloIn)),
                          ),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 22,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(word.substring(0, typed),
                        style: const TextStyle(fontFamily: 'IBMPlexMono', fontSize: 15, letterSpacing: 4, color: brandPaper, fontWeight: FontWeight.w500)),
                    if (t < 0.8) const BlinkingCaret(height: 16),
                  ]),
                ),
                const SizedBox(height: 6),
                Opacity(
                  opacity: seg(0.66, 0.76),
                  child: const MetaLabel('agen ai · android & iphone · v1.1', color: Color(0xFFF0CFC9), size: 10),
                ),
              ]),
            ),
          ),
        ),
        Positioned(
          right: 22,
          bottom: 28 + MediaQuery.paddingOf(context).bottom,
          child: Opacity(opacity: seg(0.2, 0.4) * 0.8, child: const MetaLabel('ketuk untuk lewati', color: brandPaper, size: 9.5)),
        ),
      ]),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide, required this.offset});
  final _Slide slide;
  final double offset; // 0 = centred, ±1 = one page away
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final o = offset.clamp(-1.0, 1.0);
    final fade = (1 - o.abs() * 0.9).clamp(0.0, 1.0);
    final headSize = math.min(size.width * 0.2, 110.0);
    final plateTop = pad.top + 104;
    final plateH = math.max(160.0, (size.height - plateTop - pad.bottom) * 0.5);
    return ClipRect(
      child: ColoredBox(
        color: brandRed,
        child: Stack(fit: StackFit.expand, children: [
          // framed art plate; the art drifts at half speed (parallax)
          Positioned(
            left: 22,
            right: 22,
            top: plateTop,
            height: plateH,
            child: Container(
              decoration: BoxDecoration(color: brandRed, border: Border.all(color: brandPaper, width: 1)),
              padding: const EdgeInsets.all(5),
              child: ClipRect(
                child: Transform.translate(
                  offset: Offset(o * size.width * 0.5, 0),
                  child: Opacity(
                    opacity: fade,
                    child: Image.asset(slide.art, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 26,
            right: 22,
            top: plateTop + plateH + 14,
            bottom: 96 + pad.bottom,
            child: Transform.translate(
              offset: Offset(o * -size.width * 0.18, o.abs() * 30),
              child: Opacity(
                opacity: fade,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  MetaLabel(slide.meta, color: brandPaper, size: 10.5),
                  const SizedBox(height: 8),
                  Container(height: 1, color: brandPaper),
                  const SizedBox(height: 6),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topLeft,
                      child: Text(
                        slide.headline,
                        style: TextStyle(
                          fontFamily: 'BigShoulders',
                          fontWeight: FontWeight.w300,
                          fontSize: headSize,
                          height: 0.88,
                          letterSpacing: -0.5,
                          color: brandPaper,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    slide.caption,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'IBMPlexMono', fontSize: 12, height: 1.45, color: brandPaper, letterSpacing: 0.1),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Clips to the top [f] fraction of the child (hard-edged print reveal).
class _TopReveal extends CustomClipper<Rect> {
  _TopReveal(this.f);
  final double f;
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width, size.height * f);
  @override
  bool shouldReclip(_TopReveal old) => old.f != f;
}
