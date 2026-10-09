// 1.4.4: top of the Profil tab, GitHub-profile style: photo + name/@login +
// bio, the contribution graph (green, last ~12 months, scrolls sideways on
// narrow phones) and the tech stack as logo chips.
//
// Source: the PC's GitHub sign-in (`/api/social/profile`) when the PC has one;
// otherwise the public profile of a username set here
// ([GithubPublicController], no token, cached for offline).
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/neovarch_mobile_theme.dart';
import '../github_public.dart';
import '../remote_controller.dart';
import '../social_models.dart';
import 'nv_widgets.dart';
import 'remote_social_screen.dart' show NvAvatar, CodingChip;
import 'tech_logo.dart' show TechStackChips;

class ProfileHeaderSlot extends ConsumerStatefulWidget {
  const ProfileHeaderSlot({super.key, this.autoLoad = true});

  /// Tests: skip the initial refresh from the PC / GitHub.
  final bool autoLoad;

  @override
  ConsumerState<ProfileHeaderSlot> createState() => _ProfileHeaderSlotState();
}

class _ProfileHeaderSlotState extends ConsumerState<ProfileHeaderSlot> {
  @override
  void initState() {
    super.initState();
    if (!widget.autoLoad) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final r = ref.read(remoteProvider);
      if (r.connected) await r.refreshSocial();
      if (!mounted) return;
      final gh = ref.read(githubPublicProvider);
      await gh.load();
      final stale = gh.fetchedAt == null || DateTime.now().difference(gh.fetchedAt!) > const Duration(hours: 6);
      if (!ref.read(remoteProvider).socialSignedIn && gh.login != null && stale) await gh.refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(remoteProvider);
    final gh = ref.watch(githubPublicProvider);
    final fromPc = r.socialSignedIn && r.socialProfile != null;
    final p = fromPc ? r.socialProfile : gh.profile;
    return Padding(
      key: const ValueKey('profile-header-slot'),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (p == null)
          GithubConnectCard(loading: gh.loading || r.socialLoading, error: gh.error, initial: gh.login)
        else ...[
          GithubHeader(profile: p, source: fromPc ? 'lewat PC' : 'publik', onEdit: fromPc ? null : () => showGithubLoginSheet(context, gh.login)),
          if (!fromPc && gh.error != null) ...[
            const SizedBox(height: 8),
            Text(gh.error!, key: const ValueKey('github-offline'), style: TextStyle(fontSize: 12, color: NV.muted)),
          ],
          const SizedBox(height: 12),
          ContributionGraphCard(heatmap: p.heatmap),
          if (p.languages.isNotEmpty) ...[
            const SizedBox(height: 12),
            NvPanel(
              key: const ValueKey('profile-stack'),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('TECH STACK', style: NV.monoLabel(size: 9.5)),
                const SizedBox(height: 10),
                TechStackChips(items: p.languages.take(10).toList()),
              ]),
            ),
          ],
        ],
      ]),
    );
  }
}

/// Photo, name, @login, bio, coding status.
class GithubHeader extends StatelessWidget {
  const GithubHeader({super.key, required this.profile, required this.source, this.onEdit});
  final SocialProfile profile;
  final String source;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) {
    final p = profile;
    return Padding(
      key: const ValueKey('github-header'),
      padding: const EdgeInsets.only(top: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: NV.red, width: 2)),
          child: NvAvatar(name: p.displayName, url: p.avatarUrl ?? (p.login == null ? null : 'https://github.com/${p.login}.png?size=160'), size: 68),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.displayName, key: const ValueKey('github-name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: NV.display(size: 26)),
            if (p.login != null)
              Text('@${p.login} · $source', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: NV.mono, fontSize: 12, color: NV.muted)),
            if (p.bio.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(p.bio, key: const ValueKey('github-bio'), maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: NV.text, height: 1.35)),
            ],
            if (p.status != null) ...[const SizedBox(height: 8), CodingChip(status: p.status)],
          ]),
        ),
        if (onEdit != null)
          IconButton(
            key: const ValueKey('github-edit'),
            tooltip: 'Ganti akun GitHub',
            onPressed: onEdit,
            icon: Icon(CupertinoIcons.pencil, size: 18, color: NV.muted),
          ),
      ]),
    );
  }
}

/// No profile yet: ask for a GitHub username (or point at the PC sign-in).
class GithubConnectCard extends ConsumerStatefulWidget {
  const GithubConnectCard({super.key, this.loading = false, this.error, this.initial});
  final bool loading;
  final String? error;
  final String? initial;
  @override
  ConsumerState<GithubConnectCard> createState() => _GithubConnectCardState();
}

class _GithubConnectCardState extends ConsumerState<GithubConnectCard> {
  late final _c = TextEditingController(text: widget.initial ?? '');
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NvPanel(
        key: const ValueKey('github-connect'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Profil GitHub', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: NV.text)),
          const SizedBox(height: 4),
          Text('Masukkan username GitHub untuk foto, grafik kontribusi, dan stack. Atau masuk GitHub di Neovarch PC.',
              style: TextStyle(fontSize: 13, color: NV.muted, height: 1.4)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey('github-login-field'),
                controller: _c,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: const InputDecoration(hintText: 'username', prefixText: '@', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const ValueKey('github-login-save'),
              onPressed: widget.loading ? null : _save,
              child: Text(widget.loading ? 'Memuat…' : 'Simpan'),
            ),
          ]),
          if (widget.error != null) ...[
            const SizedBox(height: 8),
            Text(widget.error!, style: TextStyle(fontSize: 12.5, color: NV.text)),
          ],
        ]),
      );

  void _save() => ref.read(githubPublicProvider).setLogin(_c.text);
}

Future<void> showGithubLoginSheet(BuildContext context, String? current) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          NvSheetTitle(kicker: 'profil', title: 'Akun GitHub'),
          const SizedBox(height: 12),
          GithubConnectCard(initial: current),
          const SizedBox(height: 8),
          Consumer(
            builder: (context, ref, _) => TextButton(
              key: const ValueKey('github-clear'),
              onPressed: () {
                ref.read(githubPublicProvider).setLogin(null);
                Navigator.pop(ctx);
              },
              child: const Text('Hapus akun dari HP ini'),
            ),
          ),
        ]),
      ),
    );

/// GitHub's green levels (light and dark site themes).
Color contributionColor(int level, {required bool dark}) {
  const lightC = [Color(0xFFEBEDF0), Color(0xFF9BE9A8), Color(0xFF40C463), Color(0xFF30A14E), Color(0xFF216E39)];
  const darkC = [Color(0xFF2D333B), Color(0xFF0E4429), Color(0xFF006D32), Color(0xFF26A641), Color(0xFF39D353)];
  return (dark ? darkC : lightC)[level.clamp(0, 4)];
}

const _monthsId = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

/// The contribution graph card: month labels, 7 x ~53 green cells (fixed
/// cell size, scrolls sideways and opens on the latest weeks), totals.
class ContributionGraphCard extends StatelessWidget {
  const ContributionGraphCard({super.key, required this.heatmap, this.cell = 11, this.gap = 3});
  final SocialHeatmap? heatmap;
  final double cell, gap;

  @override
  Widget build(BuildContext context) {
    final h = heatmap;
    final dark = NV.palette.dark;
    return NvPanel(
      key: const ValueKey('contribution-card'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('KONTRIBUSI 12 BULAN', style: NV.monoLabel(size: 9.5))),
          if (h != null) Text('${h.total} kontribusi', style: NV.monoLabel(size: 9.5, color: NV.text)),
        ]),
        const SizedBox(height: 10),
        if (h == null || h.counts.isEmpty)
          Text('Grafik kontribusi belum tersedia.', style: TextStyle(fontSize: 13, color: NV.muted))
        else ...[
          SingleChildScrollView(
            key: const ValueKey('contribution-scroll'),
            scrollDirection: Axis.horizontal,
            reverse: true, // open on the most recent weeks
            child: _Graph(heatmap: h, cell: cell, gap: gap, dark: dark),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Text('${h.activeDays} hari aktif · streak ${h.streak} hari',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: NV.monoLabel(size: 9, color: NV.muted)),
            ),
            Text('sedikit ', style: NV.monoLabel(size: 9, color: NV.muted)),
            for (var l = 0; l <= 4; l++)
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(left: 2),
                decoration: BoxDecoration(color: contributionColor(l, dark: dark), borderRadius: BorderRadius.circular(2)),
              ),
            Text(' banyak', style: NV.monoLabel(size: 9, color: NV.muted)),
          ]),
        ],
      ]),
    );
  }
}

class _Graph extends StatelessWidget {
  const _Graph({required this.heatmap, required this.cell, required this.gap, required this.dark});
  final SocialHeatmap heatmap;
  final double cell, gap;
  final bool dark;
  @override
  Widget build(BuildContext context) {
    final weeks = heatmap.weeks();
    final w = weeks.length * (cell + gap) - gap;
    final start = DateTime.tryParse(heatmap.start);
    final labels = <(double, String)>[];
    if (start != null) {
      final first = start.subtract(Duration(days: start.weekday % 7));
      var lastMonth = -1;
      for (var i = 0; i < weeks.length; i++) {
        final d = first.add(Duration(days: i * 7));
        if (d.month != lastMonth) {
          if (lastMonth != -1 || d.day <= 7) labels.add((i * (cell + gap), _monthsId[d.month - 1]));
          lastMonth = d.month;
        }
      }
    }
    final h = 7 * (cell + gap) - gap;
    return SizedBox(
      width: w,
      height: h + 16,
      child: Stack(children: [
        for (final (x, m) in labels) Positioned(left: x, top: 0, child: Text(m, style: NV.monoLabel(size: 9, color: NV.muted))),
        Positioned(
          left: 0,
          top: 16,
          child: CustomPaint(
            key: const ValueKey('contribution-graph'),
            size: Size(w, h),
            painter: ContributionPainter(weeks: weeks, max: heatmap.max, cell: cell, gap: gap, dark: dark),
          ),
        ),
      ]),
    );
  }
}

class ContributionPainter extends CustomPainter {
  ContributionPainter({required this.weeks, required this.max, required this.cell, required this.gap, required this.dark});
  final List<List<int>> weeks;
  final int max;
  final double cell, gap;
  final bool dark;

  /// Levels as GitHub draws them; [max] <= 4 means the counts already are levels.
  int levelOf(int v) => max <= 4 ? v.clamp(0, 4) : SocialHeatmap.level(v, max);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final r = Radius.circular(cell * 0.22);
    for (var w = 0; w < weeks.length; w++) {
      for (var d = 0; d < 7; d++) {
        final v = weeks[w][d];
        if (v < 0) continue;
        paint.color = contributionColor(levelOf(v), dark: dark);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * (cell + gap), d * (cell + gap), cell, cell), r), paint);
      }
    }
  }

  @override
  bool shouldRepaint(ContributionPainter old) => old.weeks != weeks || old.max != max || old.dark != dark || old.cell != cell;
}
