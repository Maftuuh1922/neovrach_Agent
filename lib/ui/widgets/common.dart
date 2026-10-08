// Shared primitives — one per concern, as the design guide asks:
// Loader (animated curve, never the literal "Loading…"), EmptyState,
// ErrorBanner, ConfirmDialog, LogView, Avatar, SectionLabel, Collapsible,
// Skeleton, StatusPill, BrandMark.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import 'brand.dart';

export 'brand.dart';
export 'motion.dart';

/// Lemniscate-bloom loader — the Desktop Loader's long-operation curve.
class NvLoader extends StatefulWidget {
  const NvLoader({super.key, this.size = 28, this.label});
  final double size;
  final String? label;
  @override
  State<NvLoader> createState() => _NvLoaderState();
}

class _NvLoaderState extends State<NvLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.cs.primary;
    final loader = SizedBox(
      width: widget.size * 1.6,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(painter: _LemniscatePainter(_c.value, color)),
      ),
    );
    if (widget.label == null) return loader;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      loader,
      const SizedBox(height: 10),
      Text(widget.label!, style: context.tt.bodySmall),
    ]);
  }
}

class _LemniscatePainter extends CustomPainter {
  _LemniscatePainter(this.t, this.color);
  final double t;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final a = size.width / 2.2;
    Offset at(double th) {
      final s = math.sin(th), c = math.cos(th);
      final d = 1 + s * s;
      return Offset(cx + a * c / d, cy + a * s * c / d);
    }

    final path = Path();
    for (var i = 0; i <= 120; i++) {
      final th = i / 120 * 2 * math.pi;
      final p = at(th);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = color.withValues(alpha: 0.18));
    const trail = 26;
    for (var i = 0; i < trail; i++) {
      final th = (t * 2 * math.pi) - i * 0.07;
      final p = at(th);
      final k = 1 - i / trail;
      canvas.drawCircle(p, 2.4 * k + 0.6, Paint()..color = color.withValues(alpha: k));
    }
  }

  @override
  bool shouldRepaint(_LemniscatePainter old) => old.t != t || old.color != color;
}

class CenterLoader extends StatelessWidget {
  const CenterLoader({super.key, this.label});
  final String? label;
  @override
  Widget build(BuildContext context) => Center(child: NvLoader(size: 30, label: label));
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.body, this.action});
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            HalftoneBackdrop(
              reach: 0.75,
              child: Padding(
                padding: EdgeInsets.all(context.hc.brand ? 22 : 0),
                child: Icon(icon, size: 40, color: context.hc.mutedForeground.withValues(alpha: context.hc.brand ? 0.95 : 0.7)),
              ),
            ),
            const SizedBox(height: 14),
            Text(title, style: context.tt.titleSmall, textAlign: TextAlign.center),
            if (body != null) ...[
              const SizedBox(height: 6),
              Text(body!, style: context.tt.bodySmall, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

/// The one error look: icon without a chip, message, optional actions.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key, this.onRetry, this.dense = false});
  final String message;
  final VoidCallback? onRetry;
  final bool dense;
  @override
  Widget build(BuildContext context) {
    final c = context.hc.destructive;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 8 : 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        border: Border(left: BorderSide(color: c, width: 2)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(Icons.error_outline, size: 18, color: c)),
        const SizedBox(width: 10),
        Expanded(child: SelectableText(message, style: TextStyle(color: context.cs.onSurface, fontSize: 13))),
        if (onRetry != null)
          TextButton(onPressed: onRetry, style: TextButton.styleFrom(visualDensity: VisualDensity.compact), child: const Text('Coba lagi')),
      ]),
    );
  }
}

class NoteBanner extends StatelessWidget {
  const NoteBanner(this.message, {super.key, this.ok = false, this.icon});
  final String message;
  final bool ok;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final c = ok ? context.hc.success : context.hc.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.08), border: Border(left: BorderSide(color: c, width: 2))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon ?? (ok ? Icons.check_circle_outline : Icons.info_outline), size: 18, color: c),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}

/// The only way to ask "are you sure": focused on Confirm, owns its pending beat.
Future<bool> confirmDialog(BuildContext context,
    {required String title, required String body, String confirm = 'Ya', bool destructive = false}) async {
  final r = await showPaperDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: DialogTheme.of(ctx).titleTextStyle ?? ctx.tt.titleMedium),
      content: Text(body, style: ctx.tt.bodyMedium),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        FilledButton(
          autofocus: true,
          style: destructive ? FilledButton.styleFrom(backgroundColor: ctx.hc.destructive, foregroundColor: ctx.cs.onError) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r == true;
}

Future<String?> promptText(BuildContext context,
    {required String title, String initial = '', String hint = '', String confirm = 'Simpan', int maxLines = 1}) {
  final ctl = TextEditingController(text: initial);
  return showPaperDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: ctx.tt.titleMedium),
      content: TextField(
        controller: ctl,
        autofocus: true,
        maxLines: maxLines,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: maxLines == 1 ? (v) => Navigator.pop(ctx, v) : null,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: Text(confirm)),
      ],
    ),
  );
}

/// Raw log output: no fill, hairline border, small mono.
class LogView extends StatelessWidget {
  const LogView(this.text, {super.key, this.maxHeight = 260, this.empty = 'log masih kosong'});
  final String text;
  final double maxHeight;
  final String empty;
  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(empty, style: context.tt.bodySmall));
    }
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: context.hc.strokeSoft),
        borderRadius: BorderRadius.circular(6),
        color: context.hc.codeBg,
      ),
      child: Stack(children: [
        SingleChildScrollView(
          reverse: true,
          padding: const EdgeInsets.fromLTRB(10, 8, 34, 8),
          child: SelectableText(text, style: monoStyle(context, size: 11.5, color: context.cs.onSurface.withValues(alpha: 0.88))),
        ),
        Positioned(
          right: 2,
          top: 2,
          child: IconButton(
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            tooltip: 'Salin',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Disalin'), duration: Duration(seconds: 1)));
            },
          ),
        ),
      ]),
    );
  }
}

int nameHue(String name) {
  var h = 0;
  for (final c in name.codeUnits) {
    h = (h * 31 + c) % 360;
  }
  return h;
}

String initials(String name) {
  final clean = name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  return (clean.isEmpty ? '?' : clean.substring(0, math.min(2, clean.length))).toUpperCase();
}

Color avatarColor(String name, Brightness b) =>
    HSLColor.fromAHSL(1, nameHue(name).toDouble(), b == Brightness.dark ? 0.42 : 0.5, b == Brightness.dark ? 0.34 : 0.46).toColor();

class AgentAvatar extends StatelessWidget {
  const AgentAvatar(this.name, {super.key, this.size = 32, this.status});
  final String name;
  final double size;
  final String? status;
  @override
  Widget build(BuildContext context) {
    final av = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: avatarColor(name, Theme.of(context).brightness), borderRadius: BorderRadius.circular(size * 0.3)),
      child: Text(initials(name),
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.36, letterSpacing: 0.3)),
    );
    if (status == null) return av;
    return Stack(clipBehavior: Clip.none, children: [
      av,
      Positioned(
        right: -2,
        bottom: -2,
        child: Container(
          width: size * 0.34,
          height: size * 0.34,
          decoration: BoxDecoration(
            color: statusColor(context, status!),
            shape: BoxShape.circle,
            border: Border.all(color: context.cs.surface, width: 2),
          ),
        ),
      ),
    ]);
  }
}

Color statusColor(BuildContext context, String status) {
  final hc = context.hc;
  switch (status) {
    case 'working':
    case 'running':
      return hc.success;
    case 'review':
      return hc.info;
    case 'blocked':
    case 'error':
    case 'failed':
      return hc.destructive;
    case 'meeting':
      return hc.warning;
    case 'done':
    case 'success':
    case 'completed':
      return hc.success.withValues(alpha: 0.6);
    default:
      return hc.mutedForeground;
  }
}

const agentStatusLabel = {
  'idle': 'santai',
  'working': 'bekerja',
  'review': 'review',
  'blocked': 'terhambat',
  'meeting': 'rapat',
  'done': 'selesai',
};

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.color, this.mono = false});
  final String label;
  final Color? color;
  final bool mono;
  @override
  Widget build(BuildContext context) {
    final c = color ?? context.hc.mutedForeground;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style: mono
              ? monoStyle(context, size: 10.5, color: c, weight: FontWeight.w600)
              : TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600, height: 1.3)),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(16, 18, 16, 8)});
  final String text;
  final Widget? trailing;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [
          Expanded(child: Text(text.toUpperCase(), style: context.tt.labelSmall?.copyWith(fontWeight: FontWeight.w600))),
          ?trailing,
        ]),
      );
}

class KeyValue extends StatelessWidget {
  const KeyValue(this.k, this.v, {super.key, this.mono = false});
  final String k;
  final String v;
  final bool mono;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 104, child: Text(k, style: context.tt.bodySmall)),
          Expanded(
            child: SelectableText(v,
                style: mono ? monoStyle(context, size: 12.5) : const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
          ),
        ]),
      );
}

/// A labelled block hidden behind a toggle (Collapsible.tsx).
class Collapsible extends StatefulWidget {
  const Collapsible({super.key, required this.label, this.text, this.child, this.count, this.initiallyOpen = false, this.empty});
  final String label;
  final String? text;
  final Widget? child;
  final int? count;
  final bool initiallyOpen;
  final String? empty;
  @override
  State<Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<Collapsible> {
  late bool open = widget.initiallyOpen;
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => setState(() => open = !open),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            AnimatedRotation(
              turns: open ? 0.25 : 0,
              duration: const Duration(milliseconds: 120),
              child: Icon(Icons.chevron_right, size: 18, color: context.hc.mutedForeground),
            ),
            const SizedBox(width: 4),
            Text(widget.label, style: context.tt.titleSmall),
            if (widget.count != null) ...[
              const SizedBox(width: 8),
              StatusPill('${widget.count}'),
            ],
            const Spacer(),
            Text(open ? 'sembunyikan' : 'tampilkan', style: context.tt.bodySmall),
          ]),
        ),
      ),
      if (open)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: widget.child ?? LogView(widget.text ?? '', empty: widget.empty ?? 'kosong'),
        ),
    ]);
  }
}

class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 14, this.width, this.radius = 4});
  final double height;
  final double? width;
  final double radius;
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: Color.lerp(context.hc.muted, context.hc.border, _c.value * 0.6),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      );
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 5, this.itemHeight = 64});
  final int count;
  final double itemHeight;
  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => Row(children: [
          const Skeleton(height: 36, width: 36, radius: 10),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Skeleton(height: 13, width: 120 + (i * 37 % 90).toDouble()),
              const SizedBox(height: 8),
              const Skeleton(height: 11),
            ]),
          ),
        ]),
      );
}

/// Brand glyph on a fixed tile (white in light, #0d1117 in dark) — the
/// caduceus ☤ stands in for Desktop's nous-girl mark.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});
  /// Badge height; the badge is 40:56, so it is narrower than tall.
  final double size;
  @override
  Widget build(BuildContext context) => BrandBadge(height: size);
}

String relTime(String iso, {bool future = false}) {
  final t = DateTime.tryParse(iso);
  if (t == null) return iso.isEmpty ? '' : iso;
  final diff = t.difference(DateTime.now());
  final abs = diff.abs();
  final mins = abs.inMinutes;
  final label = abs.inSeconds < 60
      ? 'sekarang'
      : mins < 60
          ? '$mins mnt'
          : abs.inHours < 24
              ? '${abs.inHours} jam'
              : '${abs.inDays} hari';
  if (label == 'sekarang') return future ? 'sekarang' : 'baru saja';
  return diff.isNegative ? '$label lalu' : 'dalam $label';
}

String clockOf(int ts) {
  if (ts <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

void toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
