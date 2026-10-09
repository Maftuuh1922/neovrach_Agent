// Backdrop luminance map: the wallpaper downscaled once (when it changes) to
// a small grid of average colours, run through the same pipeline as
// NvAppBackground (art tint, saturation, accent tint, dim). Every glass
// element looks up the cells under its global rect to pick light or dark
// text and a fill opacity that keeps 4.5:1 contrast.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/neovarch_mobile_theme.dart';
import '../../appearance.dart';
import '../remote_background.dart' show artTintMatrix, backgroundImage, saturationMatrix;
import 'glass_style.dart';
import 'glass_tone.dart';

/// Average colours of a [cols]×[rows] grid over an image.
@immutable
class LuminanceGrid {
  const LuminanceGrid._(this.cols, this.rows, this.cells, this.aspect);

  final int cols, rows;
  final List<Color> cells; // row-major
  /// Source image width / height (for BoxFit.cover mapping).
  final double aspect;

  /// From raw RGBA8888 pixels.
  factory LuminanceGrid.fromRgba(int width, int height, Uint8List rgba, {int cols = 16, int rows = 32}) {
    cols = cols.clamp(1, width);
    rows = rows.clamp(1, height);
    final sums = List<List<double>>.generate(cols * rows, (_) => [0, 0, 0, 0]);
    for (var y = 0; y < height; y++) {
      final gy = y * rows ~/ height;
      for (var x = 0; x < width; x++) {
        final gx = x * cols ~/ width;
        final i = (y * width + x) * 4;
        final s = sums[gy * cols + gx];
        s[0] += rgba[i];
        s[1] += rgba[i + 1];
        s[2] += rgba[i + 2];
        s[3] += 1;
      }
    }
    final cells = [
      for (final s in sums)
        s[3] == 0 ? const Color(0xFF000000) : Color.fromARGB(255, (s[0] / s[3]).round(), (s[1] / s[3]).round(), (s[2] / s[3]).round()),
    ];
    return LuminanceGrid._(cols, rows, List.unmodifiable(cells), width / height);
  }

  /// A uniform grid (tests, flat backgrounds).
  factory LuminanceGrid.solid(Color c, {double aspect = 0.5}) => LuminanceGrid._(1, 1, [c.withAlpha(255)], aspect);

  /// Same grid with every cell mapped through [f].
  LuminanceGrid map(Color Function(Color) f) => LuminanceGrid._(cols, rows, List.unmodifiable(cells.map(f)), aspect);

  Color cell(int x, int y) => cells[y.clamp(0, rows - 1) * cols + x.clamp(0, cols - 1)];
}

Color _matrix(Color c, List<double> m) {
  double ch(int r) => (m[r * 5] * c.r + m[r * 5 + 1] * c.g + m[r * 5 + 2] * c.b + m[r * 5 + 4] / 255).clamp(0.0, 1.0);
  return Color.from(alpha: 1, red: ch(0), green: ch(1), blue: ch(2));
}

/// What sits behind the glass on screen: the processed wallpaper grid laid
/// out with BoxFit.cover over [screen], or a flat [base] colour.
@immutable
class GlassBackdropMap {
  const GlassBackdropMap._(this.grid, this.base, this.screen);

  /// Flat background (Polos).
  const GlassBackdropMap.flat(Color base) : this._(null, base, Size.zero);

  /// [grid] is the raw image grid; the background pipeline is applied here.
  factory GlassBackdropMap.image(
    LuminanceGrid grid, {
    required Size screen,
    required Color base,
    Color? accent,
    double tint = 0,
    double dim = 0,
    double saturation = 1,
    bool isAsset = false,
  }) {
    final art = isAsset && accent != null ? artTintMatrix(accent) : null;
    final sat = saturation != 1 ? saturationMatrix(saturation) : null;
    final g = grid.map((c) {
      var o = c;
      if (art != null) o = _matrix(o, art);
      if (sat != null) o = _matrix(o, sat);
      if (tint > 0 && accent != null) o = Color.alphaBlend(accent.withValues(alpha: tint), o);
      if (dim > 0) o = Color.alphaBlend(base.withValues(alpha: dim), o);
      return o;
    });
    return GlassBackdropMap._(g, base, screen);
  }

  final LuminanceGrid? grid;
  final Color base;
  final Size screen;

  /// Average + extremes of the cells under [global] (screen coordinates).
  BackdropSample sample(Rect global) {
    final g = grid;
    if (g == null || screen.isEmpty) return BackdropSample.solid(base);
    // BoxFit.cover, centred.
    final scale = (screen.width / g.aspect > screen.height) ? screen.width / g.aspect : screen.height;
    final dw = scale * g.aspect, dh = scale;
    final ox = (screen.width - dw) / 2, oy = (screen.height - dh) / 2;
    int cx(double x) => (((x - ox) / dw) * g.cols).floor().clamp(0, g.cols - 1);
    int cy(double y) => (((y - oy) / dh) * g.rows).floor().clamp(0, g.rows - 1);
    final r = global.isEmpty ? Rect.fromCenter(center: global.center, width: 1, height: 1) : global;
    final x0 = cx(r.left), x1 = cx(r.right - 0.01), y0 = cy(r.top), y1 = cy(r.bottom - 0.01);
    double sr = 0, sg = 0, sb = 0;
    var n = 0;
    Color? lo, hi;
    double lLo = 2, lHi = -1;
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final c = g.cell(x, y);
        sr += c.r;
        sg += c.g;
        sb += c.b;
        n++;
        final l = relativeLuminance(c);
        if (l < lLo) {
          lLo = l;
          lo = c;
        }
        if (l > lHi) {
          lHi = l;
          hi = c;
        }
      }
    }
    final mean = Color.from(alpha: 1, red: sr / n, green: sg / n, blue: sb / n);
    return BackdropSample(mean: mean, lightest: hi ?? mean, darkest: lo ?? mean);
  }

  @override
  bool operator ==(Object other) =>
      other is GlassBackdropMap && identical(other.grid, grid) && other.base == base && other.screen == screen;
  @override
  int get hashCode => Object.hash(identityHashCode(grid), base, screen);
}

final Map<Object, LuminanceGrid> _gridCache = {};
final Map<Object, Future<LuminanceGrid?>> _pending = {};

/// Decodes [provider] at ~48 px wide and builds its grid (cached by provider).
Future<LuminanceGrid?> loadLuminanceGrid(ImageProvider provider) {
  final hit = _gridCache[provider];
  if (hit != null) return SynchronousFuture(hit);
  return _pending[provider] ??= _decode(provider).then((g) {
    _pending.remove(provider);
    if (g != null) {
      if (_gridCache.length > 8) _gridCache.clear();
      _gridCache[provider] = g;
    }
    return g;
  });
}

/// The cached grid for [provider], if already decoded.
LuminanceGrid? cachedLuminanceGrid(ImageProvider provider) => _gridCache[provider];

Future<LuminanceGrid?> _decode(ImageProvider provider) async {
  final c = Completer<ui.Image?>();
  final stream = ResizeImage(provider, width: 48, height: 96, policy: ResizeImagePolicy.fit).resolve(ImageConfiguration.empty);
  late final ImageStreamListener l;
  l = ImageStreamListener((info, _) {
    if (!c.isCompleted) c.complete(info.image.clone());
    stream.removeListener(l);
  }, onError: (e, s) {
    if (!c.isCompleted) c.complete(null);
    stream.removeListener(l);
  });
  stream.addListener(l);
  final img = await c.future;
  if (img == null) return null;
  try {
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    return LuminanceGrid.fromRgba(img.width, img.height, data.buffer.asUint8List(), cols: 16, rows: 32);
  } finally {
    img.dispose();
  }
}

/// Provides a [GlassScope] for its subtree from the configured app
/// background (Tampilan → Latar belakang) and "Gaya kaca".
class GlassBackdrop extends ConsumerStatefulWidget {
  const GlassBackdrop({super.key, required this.child, this.style, this.debugGrid});
  final Widget child;

  /// Fixed style (else [glassStyleProvider]).
  final GlassStyle? style;

  /// Tests: use this grid instead of decoding the background image.
  final LuminanceGrid? debugGrid;

  @override
  ConsumerState<GlassBackdrop> createState() => _GlassBackdropState();
}

class _GlassBackdropState extends ConsumerState<GlassBackdrop> {
  ImageProvider? _img;
  LuminanceGrid? _grid;
  Object? _memoKey;
  GlassBackdropMap? _memo;

  void _ensure(ImageProvider? img) {
    if (img == _img) return;
    _img = img;
    _grid = img == null ? null : cachedLuminanceGrid(img);
    if (img != null && _grid == null) {
      loadLuminanceGrid(img).then((g) {
        if (mounted && _img == img) setState(() => _grid = g);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final look = ref.watch(appearanceProvider);
    final GlassStyle style = widget.style ?? ref.watch(glassStyleProvider);
    final b = look.background;
    final screen = MediaQuery.sizeOf(context);
    final grid = widget.debugGrid ??
        (() {
          _ensure(b.active ? backgroundImage(b) : null);
          return _grid;
        })();
    final useImage = grid != null && (b.active || widget.debugGrid != null);
    // Memoised so GlassScope only notifies when the backdrop really changed.
    final key = Object.hash(useImage ? identityHashCode(grid) : 0, screen, NV.bg, NV.red, b.tint, b.dim, b.saturation, b.isAsset);
    if (key != _memoKey || _memo == null) {
      _memoKey = key;
      _memo = useImage
          ? GlassBackdropMap.image(grid,
              screen: screen, base: NV.bg, accent: NV.red, tint: b.tint, dim: b.dim, saturation: b.saturation, isAsset: b.isAsset)
          : GlassBackdropMap.flat(NV.bg);
    }
    final map = _memo!;
    return GlassScope(style: style, backdrop: map, child: widget.child);
  }
}
