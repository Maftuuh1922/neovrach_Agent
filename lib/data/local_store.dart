// Everything the on-device agent owns, persisted through KvStore:
// profiles, chat sessions + transcripts, memory notes, skills, projects,
// the local Kanban board, task logs/runs, cron jobs/runs, archived meetings
// and the workspace file tree the agent reads and writes.
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'kv_store.dart';

class WorkspaceFile {
  final String path;
  final String content;
  final String updatedAt;
  const WorkspaceFile(this.path, this.content, this.updatedAt);
  int get size => content.length;
  String get name => path.split('/').last;
  Map<String, dynamic> toJson() => {'content': content, 'updatedAt': updatedAt};
}

String normPath(String p) {
  var s = p.trim().replaceAll('\\', '/');
  s = s.replaceAll(RegExp(r'^\./'), '').replaceAll(RegExp(r'^/+'), '');
  final parts = <String>[];
  for (final seg in s.split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      if (parts.isNotEmpty) parts.removeLast(); // never climb out of the workspace
      continue;
    }
    parts.add(seg);
  }
  return parts.join('/');
}

class LocalStore extends ChangeNotifier {
  LocalStore(this.kv);
  final KvStore kv;
  final _rnd = Random();

  List<Profile> profiles = [];
  List<ChatSessionInfo> sessions = [];
  List<MemoryNote> memory = [];
  List<Skill> skills = [];
  List<Project> projects = [];
  List<Task> tasks = [];
  Map<String, List<String>> logs = {};
  Map<String, List<Map<String, dynamic>>> runs = {};
  List<CronJob> jobs = [];
  List<CronRun> cronRuns = [];
  List<ArchivedMeeting> archived = [];
  Map<String, String> bodies = {};
  Map<String, WorkspaceFile> files = {};
  Set<String> folders = {};

  void touch() => notifyListeners();

  String uid(String p) =>
      '$p${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_rnd.nextInt(1 << 20).toRadixString(36)}';

  Future<void> load() async {
    profiles = (await kv.getList('profiles')).map(Profile.fromJson).toList();
    if (profiles.isEmpty) {
      profiles = [
        const Profile(
          name: 'neovarch',
          role: 'orchestrator',
          description: 'Agen utama serba bisa',
          systemPrompt:
              'Kamu Neovarch, agen orkestrator serba bisa di ponsel pengguna. Jawab ringkas dan jelas, gunakan alat bila membantu, dan delegasikan ke agen lain lewat papan Kanban bila perlu.',
          deskIndex: 0,
        ),
        const Profile(
          name: 'riset',
          role: 'researcher',
          description: 'Mencari dan merangkum informasi dari web',
          systemPrompt:
              'Kamu agen riset. Ambil sumber dengan web_fetch, kutip URL-nya, dan rangkum temuan secara terstruktur.',
          deskIndex: 1,
        ),
        const Profile(
          name: 'kode',
          role: 'backend',
          description: 'Menulis dan meninjau kode',
          systemPrompt:
              'Kamu insinyur perangkat lunak senior. Tulis kode lengkap dalam blok kode bertanda bahasa, simpan berkas penting ke workspace dengan file_write.',
          deskIndex: 2,
        ),
      ];
      _saveProfiles();
    }
    sessions = (await kv.getList('sessions')).map(ChatSessionInfo.fromJson).toList();
    memory = (await kv.getList('memory')).map(MemoryNote.fromJson).toList();
    skills = (await kv.getList('skills')).map(Skill.fromJson).toList();
    if (skills.isEmpty) {
      skills = [
        Skill(
          name: 'ringkas-dokumen',
          description: 'Ringkas teks panjang jadi poin-poin keputusan',
          body: '# Ringkas dokumen\n\n1. Baca seluruh teks.\n2. Tulis TL;DR satu kalimat.\n3. Daftar poin kunci (maks 7).\n4. Tutup dengan "Tindak lanjut" bila ada.\n',
          updatedAt: DateTime.now().toIso8601String(),
        ),
        Skill(
          name: 'tulis-laporan',
          description: 'Format laporan kerja harian ke workspace',
          body: '# Laporan harian\n\nSimpan ke `laporan/YYYY-MM-DD.md` dengan file_write. Bagian: Selesai, Sedang berjalan, Hambatan, Rencana besok.\n',
          updatedAt: DateTime.now().toIso8601String(),
        ),
      ];
      _saveSkills();
    }
    projects = (await kv.getList('projects')).map(Project.fromJson).toList();
    tasks = (await kv.getList('tasks')).map(Task.fromJson).toList();
    final lg = await kv.getMap('task_logs');
    logs = lg.map((k, v) => MapEntry(k, (v as List).map((e) => '$e').toList()));
    final rn = await kv.getMap('task_runs');
    runs = rn.map((k, v) => MapEntry(
        k, (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()));
    jobs = (await kv.getList('cron_jobs')).map(CronJob.fromJson).toList();
    cronRuns = (await kv.getList('cron_runs')).map(CronRun.fromJson).toList();
    archived = (await kv.getList('meetings')).map(ArchivedMeeting.fromJson).toList();
    bodies = (await kv.getMap('meeting_bodies')).map((k, v) => MapEntry(k, '$v'));
    final fm = await kv.getMap('workspace');
    files = fm.map((k, v) {
      final m = Map<String, dynamic>.from(v as Map);
      return MapEntry(k, WorkspaceFile(k, '${m['content'] ?? ''}', '${m['updatedAt'] ?? ''}'));
    });
    folders = ((await kv.get('workspace_dirs')) as List? ?? []).map((e) => '$e').toSet();
    if (files.isEmpty) {
      writeFile('README.md',
          '# Workspace Neovarch Agent\n\nBerkas yang ditulis agent (lewat alat `file_write`) muncul di sini.\nKamu juga bisa membuat berkas sendiri dari tab **Berkas**.\n');
    }
    _migrateNeovarch();
  }

  /// v1.1 rename: the default orchestrator "hermes" becomes "neovarch"
  /// (tasks, sessions, memory and cron follow). Runs once; no-op on new installs.
  void _migrateNeovarch() {
    final old = profiles.indexWhere((p) => p.name == 'hermes');
    if (old < 0 || profiles.any((p) => p.name == 'neovarch')) return;
    String r(Object? v) => v == 'hermes' ? 'neovarch' : '${v ?? ''}';
    final pj = profiles[old].toJson()
      ..['name'] = 'neovarch'
      ..['systemPrompt'] = profiles[old].systemPrompt.replaceAll('Kamu Hermes', 'Kamu Neovarch');
    profiles[old] = Profile.fromJson(pj);
    tasks = tasks.map((t) => t.assignee == 'hermes' ? Task.fromJson(t.toJson()..['assignee'] = 'neovarch') : t).toList();
    sessions = sessions.map((x) => x.profile == 'hermes' ? ChatSessionInfo.fromJson(x.toJson()..['profile'] = 'neovarch') : x).toList();
    memory = memory.map((m) => m.scope == 'hermes' ? MemoryNote.fromJson(m.toJson()..['scope'] = r(m.scope)) : m).toList();
    jobs = jobs.map((j) => j.agent == 'hermes' ? CronJob.fromJson(j.toJson()..['agent'] = 'neovarch') : j).toList();
    _saveProfiles();
    _saveSessions();
    _saveMemory();
    saveTasks();
    saveJobs();
  }

  // ------------------------------------------------------------ profiles --
  void _saveProfiles() => kv.put('profiles', profiles.map((p) => p.toJson()).toList());

  Profile? profile(String name) => profiles.where((p) => p.name == name).firstOrNull;

  void upsertProfile(Profile p) {
    final i = profiles.indexWhere((x) => x.name == p.name);
    if (i >= 0) {
      profiles[i] = p;
    } else {
      final used = profiles.map((x) => x.deskIndex).toSet();
      final desk = p.deskIndex ??
          [0, 1, 2, 3, 4, 5, 6, 7].where((d) => !used.contains(d)).firstOrNull;
      profiles.add(p.copyWith(deskIndex: desk));
    }
    _saveProfiles();
    notifyListeners();
  }

  void removeProfile(String name) {
    profiles.removeWhere((p) => p.name == name);
    _saveProfiles();
    notifyListeners();
  }

  // ------------------------------------------------------------ sessions --
  void _saveSessions() => kv.put('sessions', sessions.map((s) => s.toJson()).toList());

  ChatSessionInfo createSession(String profile, {String? projectId, String? title}) {
    final s = ChatSessionInfo(
      id: uid('s'),
      title: title ?? 'Percakapan baru',
      profile: profile,
      projectId: projectId,
      updatedAt: DateTime.now().toIso8601String(),
    );
    sessions.insert(0, s);
    _saveSessions();
    notifyListeners();
    return s;
  }

  void updateSession(ChatSessionInfo s) {
    final i = sessions.indexWhere((x) => x.id == s.id);
    if (i >= 0) {
      sessions[i] = s;
      sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _saveSessions();
      notifyListeners();
    }
  }

  Future<void> deleteSession(String id) async {
    sessions.removeWhere((s) => s.id == id);
    _saveSessions();
    await kv.remove('msgs_$id');
    notifyListeners();
  }

  Future<List<ChatMsg>> messages(String sessionId) async =>
      (await kv.getList('msgs_$sessionId')).map(ChatMsg.fromJson).toList();

  void saveMessages(String sessionId, List<ChatMsg> msgs) =>
      kv.put('msgs_$sessionId', msgs.map((m) => m.toJson()).toList());

  // -------------------------------------------------------------- memory --
  void _saveMemory() => kv.put('memory', memory.map((m) => m.toJson()).toList());

  MemoryNote addMemory(String scope, String text) {
    final m = MemoryNote(
        id: uid('mem'), scope: scope, text: text.trim(), createdAt: DateTime.now().toIso8601String());
    memory.insert(0, m);
    _saveMemory();
    notifyListeners();
    return m;
  }

  void updateMemory(MemoryNote m) {
    final i = memory.indexWhere((x) => x.id == m.id);
    if (i >= 0) memory[i] = m;
    _saveMemory();
    notifyListeners();
  }

  bool deleteMemory(String id) {
    final before = memory.length;
    memory.removeWhere((m) => m.id == id);
    _saveMemory();
    notifyListeners();
    return memory.length != before;
  }

  List<MemoryNote> memoryFor(String profile) =>
      memory.where((m) => m.scope == '*' || m.scope == profile).toList();

  // -------------------------------------------------------------- skills --
  void _saveSkills() => kv.put('skills', skills.map((s) => s.toJson()).toList());

  void upsertSkill(Skill s, {String? oldName}) {
    final i = skills.indexWhere((x) => x.name == (oldName ?? s.name));
    if (i >= 0) {
      skills[i] = s;
    } else {
      skills.add(s);
    }
    skills.sort((a, b) => a.name.compareTo(b.name));
    _saveSkills();
    notifyListeners();
  }

  void deleteSkill(String name) {
    skills.removeWhere((s) => s.name == name);
    _saveSkills();
    notifyListeners();
  }

  // ------------------------------------------------------------ projects --
  void _saveProjects() => kv.put('projects', projects.map((p) => p.toJson()).toList());

  void upsertProject(Project p) {
    final i = projects.indexWhere((x) => x.id == p.id);
    if (i >= 0) {
      projects[i] = p;
    } else {
      projects.add(p);
    }
    if (p.folder.isNotEmpty) makeFolder(p.folder);
    _saveProjects();
    notifyListeners();
  }

  void deleteProject(String id) {
    projects.removeWhere((p) => p.id == id);
    for (final s in sessions.where((s) => s.projectId == id).toList()) {
      updateSession(s.copyWith(clearProject: true));
    }
    _saveProjects();
    notifyListeners();
  }

  // --------------------------------------------------------------- tasks --
  void saveTasks() {
    kv.put('tasks', tasks.map((t) => t.toJson()).toList());
    notifyListeners();
  }

  void saveLogs() => kv.put('task_logs', logs);
  void saveRuns() => kv.put('task_runs', runs);

  void log(String taskId, String line) {
    final l = logs.putIfAbsent(taskId, () => []);
    l.add(line);
    if (l.length > 400) l.removeRange(0, l.length - 400); // bounded tail like taskLog
    saveLogs();
  }

  Task? task(String id) => tasks.where((t) => t.id == id).firstOrNull;

  void replaceTask(Task t) {
    final i = tasks.indexWhere((x) => x.id == t.id);
    if (i >= 0) tasks[i] = t;
    saveTasks();
  }

  // ---------------------------------------------------------------- cron --
  void saveJobs() {
    kv.put('cron_jobs', jobs.map((j) => j.toJson()).toList());
    notifyListeners();
  }

  void saveCronRuns() {
    if (cronRuns.length > 100) cronRuns = cronRuns.sublist(0, 100);
    kv.put('cron_runs', cronRuns.map((r) => r.toJson()).toList());
  }

  // ------------------------------------------------------------ meetings --
  void saveMeetings() {
    kv.put('meetings', archived.map((m) => m.toJson()).toList());
    kv.put('meeting_bodies', bodies);
  }

  // ----------------------------------------------------------- workspace --
  void _saveFiles() {
    kv.put('workspace', files.map((k, v) => MapEntry(k, v.toJson())));
    kv.put('workspace_dirs', folders.toList());
  }

  WorkspaceFile writeFile(String path, String content) {
    final p = normPath(path);
    if (p.isEmpty) throw ArgumentError('path kosong');
    final f = WorkspaceFile(p, content, DateTime.now().toIso8601String());
    files[p] = f;
    _saveFiles();
    notifyListeners();
    return f;
  }

  WorkspaceFile? readFile(String path) => files[normPath(path)];

  bool deleteFile(String path) {
    final p = normPath(path);
    final removed = files.remove(p) != null;
    if (!removed) {
      // a folder: drop everything under it
      final pre = '$p/';
      files.removeWhere((k, _) => k.startsWith(pre));
      folders.removeWhere((d) => d == p || d.startsWith(pre));
    }
    _saveFiles();
    notifyListeners();
    return true;
  }

  void makeFolder(String path) {
    final p = normPath(path);
    if (p.isEmpty) return;
    folders.add(p);
    _saveFiles();
    notifyListeners();
  }

  /// Direct children of [dir]: (folders, files).
  (List<String>, List<WorkspaceFile>) listDir(String dir) {
    final d = normPath(dir);
    final pre = d.isEmpty ? '' : '$d/';
    final subdirs = <String>{};
    final out = <WorkspaceFile>[];
    for (final f in files.values) {
      if (!f.path.startsWith(pre)) continue;
      final rest = f.path.substring(pre.length);
      final slash = rest.indexOf('/');
      if (slash < 0) {
        out.add(f);
      } else {
        subdirs.add(rest.substring(0, slash));
      }
    }
    for (final f in folders) {
      if (!f.startsWith(pre) || f == d) continue;
      final rest = f.substring(pre.length);
      if (rest.isEmpty) continue;
      subdirs.add(rest.split('/').first);
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return (subdirs.toList()..sort(), out);
  }
}
