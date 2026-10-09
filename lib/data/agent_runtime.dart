// The on-device agent runtime (Mandiri mode).
//
// One turn = a small tool-calling loop over an OpenAI-compatible model:
// stream a completion, execute any tool calls with safe on-device tools,
// feed the results back, repeat (bounded). Tools only touch what the app
// owns: memory notes, the local Kanban board, the workspace files, skills,
// the clock, and a read-only web fetch.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'platform_caps.dart';

import '../models/chat_options.dart';
import '../models/models.dart';
import 'api_result.dart';
import 'device_tools.dart';
import 'llm_client.dart';
import 'local_store.dart';

class ToolSpec {
  final String name;
  final String label; // Indonesian label for the Tools settings page
  final String description;
  final Map<String, dynamic> parameters;
  /// app (memory/files/board/web), office (agents, meetings, cron), device (Android).
  final String group;
  /// Needs the user's approval in chat (private data / leaves the app).
  final bool risky;
  const ToolSpec(this.name, this.label, this.description, this.parameters, {this.group = 'app', this.risky = false});
  Map<String, dynamic> toOpenAi() => {
        'type': 'function',
        'function': {'name': name, 'description': description, 'parameters': parameters},
      };
}


const appTools = <ToolSpec>[
  ToolSpec('memory_read', 'Baca memori',
      'Read the long-term memory notes saved for this agent and shared notes. Optional query filters by substring.',
      {'type': 'object', 'properties': {'query': {'type': 'string', 'description': 'optional filter'}}}),
  ToolSpec('memory_write', 'Tulis memori',
      'Save a durable fact to long-term memory so future conversations remember it. Use scope "shared" for facts every agent should know.',
      {
        'type': 'object',
        'properties': {
          'text': {'type': 'string', 'description': 'the fact to remember, one sentence'},
          'scope': {'type': 'string', 'enum': ['agent', 'shared']}
        },
        'required': ['text']
      }),
  ToolSpec('memory_delete', 'Hapus memori', 'Delete a memory note by id (ids come from memory_read).',
      {'type': 'object', 'properties': {'id': {'type': 'string'}}, 'required': ['id']}),
  ToolSpec('list_tasks', 'Daftar tugas', 'List tasks on the local Kanban board. Optional status filter (todo, ready, running, review, blocked, done).',
      {'type': 'object', 'properties': {'status': {'type': 'string'}}}),
  ToolSpec('create_task', 'Buat tugas',
      'Create a task on the local Kanban board. If assignee is an agent name, that agent will work on it.',
      {
        'type': 'object',
        'properties': {
          'title': {'type': 'string'},
          'assignee': {'type': 'string', 'description': 'agent name, optional'},
          'body': {'type': 'string', 'description': 'details / acceptance criteria'},
          'priority': {'type': 'integer', 'description': '0 = highest'}
        },
        'required': ['title']
      }),
  ToolSpec('update_task', 'Ubah tugas', 'Update a Kanban task: status (todo, ready, running, review, blocked, done), title, body or assignee.',
      {
        'type': 'object',
        'properties': {
          'id': {'type': 'string'},
          'status': {'type': 'string'},
          'title': {'type': 'string'},
          'body': {'type': 'string'},
          'assignee': {'type': 'string'}
        },
        'required': ['id']
      }),
  ToolSpec('web_fetch', 'Ambil halaman web', 'Fetch a public http(s) URL and return its readable text (HTML stripped).',
      {
        'type': 'object',
        'properties': {
          'url': {'type': 'string'},
          'max_chars': {'type': 'integer', 'description': 'default 8000'}
        },
        'required': ['url']
      }),
  ToolSpec('current_time', 'Waktu sekarang', 'Return the current local date, time and timezone offset.',
      {'type': 'object', 'properties': {}}),
  ToolSpec('file_list', 'Daftar berkas', 'List files and folders in the app workspace directory (default root).',
      {'type': 'object', 'properties': {'dir': {'type': 'string'}}}),
  ToolSpec('file_read', 'Baca berkas', 'Read a text file from the app workspace.',
      {'type': 'object', 'properties': {'path': {'type': 'string'}}, 'required': ['path']}),
  ToolSpec('file_write', 'Tulis berkas',
      'Create or overwrite a text file in the app workspace (markdown, code, notes). The user can open it in the Files tab.',
      {
        'type': 'object',
        'properties': {'path': {'type': 'string'}, 'content': {'type': 'string'}},
        'required': ['path', 'content']
      }),
  ToolSpec('skill_load', 'Muat skill', 'Load the full instructions of a skill by name (see the skills catalog in the system prompt).',
      {'type': 'object', 'properties': {'name': {'type': 'string'}}, 'required': ['name']}),
];

/// Office tools: let the agent see and drive the virtual office.
const officeTools = <ToolSpec>[
  ToolSpec('office_view', 'Lihat kantor',
      'Look at the virtual office: returns a rendered picture of the isometric office (agents at their desks, in the meeting room '
      'or lounge, the Kanban wall) which you will see on the next step, plus the text status. Use it when you need to see the office.',
      {'type': 'object', 'properties': {}}, group: 'office'),
  ToolSpec('office_status', 'Status kantor',
      'Snapshot of the virtual office: every agent with status (idle/working/review/blocked/meeting) and current task, '
      'Kanban counts per column, live meeting, cron jobs.',
      {'type': 'object', 'properties': {}}, group: 'office'),
  ToolSpec('task_action', 'Aksi tugas',
      'Act on a Kanban task: run (start the assignee now), cancel (stop a running task), steer (send guidance to a running task, needs message), '
      'move (needs status), delete.',
      {
        'type': 'object',
        'properties': {
          'id': {'type': 'string'},
          'action': {'type': 'string', 'enum': ['run', 'cancel', 'steer', 'move', 'delete']},
          'message': {'type': 'string'},
          'status': {'type': 'string'}
        },
        'required': ['id', 'action']
      },
      group: 'office'),
  ToolSpec('list_meetings', 'Daftar rapat', 'List live and archived meetings; with id returns that meeting\'s minutes/transcript.',
      {'type': 'object', 'properties': {'id': {'type': 'string'}}}, group: 'office'),
  ToolSpec('start_meeting', 'Mulai rapat', 'Start a meeting between 2–4 agents on a topic; they take turns and produce minutes.',
      {
        'type': 'object',
        'properties': {
          'topic': {'type': 'string'},
          'participants': {'type': 'array', 'items': {'type': 'string'}},
          'moderator': {'type': 'string'}
        },
        'required': ['topic', 'participants']
      },
      group: 'office'),
  ToolSpec('list_cron', 'Daftar cron', 'List scheduled cron jobs with schedule, state, next and last run.',
      {'type': 'object', 'properties': {}}, group: 'office'),
  ToolSpec('create_cron', 'Buat cron',
      'Schedule a prompt: schedule like "30m", "every 2h" or a 5-field cron expression. Created paused unless paused=false.',
      {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'schedule': {'type': 'string'},
          'prompt': {'type': 'string'},
          'agent': {'type': 'string'},
          'paused': {'type': 'boolean'}
        },
        'required': ['schedule', 'prompt']
      },
      group: 'office'),
  ToolSpec('cron_action', 'Aksi cron', 'pause, resume, run (now) or remove a cron job by id.',
      {
        'type': 'object',
        'properties': {
          'id': {'type': 'string'},
          'action': {'type': 'string', 'enum': ['pause', 'resume', 'run', 'remove']}
        },
        'required': ['id', 'action']
      },
      group: 'office'),
  ToolSpec('manage_agent', 'Kelola agent', 'Create a new agent profile (action=create, name, role, description), bring one into the office (spawn) or remove it (kill).',
      {
        'type': 'object',
        'properties': {
          'action': {'type': 'string', 'enum': ['create', 'spawn', 'kill']},
          'name': {'type': 'string'},
          'role': {'type': 'string'},
          'description': {'type': 'string'}
        },
        'required': ['action', 'name']
      },
      group: 'office'),
];

/// Every tool the on-device agent knows, in settings order.
const allTools = <ToolSpec>[...appTools, ...officeTools, ...deviceTools];

/// Tools that existed in v1.0 (used to migrate the old "enabled" list).
const v10ToolNames = {
  'memory_read', 'memory_write', 'memory_delete', 'list_tasks', 'create_task', 'update_task',
  'web_fetch', 'current_time', 'file_list', 'file_read', 'file_write', 'skill_load',
};

ToolSpec? toolSpec(String name) => allTools.where((t) => t.name == name).firstOrNull;

/// Whether this particular call needs approval (some actions of a safe tool are destructive).
bool callIsRisky(String name, Map<String, dynamic> a) {
  final spec = toolSpec(name);
  if (spec == null) return false;
  if (spec.risky) return true;
  if (name == 'task_action' && a['action'] == 'delete') return true;
  if (name == 'cron_action' && a['action'] == 'remove') return true;
  if (name == 'manage_agent' && a['action'] == 'kill') return true;
  if (name == 'memory_delete') return true;
  return false;
}

/// The office as the agent sees it (LocalBackend implements this).
abstract class OfficeHooks {
  Future<ApiResult> request(String method, String path, {Map<String, String>? query, Map<String, dynamic>? body, Duration? timeout});
  List<Agent> agents();
  List<Meeting> liveMeetings();
}

/// Hooks the runtime uses to reach the local board without depending on it.
abstract class BoardHooks {
  Map<String, dynamic> createTask(Map<String, dynamic> body, String createdBy);
  String? updateTask(String id, Map<String, dynamic> patch);
}

class ToolResult {
  final String text;
  final String summary;
  final bool failed;
  /// Images (data URLs) to show the model on the next step (camera tool).
  final List<String> images;
  const ToolResult(this.text, this.summary, {this.failed = false, this.images = const []});
}

class AgentRuntime {
  /// Renders the office view to an image data URL (wired by the UI layer;
  /// null where rendering is unavailable).
  static Future<String?> Function()? officeSnapshot;

  AgentRuntime({required this.store, required this.llm, required this.enabledTools, this.board});

  final LocalStore store;
  final LlmClient? Function() llm;
  final Set<String> Function() enabledTools;
  BoardHooks? board;
  OfficeHooks? office;

  static const maxSteps = 10;

  /// Pending approval prompts (request id → completer), answered from chat.
  final Map<String, Completer<String>> _approvals = {};
  void resolveApproval(String requestId, String choice) => _approvals.remove(requestId)?.complete(choice);

  /// Short text snapshot of the office for the system prompt.
  String officeSummary() {
    final o = office;
    final b = StringBuffer();
    final agents = o?.agents() ?? const <Agent>[];
    if (agents.isNotEmpty) {
      b.writeln('Agen: ${agents.map((a) => '${a.name} (${a.role}) ${a.status}${a.currentTaskId != null ? ' → ${a.currentTaskId}' : ''}').join('; ')}.');
    }
    final counts = <String, int>{};
    for (final t in store.tasks) {
      counts[t.status] = (counts[t.status] ?? 0) + 1;
    }
    b.writeln('Papan Kanban: ${counts.isEmpty ? 'kosong' : counts.entries.map((e) => '${e.key} ${e.value}').join(', ')}.');
    final open = store.tasks.where((t) => t.status != 'done').take(8).toList();
    for (final t in open) {
      b.writeln('- ${t.id} [${t.status}] ${t.title} — ${t.assignee ?? 'belum ditugaskan'}');
    }
    final live = o?.liveMeetings().where((m) => m.live).toList() ?? const <Meeting>[];
    if (live.isNotEmpty) b.writeln('Rapat berlangsung: ${live.map((m) => '"${m.topic}" (${m.participants.join(', ')})').join('; ')}.');
    final jobs = store.jobs;
    if (jobs.isNotEmpty) {
      b.writeln('Cron: ${jobs.length} job (${jobs.where((j) => j.enabled).length} aktif): ${jobs.take(5).map((j) => '${j.id} "${j.name}" ${j.schedule}${j.enabled ? '' : ' (pause)'}').join('; ')}.');
    }
    return b.toString().trim();
  }

  String systemPrompt(Profile p, {String? extra, Project? project, ChatOptions? options}) {
    final now = DateTime.now();
    final mem = options?.memory == false ? const <MemoryNote>[] : store.memoryFor(p.name);
    final skills = store.skills.where((s) => s.enabled).toList();
    final agents = store.profiles.where((x) => !x.hidden).map((x) => '${x.name} (${x.role})').join(', ');
    final b = StringBuffer()
      ..writeln('Kamu adalah "${p.name}", agen Neovarch (peran: ${p.role}) yang berjalan langsung di ponsel pengguna lewat aplikasi Neovarch Agent.')
      ..writeln('Balas dalam bahasa yang dipakai pengguna (default Bahasa Indonesia). Gunakan Markdown; blok kode diberi nama bahasanya.')
      ..writeln('Tanggal/waktu perangkat: ${now.toIso8601String()} (UTC${now.timeZoneOffset.isNegative ? '-' : '+'}${now.timeZoneOffset.inHours}).')
      ..writeln('Agen lain di kantor: $agents.')
      ..writeln()
      ..writeln('## Kantor virtual (keadaan saat ini)')
      ..writeln('Kamu bisa melihat dan mengubah kantor lewat alat office_view (gambar), office_status, list_tasks, create_task, update_task, task_action, '
          'list_meetings, start_meeting, list_cron, create_cron, cron_action, manage_agent.')
      ..writeln(officeSummary())
      ..writeln()
      ..writeln('## Perangkat')
      ..writeln('Kamu berjalan di ponsel Android pengguna. Alat perangkat (device_info, notify, open_intent, location_get, contacts_search, '
          'calendar_events, apps_list, storage_*, document_pick, camera_capture, clipboard_*) meminta izin Android saat pertama dipakai; '
          'aksi yang sensitif menunggu persetujuan pengguna. Kamu tidak bisa mengetuk atau membaca layar aplikasi lain.');
    if (p.systemPrompt.trim().isNotEmpty) {
      b
        ..writeln()
        ..writeln('## Persona')
        ..writeln(p.systemPrompt.trim());
    }
    if (project != null) {
      b
        ..writeln()
        ..writeln('## Proyek aktif: ${project.name}')
        ..writeln(project.description)
        ..writeln(project.folder.isNotEmpty
            ? 'Folder kerja proyek di workspace: `${project.folder}/` — simpan berkas proyek di sana.'
            : '');
    }
    if (mem.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## Memori jangka panjang (dari memory_write)');
      for (final m in mem.take(40)) {
        b.writeln('- [${m.id}] ${m.text}');
      }
    }
    if (skills.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## Katalog skill (muat dengan skill_load sebelum dipakai)');
      for (final s in skills) {
        b.writeln('- ${s.name}: ${s.description}');
      }
    }
    if (options != null && options.persona.trim().isNotEmpty) {
      b
        ..writeln()
        ..writeln('## Instruksi sesi ini')
        ..writeln(options.persona.trim());
    }
    if (extra != null && extra.trim().isNotEmpty) {
      b
        ..writeln()
        ..writeln(extra.trim());
    }
    return b.toString();
  }

  /// Convert the display transcript to OpenAI messages.
  List<Map<String, dynamic>> toOpenAi(List<ChatMsg> history) {
    final out = <Map<String, dynamic>>[];
    for (final m in history) {
      if (m.role == 'user') {
        if (m.images.isEmpty) {
          out.add({'role': 'user', 'content': m.content});
        } else {
          out.add({
            'role': 'user',
            'content': [
              if (m.content.isNotEmpty) {'type': 'text', 'text': m.content},
              for (final img in m.images) {'type': 'image_url', 'image_url': {'url': img}},
            ]
          });
        }
      } else if (m.role == 'assistant') {
        final done = m.tools.where((t) => !t.running).toList();
        if (done.isEmpty) {
          if (m.content.trim().isEmpty) continue;
          out.add({'role': 'assistant', 'content': m.content});
        } else {
          out.add({
            'role': 'assistant',
            'content': m.content.isEmpty ? null : m.content,
            'tool_calls': [
              for (final t in done)
                {
                  'id': t.id,
                  'type': 'function',
                  'function': {'name': t.name, 'arguments': t.args.isEmpty ? '{}' : t.args}
                }
            ],
          });
          for (final t in done) {
            out.add({'role': 'tool', 'tool_call_id': t.id, 'content': t.result ?? ''});
          }
        }
      }
    }
    return out;
  }

  /// Resolve a client for a specific provider id (per-session model pick).
  LlmClient? Function(String providerId)? llmById;

  /// Run one turn. [history] must already end with the new user message.
  /// [interactive] = a person is watching the chat and can approve risky tools.
  Stream<ChatEvent> run({
    required Profile profile,
    required List<ChatMsg> history,
    String? extraSystem,
    Project? project,
    CancelToken? cancel,
    bool allowTools = true,
    List<String> Function()? pendingSteer,
    ChatOptions? options,
    bool interactive = false,
  }) async* {
    final opt = options ?? const ChatOptions();
    final client = (opt.providerId != null ? llmById?.call(opt.providerId!) : null) ?? llm();
    if (client == null || !client.configured) {
      yield const ErrorEvent('Penyedia LLM belum diatur. Buka Pengaturan → Penyedia & model.');
      return;
    }
    final model = (opt.model?.isNotEmpty == true ? opt.model : null) ??
        (profile.model?.isNotEmpty == true ? profile.model : null) ??
        client.model;
    final toolsOn = allowTools && opt.tools;
    final tools = toolsOn
        ? allTools
            .where((t) => enabledTools().contains(t.name) && opt.toolGroups.contains(t.group))
            .where((t) => offersDeviceTools || t.group != 'device')
            .where((t) => opt.memory || !t.name.startsWith('memory'))
            .map((t) => t.toOpenAi())
            .toList()
        : <Map<String, dynamic>>[];
    // Reasoning controls, per provider wire format.
    final wire = reasoningWireFor(client.baseUrl);
    final canReason = modelSupportsReasoning(model);
    final extra = canReason ? reasoningBody(wire, opt.effort, opt.reasoningBudget) : <String, dynamic>{};
    var sys = systemPrompt(profile, extra: extraSystem, project: project, options: opt);
    final msgs = <Map<String, dynamic>>[
      {'role': 'system', 'content': sys},
      ...toOpenAi(history),
    ];
    final sessionAllowed = <String>{};
    for (var step = 0; step < maxSteps; step++) {
      if (cancel?.isCancelled == true) break;
      final steer = pendingSteer?.call() ?? const [];
      for (final s in steer) {
        msgs.add({'role': 'user', 'content': '[Arahan dari pengguna] $s'});
      }
      yield const NewAssistantEvent();
      final acc = StringBuffer();
      final calls = <int, Map<String, String>>{};
      final sw = Stopwatch()..start();
      var completion = 0, prompt = 0;
      double? cost;
      String? finish;
      var inThink = false;
      try {
        await for (final c in client.stream(msgs,
            tools: tools.isEmpty ? null : tools,
            modelOverride: model,
            temperature: opt.temperature,
            topP: opt.topP,
            maxTokens: opt.maxTokens,
            streaming: opt.streaming,
            extra: extra,
            cancel: cancel)) {
          switch (c) {
            case LlmText(:final text):
              // Route inline <think> blocks to the reasoning disclosure.
              var t = text;
              while (t.isNotEmpty) {
                if (inThink) {
                  final end = t.indexOf('</think>');
                  if (end < 0) {
                    yield ReasoningEvent(t);
                    t = '';
                  } else {
                    yield ReasoningEvent(t.substring(0, end));
                    t = t.substring(end + 8);
                    inThink = false;
                  }
                } else {
                  final start = t.indexOf('<think>');
                  final visible = start < 0 ? t : t.substring(0, start);
                  if (visible.isNotEmpty) {
                    acc.write(visible);
                    yield DeltaEvent(visible);
                  }
                  if (start < 0) {
                    t = '';
                  } else {
                    t = t.substring(start + 7);
                    inThink = true;
                  }
                }
              }
            case LlmReasoning(:final text):
              yield ReasoningEvent(text);
            case LlmToolCallDelta(:final index, :final id, :final name, :final argsDelta):
              final e = calls.putIfAbsent(index, () => {'id': '', 'name': '', 'args': ''});
              if (id != null && id.isNotEmpty) e['id'] = id;
              if (name != null && name.isNotEmpty) e['name'] = e['name']! + name;
              e['args'] = e['args']! + argsDelta;
            case LlmFinish(:final reason, :final promptTokens, :final completionTokens, cost: final c2):
              finish = reason;
              prompt = promptTokens;
              completion = completionTokens;
              cost = c2;
          }
        }
      } on LlmException catch (e) {
        yield ErrorEvent(e.message);
        return;
      }
      final secs = sw.elapsedMilliseconds / 1000.0;
      if (completion == 0) completion = (acc.length / 4).round();
      if (prompt == 0) prompt = (jsonEncode(msgs).length / 4).round();
      yield UsageEvent(prompt, completion, secs > 0 ? completion / secs : 0, cost);
      if (cancel?.isCancelled == true || finish == 'cancelled') break;
      if (calls.isEmpty) {
        yield const DoneEvent();
        return;
      }
      // Execute tool calls, then loop with their results.
      final ordered = calls.keys.toList()..sort();
      final toolCalls = <Map<String, dynamic>>[];
      for (final i in ordered) {
        final c = calls[i]!;
        if (c['id']!.isEmpty) c['id'] = 'call_${DateTime.now().microsecondsSinceEpoch}_$i';
        toolCalls.add({
          'id': c['id'],
          'type': 'function',
          'function': {'name': c['name'], 'arguments': c['args']!.isEmpty ? '{}' : c['args']}
        });
      }
      msgs.add({'role': 'assistant', 'content': acc.isEmpty ? null : acc.toString(), 'tool_calls': toolCalls});
      final newImages = <String>[];
      for (final i in ordered) {
        final c = calls[i]!;
        yield ToolStartEvent(c['id']!, c['name']!, c['args']!);
        final t0 = Stopwatch()..start();
        Map<String, dynamic> parsed = {};
        try {
          final d = jsonDecode(c['args']!.isEmpty ? '{}' : c['args']!);
          if (d is Map) parsed = Map<String, dynamic>.from(d);
        } catch (_) {}
        ToolResult r;
        // Approval gate for risky calls (device/private data, deletes).
        String? denied;
        if (callIsRisky(c['name']!, parsed) && !sessionAllowed.contains(c['name'])) {
          if (opt.approval == 'deny') {
            denied = 'ditolak oleh mode persetujuan sesi ("Tolak semua")';
          } else if (opt.approval == 'ask') {
            if (!interactive) {
              denied = 'butuh persetujuan pengguna — hanya bisa dijalankan dari chat';
            } else {
              final rid = 'appr_${DateTime.now().microsecondsSinceEpoch}';
              final done = Completer<String>();
              _approvals[rid] = done;
              cancel?.onCancel(() {
                if (!done.isCompleted) done.complete('deny');
              });
              final spec = toolSpec(c['name']!);
              yield ApprovalEvent(rid, '${c['name']} ${const JsonEncoder.withIndent('  ').convert(parsed)}',
                  'Agen ingin memakai "${spec?.label ?? c['name']}". ${spec?.group == 'device' ? 'Ini menyentuh data/aplikasi di ponselmu.' : 'Aksi ini tidak bisa dibatalkan.'}',
                  const ['once', 'session', 'deny']);
              final choice = await done.future;
              if (choice == 'deny') denied = 'ditolak pengguna';
              if (choice == 'session' || choice == 'always') sessionAllowed.add(c['name']!);
            }
          }
        }
        if (denied != null) {
          r = ToolResult('error: $denied', denied, failed: true);
        } else {
          r = await execute(profile, c['name']!, c['args']!);
        }
        newImages.addAll(r.images);
        yield ToolDoneEvent(c['id']!, c['name']!,
            summary: r.summary,
            result: r.text,
            failed: r.failed,
            durationS: t0.elapsedMilliseconds / 1000.0);
        msgs.add({'role': 'tool', 'tool_call_id': c['id'], 'content': r.text});
      }
      if (newImages.isNotEmpty) {
        msgs.add({
          'role': 'user',
          'content': [
            {'type': 'text', 'text': '[Gambar dari alat camera_capture]'},
            for (final img in newImages) {'type': 'image_url', 'image_url': {'url': img}},
          ]
        });
      }
    }
    yield const DoneEvent();
  }

  Future<ToolResult> execute(Profile p, String name, String rawArgs) async {
    Map<String, dynamic> a;
    try {
      final d = rawArgs.trim().isEmpty ? {} : jsonDecode(rawArgs);
      a = d is Map ? Map<String, dynamic>.from(d) : {};
    } catch (_) {
      return const ToolResult('error: argumen bukan JSON yang valid', 'argumen tidak valid', failed: true);
    }
    if (!enabledTools().contains(name)) {
      return ToolResult('error: alat "$name" dinonaktifkan pengguna', 'alat dinonaktifkan', failed: true);
    }
    final dev = await runDeviceTool(name, a);
    if (dev != null) return dev;
    final off = await _officeTool(name, a);
    if (off != null) return off;
    try {
      switch (name) {
        case 'memory_read':
          final q = '${a['query'] ?? ''}'.toLowerCase();
          final notes = store.memoryFor(p.name).where((m) => q.isEmpty || m.text.toLowerCase().contains(q)).toList();
          if (notes.isEmpty) return const ToolResult('(memori kosong)', 'tidak ada catatan');
          return ToolResult(
              notes.map((m) => '[${m.id}] (${m.scope == '*' ? 'bersama' : m.scope}) ${m.text}').join('\n'),
              '${notes.length} catatan');
        case 'memory_write':
          final text = '${a['text'] ?? ''}'.trim();
          if (text.isEmpty) return const ToolResult('error: text kosong', 'teks kosong', failed: true);
          final m = store.addMemory(a['scope'] == 'shared' ? '*' : p.name, text);
          return ToolResult('tersimpan dengan id ${m.id}', 'Disimpan: ${_clip(text, 60)}');
        case 'memory_delete':
          final ok = store.deleteMemory('${a['id']}');
          return ToolResult(ok ? 'dihapus' : 'id tidak ditemukan', ok ? 'catatan dihapus' : 'id tidak ditemukan',
              failed: !ok);
        case 'list_tasks':
          final st = '${a['status'] ?? ''}';
          final list = store.tasks.where((t) => st.isEmpty || t.status == st).toList();
          if (list.isEmpty) return const ToolResult('(papan kosong)', '0 tugas');
          return ToolResult(
              list.map((t) => '${t.id} [${t.status}] ${t.title} — ${t.assignee ?? '-'} (p${t.priority})').join('\n'),
              '${list.length} tugas');
        case 'create_task':
          if (board == null) return const ToolResult('error: papan tidak tersedia', 'papan tidak tersedia', failed: true);
          final r = board!.createTask(a, 'agent:${p.name}');
          if (r['error'] != null) return ToolResult('error: ${r['error']}', '${r['error']}', failed: true);
          return ToolResult('tugas dibuat: ${r['id']}', 'Tugas "${_clip('${a['title']}', 50)}" dibuat');
        case 'update_task':
          if (board == null) return const ToolResult('error: papan tidak tersedia', 'papan tidak tersedia', failed: true);
          final err = board!.updateTask('${a['id']}', a);
          if (err != null) return ToolResult('error: $err', err, failed: true);
          return ToolResult('tugas ${a['id']} diperbarui', 'Tugas ${a['id']} diperbarui');
        case 'current_time':
          final n = DateTime.now();
          return ToolResult('${n.toIso8601String()} (offset ${n.timeZoneOffset.inMinutes} menit, ${n.timeZoneName})',
              '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}');
        case 'web_fetch':
          return await _webFetch('${a['url'] ?? ''}', (a['max_chars'] as num?)?.toInt() ?? 8000);
        case 'file_list':
          final (dirs, files) = store.listDir('${a['dir'] ?? ''}');
          final lines = [...dirs.map((d) => '$d/'), ...files.map((f) => '${f.name} (${f.size} b)')];
          return ToolResult(lines.isEmpty ? '(folder kosong)' : lines.join('\n'), '${lines.length} entri');
        case 'file_read':
          final f = store.readFile('${a['path']}');
          if (f == null) return ToolResult('error: berkas ${a['path']} tidak ada', 'tidak ditemukan', failed: true);
          return ToolResult(_clip(f.content, 20000), 'Membaca ${f.path} (${_size(f.size)})');
        case 'file_write':
          final f = store.writeFile('${a['path']}', '${a['content'] ?? ''}');
          return ToolResult('tertulis: ${f.path} (${f.size} karakter)', 'Menulis ${f.path} (${_size(f.size)})');
        case 'skill_load':
          final s = store.skills.where((x) => x.name == '${a['name']}').firstOrNull;
          if (s == null) return ToolResult('error: skill ${a['name']} tidak ada', 'skill tidak ada', failed: true);
          return ToolResult(s.body, 'Memuat skill ${s.name}');
      }
      return ToolResult('error: alat $name tidak dikenal', 'alat tidak dikenal', failed: true);
    } catch (e) {
      return ToolResult('error: $e', 'gagal: ${_clip('$e', 60)}', failed: true);
    }
  }

  Future<ToolResult?> _officeTool(String name, Map<String, dynamic> a) async {
    if (!officeTools.any((t) => t.name == name)) return null;
    final o = office;
    if (o == null) return const ToolResult('error: kantor tidak tersedia di mode ini', 'kantor tidak tersedia', failed: true);
    ToolResult fromApi(ApiResult r, String okSummary) => r.ok
        ? ToolResult(const JsonEncoder.withIndent(' ').convert(r.data), okSummary)
        : ToolResult('error: ${r.error}', '${r.error}', failed: true);
    switch (name) {
      case 'office_status':
        return ToolResult(officeSummary(), '${o.agents().length} agent · ${store.tasks.length} tugas');
      case 'office_view':
        String? img;
        try {
          img = await officeSnapshot?.call();
        } catch (_) {}
        return ToolResult(
            '${img == null ? '(gambar kantor tidak tersedia; status teks saja)\n' : 'Gambar kantor dilampirkan untuk langkah berikutnya.\n'}${officeSummary()}',
            img == null ? 'Status kantor (teks)' : 'Melihat kantor',
            images: img == null ? const [] : [img]);
      case 'task_action':
        final id = '${a['id'] ?? ''}';
        final r = await o.request('POST', '/api/neovarch/tasks/${Uri.encodeComponent(id)}', body: {
          'action': '${a['action']}',
          if (a['message'] != null) 'message': '${a['message']}',
          if (a['status'] != null) 'status': '${a['status']}',
        });
        return fromApi(r, 'Tugas $id: ${a['action']}');
      case 'list_meetings':
        final id = a['id'] as String?;
        final r = await o.request('GET', '/api/neovarch/meeting', query: id != null && id.isNotEmpty ? {'id': id} : null);
        if (!r.ok) return fromApi(r, '');
        if (id != null && id.isNotEmpty) return ToolResult(_clip('${r.map['body']}', 20000), 'Notulen $id');
        final live = r.list('live');
        final arch = r.list('archived');
        final lines = [
          for (final m in live) 'LIVE ${m['id']} "${m['topic']}" ${m['state']} · ${(m['participants'] as List?)?.join(', ')}',
          for (final m in arch.take(15)) 'ARSIP ${m['id']} "${m['topic']}"',
        ];
        return ToolResult(lines.isEmpty ? '(belum ada rapat)' : lines.join('\n'), '${live.length} berlangsung · ${arch.length} arsip');
      case 'start_meeting':
        final r = await o.request('POST', '/api/neovarch/meeting', body: {
          'topic': '${a['topic'] ?? ''}',
          'participants': a['participants'] is List ? a['participants'] : '${a['participants'] ?? ''}'.split(RegExp(r'[,\s]+')),
          'moderator': ?a['moderator'],
          'mode': 'auto',
        });
        return fromApi(r, 'Rapat "${_clip('${a['topic']}', 40)}" dimulai');
      case 'list_cron':
        final r = await o.request('GET', '/api/neovarch/cron');
        if (!r.ok) return fromApi(r, '');
        final jobs = r.list('jobs');
        return ToolResult(
            jobs.isEmpty
                ? '(belum ada job)'
                : jobs.map((j) => '${j['id']} "${j['name']}" ${j['schedule']} ${j['enabled'] == true ? 'aktif' : 'pause'} · berikut ${j['nextRunAt'] ?? '-'} · terakhir ${j['lastStatus'] ?? '-'}').join('\n'),
            '${jobs.length} job');
      case 'create_cron':
        final r = await o.request('POST', '/api/neovarch/cron', body: {'action': 'create', ...a});
        return fromApi(r, 'Cron "${a['name'] ?? a['schedule']}" dibuat${a['paused'] == false ? '' : ' (pause)'}');
      case 'cron_action':
        final r = await o.request('POST', '/api/neovarch/cron', body: {'action': '${a['action']}', 'id': '${a['id']}'});
        return fromApi(r, 'Cron ${a['id']}: ${a['action']}');
      case 'manage_agent':
        final r = await o.request('POST', '/api/neovarch/agents', body: a);
        return fromApi(r, 'Agent ${a['name']}: ${a['action']}');
    }
    return null;
  }

  Future<ToolResult> _webFetch(String url, int maxChars) async {
    final u = Uri.tryParse(url);
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https')) {
      return const ToolResult('error: hanya URL http(s)', 'URL tidak valid', failed: true);
    }
    final r = await http.get(u, headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) NeovarchAgent/1.1',
      'Accept': 'text/html,text/plain,application/json;q=0.9,*/*;q=0.5',
    }).timeout(const Duration(seconds: 20));
    var body = r.body;
    final ct = r.headers['content-type'] ?? '';
    String title = '';
    if (ct.contains('html') || body.trimLeft().startsWith('<')) {
      final tm = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false).firstMatch(body);
      title = tm != null ? _decode(tm.group(1)!.trim()) : '';
      body = htmlToText(body);
    }
    final text = _clip(body, maxChars.clamp(500, 30000));
    return ToolResult('URL: $url\nHTTP ${r.statusCode}\n${title.isNotEmpty ? 'Judul: $title\n' : ''}\n$text',
        'Mengambil ${u.host}${title.isNotEmpty ? ' — ${_clip(title, 40)}' : ''} (${_size(body.length)})',
        failed: r.statusCode >= 400);
  }
}

String htmlToText(String html) {
  var s = html
      .replaceAll(RegExp(r'<(script|style|noscript|svg|head)[^>]*>[\s\S]*?</\1>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|h[1-6]|li|tr|section|article)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ');
  s = _decode(s);
  s = s.replaceAll(RegExp(r'[ \t\f\r]+'), ' ').replaceAll(RegExp(r'\n\s*\n\s*(\n\s*)+'), '\n\n');
  return s.trim();
}

String _decode(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&#x27;', "'");

String _clip(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}…';
String _size(int n) => n < 1024 ? '$n b' : '${(n / 1024).toStringAsFixed(1)} KB';
