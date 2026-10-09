// "Kelengkungan sudut" card: live preview (card → bubble → button, all
// concentric), a 0–32 dp glass slider and the Kotak / Sedang / Bulat / Pil
// presets. Changes apply app-wide immediately and persist.
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/neovarch_mobile_theme.dart';
import 'corner_radius.dart';
import 'glass_surfaces.dart';
import 'panel_tone.dart';

class NvCornerRadiusCard extends ConsumerWidget {
  const NvCornerRadiusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.watch(cornerRadiusProvider);
    final tone = NvPanelToneScope.of(context);
    final v = ctl.value;
    return NvGlassCard(
      key: const ValueKey('corner-card'),
      icon: CupertinoIcons.app,
      title: 'Kelengkungan sudut',
      caption: 'Kartu, tombol, gelembung chat, sheet & bilah navigasi',
      trailing: Text.rich(
        TextSpan(children: [
          TextSpan(text: v.round().toString(), style: TextStyle(fontFamily: NV.display_, fontSize: 22, fontWeight: FontWeight.w700, color: tone.text, fontFeatures: const [FontFeature.tabularFigures()])),
          TextSpan(text: ' dp', style: TextStyle(fontFamily: NV.sans, fontSize: 12.5, fontWeight: FontWeight.w600, color: tone.muted)),
        ]),
        key: const ValueKey('corner-value'),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Preview(radius: v),
        const SizedBox(height: NvSpace.m),
        Row(children: [
          Icon(CupertinoIcons.square, size: 16, color: tone.muted),
          const SizedBox(width: NvSpace.xs),
          Expanded(
            child: NvGlassSlider(
              key: const ValueKey('corner-slider'),
              value: v,
              min: kCornerMin,
              max: kCornerMax,
              divisions: 32,
              semanticLabel: 'Kelengkungan sudut',
              onChanged: ctl.set,
            ),
          ),
          const SizedBox(width: NvSpace.xs),
          Icon(CupertinoIcons.circle, size: 16, color: tone.muted),
        ]),
        const SizedBox(height: NvSpace.s),
        Row(children: [
          for (var i = 0; i < cornerPresets.length; i++) ...[
            if (i > 0) const SizedBox(width: NvSpace.s),
            Expanded(child: _Preset(name: cornerPresets[i].$1, value: cornerPresets[i].$2, selected: v == cornerPresets[i].$2, onTap: () => ctl.set(cornerPresets[i].$2))),
          ],
        ]),
      ]),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.radius});
  final double radius;
  @override
  Widget build(BuildContext context) {
    final tone = NvPanelToneScope.of(context);
    final dur = nvMotion(context, 200);
    const pad = 12.0;
    final radii = NvRadii(radius);
    final innerR = radii.inner(radius, pad);
    final bar = tone.muted.withValues(alpha: 0.35);
    Widget line(double w) => Container(width: w, height: 7, decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(4)));
    return AnimatedContainer(
      key: const ValueKey('corner-preview'),
      duration: dur,
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: Color.alphaBlend(tone.track, const Color(0x00000000)),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: tone.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          AnimatedContainer(
            duration: dur,
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: NV.red.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(innerR.clamp(0, 14))),
          ),
          const SizedBox(width: NvSpace.s),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [line(84), const SizedBox(height: 5), line(52)]),
        ]),
        const SizedBox(height: NvSpace.m),
        Align(
          alignment: Alignment.centerRight,
          child: AnimatedContainer(
            duration: dur,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: NV.red, borderRadius: BorderRadius.circular(radii.bubble.clamp(0, innerR + 6))),
            child: Text('Halo! Sudutnya pas?', style: TextStyle(fontFamily: NV.sans, fontSize: 13, fontWeight: FontWeight.w500, color: NV.onRed)),
          ),
        ),
        const SizedBox(height: NvSpace.s),
        Row(children: [
          Expanded(
            child: AnimatedContainer(
              duration: dur,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tone.track, borderRadius: BorderRadius.circular(innerR), border: Border.all(color: tone.hairline)),
              child: Text('Batal', style: TextStyle(fontFamily: NV.sans, fontSize: 13, fontWeight: FontWeight.w600, color: tone.text)),
            ),
          ),
          const SizedBox(width: NvSpace.s),
          Expanded(
            child: AnimatedContainer(
              duration: dur,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tone.text, borderRadius: BorderRadius.circular(innerR)),
              child: Text('Simpan', style: TextStyle(fontFamily: NV.sans, fontSize: 13, fontWeight: FontWeight.w600, color: tone.dark ? NV.bg : const Color(0xFFFFFFFF))),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _Preset extends StatelessWidget {
  const _Preset({required this.name, required this.value, required this.selected, required this.onTap});
  final String name;
  final double value;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final tone = NvPanelToneScope.of(context);
    final dur = nvMotion(context, 220);
    final r = NV.ctlFor(AppCornerRadius.of(context).card).clamp(4.0, 16.0);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Sudut $name',
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('corner-preset-$name'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: dur,
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? tone.lens : tone.track.withValues(alpha: tone.track.a * 0.6),
            borderRadius: BorderRadius.circular(r),
            border: Border.all(color: selected ? NV.red.withValues(alpha: 0.9) : tone.hairline, width: selected ? 1.5 : 1),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            // the preset's shape at icon size (radius scaled 18/32)
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(value * 9 / 32),
                border: Border.all(color: selected ? tone.text : tone.muted, width: 1.6),
              ),
            ),
            const SizedBox(height: 6),
            Text(name, style: TextStyle(fontFamily: NV.sans, fontSize: 12.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? tone.text : tone.muted)),
          ]),
        ),
      ),
    );
  }
}
