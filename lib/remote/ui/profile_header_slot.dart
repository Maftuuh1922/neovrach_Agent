// 1.4.4: top of the Profil tab, GitHub-profile style: photo + name/@login +
// bio, the contribution graph (theme accent, last ~12 months, scrolls sideways on
// narrow phones), the pinned repositories and the tech stack as logo chips.
//
// Source: the PC's GitHub sign-in (`/api/social/profile`) when the PC has one;
// otherwise the public profile of a username set here
// ([GithubPublicController], no token, cached for offline).
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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
          if (p.pinned.isNotEmpty) ...[
            const SizedBox(height: 12),
            PinnedReposCard(repos: p.pinned),
          ],
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

/// Contribution levels 0..4 in the active theme accent: the empty cell is a
/// faint text tint over the card, levels 1-4 the accent at 25/45/70/100%
/// over that empty colour (works for every accent, light and dark).
Color contributionColor(int level, {NvPalette? palette}) {
  final p = palette ?? NV.palette;
  final empty = Color.lerp(p.dark ? p.raised : p.bg, p.text, p.dark ? 0.08 : 0.09)!;
  const alphas = [0.0, 0.25, 0.45, 0.70, 1.0];
  final l = level.clamp(0, 4);
  if (l == 0) return empty;
  return Color.alphaBlend(p.accent.withValues(alpha: alphas[l]), empty);
}

/// Pinned repositories as GitHub shows them: name, description, language
/// dot + name, stars, forks; a tap opens the repo.
class PinnedReposCard extends StatelessWidget {
  const PinnedReposCard({super.key, required this.repos, this.onOpen});
  final List<PinnedRepo> repos;

  /// Test seam; defaults to opening the URL in the browser / GitHub app.
  final void Function(String url)? onOpen;

  @override
  Widget build(BuildContext context) => NvPanel(
        key: const ValueKey('profile-pinned'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('REPO DISEMATKAN', style: NV.monoLabel(size: 9.5))),
            Text('${repos.length}', style: NV.monoLabel(size: 9.5, color: NV.text)),
          ]),
          const SizedBox(height: 6),
          for (var i = 0; i < repos.length && i < 6; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: NV.glassBorder),
            _PinnedTile(repo: repos[i], onOpen: onOpen),
          ],
        ]),
      );
}

class _PinnedTile extends StatelessWidget {
  const _PinnedTile({required this.repo, this.onOpen});
  final PinnedRepo repo;
  final void Function(String url)? onOpen;
  @override
  Widget build(BuildContext context) {
    final r = repo;
    final dot = r.languageArgb == null ? NV.red : Color(r.languageArgb!);
    final meta = NV.monoLabel(size: 10, color: NV.muted);
    return InkWell(
      key: ValueKey('pinned-${r.name}'),
      borderRadius: BorderRadius.circular(10),
      onTap: r.url.isEmpty ? null : () => onOpen != null ? onOpen!(r.url) : launchUrl(Uri.parse(r.url), mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(CupertinoIcons.book, size: 15, color: NV.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: NV.redInk)),
            ),
            Icon(CupertinoIcons.arrow_up_right, size: 13, color: NV.faint),
          ]),
          if (r.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(r.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: NV.muted, height: 1.35)),
          ],
          const SizedBox(height: 6),
          Row(children: [
            if (r.language != null) ...[
              Container(width: 9, height: 9, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Flexible(child: Text(r.language!, maxLines: 1, overflow: TextOverflow.ellipsis, style: meta)),
              const SizedBox(width: 14),
            ],
            Icon(CupertinoIcons.star, size: 12, color: NV.muted),
            const SizedBox(width: 3),
            Text('${r.stars}', style: meta),
            const SizedBox(width: 12),
            Icon(CupertinoIcons.arrow_branch, size: 12, color: NV.muted),
            const SizedBox(width: 3),
            Text('${r.forks}', style: meta),
          ]),
        ]),
      ),
    );
  }
}

const _monthsId = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

/// The contribution graph card: month labels, 7 x ~53 accent cells (fixed
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
                decoration: BoxDecoration(color: contributionColor(l), borderRadius: BorderRadius.circular(2)),
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
  ContributionPainter({required this.weeks, required this.max, required this.cell, required this.gap, required this.dark, NvPalette? palette}) : palette = palette ?? NV.palette;
  final List<List<int>> weeks;
  final int max;
  final double cell, gap;
  final bool dark;
  final NvPalette palette;

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
        paint.color = contributionColor(levelOf(v), palette: palette);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * (cell + gap), d * (cell + gap), cell, cell), r), paint);
      }
    }
  }

  @override
  bool shouldRepaint(ContributionPainter old) => old.weeks != weeks || old.max != max || old.dark != dark || old.cell != cell || old.palette != palette;
}
