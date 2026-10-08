// LocalBackend — the Mandiri (on-device) answer to every `/api/neovarch/*`
// route, so the office UI is identical whichever backend is connected.
//
// Behaviour mirrors the server where it matters:
//   * tasks: assigning a task to an agent queues it; the agent works it
//     through the LLM (tools allowed), the output lands in the task log and
//     the card moves to REVIEW. Steer appends guidance the worker reads
//     before its next step; cancel releases the claim (back to ready).
//   * meetings: 2–4 agents take turns, then the moderator writes minutes
//     with Keputusan / TINDAK LANJUT / Risiko; action items become tasks.
//   * cron: scheduled prompts fire while the app is open (paused on create
//     by default, like the server).
import 'dart:async';

import '../models/models.dart';
import 'agent_runtime.dart';
import 'api_result.dart';
import 'cron_schedule.dart';
import 'llm_client.dart';
import 'local_store.dart';
import 'office_backend.dart';

final _namePattern = RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$');

class LocalBackend extends OfficeBackend implements BoardHooks, OfficeHooks {
  LocalBackend({required this.store, required this.runtime, required this.autoRun}) {
    runtime.board = this;
    runtime.office = this;
    _cronTimer = Timer.periodic(const Duration(seconds: 30), (_) => _cronTick());
    // Tasks that were "running" when the app died go back to the queue.
    for (final t in store.tasks.where((t) => t.status == 'running').toList()) {
      store.replaceTask(t.copyWith(status: 'ready'));
      store.log(t.id, '[sistem] aplikasi ditutup saat tugas berjalan — dikembalikan ke antrean');
    }
    Future.microtask(_pump);
  }

  final LocalStore store;
  final AgentRuntime runtime;
  final bool Function() autoRun;
  Timer? _cronTimer;

  final Map<String, CancelToken> _running = {}; // taskId -> token
  final Map<String, List<String>> _steer = {};
  final List<Meeting> _live = [];
  bool _meetingBusy = false;

  @override
  String get kind => 'local';
  @override
  bool get supportsMove => true;

  bool get _llmReady => runtime.llm()?.configured == true;

  @override
  List<Meeting> liveMeetings() => List.of(_live);

  // ---------------------------------------------------------------- agents --
  @override
  List<Agent> agents() {
    final liveMeeting = _live.where((m) => m.live).firstOrNull;
    final out = <Agent>[];
    for (final p in store.profiles.where((p) => !p.hidden)) {
      final mine = store.tasks.where((t) => t.assignee == p.name).toList();
      Task? pick(String s) => mine.where((t) => t.status == s).firstOrNull;
      final active = pick('running') ?? pick('review') ?? pick('blocked');
      var status = switch (active?.status) {
        'running' => 'working',
        'review' => 'review',
        'blocked' => 'blocked',
        _ => 'idle',
      };
      if (liveMeeting != null && liveMeeting.participants.contains(p.name)) status = 'meeting';
      out.add(Agent(
        name: p.name,
        displayName: p.name,
        role: p.role,
        deskIndex: p.deskIndex,
        status: status,
        currentTaskId: active?.id,
      ));
    }
    return out;
  }

  // ------------------------------------------------------------ board hooks --
  @override
  Map<String, dynamic> createTask(Map<String, dynamic> body, String createdBy) {
    final title = '${body['title'] ?? ''}'.trim();
    if (title.isEmpty) return {'error': 'judul tugas wajib diisi'};
    final assignee = '${body['assignee'] ?? ''}'.trim();
    if (assignee.isNotEmpty && store.profile(assignee) == null) {
      return {'error': 'agent "$assignee" tidak dikenal'};
    }
    final now = DateTime.now().toIso8601String();
    final originRaw = body['origin'];
    TaskOrigin? origin;
    if (originRaw is Map) {
      origin = TaskOrigin.fromJson(Map<String, dynamic>.from(originRaw));
    } else if (createdBy.contains(':')) {
      final i = createdBy.indexOf(':');
      origin = TaskOrigin(kind: createdBy.substring(0, i), ref: createdBy.substring(i + 1), raw: createdBy);
    }
    final t = Task(
      id: store.uid('t_'),
      title: title.length > 300 ? title.substring(0, 300) : title,
      status: assignee.isEmpty ? 'todo' : 'ready',
      assignee: assignee.isEmpty ? null : assignee,
      priority: (body['priority'] is num) ? (body['priority'] as num).toInt() : 2,
      body: (body['body'] != null && '${body['body']}'.trim().isNotEmpty) ? '${body['body']}' : null,
      createdAt: now,
      updatedAt: now,
      origin: origin,
    );
    store.tasks.insert(0, t);
    store.saveTasks();
    store.log(t.id, '\$ neovarch kanban create "${t.title}"${t.assignee != null ? ' --assignee ${t.assignee}' : ''}');
    Future.microtask(_pump);
    return t.toJson();
  }

  @override
  String? updateTask(String id, Map<String, dynamic> patch) {
    final t = store.task(id);
    if (t == null) return 'tugas $id tidak ditemukan';
    final status = patch['status'] as String?;
    if (status != null && !statusLabel.containsKey(status)) return 'status "$status" tidak dikenal';
    final assignee = patch['assignee'] as String?;
    if (assignee != null && assignee.isNotEmpty && store.profile(assignee) == null) {
      return 'agent "$assignee" tidak dikenal';
    }
    if (status != null && status != 'running') _running.remove(id)?.cancel();
    store.replaceTask(t.copyWith(
      status: status,
      title: patch['title'] as String?,
      body: patch['body'] as String?,
      assignee: assignee,
    ));
    if (status != null) store.log(id, '[sistem] status → $status');
    Future.microtask(_pump);
    return null;
  }

  // ----------------------------------------------------------------- runner --
  void _pump() {
    if (!autoRun() || !_llmReady) return;
    final busy = _running.keys.map((id) => store.task(id)?.assignee).toSet();
    final queue = store.tasks.where((t) => t.status == 'ready' && t.assignee != null).toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    for (final t in queue) {
      if (busy.contains(t.assignee)) continue;
      busy.add(t.assignee);
      unawaited(_runTask(t));
    }
  }

  Future<void> _runTask(Task task) async {
    final p = store.profile(task.assignee!);
    if (p == null) return;
    final token = CancelToken();
    _running[task.id] = token;
    final runId = store.uid('r');
    store.replaceTask(task.copyWith(status: 'running'));
    store.log(task.id, '[worker ${p.name}] mengambil tugas (run $runId)');
    final history = [
      ChatMsg(
        id: 'u',
        role: 'user',
        ts: DateTime.now().millisecondsSinceEpoch,
        content: 'Kerjakan tugas Kanban ini sampai tuntas, lalu tulis hasil akhirnya.\n\n'
            'ID: ${task.id}\nJudul: ${task.title}\n${task.body != null ? 'Uraian:\n${task.body}\n' : ''}'
            '\nJangan ubah status tugas ini sendiri — setelah kamu selesai, tugas otomatis pindah ke REVIEW.',
      )
    ];
    final out = StringBuffer();
    String? error;
    await for (final e in runtime.run(
      profile: p,
      history: history,
      cancel: token,
      extraSystem: 'Kamu sedang bekerja sebagai worker Kanban tanpa pengguna yang menunggu di chat.',
      pendingSteer: () {
        final s = _steer.remove(task.id) ?? const <String>[];
        for (final m in s) {
          store.log(task.id, '[worker ${p.name}] menerima arahan: $m');
        }
        return s;
      },
    )) {
      switch (e) {
        case NewAssistantEvent():
          if (out.isNotEmpty) out.write('\n\n');
        case DeltaEvent(:final text):
          out.write(text);
        case ToolStartEvent(:final name, :final args):
          store.log(task.id, '[alat] $name ${args.length > 160 ? '${args.substring(0, 160)}…' : args}');
        case ToolDoneEvent(:final name, :final summary, :final failed):
          store.log(task.id, '[alat] $name → ${failed ? 'GAGAL ' : ''}${summary ?? ''}');
        case ErrorEvent(:final message):
          error = message;
        default:
          break;
      }
    }
    _running.remove(task.id);
    final current = store.task(task.id);
    final runs = store.runs.putIfAbsent(task.id, () => []);
    if (token.isCancelled) {
      runs.add({'id': runId, 'status': 'cancelled', 'profile': p.name, 'outcome': 'dilepas'});
      store.log(task.id, '[sistem] claim worker dilepas');
    } else if (error != null) {
      runs.add({'id': runId, 'status': 'failed', 'profile': p.name, 'error': error});
      store.log(task.id, '[galat] $error');
      if (current != null && current.status == 'running') {
        store.replaceTask(current.copyWith(status: 'blocked'));
      }
    } else {
      final text = stripThink(out.toString()).trim();
      runs.add({
        'id': runId,
        'status': 'completed',
        'profile': p.name,
        'outcome': 'ok',
        'summary': text.length > 200 ? '${text.substring(0, 200)}…' : text,
      });
      for (final line in text.split('\n')) {
        store.log(task.id, line);
      }
      if (current != null && current.status == 'running') {
        store.replaceTask(current.copyWith(status: 'review', output: text));
      }
      store.log(task.id, '[worker ${p.name}] selesai → REVIEW');
    }
    store.saveRuns();
    _pump();
  }

  // ---------------------------------------------------------------- meetings --
  Future<String> _say(Profile p, Meeting m, String instruction, {int maxTokens = 400}) async {
    final client = runtime.llm()!;
    final transcript = m.turns.map((t) => '${t.speaker}: ${t.text}').join('\n\n');
    return client.complete([
      {
        'role': 'system',
        'content': '${runtime.systemPrompt(p)}\n\nKamu sedang ikut rapat tim dengan ${m.participants.join(', ')} '
            '(moderator: ${m.moderator}). Topik: "${m.topic}". Bicara sebagai ${p.name} saja, tanpa menulis nama pembicara lain.'
      },
      {
        'role': 'user',
        'content': '${transcript.isEmpty ? '(belum ada yang bicara)' : 'Transkrip sejauh ini:\n\n$transcript'}\n\n$instruction'
      },
    ], maxTokens: maxTokens, modelOverride: p.model);
  }

  Future<void> _runMeeting(int index) async {
    _meetingBusy = true;
    Meeting m = _live[index];
    void set(Meeting n) {
      final i = _live.indexWhere((x) => x.id == n.id);
      if (i >= 0) _live[i] = n;
      m = n;
      store.touch();
    }

    Meeting copy({String? state, String? phase, String? speaker, bool clearSpeaker = false, List<MeetingTurn>? turns, String? minutes}) =>
        Meeting(
          id: m.id,
          topic: m.topic,
          participants: m.participants,
          moderator: m.moderator,
          mode: m.mode,
          state: state ?? m.state,
          phase: phase ?? m.phase,
          currentSpeaker: clearSpeaker ? null : (speaker ?? m.currentSpeaker),
          turns: turns ?? m.turns,
          minutes: minutes ?? m.minutes,
        );

    try {
      set(copy(state: 'running', phase: 'pembuka'));
      final order = <(String, String, int)>[]; // speaker, kind, round
      final others = m.participants.where((x) => x != m.moderator).toList();
      switch (m.mode) {
        case 'directed':
          order.add((m.moderator, 'opening', 1));
          for (final o in others) {
            order.add((o, 'speech', 1));
          }
          order.add((m.moderator, 'speech', 2));
        case 'manual':
          order.add((m.moderator, 'opening', 1));
          final named = others.where((o) => m.topic.toLowerCase().contains(o.toLowerCase())).toList();
          for (final o in (named.isEmpty ? others : named)) {
            order.add((o, 'speech', 1));
          }
        default: // auto: everyone, two rounds
          order.add((m.moderator, 'opening', 1));
          for (final o in others) {
            order.add((o, 'speech', 1));
          }
          for (final o in m.participants) {
            order.add((o, 'speech', 2));
          }
      }
      for (final (who, kind, round) in order) {
        final p = store.profile(who);
        if (p == null) continue;
        set(copy(speaker: who, phase: 'ronde $round'));
        final text = await _say(
            p,
            m,
            kind == 'opening'
                ? 'Kamu moderator. Buka rapat: jelaskan tujuan dan pertanyaan kunci dalam 2-4 kalimat.'
                : 'Giliranmu (ronde $round). Tanggapi poin sebelumnya, beri pendapat/usulan konkret dalam 2-4 kalimat.');
        set(copy(turns: [
          ...m.turns,
          MeetingTurn(round: round, speaker: who, kind: kind, text: text, ts: DateTime.now().millisecondsSinceEpoch)
        ]));
      }
      final mod = store.profile(m.moderator) ?? store.profile(m.participants.first)!;
      set(copy(speaker: mod.name, phase: 'notulen'));
      final roster = store.profiles.map((p) => p.name).join(', ');
      final minutes = await _say(
          mod,
          m,
          'Rapat selesai. Tulis notulen markdown PERSIS dengan format ini:\n\n'
          '# Notulen: <topik>\n\n## Keputusan\n- ...\n\n## TINDAK LANJUT\n- [ ] <tugas konkret> (pemilik: <nama agent>, tenggat: <YYYY-MM-DD atau kosongkan>)\n\n## Risiko\n- ...\n\n'
          'Pemilik harus salah satu dari: $roster. Jangan menambah bagian lain.',
          maxTokens: 900);
      set(copy(
          state: 'done',
          phase: 'selesai',
          clearSpeaker: true,
          minutes: minutes,
          turns: [
            ...m.turns,
            MeetingTurn(round: 0, speaker: mod.name, kind: 'minutes', text: 'notulen siap', ts: DateTime.now().millisecondsSinceEpoch)
          ]));
    } catch (e) {
      set(copy(state: 'error', phase: 'galat: $e', clearSpeaker: true));
    } finally {
      _meetingBusy = false;
    }
    if (m.state == 'done') _archive(m);
    // A queued meeting waits for the single execution slot.
    final next = _live.indexWhere((x) => x.state == 'queued');
    if (next >= 0) unawaited(_runMeeting(next));
  }

  void _archive(Meeting m) {
    final turns = m.turns
        .where((t) => t.kind != 'minutes')
        .map((t) => '**${t.speaker}** (${t.kind} r${t.round}): ${t.text}')
        .join('\n\n');
    store.bodies[m.id] =
        '# ${m.topic}\n\nPeserta: ${m.participants.join(', ')} — Moderator: ${m.moderator} — Mode: ${m.mode}\n\n$turns\n\n---\n\n${m.minutes}';
    store.archived.insert(
        0,
        ArchivedMeeting(
          id: m.id,
          topic: m.topic,
          startedAt: DateTime.now().toIso8601String().substring(0, 10),
          participants: m.participants,
          moderator: m.moderator,
          mode: m.mode,
          turnCount: m.turns.length,
          preview: m.turns.isNotEmpty ? m.turns.first.text : m.topic,
        ));
    store.saveMeetings();
    store.writeFile('rapat/${m.id}.md', store.bodies[m.id]!);
  }

  /// Parse `## TINDAK LANJUT` (or `## Aksi`) items out of minutes markdown.
  List<Candidate> actionItems(String minutes) {
    final roster = store.profiles.map((p) => p.name).toSet();
    final lines = minutes.split('\n');
    var inSection = false;
    final out = <Candidate>[];
    for (final raw in lines) {
      final l = raw.trim();
      if (l.startsWith('#')) {
        final h = l.replaceAll('#', '').trim().toLowerCase();
        inSection = h.contains('tindak lanjut') || h == 'aksi' || h.contains('action');
        continue;
      }
      if (!inSection) continue;
      final m = RegExp(r'^[-*]\s*(\[[ xX]\]\s*)?(.+)$').firstMatch(l);
      if (m == null) continue;
      var text = m.group(2)!.trim();
      var owner = '';
      String? due;
      final paren = RegExp(r'\(([^)]*)\)\s*$').firstMatch(text);
      if (paren != null) {
        final inner = paren.group(1)!;
        final om = RegExp(r'(pemilik|owner|pj)\s*:\s*([^,;]+)', caseSensitive: false).firstMatch(inner);
        final dm = RegExp(r'(tenggat|due)\s*:\s*([^,;]+)', caseSensitive: false).firstMatch(inner);
        if (om != null || dm != null) {
          owner = om?.group(2)?.trim() ?? '';
          final d = dm?.group(2)?.trim() ?? '';
          due = d.isEmpty || d.startsWith('<') || d == '-' ? null : d;
          text = text.substring(0, paren.start).trim();
        }
      }
      final ownerKey = owner.toLowerCase().replaceAll('@', '');
      out.add(Candidate(
          text: text, owner: owner, suggested: roster.contains(ownerKey) ? ownerKey : null, due: due));
    }
    return out;
  }

  // -------------------------------------------------------------------- cron --
  void _cronTick() {
    final now = DateTime.now();
    var changed = false;
    for (var i = 0; i < store.jobs.length; i++) {
      final j = store.jobs[i];
      if (!j.enabled) continue;
      final due = DateTime.tryParse(j.nextRunAt ?? '');
      if (due == null) {
        store.jobs[i] = _withNext(j, now);
        changed = true;
        continue;
      }
      if (!due.isAfter(now)) unawaited(_runJob(j.id, 'scheduler'));
    }
    if (changed) store.saveJobs();
  }

  CronJob _withNext(CronJob j, DateTime from, {String? state, bool? enabled, String? lastRunAt, String? lastStatus, String? lastError, int? failureStreak, String? lastOutput, bool clearError = false}) {
    final en = enabled ?? j.enabled;
    return CronJob(
      id: j.id,
      name: j.name,
      prompt: j.prompt,
      schedule: j.schedule,
      scheduleKind: j.scheduleKind,
      enabled: en,
      state: state ?? (en ? 'scheduled' : 'paused'),
      nextRunAt: en ? nextRun(j.schedule, from)?.toIso8601String() : null,
      lastRunAt: lastRunAt ?? j.lastRunAt,
      lastStatus: lastStatus ?? j.lastStatus,
      lastError: clearError ? null : (lastError ?? j.lastError),
      failureStreak: failureStreak ?? j.failureStreak,
      agent: j.agent,
      lastOutput: lastOutput ?? j.lastOutput,
    );
  }

  final Set<String> _jobsRunning = {};

  Future<void> _runJob(String id, String source) async {
    if (_jobsRunning.contains(id)) return;
    final idx = store.jobs.indexWhere((j) => j.id == id);
    if (idx < 0) return;
    final j = store.jobs[idx];
    _jobsRunning.add(id);
    final started = DateTime.now();
    store.jobs[idx] = _withNext(j, started, state: 'running');
    store.saveJobs();
    final p = store.profile(j.agent ?? '') ?? store.profiles.first;
    final out = StringBuffer();
    String? error;
    if (!_llmReady) {
      error = 'penyedia LLM belum diatur';
    } else {
      await for (final e in runtime.run(
        profile: p,
        history: [ChatMsg(id: 'u', role: 'user', ts: started.millisecondsSinceEpoch, content: j.prompt)],
        extraSystem: 'Ini eksekusi cron terjadwal "${j.name}" (${j.schedule}). Tidak ada pengguna yang menunggu; tulis hasil yang bisa dibaca nanti.',
      )) {
        if (e is DeltaEvent) out.write(e.text);
        if (e is NewAssistantEvent && out.isNotEmpty) out.write('\n\n');
        if (e is ErrorEvent) error = e.message;
      }
    }
    _jobsRunning.remove(id);
    final i2 = store.jobs.indexWhere((x) => x.id == id);
    final finished = DateTime.now();
    final ok = error == null;
    final text = stripThink(out.toString());
    if (ok) {
      final stamp = finished.toIso8601String().substring(0, 16).replaceAll(':', '-');
      store.writeFile('cron/${j.name}/$stamp.md', '# ${j.name}\n\n_${finished.toIso8601String()}_\n\n$text\n');
    }
    if (i2 >= 0) {
      final cur = store.jobs[i2];
      store.jobs[i2] = _withNext(cur, finished,
          lastRunAt: started.toIso8601String(),
          lastStatus: ok ? 'success' : 'error',
          lastError: error,
          clearError: ok,
          failureStreak: ok ? 0 : cur.failureStreak + 1,
          lastOutput: ok ? text : cur.lastOutput);
    }
    store.cronRuns.insert(
        0,
        CronRun(
            id: store.uid('cr'),
            jobId: id,
            status: ok ? 'success' : 'error',
            startedAt: started.toIso8601String(),
            finishedAt: finished.toIso8601String()));
    store.saveCronRuns();
    store.saveJobs();
  }

  // ------------------------------------------------------------------ router --
  @override
  Future<ApiResult> request(String method, String path,
      {Map<String, String>? query, Map<String, dynamic>? body, Duration? timeout}) async {
    final b = body ?? const <String, dynamic>{};
    final q = query ?? const <String, String>{};
    method = method.toUpperCase();

    if (path == '/api/neovarch/tasks') {
      if (method == 'GET') {
        return ApiResult.success({'tasks': store.tasks.map((t) => t.toJson()).toList(), 'agents': agents().map((a) => a.toJson()).toList()});
      }
      if (b['items'] is List) {
        final origin = b['origin'];
        if (origin is! Map || !['meeting', 'cron', 'agent', 'manual'].contains(origin['kind'])) {
          return ApiResult.fail(400, 'origin.kind tidak dikenal');
        }
        final items = (b['items'] as List).take(25).toList();
        if (items.isEmpty) return ApiResult.fail(400, 'tidak ada item');
        final created = <Map<String, dynamic>>[];
        final failed = <Map<String, dynamic>>[];
        for (final it in items.cast<Map>()) {
          if ('${it['assignee'] ?? ''}'.trim().isEmpty) {
            failed.add({'title': it['title'], 'error': 'penanggung belum dipilih'});
            continue;
          }
          final r = createTask({...Map<String, dynamic>.from(it), 'origin': origin}, '${origin['kind']}:${origin['ref'] ?? ''}');
          if (r['error'] != null) {
            failed.add({'title': it['title'], 'error': r['error']});
          } else {
            created.add(r);
          }
        }
        return ApiResult(
            ok: created.isNotEmpty,
            status: created.isNotEmpty ? 201 : 502,
            data: {'success': created.isNotEmpty, 'created': created, 'failed': failed, 'origin': origin},
            error: created.isEmpty ? 'tidak ada tugas yang dibuat' : null);
      }
      if ('${b['title'] ?? ''}'.trim().isEmpty || '${b['assignee'] ?? ''}'.trim().isEmpty) {
        return ApiResult.fail(400, 'title dan assignee wajib diisi');
      }
      final r = createTask(b, 'manual:');
      if (r['error'] != null) return ApiResult.fail(400, '${r['error']}');
      return ApiResult.success({'success': true, 'task': r}, 201);
    }

    final taskHit = RegExp(r'^/api/neovarch/tasks/([^/]+)$').firstMatch(path);
    if (taskHit != null) {
      final id = Uri.decodeComponent(taskHit.group(1)!);
      final t = store.task(id);
      if (t == null) return ApiResult.fail(404, 'tugas tidak ditemukan');
      if (method == 'GET') {
        return ApiResult.success({'taskId': id, 'runs': store.runs[id] ?? [], 'log': (store.logs[id] ?? []).join('\n')});
      }
      switch ('${b['action'] ?? ''}') {
        case 'steer':
          final msg = '${b['message'] ?? ''}'.trim();
          if (msg.isEmpty) return ApiResult.fail(400, 'pesan arahan kosong');
          store.log(id, '[arahan] $msg');
          if (_running.containsKey(id)) {
            _steer.putIfAbsent(id, () => []).add(msg);
          } else {
            // Not running: it rides along as a comment in the body, like a CLI comment.
            store.replaceTask(t.copyWith(body: '${t.body ?? ''}\n\n[Arahan] $msg'.trim()));
          }
          return ApiResult.success({'success': true, 'steered': true});
        case 'cancel':
          if (t.status != 'running') {
            return ApiResult.fail(409, 'tugas tidak sedang berjalan (cannot reclaim)');
          }
          _running.remove(id)?.cancel();
          store.replaceTask(t.copyWith(status: 'ready'));
          return ApiResult.success({'success': true, 'released': true});
        case 'move':
          final err = updateTask(id, {'status': '${b['status']}'});
          return err == null ? ApiResult.success({'success': true}) : ApiResult.fail(400, err);
        case 'run':
          if (!_llmReady) return ApiResult.fail(409, 'penyedia LLM belum diatur');
          if (t.assignee == null) return ApiResult.fail(400, 'pilih penanggung dulu');
          if (_running.containsKey(id)) return ApiResult.fail(409, 'tugas sudah berjalan');
          unawaited(_runTask(t));
          return ApiResult.success({'success': true});
        case 'delete':
          _running.remove(id)?.cancel();
          store.tasks.removeWhere((x) => x.id == id);
          store.saveTasks();
          return ApiResult.success({'success': true});
      }
      return ApiResult.fail(400, 'aksi tidak dikenal');
    }

    if (path == '/api/neovarch/agents') {
      if (method == 'GET') {
        return ApiResult.success({
          'available': store.profiles
              .map((p) => {
                    'name': p.name,
                    'total': store.tasks.where((t) => t.assignee == p.name).length,
                    'profile': true,
                    'inOffice': !p.hidden,
                    'reason': p.hidden ? 'killed' : null,
                  })
              .toList(),
          'killed': store.profiles.where((p) => p.hidden).map((p) => p.name).toList(),
        });
      }
      final action = '${b['action'] ?? ''}';
      final name = '${b['name'] ?? ''}'.trim().toLowerCase();
      if (name.isEmpty) return ApiResult.fail(400, 'nama wajib diisi');
      switch (action) {
        case 'create':
          if (!_namePattern.hasMatch(name)) {
            return ApiResult.fail(400, 'nama hanya huruf kecil, angka, - dan _ (maks 64)');
          }
          if (store.profile(name) != null) return ApiResult.fail(400, 'profil "$name" sudah ada');
          store.upsertProfile(Profile(
            name: name,
            role: '${b['role'] ?? roleFor(name)}',
            description: '${b['description'] ?? ''}',
            systemPrompt: '${b['systemPrompt'] ?? b['description'] ?? ''}',
          ));
          return ApiResult.success({'success': true, 'action': 'create', 'name': name, 'description': b['description'] ?? ''}, 201);
        case 'spawn':
          final p = store.profile(name);
          if (p == null) return ApiResult.fail(400, 'profil "$name" tidak dikenal');
          store.upsertProfile(p.copyWith(hidden: false));
          return ApiResult.success({'success': true, 'action': 'spawn', 'name': name, 'changed': p.hidden});
        case 'kill':
          final p = store.profile(name);
          if (p == null) return ApiResult.fail(409, 'profil "$name" tidak ada');
          if (store.profiles.length <= 1) return ApiResult.fail(400, 'profil terakhir tidak bisa dihapus');
          final live = store.tasks.where((t) => t.assignee == name && (t.status == 'running' || t.status == 'review')).map((t) => t.id).toList();
          if (live.isNotEmpty) {
            return ApiResult.fail(409, 'masih ada tugas aktif (${live.join(', ')}) — hentikan dulu');
          }
          final purged = store.tasks.where((t) => t.assignee == name).length;
          store.tasks.removeWhere((t) => t.assignee == name);
          store.saveTasks();
          store.memory.removeWhere((m) => m.scope == name);
          store.removeProfile(name);
          return ApiResult.success({'success': true, 'action': 'kill', 'name': name, 'deleted': true, 'purged': purged, 'killed': []});
      }
      return ApiResult.fail(400, 'aksi tidak dikenal');
    }

    if (path == '/api/neovarch/cron') {
      if (method == 'GET') {
        final id = q['id'];
        if (id != null) {
          final j = store.jobs.where((x) => x.id == id).firstOrNull;
          if (j == null) return ApiResult.fail(404, 'job tidak ditemukan');
          return ApiResult.success({'job': j.toJson(), 'runs': store.cronRuns.where((r) => r.jobId == id).map((r) => r.toJson()).toList()});
        }
        return ApiResult.success({'jobs': store.jobs.map((j) => j.toJson()).toList(), 'runs': store.cronRuns.take(30).map((r) => r.toJson()).toList()});
      }
      final action = '${b['action'] ?? ''}';
      if (action == 'create') {
        final schedule = '${b['schedule'] ?? ''}'.trim();
        final err = validateSchedule(schedule);
        if (err != null) return ApiResult.fail(400, err);
        final prompt = '${b['prompt'] ?? ''}'.trim();
        if (prompt.isEmpty) return ApiResult.fail(400, 'prompt wajib diisi');
        final paused = b['paused'] != false;
        final name = '${b['name'] ?? ''}'.trim();
        var j = CronJob(
          id: store.uid(''),
          name: name.isEmpty ? 'job-${store.jobs.length + 1}' : name,
          prompt: prompt,
          schedule: schedule,
          scheduleKind: parseInterval(schedule) != null ? 'interval' : 'cron',
          enabled: !paused,
          agent: (b['agent'] as String?)?.isNotEmpty == true ? b['agent'] as String : null,
        );
        j = _withNext(j, DateTime.now());
        store.jobs.insert(0, j);
        store.saveJobs();
        return ApiResult.success({'success': true, 'id': j.id, 'job': j.toJson()}, 201);
      }
      final id = '${b['id'] ?? ''}';
      final i = store.jobs.indexWhere((x) => x.id == id);
      if (i < 0) return ApiResult.fail(400, 'job tidak dikenal');
      final now = DateTime.now();
      switch (action) {
        case 'pause':
          store.jobs[i] = _withNext(store.jobs[i], now, enabled: false);
        case 'resume':
          store.jobs[i] = _withNext(store.jobs[i], now, enabled: true);
        case 'run':
          unawaited(_runJob(id, 'manual'));
        case 'remove':
          store.jobs.removeAt(i);
          store.saveJobs();
          return ApiResult.success({'success': true, 'action': action, 'id': id, 'job': null});
        default:
          return ApiResult.fail(400, 'aksi tidak dikenal');
      }
      store.saveJobs();
      return ApiResult.success({'success': true, 'action': action, 'id': id, 'job': store.jobs.where((x) => x.id == id).firstOrNull?.toJson()});
    }

    if (path == '/api/neovarch/cron/actions') {
      final j = store.jobs.where((x) => x.id == q['from']).firstOrNull;
      if (j == null) return ApiResult.fail(404, 'job tidak ditemukan');
      return ApiResult.success({
        'job': {'id': j.id, 'name': j.name},
        'items': j.failureStreak > 0
            ? [
                {
                  'text': 'Perbaiki cron "${j.name}" (gagal ${j.failureStreak}×)',
                  'owner': '',
                  'body': 'Jadwal: ${j.schedule}\nPrompt: ${j.prompt}\n\nGalat terakhir:\n${j.lastError ?? '-'}'
                }
              ]
            : [],
        'roster': store.profiles.map((p) => p.name).toList(),
      });
    }

    if (path == '/api/neovarch/meeting') {
      if (method == 'POST') {
        final topic = '${b['topic'] ?? ''}'.trim();
        if (topic.isEmpty) return ApiResult.fail(400, 'topik wajib diisi');
        final known = store.profiles.map((p) => p.name).toSet();
        final parts = ((b['participants'] as List?) ?? []).map((e) => '$e').where(known.contains).toSet().toList();
        if (parts.length < 2) return ApiResult.fail(400, 'pilih minimal 2 peserta yang dikenal');
        if (!_llmReady) return ApiResult.fail(409, 'LLM belum dikonfigurasi — atur penyedia di Pengaturan');
        var moderator = '${b['moderator'] ?? ''}';
        if (!parts.contains(moderator)) moderator = parts.first;
        final m = Meeting(
          id: 'm${DateTime.now().millisecondsSinceEpoch}',
          topic: topic,
          participants: parts.take(4).toList(),
          moderator: moderator,
          mode: '${b['mode'] ?? 'auto'}',
          state: _meetingBusy ? 'queued' : 'running',
          phase: _meetingBusy ? 'menunggu giliran' : 'pembuka',
        );
        _live.insert(0, m);
        if (!_meetingBusy) unawaited(_runMeeting(0));
        return ApiResult.success({'meeting': m.toJson()});
      }
      final id = q['id'];
      if (id != null) {
        final body = store.bodies[id];
        if (body == null) return ApiResult.fail(404, 'transkrip tidak ditemukan');
        return ApiResult.success({'id': id, 'body': body});
      }
      return ApiResult.success({
        'configured': _llmReady,
        'live': _live.map((m) => m.toJson()).toList(),
        'active': _live.where((m) => m.state == 'running').firstOrNull?.id,
        'archived': store.archived.map((a) => a.toJson()).toList(),
      });
    }

    if (path == '/api/neovarch/meeting/actions') {
      final from = q['from'] ?? '';
      final live = _live.where((m) => m.id == from).firstOrNull;
      String? minutes = live?.minutes;
      if (minutes == null || minutes.isEmpty) {
        final body = store.bodies[from];
        if (body == null) return ApiResult.fail(404, 'rapat tidak ditemukan');
        minutes = body;
      }
      final a = store.archived.where((x) => x.id == from).firstOrNull;
      return ApiResult.success({
        'meeting': {'id': from, 'topic': live?.topic ?? a?.topic ?? ''},
        'items': actionItems(minutes).map((c) => {'text': c.text, 'owner': c.owner, 'suggested': c.suggested, 'due': c.due}).toList(),
        'roster': store.profiles.map((p) => p.name).toList(),
      });
    }

    if (path == '/api/neovarch/chat') {
      // Mandiri mode chats through sessions (ChatScreen); this keeps the
      // route answering so nothing that calls it breaks.
      final names = store.profiles.map((p) => p.name).toList();
      return ApiResult.success({'sessions': [], 'agents': names, 'profiles': names});
    }
    return ApiResult.fail(404, 'endpoint tidak dikenal: $path');
  }

  void kick() => _pump();

  @override
  void dispose() {
    _cronTimer?.cancel();
    for (final t in _running.values) {
      t.cancel();
    }
  }
}
