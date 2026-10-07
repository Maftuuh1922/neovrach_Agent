// Appearance — Hermes Desktop's theme presets (Nous, Nous Alt, GitHub,
// Classic Hermes, Catppuccin, Everforest, Solarized, Midnight, Ember, Mono,
// Cyberpunk, Slate) plus "Kantor Hermes"; color mode; font; chat text size.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/app_controller.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/hermes_themes.dart';

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: Text('Tampilan', style: context.tt.titleMedium)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('MODE WARNA', style: context.tt.labelSmall),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('Sistem'), icon: Icon(Icons.brightness_auto_outlined, size: 18)),
            ButtonSegment(value: ThemeMode.light, label: Text('Terang'), icon: Icon(Icons.light_mode_outlined, size: 18)),
            ButtonSegment(value: ThemeMode.dark, label: Text('Gelap'), icon: Icon(Icons.dark_mode_outlined, size: 18)),
          ],
          selected: {s.themeMode},
          onSelectionChanged: (v) => s.update((x) => x.themeMode = v.first),
        ),
        if (themeByName(s.themeName).darkOnly)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('Tema ini khusus gelap.', style: context.tt.bodySmall)),
        const SizedBox(height: 20),
        Text('TEMA', style: context.tt.labelSmall),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.25,
          children: [
            for (final t in hermesThemes) _ThemeCard(theme: t, selected: s.themeName == t.name, dark: dark, onTap: () => s.update((x) => x.themeName = t.name)),
          ],
        ),
        const SizedBox(height: 20),
        Text('HURUF', style: context.tt.labelSmall),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: s.fontChoice,
          items: const [
            DropdownMenuItem(value: 'tema', child: Text('Ikuti tema')),
            DropdownMenuItem(value: 'inter', child: Text('Inter')),
            DropdownMenuItem(value: 'system', child: Text('Huruf sistem')),
            DropdownMenuItem(value: 'courierPrime', child: Text('Courier Prime')),
            DropdownMenuItem(value: 'plexMono', child: Text('IBM Plex Mono')),
            DropdownMenuItem(value: 'barlow', child: Text('Barlow')),
          ],
          onChanged: (v) => s.update((x) => x.fontChoice = v ?? 'tema'),
        ),
        const SizedBox(height: 20),
        Text('UKURAN TEKS CHAT · ${(s.chatScale * 100).round()}%', style: context.tt.labelSmall),
        Slider(value: s.chatScale, min: 0.85, max: 1.4, divisions: 11, onChanged: (v) => s.update((x) => x.chatScale = v)),
      ]),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.theme, required this.selected, required this.dark, required this.onTap});
  final HermesTheme theme;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = theme.palette(dark ? Brightness.dark : Brightness.light);
    return Material(
      color: p.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: selected ? context.cs.primary : p.border, width: selected ? 2 : 1)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              for (final c in [p.primary, p.secondary, p.userBubble, p.mutedForeground])
                Container(width: 14, height: 14, margin: const EdgeInsets.only(right: 4), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
              const Spacer(),
              if (selected) Icon(Icons.check_circle, size: 18, color: p.primary),
            ]),
            const Spacer(),
            Container(height: 8, width: 70, decoration: BoxDecoration(color: p.userBubble, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 4),
            Container(height: 6, width: 100, decoration: BoxDecoration(color: p.muted, borderRadius: BorderRadius.circular(3))),
            const SizedBox(height: 8),
            Text(theme.label, style: TextStyle(color: p.foreground, fontWeight: FontWeight.w600, fontSize: 13)),
            Text(theme.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.mutedForeground, fontSize: 10.5)),
          ]),
        ),
      ),
    );
  }
}
