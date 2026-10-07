// Session history: list, search, rename, delete, group by project, filter
// by profile. Drawer on phones, left column on wide screens.
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/chat_engine.dart';
import '../../../models/models.dart';
import '../../../state/app_controller.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/common.dart';

class SessionsPanel extends ConsumerStatefulWidget {
  const SessionsPanel({super.key, this.onPicked});
  final VoidCallback? onPicked;
  @override
  ConsumerState<SessionsPanel> createState() => _SessionsPanelState();
}

class _SessionsPanelState extends ConsumerState<SessionsPanel> {
  String query = '';
  String? profileFilter;
  bool groupByProject = false;

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    final store = ref.watch(storeProvider);
    final settings = ref.watch(settingsProvider);
    final local = chat.engine is LocalChatEngine;
    final perAgent = chat.engine.perAgentThreads;
    var list = chat.sessions.where((s) {
      if (profileFilter != null && s.profile != profileFilter) return false;
      if (query.isEmpty) return true;
      final q = query.toLowerCase();
      return s.title.toLowerCase().contains(q) || s.id.toLowerCase().contains(q) || s.preview.toLowerCase().contains(q);
    }).toList();
    final profiles = local ? store.profiles.where((p) => !p.hidden).map((p) => p.name).toList() : <String>[];

    Widget tile(ChatSessionInfo s) {
      final selected = chat.current?.id == s.id;
      return Material(
        color: selected ? context.cs.secondaryContainer.withValues(alpha: 0.7) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            chat.open(s);
            widget.onPicked?.call();
          },
          onLongPress: perAgent ? null : () => _menu(s),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(children: [
              AgentAvatar(s.profile, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.title.isEmpty ? '(tanpa judul)' : s.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(
                    [if (!perAgent) s.profile, if (s.updatedAt.isNotEmpty) relTime(s.updatedAt), if (s.messageCount > 0) '${s.messageCount} pesan']
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.tt.bodySmall?.copyWith(fontSize: 11.5),
                  ),
                ]),
              ),
              if (!perAgent)
                IconButton(
                  icon: const Icon(Icons.more_horiz, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _menu(s),
                ),
            ]),
          ),
        ),
      );
    }

    final children = <Widget>[];
    if (groupByProject && local) {
      final byProject = <String?, List<ChatSessionInfo>>{};
      for (final s in list) {
        byProject.putIfAbsent(s.projectId, () => []).add(s);
      }
      for (final p in store.projects) {
        final items = byProject[p.id] ?? [];
        children.add(SectionLabel('${p.name} (${items.length})', padding: const EdgeInsets.fromLTRB(12, 14, 12, 4)));
        if (items.isEmpty) {
          children.add(Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 4), child: Text('belum ada sesi', style: context.tt.bodySmall)));
        }
        children.addAll(items.map(tile));
      }
      final loose = byProject[null] ?? [];
      if (loose.isNotEmpty) {
        children.add(SectionLabel('Tanpa proyek (${loose.length})', padding: const EdgeInsets.fromLTRB(12, 14, 12, 4)));
        children.addAll(loose.map(tile));
      }
    } else {
      children.addAll(list.map(tile));
    }

    return Container(
      color: context.hc.sidebar,
      child: SafeArea(
        right: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
            child: Row(children: [
              const BrandMark(size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Neovarch', style: context.tt.titleMedium),
                  Text(ref.read(appProvider).mode.label, style: context.tt.bodySmall?.copyWith(fontSize: 11)),
                ]),
              ),
              IconButton(
                tooltip: 'Muat ulang',
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: chat.loadSessions,
              ),
            ]),
          ),
          if (chat.engine.canCreate && !perAgent)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: FilledButton.icon(
                onPressed: () async {
                  await chat.newSession(profile: profileFilter ?? settings.defaultProfile);
                  widget.onPicked?.call();
                },
                icon: const Icon(Icons.edit_square, size: 18),
                label: const Text('Percakapan baru'),
              ),
            ),
          // SearchField: borderless, underline on focus. Hidden on empty lists.
          if (chat.sessions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: TextField(
                onChanged: (v) => setState(() => query = v),
                decoration: InputDecoration(
                  hintText: 'Cari sesi (judul atau id)',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: context.cs.primary)),
                ),
              ),
            ),
          if (local && profiles.length > 1)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: const Text('Semua'),
                      selected: profileFilter == null,
                      onSelected: (_) => setState(() => profileFilter = null),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  for (final p in profiles)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(p),
                        selected: profileFilter == p,
                        onSelected: (_) => setState(() => profileFilter = profileFilter == p ? null : p),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ),
          if (local)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 8, 0),
              child: Row(children: [
                Text('Kelompokkan per proyek', style: context.tt.bodySmall),
                const Spacer(),
                Switch(value: groupByProject, onChanged: (v) => setState(() => groupByProject = v)),
              ]),
            ),
          if (chat.listError != null) ErrorBanner(chat.listError!, onRetry: chat.loadSessions, dense: true),
          Expanded(
            child: chat.listLoading && chat.sessions.isEmpty
                ? const SkeletonList(count: 6)
                : children.isEmpty
                    ? EmptyState(
                        icon: Icons.forum_outlined,
                        title: query.isEmpty ? 'Belum ada percakapan' : 'Tidak ada yang cocok',
                        body: query.isEmpty ? 'Mulai percakapan baru dengan agent.' : null,
                      )
                    : ListView(padding: const EdgeInsets.fromLTRB(6, 4, 6, 12), children: children),
          ),
        ]),
      ),
    );
  }

  Future<void> _menu(ChatSessionInfo s) async {
    final chat = ref.read(chatProvider);
    final store = ref.read(storeProvider);
    final local = chat.engine is LocalChatEngine;
    final action = await showPaperSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ctx.tt.titleSmall), subtitle: Text(s.id, style: monoStyle(ctx, size: 11))),
          if (chat.engine.canRename) ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Ganti nama'), onTap: () => Navigator.pop(ctx, 'rename')),
          if (local) ListTile(leading: const Icon(Icons.folder_outlined), title: const Text('Pindahkan ke proyek'), onTap: () => Navigator.pop(ctx, 'project')),
          ListTile(
            leading: Icon(Icons.delete_outline, color: ctx.hc.destructive),
            title: Text('Hapus', style: TextStyle(color: ctx.hc.destructive)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ]),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'rename':
        final t = await promptText(context, title: 'Ganti nama sesi', initial: s.title);
        if (t != null && t.trim().isNotEmpty) {
          final err = await chat.rename(s, t.trim());
          if (err != null && mounted) toast(context, err);
        }
      case 'project':
        final pick = await showPaperSheet<String>(
          context: context,
          builder: (ctx) => SafeArea(
            child: ListView(shrinkWrap: true, children: [
              ListTile(leading: const Icon(Icons.block), title: const Text('Tanpa proyek'), onTap: () => Navigator.pop(ctx, '')),
              for (final p in store.projects)
                ListTile(leading: const Icon(Icons.folder_outlined), title: Text(p.name), onTap: () => Navigator.pop(ctx, p.id)),
              if (store.projects.isEmpty)
                const ListTile(title: Text('Belum ada proyek — buat di Lainnya → Proyek')),
            ]),
          ),
        );
        if (pick != null) await chat.setProject(s, pick.isEmpty ? null : pick);
      case 'delete':
        if (await confirmDialog(context,
            title: 'Hapus percakapan?',
            body: local
                ? 'Transkrip "${s.title}" dihapus dari perangkat ini.'
                : 'Sesi dihapus di backend yang terhubung.',
            confirm: 'Hapus',
            destructive: true)) {
          final err = await chat.delete(s);
          if (err != null && mounted) toast(context, 'Gagal menghapus: $err');
        }
    }
  }
}
