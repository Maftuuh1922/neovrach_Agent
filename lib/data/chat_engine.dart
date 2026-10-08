// Chat engines: one UI (ChatScreen) over three ways of talking to an agent.
//
//   LocalChatEngine   — the on-device runtime (streaming + tools), sessions
//                       and transcripts persisted on the phone.
//   GatewayChatEngine — a remote Neovarch core gateway over JSON-RPC/WebSocket.
//   OfficeChatEngine  — `/api/neovarch/chat` of the Next.js office server (or
//                       the demo): one thread per agent, no streaming.
import 'dart:async';

import '../models/chat_options.dart';
import '../models/models.dart';
import 'agent_runtime.dart';
import 'gateway_client.dart';
import 'llm_client.dart';
import 'local_store.dart';
import 'office_backend.dart';

abstract class ChatEngine {
  String get kind;
  bool get supportsImages => false;
  bool get canRename => true;
  bool get canCreate => true;
  bool get perAgentThreads => false;

  Future<List<ChatSessionInfo>> listSessions();
  Future<ChatSessionInfo> createSession({required String profile, String? projectId});
  Future<List<ChatMsg>> history(ChatSessionInfo s);

  /// [history] already ends with [user].
  Stream<ChatEvent> send(ChatSessionInfo s, List<ChatMsg> history, ChatMsg user);
  Future<void> rename(ChatSessionInfo s, String title);
  Future<void> delete(ChatSessionInfo s);
  Future<void> interrupt(ChatSessionInfo s);
  Future<void> respondApproval(ChatSessionInfo s, String requestId, String choice) async {}
  Future<void> setProject(ChatSessionInfo s, String? projectId) async {}
  void saveTranscript(ChatSessionInfo s, List<ChatMsg> msgs) {}
  Future<List<String>> profiles();
  void dispose() {}
}

// ------------------------------------------------------------------ local --

class LocalChatEngine extends ChatEngine {
  LocalChatEngine(this.store, this.runtime, {this.optionsFor});
  final LocalStore store;
  final AgentRuntime runtime;
  /// Per-session chat options (model, reasoning, tools, approval …).
  final ChatOptions Function(String sessionId)? optionsFor;
  final Map<String, CancelToken> _cancel = {};

  @override
  String get kind => 'local';
  @override
  bool get supportsImages => true;

  @override
  Future<List<ChatSessionInfo>> listSessions() async => List.of(store.sessions);

  @override
  Future<ChatSessionInfo> createSession({required String profile, String? projectId}) async =>
      store.createSession(profile, projectId: projectId);

  @override
  Future<List<ChatMsg>> history(ChatSessionInfo s) => store.messages(s.id);

  @override
  Stream<ChatEvent> send(ChatSessionInfo s, List<ChatMsg> history, ChatMsg user) async* {
    final p = store.profile(s.profile) ?? store.profiles.first;
    final token = CancelToken();
    _cancel[s.id] = token;
    final project = store.projects.where((x) => x.id == s.projectId).firstOrNull;
    yield* runtime.run(profile: p, history: history, project: project, cancel: token, options: optionsFor?.call(s.id), interactive: true);
    _cancel.remove(s.id);
    // First exchange: give the session a short title, as Desktop does.
    if (s.title == 'Percakapan baru' && !token.isCancelled) {
      final c = runtime.llm();
      if (c != null && c.configured) {
        try {
          final t = await c.complete([
            {
              'role': 'system',
              'content': 'Buat judul percakapan 2-6 kata dari pesan pengguna. Balas judulnya saja tanpa tanda kutip.'
            },
            {'role': 'user', 'content': user.content.isEmpty ? '(gambar)' : user.content},
          ], maxTokens: 24, modelOverride: p.model);
          final clean = t.replaceAll(RegExp(r'''^["'\s#*]+|["'\s*.]+$'''), '');
          if (clean.isNotEmpty && clean.length < 80) yield TitleEvent(clean);
        } catch (_) {
          final fallback = user.content.trim();
          if (fallback.isNotEmpty) {
            yield TitleEvent(fallback.length > 40 ? '${fallback.substring(0, 40)}…' : fallback);
          }
        }
      }
    }
  }

  @override
  Future<void> respondApproval(ChatSessionInfo s, String requestId, String choice) async => runtime.resolveApproval(requestId, choice);

  @override
  Future<void> rename(ChatSessionInfo s, String title) async => store.updateSession(s.copyWith(title: title));

  @override
  Future<void> delete(ChatSessionInfo s) => store.deleteSession(s.id);

  @override
  Future<void> interrupt(ChatSessionInfo s) async => _cancel[s.id]?.cancel();

  @override
  Future<void> setProject(ChatSessionInfo s, String? projectId) async =>
      store.updateSession(s.copyWith(projectId: projectId, clearProject: projectId == null));

  @override
  void saveTranscript(ChatSessionInfo s, List<ChatMsg> msgs) {
    store.saveMessages(s.id, msgs);
    final last = msgs.lastWhere((m) => m.role == 'assistant' && m.content.isNotEmpty,
        orElse: () => msgs.isNotEmpty ? msgs.last : ChatMsg(id: '', role: 'user', ts: 0));
    final cur = store.sessions.where((x) => x.id == s.id).firstOrNull ?? s;
    store.updateSession(cur.copyWith(
      updatedAt: DateTime.now().toIso8601String(),
      messageCount: msgs.where((m) => m.role == 'user' || m.role == 'assistant').length,
      preview: last.content.length > 120 ? last.content.substring(0, 120) : last.content,
    ));
  }

  @override
  Future<List<String>> profiles() async => store.profiles.where((p) => !p.hidden).map((p) => p.name).toList();
}

// ---------------------------------------------------------------- gateway --

class GatewayChatEngine extends ChatEngine {
  GatewayChatEngine(this.client, {this.profile});
  final GatewayClient client;
  final String? profile;
  final Map<String, String> _live = {}; // stored id -> live session id
  final Map<String, dynamic> _approvalRid = {};

  @override
  String get kind => 'gateway';
  @override
  bool get supportsImages => false;

  Map<String, dynamic> get _p => {if (profile != null && profile!.isNotEmpty) 'profile': profile};

  @override
  Future<List<ChatSessionInfo>> listSessions() async {
    final r = await client.call('session.list', {..._p, 'limit': 100});
    final rows = (r is Map ? r['sessions'] : null) as List? ?? [];
    return rows.whereType<Map>().map((row) {
      final started = row['started_at'];
      final ts = started is num
          ? DateTime.fromMillisecondsSinceEpoch((started * (started > 1e12 ? 1 : 1000)).toInt()).toIso8601String()
          : '${started ?? ''}';
      return ChatSessionInfo(
        id: '${row['id']}',
        title: '${row['title'] ?? row['preview'] ?? row['id']}',
        profile: profile ?? 'default',
        updatedAt: ts,
        messageCount: (row['message_count'] as num?)?.toInt() ?? 0,
        preview: '${row['preview'] ?? ''}',
      );
    }).toList();
  }

  @override
  Future<ChatSessionInfo> createSession({required String profile, String? projectId}) async {
    final r = await client.call('session.create', {..._p, 'source': 'mobile'}) as Map;
    final live = '${r['session_id']}';
    final stored = '${r['stored_session_id'] ?? live}';
    _live[stored] = live;
    return ChatSessionInfo(
        id: stored, title: 'Percakapan baru', profile: this.profile ?? 'default', updatedAt: DateTime.now().toIso8601String());
  }

  Future<String> _liveId(ChatSessionInfo s) async {
    final known = _live[s.id];
    if (known != null) return known;
    final r = await client.call('session.resume', {..._p, 'session_id': s.id, 'source': 'mobile'}) as Map;
    final live = '${r['session_id']}';
    _live[s.id] = live;
    return live;
  }

  @override
  Future<List<ChatMsg>> history(ChatSessionInfo s) async {
    final r = await client.call('session.resume', {..._p, 'session_id': s.id, 'source': 'mobile'}) as Map;
    _live[s.id] = '${r['session_id']}';
    final msgs = (r['messages'] as List?) ?? [];
    final out = <ChatMsg>[];
    var i = 0;
    for (final m in msgs.whereType<Map>()) {
      final role = '${m['role'] ?? ''}';
      if (role != 'user' && role != 'assistant') continue;
      var content = m['content'] ?? m['text'] ?? '';
      if (content is List) {
        content = content.whereType<Map>().map((p) => p['text'] ?? '').join('\n');
      }
      out.add(ChatMsg(id: 'h${i++}', role: role, content: '$content', ts: 0));
    }
    return out;
  }

  @override
  Stream<ChatEvent> send(ChatSessionInfo s, List<ChatMsg> history, ChatMsg user) async* {
    final String sid;
    try {
      sid = await _liveId(s);
    } catch (e) {
      yield ErrorEvent('$e');
      return;
    }
    final out = StreamController<ChatEvent>();
    var afterTool = false;
    final sw = Stopwatch()..start();
    var chars = 0;
    late final StreamSubscription sub;
    sub = client.events.listen((f) {
      if (f.type == 'gateway.disconnected') {
        out.add(const ErrorEvent('koneksi gateway terputus'));
        out.close();
        return;
      }
      if (f.sessionId != null && f.sessionId != sid) return;
      final p = f.payload;
      switch (f.type) {
        case 'message.delta':
          if (afterTool) {
            out.add(const NewAssistantEvent());
            afterTool = false;
          }
          final t = '${p['text'] ?? ''}';
          chars += t.length;
          out.add(DeltaEvent(t));
        case 'reasoning.delta' || 'thinking.delta':
          out.add(ReasoningEvent('${p['text'] ?? ''}'));
        case 'tool.start':
          out.add(ToolStartEvent('${p['tool_id']}', '${p['name']}', '${p['args_text'] ?? p['preview'] ?? p['args'] ?? ''}'));
        case 'tool.complete':
          afterTool = true;
          out.add(ToolDoneEvent('${p['tool_id']}', '${p['name']}',
              summary: p['summary'] as String?,
              result: (p['result_text'] ?? p['result'])?.toString(),
              durationS: (p['duration_s'] as num?)?.toDouble()));
        case 'session.title':
          out.add(TitleEvent('${p['title']}'));
        case 'approval.request' || 'server.approval.request':
          final rid = p['request_id'] ?? p['_rid'];
          _approvalRid['$rid'] = p['_rid'];
          out.add(ApprovalEvent('$rid', '${p['command'] ?? ''}', '${p['description'] ?? ''}',
              ((p['choices'] as List?) ?? ['once', 'session', 'deny']).map((e) => e is Map ? '${e['id'] ?? e['value'] ?? e}' : '$e').toList()));
        case 'error':
          out.add(ErrorEvent('${p['message'] ?? 'galat gateway'}'));
          out.close();
        case 'message.complete':
          final u = p['usage'];
          final secs = sw.elapsedMilliseconds / 1000.0;
          final ct = u is Map ? ((u['output_tokens'] ?? u['completion_tokens']) as num?)?.toInt() ?? chars ~/ 4 : chars ~/ 4;
          final pt = u is Map ? ((u['input_tokens'] ?? u['prompt_tokens']) as num?)?.toInt() ?? 0 : 0;
          out.add(UsageEvent(pt, ct, secs > 0 ? ct / secs : 0));
          out.add(const DoneEvent());
          out.close();
      }
    });
    out.onCancel = () => sub.cancel();
    yield const NewAssistantEvent();
    try {
      await client.call('prompt.submit', {..._p, 'session_id': sid, 'text': user.content, 'surface': 'mobile'});
    } catch (e) {
      await sub.cancel();
      yield ErrorEvent('$e');
      return;
    }
    yield* out.stream;
    await sub.cancel();
  }

  @override
  Future<void> rename(ChatSessionInfo s, String title) async =>
      client.call('session.title', {..._p, 'session_id': await _liveId(s), 'title': title});

  @override
  Future<void> delete(ChatSessionInfo s) async => client.call('session.delete', {..._p, 'session_id': s.id});

  @override
  Future<void> interrupt(ChatSessionInfo s) async {
    final id = _live[s.id];
    if (id != null) await client.call('session.interrupt', {..._p, 'session_id': id});
  }

  @override
  Future<void> respondApproval(ChatSessionInfo s, String requestId, String choice) async {
    final rid = _approvalRid.remove(requestId);
    if (rid != null && rid is String && rid.isNotEmpty) {
      client.respondServerRequest(rid, {'choice': choice});
    }
    await client.call('approval.respond', {..._p, 'session_id': _live[s.id] ?? s.id, 'choice': choice, 'request_id': requestId});
  }

  @override
  Future<List<String>> profiles() async => [profile ?? 'default'];

  @override
  void dispose() => client.close();
}

// ----------------------------------------------------------------- office --

class OfficeChatEngine extends ChatEngine {
  OfficeChatEngine(this.backend);
  final OfficeBackend backend;
  List<String> _profiles = [];

  @override
  String get kind => 'office';
  @override
  bool get canRename => false;
  @override
  bool get perAgentThreads => true;

  @override
  Future<List<ChatSessionInfo>> listSessions() async {
    final r = await backend.get('/api/neovarch/chat');
    if (!r.ok) throw Exception(r.error ?? 'gagal memuat daftar percakapan');
    final sessions = r.list('sessions');
    final byAgent = {for (final s in sessions) '${s['agent']}': s};
    _profiles = ((r.map['profiles'] as List?) ?? []).map((e) => '$e').toList();
    final agents = ((r.map['agents'] as List?) ?? []).map((e) => '$e').toList();
    final names = [...sessions.map((s) => '${s['agent']}'), ...agents.where((a) => !byAgent.containsKey(a)).toList()..sort()];
    return names.map((n) {
      final s = byAgent[n];
      return ChatSessionInfo(
        id: n,
        title: s != null ? '${s['title']}' : (_profiles.contains(n) ? 'mulai percakapan' : 'belum punya profil'),
        profile: n,
        updatedAt: '${s?['updatedAt'] ?? ''}',
        messageCount: (s?['messageCount'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  @override
  Future<ChatSessionInfo> createSession({required String profile, String? projectId}) async =>
      ChatSessionInfo(id: profile, title: 'percakapan baru', profile: profile);

  @override
  Future<List<ChatMsg>> history(ChatSessionInfo s) async {
    final r = await backend.get('/api/neovarch/chat', {'agent': s.profile});
    if (!r.ok) throw Exception(r.error ?? 'gagal memuat percakapan');
    var i = 0;
    return r
        .list('messages')
        .where((m) => m['role'] == 'user' || m['role'] == 'assistant')
        .map((m) => ChatMsg(id: 'o${i++}', role: '${m['role']}', content: '${m['content'] ?? ''}', ts: (m['ts'] as num?)?.toInt() ?? 0))
        .toList();
  }

  @override
  Stream<ChatEvent> send(ChatSessionInfo s, List<ChatMsg> history, ChatMsg user) async* {
    yield const NewAssistantEvent();
    // A reply can take minutes because the agent may run tools.
    final r = await backend.post('/api/neovarch/chat', {'agent': s.profile, 'message': user.content},
        timeout: const Duration(seconds: 300));
    if (!r.ok) {
      yield ErrorEvent(r.error ?? 'agent tidak menjawab');
      return;
    }
    yield DeltaEvent('${r.map['reply'] ?? '(kosong)'}');
    yield const DoneEvent();
  }

  @override
  Future<void> rename(ChatSessionInfo s, String title) async {}

  @override
  Future<void> delete(ChatSessionInfo s) async {
    final r = await backend.delete('/api/neovarch/chat', {'agent': s.profile});
    if (!r.ok) throw Exception(r.error ?? 'gagal menghapus thread');
  }

  @override
  Future<void> interrupt(ChatSessionInfo s) async {}

  @override
  Future<List<String>> profiles() async => _profiles;
}
