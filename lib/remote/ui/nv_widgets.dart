// Building blocks of the Neovarch Remote look (see neovarch_mobile_theme):
// header with a mono kicker over a serif title, "// LABEL" sections,
// rounded 16px panels with 1px borders, 14px chat blocks, a floating nav bar
// with a red top indicator. Flat colours only.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme/neovarch_mobile_theme.dart';
import '../../ui/widgets/common.dart' show clockOf, LogView, reduceMotion;

/// Screen header: `// KICKER` in mono, a serif title, optional status line and
/// actions on the right. Replaces the stock AppBar on every remote tab.
class NvHeader extends StatelessWidget {
  const NvHeader({super.key, required this.kicker, required this.title, this.status, this.actions = const [], this.onBack});
  final String kicker;
  final String title;
  final Widget? status;
  final List<Widget> actions;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.fromLTRB(onBack != null ? 8 : 20, top + 14, 12, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (onBack != null)
          Padding(
            padding: const EdgeInsets.only(right: 4, bottom: 2),
            child: NvIconButton(icon: Icons.arrow_back, tooltip: 'Kembali', onPressed: onBack),
          ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('// ${kicker.toUpperCase()}', style: NV.monoLabel(color: NV.red)),
            const SizedBox(height: 6),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: NV.display(size: 34)),
            if (status != null) ...[const SizedBox(height: 6), status!],
          ]),
        ),
        for (final a in actions) Padding(padding: const EdgeInsets.only(left: 6, bottom: 2), child: a),
      ]),
    );
  }
}

/// Square-ish 40px icon button on a bordered rounded tile.
class NvIconButton extends StatelessWidget {
  const NvIconButton({super.key, required this.icon, required this.onPressed, this.tooltip, this.accent = false, this.size = 40});
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool accent;
  final double size;
  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final btn = Material(
      color: accent && enabled ? NV.red : NV.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NV.rCtl),
        side: BorderSide(color: accent && enabled ? NV.red : NV.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.48, color: !enabled ? NV.faint : (accent ? NV.text : NV.text)),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// `// LABEL` section header in mono with an optional trailing widget.
class NvSection extends StatelessWidget {
  const NvSection(this.label, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(20, 22, 20, 10), this.count});
  final String label;
  final Widget? trailing;
  final EdgeInsets padding;
  final int? count;
  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [
          Text('// ${label.toUpperCase()}', style: NV.monoLabel()),
          if (count != null) ...[const SizedBox(width: 8), NvPill('$count')],
          const SizedBox(width: 10),
          const Expanded(child: Divider(color: NV.border, height: 1)),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ]),
      );
}

/// Rounded 16px surface with a 1px border.
class NvPanel extends StatelessWidget {
  const NvPanel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.margin = EdgeInsets.zero, this.color = NV.surface, this.borderColor = NV.border, this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final Color color;
  final Color borderColor;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: margin,
        child: Material(
          color: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NV.rCard), side: BorderSide(color: borderColor)),
          clipBehavior: Clip.antiAlias,
          child: onTap == null ? Padding(padding: padding, child: child) : InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
        ),
      );
}

/// Full-radius small badge (counts, priorities, states).
class NvPill extends StatelessWidget {
  const NvPill(this.label, {super.key, this.color = NV.muted, this.filled = false});
  final String label;
  final Color color;
  final bool filled;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
        decoration: BoxDecoration(
          color: filled ? color : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: filled ? color : color.withValues(alpha: 0.35)),
        ),
        child: Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: NV.monoLabel(size: 10, color: filled ? NV.text : color)),
      );
}

class NvDot extends StatelessWidget {
  const NvDot(this.color, {super.key, this.size = 8});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

/// Row inside a panel list: rounded icon tile, title, subtitle, trailing.
class NvRow extends StatelessWidget {
  const NvRow({super.key, required this.icon, required this.title, this.subtitle, this.trailing, this.onTap, this.accent = false, this.mono = false});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool accent;
  final bool mono;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent ? NV.redWash : NV.raised,
                borderRadius: BorderRadius.circular(NV.rCtl),
                border: Border.all(color: accent ? NV.darkRed : NV.border),
              ),
              child: Icon(icon, size: 19, color: accent ? NV.red : NV.muted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: NV.text)),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono ? NV.monoLabel(size: 11, color: NV.muted).copyWith(letterSpacing: 0.2) : const TextStyle(fontSize: 12.5, color: NV.muted)),
                ],
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ]),
        ),
      );
}

/// Several [NvRow]s in one bordered panel with hairline separators.
class NvList extends StatelessWidget {
  const NvList({super.key, required this.children, this.margin = const EdgeInsets.symmetric(horizontal: 16)});
  final List<Widget> children;
  final EdgeInsets margin;
  @override
  Widget build(BuildContext context) => NvPanel(
        margin: margin,
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(indent: 64, height: 1, color: NV.border),
            children[i],
          ],
        ]),
      );
}

/// Key/value line in mono label + body text.
class NvKv extends StatelessWidget {
  const NvKv(this.k, this.v, {super.key, this.mono = false, this.valueColor});
  final String k;
  final String v;
  final bool mono;
  final Color? valueColor;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 112, child: Text(k.toUpperCase(), style: NV.monoLabel(size: 10))),
          Expanded(
            child: Text(v,
                style: mono
                    ? TextStyle(fontFamily: NV.mono, fontSize: 12.5, color: valueColor ?? NV.text)
                    : TextStyle(fontSize: 14, color: valueColor ?? NV.text, fontWeight: FontWeight.w500)),
          ),
        ]),
      );
}

/// Empty / idle state with a piece of the dithered red art.
class NvEmpty extends StatelessWidget {
  const NvEmpty({super.key, required this.title, this.body, this.art, this.action, this.kicker});
  final String title;
  final String? body;
  final String? art;
  final String? kicker;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (art != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(NV.rCard),
              child: Container(
                foregroundDecoration: BoxDecoration(borderRadius: BorderRadius.circular(NV.rCard), border: Border.all(color: NV.border)),
                child: AspectRatio(aspectRatio: 16 / 9, child: Image.asset(art!, fit: BoxFit.cover, filterQuality: FilterQuality.medium)),
              ),
            ),
          const SizedBox(height: 18),
          if (kicker != null) ...[Text('// ${kicker!.toUpperCase()}', style: NV.monoLabel(color: NV.red)), const SizedBox(height: 8)],
          Text(title, style: NV.display(size: 28)),
          if (body != null) ...[
            const SizedBox(height: 8),
            Text(body!, style: const TextStyle(fontSize: 14, height: 1.5, color: NV.muted)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      );
}

/// Error / warning strip: rounded 12px, tinted, left rule kept inside.
class NvNotice extends StatelessWidget {
  const NvNotice(this.message, {super.key, this.color = NV.red, this.icon = Icons.error_outline, this.action});
  final String message;
  final Color color;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(NV.rCtl),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 18, color: color)),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 13.5, height: 1.45, color: NV.text))),
          ?action,
        ]),
      );
}

/// The user's turn: a rounded 14px block on a red-tinted surface with a red
/// left rule and a mono "// KAMU" label. Not a Material bubble.
class NvUserMessage extends StatelessWidget {
  const NvUserMessage({super.key, required this.msg, this.scale = 1});
  final ChatMsg msg;
  final double scale;
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: math.min(560, w * 0.86)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(NV.rMsg),
          child: Container(
            decoration: BoxDecoration(
              color: NV.redWash,
              borderRadius: BorderRadius.circular(NV.rMsg),
              border: Border.all(color: NV.darkRed.withValues(alpha: 0.7)),
            ),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(width: 3, color: NV.red),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(13, 10, 14, 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text('// KAMU${msg.ts > 0 ? '  ·  ${clockOf(msg.ts)}' : ''}', style: NV.monoLabel(size: 9.5, color: NV.red)),
                      const SizedBox(height: 5),
                      SelectableText(msg.content, style: TextStyle(fontSize: 14.5 * scale, height: 1.5, color: NV.text)),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mono label above an assistant turn ("// NEOVARCH · PC KANTOR").
class NvAgentLabel extends StatelessWidget {
  const NvAgentLabel(this.label, {super.key, this.live = false});
  final String label;
  final bool live;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: NV.red, shape: BoxShape.circle),
            child: const Text('N', style: TextStyle(fontFamily: NV.serif, fontSize: 13, height: 1.1, color: NV.text)),
          ),
          const SizedBox(width: 8),
          Flexible(child: Text('// ${label.toUpperCase()}', maxLines: 1, overflow: TextOverflow.ellipsis, style: NV.monoLabel(size: 9.5))),
          if (live) ...[const SizedBox(width: 8), const _LiveDot()],
        ]),
      );
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!reduceMotion(context) && !_c.isAnimating) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: Tween(begin: 0.3, end: 1.0).animate(_c), child: const NvDot(NV.red, size: 6));
}

/// A tool call the agent wants to run: rounded panel, red rule, command in
/// mono, choices as rounded buttons.
class NvApprovalCard extends StatelessWidget {
  const NvApprovalCard({super.key, required this.command, required this.description, required this.choices, required this.onChoice, this.origin, this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 10)});
  final String command;
  final String description;
  final List<String> choices;
  final void Function(String) onChoice;
  final String? origin;
  final EdgeInsets margin;

  static String label(String c) => switch (c) {
        'once' => 'Izinkan sekali',
        'session' => 'Izinkan sesi ini',
        'always' => 'Selalu izinkan',
        'deny' => 'Tolak',
        _ => c,
      };

  @override
  Widget build(BuildContext context) {
    final allow = choices.where((c) => c != 'deny').toList();
    final deny = choices.contains('deny');
    return NvPanel(
      margin: margin,
      borderColor: NV.darkRed,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.shield_outlined, size: 16, color: NV.red),
          const SizedBox(width: 8),
          Text('// PERLU PERSETUJUAN', style: NV.monoLabel(color: NV.red)),
          const SizedBox(width: 10),
          Expanded(
            child: origin != null && origin!.isNotEmpty
                ? Align(alignment: Alignment.centerRight, child: NvPill(origin!, color: NV.muted))
                : const SizedBox.shrink(),
          ),
        ]),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(description, style: const TextStyle(fontSize: 14, height: 1.45, color: NV.text)),
        ],
        const SizedBox(height: 10),
        ClipRRect(borderRadius: BorderRadius.circular(NV.rCtl), child: LogView(command, maxHeight: 120)),
        const SizedBox(height: 12),
        Row(children: [
          if (allow.isNotEmpty)
            Expanded(child: FilledButton(onPressed: () => onChoice(allow.first), child: Text(label(allow.first), maxLines: 1, overflow: TextOverflow.ellipsis))),
          if (deny) ...[
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: () => onChoice('deny'), child: const Text('Tolak'))),
          ],
        ]),
        if (allow.length > 1) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in allow.skip(1))
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                onPressed: () => onChoice(c),
                child: Text(label(c), style: const TextStyle(fontSize: 13)),
              ),
          ]),
        ],
      ]),
    );
  }
}

/// Floating rounded tab bar: surface plate, 20px radius, each active tab is
/// a red-wash rounded tile with a short red bar on its top edge.
class NvNavBar extends StatelessWidget {
  const NvNavBar({super.key, required this.index, required this.onTap, required this.items, this.badges = const {}, this.dots = const {}});
  final int index;
  final ValueChanged<int> onTap;
  final List<(IconData, IconData, String)> items;
  final Map<int, int> badges;
  final Map<int, Color> dots;

  @override
  Widget build(BuildContext context) {
    final dur = reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 240);
    return Container(
      decoration: BoxDecoration(
        color: NV.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NV.borderStrong),
      ),
      padding: const EdgeInsets.all(6),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / items.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: dur,
            curve: Curves.easeOutCubic,
            left: w * index,
            top: 0,
            bottom: 0,
            width: w,
            child: Container(
              decoration: BoxDecoration(
                color: NV.redWash,
                borderRadius: BorderRadius.circular(NV.rCtl + 2),
                border: Border.all(color: NV.darkRed.withValues(alpha: 0.8)),
              ),
              alignment: Alignment.topCenter,
              child: Container(
                width: 22,
                height: 3,
                decoration: const BoxDecoration(color: NV.red, borderRadius: BorderRadius.vertical(bottom: Radius.circular(3))),
              ),
            ),
          ),
          Row(children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == index,
                  label: items[i].$3,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(i),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Stack(clipBehavior: Clip.none, children: [
                        Icon(i == index ? items[i].$2 : items[i].$1, size: 21, color: i == index ? NV.red : NV.muted),
                        if ((badges[i] ?? 0) > 0)
                          Positioned(
                            right: -10,
                            top: -6,
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 16),
                              height: 16,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: NV.red, borderRadius: BorderRadius.circular(999), border: Border.all(color: NV.surface, width: 1.5)),
                              child: Text('${badges[i]}', style: const TextStyle(fontFamily: NV.mono, fontSize: 9.5, color: NV.text, height: 1.1)),
                            ),
                          )
                        else if (dots[i] != null)
                          Positioned(right: -3, top: -2, child: NvDot(dots[i]!, size: 8)),
                      ]),
                      const SizedBox(height: 4),
                      Text(items[i].$3.toUpperCase(), style: NV.monoLabel(size: 9.5, color: i == index ? NV.text : NV.muted)),
                    ]),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

/// Rounded top sheet title: `// KICKER` + serif title.
class NvSheetTitle extends StatelessWidget {
  const NvSheetTitle({super.key, required this.kicker, required this.title, this.trailing});
  final String kicker;
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('// ${kicker.toUpperCase()}', style: NV.monoLabel(color: NV.red)),
            const SizedBox(height: 6),
            Text(title, style: NV.display(size: 28)),
          ]),
        ),
        ?trailing,
      ]);
}
