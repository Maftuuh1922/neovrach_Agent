// Accent picker: a tidy, horizontally scrolling row of curated swatches
// (same OKLCH lightness/chroma band, so they all sit well together), the
// brand red, "Dari wallpaper" colours pulled from the background, and a
// compact "Kustom" swatch that opens a smooth HSV picker.
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/neovarch_mobile_theme.dart';
import '../../appearance.dart' show hexOf, parseHexColor, accentPresets;
import 'corner_radius.dart';
import 'glass_surfaces.dart';
import 'glass_tone.dart';

/// Brand default (Neovarch red) — shown first, separate from the curated set.
const nvBrandSwatch = ('Neovarch', NvPalette.defaultAccent);

/// Curated accents: OKLCH L≈0.60–0.74, C≈0.11–0.16 around the hue circle
/// (plus a warm graphite), so any of them harmonises with the neutral
/// surfaces and with each other.
const nvAccentSwatches = <(String, Color)>[
  ('Mawar', Color(0xFFDA5B76)),
  ('Merah', Color(0xFFE24947)),
  ('Koral', Color(0xFFDF7752)),
  ('Amber', Color(0xFFDF9B44)),
  ('Zaitun', Color(0xFF96A04C)),
  ('Hijau', Color(0xFF4FA866)),
  ('Toska', Color(0xFF18A7A1)),
  ('Langit', Color(0xFF369DD1)),
  ('Biru', Color(0xFF487CDE)),
  ('Ungu', Color(0xFF8968D4)),
  ('Anggrek', Color(0xFFBA64B4)),
  ('Grafit', Color(0xFF8C857F)),
];

/// Display name of [c]: a curated / brand swatch, a desktop preset, else null.
String? accentName(Color c) {
  final v = c.toARGB32();
  if (nvBrandSwatch.$2.toARGB32() == v) return nvBrandSwatch.$1;
  for (final (n, s) in nvAccentSwatches) {
    if (s.toARGB32() == v) return n;
  }
  for (final (n, s) in accentPresets) {
    if (s.toARGB32() == v) return n;
  }
  return null;
}

/// Normalises user hex input: "#abc", "abc", "#AABBCC" → "#AABBCC"; null if invalid.
String? normalizeHex(String raw) {
  final c = parseHexColor(raw);
  return c == null ? null : hexOf(c);
}

class NvAccentPicker extends StatelessWidget {
  const NvAccentPicker({super.key, required this.current, required this.onPick, this.wallpaper = const []});
  final Color current;
  final ValueChanged<Color> onPick;
  /// Harmonised colours extracted from the wallpaper ("Dari wallpaper").
  final List<Color> wallpaper;

  bool _isCurated(Color c) {
    final v = c.toARGB32();
    return v == nvBrandSwatch.$2.toARGB32() || nvAccentSwatches.any((s) => s.$2.toARGB32() == v) || wallpaper.any((w) => w.toARGB32() == v);
  }

  Future<void> _custom(BuildContext context) async {
    final c = await showNvHsvPicker(context, initial: current);
    if (c != null) onPick(c);
  }

  @override
  Widget build(BuildContext context) {
    final tone = GlassToneScope.of(context);
    final cur = current.toARGB32();
    final custom = !_isCurated(current);
    Widget sw(String key, String name, Color c) => NvSwatch(key: ValueKey('accent-$key'), color: c, name: name, selected: c.toARGB32() == cur, onTap: () => onPick(c));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: NvSwatch.extent,
        child: SingleChildScrollView(
          key: const ValueKey('accent-row'),
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(children: [
            sw(nvBrandSwatch.$1, nvBrandSwatch.$1, nvBrandSwatch.$2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: NvSpace.s),
              child: Center(child: Container(width: 1, height: 22, color: tone.hairline)),
            ),
            for (final (n, c) in nvAccentSwatches) Padding(padding: const EdgeInsets.only(right: NvSpace.s), child: sw(n, n, c)),
            NvSwatch(
              key: const ValueKey('accent-custom'),
              color: custom ? current : null,
              name: 'Kustom',
              selected: custom,
              onTap: () => _custom(context),
            ),
          ]),
        ),
      ),
      if (wallpaper.isNotEmpty) ...[
        const SizedBox(height: NvSpace.m),
        Row(children: [
          Icon(CupertinoIcons.photo, size: 14, color: tone.muted),
          const SizedBox(width: 6),
          Text('Dari wallpaper', style: TextStyle(fontFamily: NV.sans, fontSize: 12.5, fontWeight: FontWeight.w600, color: tone.muted)),
          const SizedBox(width: NvSpace.m),
          Expanded(
            child: SizedBox(
              height: NvSwatch.extent,
              child: SingleChildScrollView(
                key: const ValueKey('accent-wallpaper-row'),
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: Row(children: [
                  for (var i = 0; i < wallpaper.length; i++)
                    Padding(padding: const EdgeInsets.only(right: NvSpace.s), child: sw('wall-$i', 'Wallpaper ${i + 1}', wallpaper[i])),
                ]),
              ),
            ),
          ),
        ]),
      ],
    ]);
  }
}

/// One round swatch with an animated selection ring (gap + ring in the
/// theme's text colour, so it is visible on any accent). [color] null draws
/// the "Kustom" conic hue swatch.
class NvSwatch extends StatelessWidget {
  const NvSwatch({super.key, required this.color, required this.name, required this.selected, required this.onTap});
  final Color? color;
  final String name;
  final bool selected;
  final VoidCallback onTap;
  static const extent = 40.0;
  static const dot = 28.0;

  @override
  Widget build(BuildContext context) {
    final tone = GlassToneScope.of(context);
    final dur = nvMotion(context, 260);
    final fill = color;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: Tooltip(
        message: name,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(
            width: extent,
            height: extent,
            child: Stack(alignment: Alignment.center, children: [
              AnimatedContainer(
                duration: dur,
                curve: Curves.easeOutBack,
                width: selected ? extent : dot,
                height: selected ? extent : dot,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? tone.text : const Color(0x00000000), width: 2),
                ),
              ),
              AnimatedScale(
                duration: dur,
                curve: Curves.easeOutBack,
                scale: selected ? 0.92 : 1,
                child: Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: fill,
                    gradient: fill == null ? const SweepGradient(colors: _hueStops) : null,
                    border: Border.all(color: tone.hairline),
                  ),
                  child: fill == null
                      ? Icon(CupertinoIcons.add, size: 14, color: const Color(0xFFFFFFFF).withValues(alpha: 0.95))
                      : AnimatedOpacity(
                          duration: dur,
                          opacity: selected ? 1 : 0,
                          child: Icon(CupertinoIcons.checkmark_alt, size: 15, color: NvPalette.from(fill, Brightness.dark).onAccent),
                        ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

const _hueStops = <Color>[
  Color(0xFFFF0000), Color(0xFFFF8000), Color(0xFFFFFF00), Color(0xFF80FF00), Color(0xFF00FF00), Color(0xFF00FF80), //
  Color(0xFF00FFFF), Color(0xFF0080FF), Color(0xFF0000FF), Color(0xFF8000FF), Color(0xFFFF00FF), Color(0xFFFF0080), Color(0xFFFF0000),
];

/// Continuous hue gradient (13 stops = every 30°, no banding).
const nvHueGradient = LinearGradient(colors: _hueStops);

/// Opens the HSV picker as a glass bottom sheet; returns the applied colour.
Future<Color?> showNvHsvPicker(BuildContext context, {required Color initial}) => showModalBottomSheet<Color>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0x00000000),
      showDragHandle: false,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: NvHsvPickerSheet(initial: initial),
      ),
    );

class NvHsvPickerSheet extends StatelessWidget {
  const NvHsvPickerSheet({super.key, required this.initial});
  final Color initial;
  @override
  Widget build(BuildContext context) {
    final radii = AppCornerRadius.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(NvSpace.s, 0, NvSpace.s, NvSpace.s),
      child: NvGlassSurface(
        radius: radii.sheet.clamp(12.0, 36.0),
        fill: Color.lerp(NV.surface, NV.red, 0.05)!.withValues(alpha: 0.94),
        padding: const EdgeInsets.fromLTRB(NvSpace.xl, NvSpace.m, NvSpace.xl, NvSpace.xl),
        child: NvHsvPicker(initial: initial, onApply: (c) => Navigator.of(context).pop(c)),
      ),
    );
  }
}

/// Saturation/brightness pad + continuous hue slider + hex field, with a
/// live preview. [onApply] fires on "Pakai".
class NvHsvPicker extends StatefulWidget {
  const NvHsvPicker({super.key, required this.initial, required this.onApply});
  final Color initial;
  final ValueChanged<Color> onApply;
  @override
  State<NvHsvPicker> createState() => NvHsvPickerState();
}

class NvHsvPickerState extends State<NvHsvPicker> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial.withAlpha(255));
  late final TextEditingController _hex = TextEditingController(text: hexOf(widget.initial));
  final _focus = FocusNode();
  bool _hexError = false;
  // Exact colour when it came from hex / initial (HSV round-trips can be off by one).
  late Color? _exact = widget.initial.withAlpha(255);

  Color get color => _exact ?? _hsv.toColor();

  void _set(HSVColor h, {bool fromHex = false}) {
    setState(() {
      _hsv = h;
      _hexError = false;
      if (!fromHex) {
        _exact = null;
        _hex.text = hexOf(h.toColor());
      }
    });
  }

  void _submitHex(String v) {
    final c = parseHexColor(v);
    if (c == null) {
      setState(() => _hexError = true);
      return;
    }
    _set(HSVColor.fromColor(c), fromHex: true);
    _exact = c;
    _hex.text = hexOf(c);
  }

  @override
  void dispose() {
    _hex.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tone = GlassToneScope.of(context);
    final radii = AppCornerRadius.of(context);
    final c = color;
    final padR = radii.inner(radii.sheet.clamp(12.0, 36.0), NvSpace.xl).clamp(6.0, 20.0);
    final on = NvPalette.from(c, Brightness.dark).onAccent;
    return Column(key: const ValueKey('hsv-picker'), mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(child: Container(width: 36, height: 5, decoration: BoxDecoration(color: tone.muted.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(3)))),
      const SizedBox(height: NvSpace.l),
      Row(children: [
        Expanded(
          child: Text('Warna kustom',
              style: TextStyle(fontFamily: NV.display_, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: NV.tracking(22), color: tone.text)),
        ),
        // live preview chip: the colour as a button with its legible on-colour
        AnimatedContainer(
          key: const ValueKey('hsv-preview'),
          duration: nvMotion(context, 160),
          padding: const EdgeInsets.symmetric(horizontal: NvSpace.m, vertical: 7),
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(radii.control.clamp(0, 18)), border: Border.all(color: tone.hairline)),
          child: Text('Aa', style: TextStyle(fontFamily: NV.sans, fontSize: 14, fontWeight: FontWeight.w700, color: on)),
        ),
      ]),
      const SizedBox(height: NvSpace.l),
      AspectRatio(
        aspectRatio: 1.7,
        child: _SvPad(key: const ValueKey('hsv-pad'), hsv: _hsv, radius: padR, onChanged: _set),
      ),
      const SizedBox(height: NvSpace.m),
      NvGlassSlider(
        key: const ValueKey('hsv-hue'),
        value: _hsv.hue,
        min: 0,
        max: 360,
        trackHeight: 14,
        semanticLabel: 'Rona',
        trackGradient: nvHueGradient,
        thumbColor: HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor(),
        onChanged: (v) => _set(_hsv.withHue(v.clamp(0, 359.999))),
      ),
      const SizedBox(height: NvSpace.m),
      Row(children: [
        Expanded(
          child: _GlassField(
            key: const ValueKey('hsv-hex'),
            controller: _hex,
            focus: _focus,
            error: _hexError,
            swatch: c,
            onSubmitted: _submitHex,
          ),
        ),
        const SizedBox(width: NvSpace.m),
        SizedBox(
          height: 48,
          child: FilledButton(
            key: const ValueKey('hsv-apply'),
            style: FilledButton.styleFrom(
              backgroundColor: c,
              foregroundColor: on,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radii.control.clamp(0, 24))),
              padding: const EdgeInsets.symmetric(horizontal: NvSpace.xl),
            ),
            onPressed: () {
              if (_focus.hasFocus) _submitHex(_hex.text);
              widget.onApply(color);
            },
            child: const Text('Pakai'),
          ),
        ),
      ]),
    ]);
  }
}

/// Saturation (x) × brightness (y) pad for the current hue: two smooth
/// gradients, a glass ring thumb filled with the live colour.
class _SvPad extends StatelessWidget {
  const _SvPad({super.key, required this.hsv, required this.radius, required this.onChanged});
  final HSVColor hsv;
  final double radius;
  final void Function(HSVColor) onChanged;
  @override
  Widget build(BuildContext context) {
    final tone = GlassToneScope.of(context);
    return LayoutBuilder(builder: (context, c) {
      void at(Offset p) {
        final s = (p.dx / c.maxWidth).clamp(0.0, 1.0);
        final v = 1 - (p.dy / c.maxHeight).clamp(0.0, 1.0);
        onChanged(hsv.withSaturation(s).withValue(v));
      }

      final x = hsv.saturation * c.maxWidth, y = (1 - hsv.value) * c.maxHeight;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => at(d.localPosition),
        onPanStart: (d) => at(d.localPosition),
        onPanUpdate: (d) => at(d.localPosition),
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [const Color(0xFFFFFFFF), HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()]),
                ),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xFF000000)]),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius), border: Border.all(color: tone.hairline))),
            ),
          ),
          Positioned(
            left: x - 14,
            top: y - 14,
            child: IgnorePointer(
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hsv.toColor(),
                  border: Border.all(color: const Color(0xFFFFFFFF), width: 3),
                  boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 8, offset: Offset(0, 2))],
                ),
              ),
            ),
          ),
        ]),
      );
    });
  }
}

/// Glass-style text field (hex): translucent tone fill, hairline, accent
/// focus ring; a swatch prefix showing the colour.
class _GlassField extends StatefulWidget {
  const _GlassField({super.key, required this.controller, required this.focus, required this.error, required this.swatch, required this.onSubmitted});
  final TextEditingController controller;
  final FocusNode focus;
  final bool error;
  final Color swatch;
  final ValueChanged<String> onSubmitted;
  @override
  State<_GlassField> createState() => _GlassFieldState();
}

class _GlassFieldState extends State<_GlassField> {
  @override
  void initState() {
    super.initState();
    widget.focus.addListener(_f);
  }

  void _f() => setState(() {});

  @override
  void dispose() {
    widget.focus.removeListener(_f);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tone = GlassToneScope.of(context);
    final radii = AppCornerRadius.of(context);
    final focused = widget.focus.hasFocus;
    final br = BorderRadius.circular(radii.control.clamp(0, 24));
    return AnimatedContainer(
      duration: nvMotion(context, 160),
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: NvSpace.m),
      decoration: BoxDecoration(
        color: Color.alphaBlend(tone.track, tone.fill.withValues(alpha: 0.5)),
        borderRadius: br,
        border: Border.all(color: widget.error ? NV.red : (focused ? NV.red.withValues(alpha: 0.85) : tone.hairline), width: focused || widget.error ? 1.5 : 1),
      ),
      child: Row(children: [
        Container(width: 20, height: 20, decoration: BoxDecoration(color: widget.swatch, shape: BoxShape.circle, border: Border.all(color: tone.hairline))),
        const SizedBox(width: NvSpace.s),
        Expanded(
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focus,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')), LengthLimitingTextInputFormatter(7)],
            style: NV.code(size: 15, color: tone.text),
            cursorColor: NV.red,
            decoration: InputDecoration(
              isCollapsed: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: '#RRGGBB',
              hintStyle: NV.code(size: 15, color: tone.muted),
            ),
            onSubmitted: widget.onSubmitted,
          ),
        ),
        if (widget.error) Text('hex?', style: TextStyle(fontSize: 12, color: tone.muted)),
      ]),
    );
  }
}
