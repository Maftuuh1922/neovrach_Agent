// "Bagikan profil": a shareable liquid-glass profile card. The card is frosted
// glass (blur over the user's custom background or an accent glow, specular rim
// and a moving sheen) with avatar, name/@login, bio, the 365-day heatmap, top
// stack chips, the "lagi ngoding" status and a small Neovarch mark. It exports
// as a PNG: story 1080×1920 or square 1080×1080 (rendered at 3× from a
// 360-wide logical card), then goes to the Android share sheet or the gallery.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/device_tools.dart' show deviceCall;
import '../../theme/neovarch_mobile_theme.dart';
import '../../ui/widgets/common.dart' show toast;
import '../social_models.dart';
import 'nv_widgets.dart';
import 'remote_background.dart' show NvAppBackground;
import 'remote_social_screen.dart' show NvAvatar, SocialHeatmapView;
import 'tech_logo.dart';

enum ShareCardFormat { story, square }

extension ShareCardFormatX on ShareCardFormat {
  /// Logical size; the export renders at [kShareCardPixelRatio].
  Size get logicalSize => this == ShareCardFormat.story ? const Size(360, 640) : const Size(360, 360);
  Size get pixelSize => logicalSize * kShareCardPixelRatio;
  String get label => this == ShareCardFormat.story ? 'Story 9:16' : 'Kotak 1:1';
}

const double kShareCardPixelRatio = 3;

/// The card as it is exported. [sheen] 0..1 moves the light band across the
/// glass; [background] overrides the app background (tests / screenshots).
class ProfileShareCard extends StatelessWidget {
  const ProfileShareCard({super.key, required this.profile, this.format = ShareCardFormat.story, this.sheen = 0.32, this.background, this.avatar});
  final SocialProfile profile;
  final ShareCardFormat format;
  final double sheen;
  final Widget? background;
  final ImageProvider? avatar;

  @override
  Widget build(BuildContext context) {
    final size = format.logicalSize;
    final story = format == ShareCardFormat.story;
    final radius = BorderRadius.circular(story ? 30 : 26);
    return SizedBox.fromSize(
      size: size,
      // self-contained text styling: the card is also rendered outside a Scaffold
      child: Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle(
          style: TextStyle(fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily, fontSize: 14, color: NV.text),
          child: ClipRect(
        child: Stack(fit: StackFit.expand, children: [
          ColoredBox(color: NV.bg),
          _AccentGlow(story: story),
          background ?? const NvAppBackground(),
          Padding(
            padding: story ? const EdgeInsets.fromLTRB(22, 74, 22, 74) : const EdgeInsets.all(16),
            child: _GlassPanel(
              radius: radius,
              sheen: sheen,
              child: Padding(
                padding: story ? const EdgeInsets.fromLTRB(22, 26, 22, 22) : const EdgeInsets.fromLTRB(18, 18, 18, 14),
                child: _CardContent(profile: profile, story: story, avatar: avatar),
              ),
            ),
          ),
          if (story)
            Positioned(
              left: 0,
              right: 0,
              bottom: 32,
              child: Center(
                child: Text('neovarch agent · profil', style: NV.monoLabel(size: 9, color: NV.text.withValues(alpha: 0.55))),
              ),
            ),
        ]),
      ),
        ),
      ),
    );
  }
}

/// Soft accent light behind the glass when there is no custom background.
class _AccentGlow extends StatelessWidget {
  const _AccentGlow({required this.story});
  final bool story;
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GlowPainter(NV.red, NV.bg, NV.palette.dark));
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.accent, this.bg, this.dark);
  final Color accent, bg;
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    void blob(Offset c, double r, double a) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [accent.withValues(alpha: a), accent.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    final w = size.width, h = size.height;
    blob(Offset(w * 0.15, h * 0.18), w * 0.75, dark ? 0.55 : 0.35);
    blob(Offset(w * 0.95, h * 0.62), w * 0.70, dark ? 0.38 : 0.25);
    blob(Offset(w * 0.30, h * 0.98), w * 0.55, dark ? 0.30 : 0.20);
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.accent != accent || old.bg != bg || old.dark != dark;
}

/// Frosted glass: backdrop blur + saturation, flat accent-tinted fill, the
/// shared specular rim and a diagonal sheen band at [sheen].
class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.radius, required this.sheen, required this.child});
  final BorderRadius radius;
  final double sheen;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final dark = NV.palette.dark;
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.compose(
          outer: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          inner: ColorFilter.matrix(_saturation(1.6)),
        ),
        child: CustomPaint(
          foregroundPainter: _SheenPainter(t: sheen, radius: radius, strength: dark ? 0.16 : 0.32),
          child: Container(
            key: const ValueKey('share-glass'),
            decoration: BoxDecoration(
              borderRadius: radius,
              color: Color.lerp(NV.surface, NV.red, dark ? 0.10 : 0.05)!.withValues(alpha: dark ? 0.42 : 0.55),
            ),
            foregroundDecoration: const BoxDecoration(),
            child: CustomPaint(
              foregroundPainter: NvGlassRimPainter(borderRadius: radius, rim: NV.glassRim, chroma: true, strength: 1.4),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  static List<double> _saturation(double s) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final a = 1 - s;
    return [a * r + s, a * g, a * b, 0, 0, a * r, a * g + s, a * b, 0, 0, a * r, a * g, a * b + s, 0, 0, 0, 0, 0, 1, 0];
  }
}

class _SheenPainter extends CustomPainter {
  _SheenPainter({required this.t, required this.radius, required this.strength});
  final double t;
  final BorderRadius radius;
  final double strength;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(radius.toRRect(rect));
    // a soft white band travelling from top-left to bottom-right
    final d = size.width + size.height;
    final x = -size.height + d * t;
    final band = Path()
      ..moveTo(x, 0)
      ..lineTo(x + size.width * 0.35, 0)
      ..lineTo(x + size.width * 0.35 - size.height, size.height)
      ..lineTo(x - size.height, size.height)
      ..close();
    canvas.drawPath(
      band,
      Paint()
        ..shader = LinearGradient(colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: strength),
          Colors.white.withValues(alpha: 0),
        ]).createShader(Rect.fromLTWH(x - size.height * 0.5, 0, size.width * 0.35, size.height)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SheenPainter old) => old.t != t || old.strength != strength;
}

class _CardContent extends StatelessWidget {
  const _CardContent({required this.profile, required this.story, this.avatar});
  final SocialProfile profile;
  final bool story;
  final ImageProvider? avatar;
  @override
  Widget build(BuildContext context) {
    final p = profile;
    final s = p.status;
    final coding = s?.coding == true;
    final head = Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      _ShareAvatar(name: p.displayName, url: p.avatarUrl, image: avatar, size: story ? 64 : 46),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(p.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: NV.display(size: story ? 28 : 22)),
          if (p.login != null) Text('@${p.login}', style: TextStyle(fontFamily: NV.mono, fontSize: story ? 12.5 : 11, color: NV.muted)),
        ]),
      ),
    ]);
    final status = Container(
      key: const ValueKey('share-status'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: coding ? NV.red.withValues(alpha: 0.18) : NV.text.withValues(alpha: 0.06),
        border: Border.all(color: coding ? NV.red : NV.glassBorder),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        NvDot(coding ? NV.red : NV.faint, size: 7),
        const SizedBox(width: 6),
        Text(
          coding ? (s?.project != null ? 'Lagi ngoding · ${s!.project}' : 'Lagi ngoding') : (s?.lastActiveAt != null ? 'Aktif ${socialAgo(s!.lastActiveAt)}' : 'Neovarch Agent'),
          style: TextStyle(fontSize: 11.5, color: NV.text),
        ),
      ]),
    );
    final chips = Wrap(spacing: 6, runSpacing: 6, children: [
      for (final l in p.languages.take(story ? 6 : 5)) TechChip(item: l, caption: story, share: story, size: story ? 18 : 20),
    ]);
    final mark = Row(mainAxisSize: MainAxisSize.min, children: [
      Image.asset('assets/brand/monogram.png', width: 14, height: 14, color: NV.text.withValues(alpha: 0.8)),
      const SizedBox(width: 5),
      Text('Neovarch Agent', style: NV.monoLabel(size: 8.5, color: NV.text.withValues(alpha: 0.75))),
    ]);
    final heat = p.heatmap == null
        ? const SizedBox.shrink()
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AKTIVITAS 365 HARI', style: NV.monoLabel(size: 8.5)),
            const SizedBox(height: 6),
            SocialHeatmapView(heatmap: p.heatmap!),
          ]);
    if (!story) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        head,
        const SizedBox(height: 10),
        status,
        const SizedBox(height: 12),
        heat,
        const Spacer(),
        chips,
        const SizedBox(height: 10),
        Align(alignment: Alignment.bottomRight, child: mark),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      head,
      if (p.bio.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(p.bio, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, height: 1.45, color: NV.text)),
      ],
      const SizedBox(height: 14),
      status,
      const SizedBox(height: 18),
      heat,
      const SizedBox(height: 16),
      Text('STACK YANG SERING DIPAKAI', style: NV.monoLabel(size: 8.5)),
      const SizedBox(height: 8),
      chips,
      const Spacer(),
      Align(alignment: Alignment.bottomRight, child: mark),
    ]);
  }
}

class _ShareAvatar extends StatelessWidget {
  const _ShareAvatar({required this.name, this.url, this.image, required this.size});
  final String name;
  final String? url;
  final ImageProvider? image;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: NV.glassRim, width: 1.2)),
        child: image == null
            ? NvAvatar(name: name, url: url, size: size)
            : Container(
                width: size,
                height: size,
                decoration: BoxDecoration(shape: BoxShape.circle, image: DecorationImage(image: image!, fit: BoxFit.cover)),
              ),
      );
}

// ------------------------------------------------------------------ export --

/// Render the card offscreen (no tilt, sheen at rest) at 3× and return PNG
/// bytes of exactly [ShareCardFormat.pixelSize].
Future<Uint8List> renderShareCardPng(GlobalKey boundaryKey) async {
  final ro = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final img = ro.toImageSync(pixelRatio: kShareCardPixelRatio);
  try {
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    img.dispose();
  }
}

/// Width/height of a PNG from its IHDR chunk.
(int, int) pngSize(Uint8List png) {
  final b = ByteData.sublistView(png);
  return (b.getUint32(16), b.getUint32(20));
}

/// Test seams for the platform side.
Future<String> Function(Uint8List png, String name) writeShareFile = (png, name) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/share')..createSync(recursive: true);
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(png, flush: true);
  return f.path;
};
Future<Object?> Function(String method, Map<String, dynamic> args) shareChannel = (m, a) => deviceCall<Object>(m, a);

Future<void> sharePng(BuildContext context, Uint8List png, {String? link}) async {
  try {
    final path = await writeShareFile(png, 'neovarch-profil-${DateTime.now().millisecondsSinceEpoch}.png');
    await shareChannel('shareImage', {'path': path, 'mime': 'image/png', 'text': link ?? 'Profil Neovarch saya'});
  } catch (e) {
    if (context.mounted) toast(context, 'Gagal membagikan: $e');
  }
}

Future<void> savePngToGallery(BuildContext context, Uint8List png) async {
  try {
    final path = await writeShareFile(png, 'neovarch-profil-${DateTime.now().millisecondsSinceEpoch}.png');
    final r = await shareChannel('saveImageToGallery', {'path': path, 'name': path.split('/').last});
    if (context.mounted) toast(context, r == true || r is String ? 'Tersimpan di galeri (Pictures/Neovarch)' : 'Gagal menyimpan ke galeri');
  } catch (e) {
    if (context.mounted) toast(context, 'Gagal menyimpan: $e');
  }
}

// ------------------------------------------------------------- preview sheet --

Future<void> showProfileShareSheet(BuildContext context, SocialProfile profile, {String? gistUrl, Widget? debugBackground}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: NV.bg,
      builder: (ctx) => ProfileSharePreview(profile: profile, gistUrl: gistUrl, debugBackground: debugBackground),
    );

/// Live preview: the sheen sweeps across the glass and the card tilts with a
/// drag (disabled with "reduce motion"); buttons export the still card.
class ProfileSharePreview extends StatefulWidget {
  const ProfileSharePreview({super.key, required this.profile, this.gistUrl, this.debugBackground, this.animate = true});
  final SocialProfile profile;
  final String? gistUrl;
  final Widget? debugBackground;
  final bool animate;
  @override
  State<ProfileSharePreview> createState() => _ProfileSharePreviewState();
}

class _ProfileSharePreviewState extends State<ProfileSharePreview> with SingleTickerProviderStateMixin {
  late final AnimationController _sheen = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));
  final exportKey = GlobalKey();
  ShareCardFormat format = ShareCardFormat.story;
  Offset tilt = Offset.zero;
  bool busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (widget.animate && !reduce) {
      if (!_sheen.isAnimating) _sheen.repeat();
    } else {
      _sheen.stop();
      _sheen.value = 0.32;
    }
  }

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  Future<void> _export(Future<void> Function(Uint8List png) then) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await then(await renderShareCardPng(exportKey));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final size = format.logicalSize;
    final maxH = MediaQuery.sizeOf(context).height * 0.58;
    final scale = math.min(1.0, maxH / size.height);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 12), child: NvSheetTitle(kicker: 'profil · png', title: 'Bagikan profil')),
      CupertinoSlidingSegmentedControl<ShareCardFormat>(
        key: const ValueKey('share-format'),
        groupValue: format,
        thumbColor: NV.raised,
        backgroundColor: NV.surface,
        children: {for (final f in ShareCardFormat.values) f: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), child: Text(f.label, style: TextStyle(color: NV.text, fontSize: 13)))},
        onValueChanged: (f) => setState(() => format = f ?? format),
      ),
      const SizedBox(height: 14),
      // Hidden export copy: still, untilted, exact logical size. It is laid out
      // and painted (its RepaintBoundary has its own layer) but clipped to 0×0.
      ClipRect(
        child: SizedBox.shrink(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          maxWidth: size.width,
          maxHeight: size.height,
          child: RepaintBoundary(
            key: exportKey,
            child: ProfileShareCard(profile: widget.profile, format: format, background: widget.debugBackground),
          ),
        ),
        ),
      ),
      GestureDetector(
        onPanUpdate: reduce ? null : (d) => setState(() => tilt = Offset((tilt.dx + d.delta.dx / 300).clamp(-0.35, 0.35), (tilt.dy + d.delta.dy / 300).clamp(-0.35, 0.35))),
        onPanEnd: (_) => setState(() => tilt = Offset.zero),
        child: TweenAnimationBuilder<Offset>(
          tween: Tween(end: tilt),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          builder: (context, t, child) => Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateX(-t.dy)
              ..rotateY(t.dx),
            child: child,
          ),
          child: SizedBox(
            width: size.width * scale,
            height: size.height * scale,
            child: FittedBox(
              child: AnimatedBuilder(
                animation: _sheen,
                builder: (context, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: ProfileShareCard(
                    key: const ValueKey('share-card-preview'),
                    profile: widget.profile,
                    format: format,
                    sheen: reduce || !widget.animate ? 0.32 : Curves.easeInOut.transform(_sheen.value),
                    background: widget.debugBackground,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.paddingOf(context).bottom),
        child: Row(children: [
          Expanded(
            child: FilledButton.icon(
              key: const ValueKey('share-send'),
              onPressed: busy ? null : () => _export((png) => sharePng(context, png, link: widget.gistUrl)),
              icon: const Icon(CupertinoIcons.share, size: 18),
              label: const Text('Bagikan'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('share-save'),
              onPressed: busy ? null : () => _export((png) => savePngToGallery(context, png)),
              icon: const Icon(CupertinoIcons.arrow_down_to_line, size: 18),
              label: const Text('Simpan ke galeri'),
            ),
          ),
          if (widget.gistUrl != null) ...[
            const SizedBox(width: 8),
            NvIconButton(
              key: const ValueKey('share-link'),
              tooltip: 'Salin tautan profil (Gist)',
              icon: CupertinoIcons.link,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.gistUrl!));
                toast(context, 'Tautan profil disalin');
              },
            ),
          ],
        ]),
      ),
    ]);
  }
}
