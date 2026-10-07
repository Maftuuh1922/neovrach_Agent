// Chat state: the session list, the open transcript, streaming, tools,
// queue, approvals, and per-session drafts. One controller over whichever
// ChatEngine the connection mode provides.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/chat_engine.dart';
import '../models/models.dart';
import 'app_controller.dart';

class PendingApproval {
  final String requestId;
  final String command;
  final String description;
  final List<String> choices;
  const PendingApproval(this.requestId, this.command, this.description, this.choices);
}

class ChatController extends ChangeNotifier {
  ChatController(this.app);
  final AppController app;
  ChatEngine get engine => app.chat;

  List<ChatSessionInfo> _sessions = [];

  /// On-device sessions live in the store (the authority); remote ones are
  /// a cache of the server's list.
  List<ChatSessionInfo> get sessions => engine is LocalChatEngine ? app.store.sessions : _sessions;
  set sessions(List<ChatSessionInfo> v) {
    if (engine is LocalChatEngine) return;
    _sessions = v;
  }

  bool listLoading = false;
  String? listError;

  ChatSessionInfo? current;
  List<ChatMsg> messages = [];
  bool historyLoading = false;
  bool streaming = false;
  String? error;
  PendingApproval? approval;
  double? tokensPerSecond;
  int contextTokens = 0;

  // /usage — totals for the open session (this app run).
  int usagePrompt = 0;
  int usageCompletion = 0;
  double usageCost = 0;
  int usageTurns = 0;

  /// Prompts typed while a turn streams; sent in order afterwards.
  final List<String> queue = [];
  final Map<String, String> drafts = {};
  final List<String> promptHistory = [];

  /// Called with the final assistant text (voice read-back).
  void Function(String text)? onReply;

  StreamSubscription<ChatEvent>? _sub;
  int _gen = 0;

  void reset() {
    _sub?.cancel();
    _sub = null;
    _sessions = [];
    current = null;
    messages = [];
    streaming = false;
    error = null;
    approval = null;
    queue.clear();
    notifyListeners();
    unawaited(loadSessions());
  }

  Future<void> loadSessions() async {
    listLoading = true;
    listError = null;
    notifyListeners();
    try {
      sessions = await engine.listSessions();
    } catch (e) {
      listError = '$e'.replaceFirst('Exception: ', '');
    }
    listLoading = false;
    notifyListeners();
  }

  Future<void> open(ChatSessionInfo s) async {
    if (current?.id == s.id && messages.isNotEmpty) return;
    final gen = ++_gen;
    current = s;
    messages = [];
    error = null;
    approval = null;
    usagePrompt = usageCompletion = usageTurns = 0;
    usageCost = 0;
    historyLoading = true;
    app.settings.rememberSession(s.id);
    notifyListeners();
    try {
      final h = await engine.history(s);
      if (gen != _gen) return; // a newer open won: never clobber it
      messages = h;
    } catch (e) {
      if (gen != _gen) return;
      error = '$e'.replaceFirst('Exception: ', '');
    }
    historyLoading = false;
    notifyListeners();
  }

  Future<ChatSessionInfo?> newSession({String? profile, String? projectId}) async {
    try {
      final s = await engine.createSession(profile: profile ?? app.settings.defaultProfile, projectId: projectId);
      if (!sessions.any((x) => x.id == s.id)) sessions.insert(0, s);
      _gen++;
      current = s;
      messages = [];
      error = null;
      approval = null;
      app.settings.rememberSession(s.id);
      notifyListeners();
      return s;
    } catch (e) {
      error = '$e'.replaceFirst('Exception: ', '');
      notifyListeners();
      return null;
    }
  }

  void closeSession() {
    _gen++;
    current = null;
    messages = [];
    notifyListeners();
  }

  Future<void> send(String text, {List<String> images = const []}) async {
    final t = text.trim();
    if (t.isEmpty && images.isEmpty) return;
    if (streaming) {
      queue.add(t);
      notifyListeners();
      return;
    }
    var s = current ?? await newSession();
    if (s == null) return;
    if (promptHistory.isEmpty || promptHistory.last != t) promptHistory.add(t);
    final user = ChatMsg(
      id: 'u${DateTime.now().microsecondsSinceEpoch}',
      role: 'user',
      content: t,
      images: images,
      ts: DateTime.now().millisecondsSinceEpoch,
    );
    messages = [...messages, user];
    drafts.remove(s.id);
    streaming = true;
    error = null;
    notifyListeners();

    ChatMsg? cur;
    final history = List<ChatMsg>.of(messages);
    final completer = Completer<void>();
    _sub = engine.send(s, history, user).listen((e) {
      switch (e) {
        case NewAssistantEvent():
          if (cur == null || cur!.content.isNotEmpty || cur!.tools.isNotEmpty) {
            cur?.streaming = false;
            cur = ChatMsg(
                id: 'a${DateTime.now().microsecondsSinceEpoch}',
                role: 'assistant',
                ts: DateTime.now().millisecondsSinceEpoch,
                streaming: true);
            messages = [...messages, cur!];
          }
        case DeltaEvent(:final text):
          cur ??= _ensureAssistant();
          cur!.content += text;
        case ReasoningEvent(:final text):
          cur ??= _ensureAssistant();
          cur!.reasoning += text;
        case ToolStartEvent(:final id, :final name, :final args):
          cur ??= _ensureAssistant();
          cur!.tools.add(ToolActivity(id: id, name: name, args: args));
        case ToolDoneEvent(:final id, :final name, :final summary, :final result, :final failed, :final durationS):
          cur ??= _ensureAssistant();
          final t = cur!.tools.where((x) => x.id == id).firstOrNull;
          if (t != null) {
            t
              ..running = false
              ..summary = summary
              ..result = result
              ..failed = failed
              ..durationS = durationS;
          } else {
            cur!.tools.add(ToolActivity(id: id, name: name, summary: summary, result: result, running: false, failed: failed, durationS: durationS));
          }
        case TitleEvent(:final title):
          final c = current;
          if (c != null) {
            current = c.copyWith(title: title);
            final i = sessions.indexWhere((x) => x.id == c.id);
            if (i >= 0) sessions[i] = sessions[i].copyWith(title: title);
            engine.rename(current!, title);
          }
        case UsageEvent(:final promptTokens, :final completionTokens, :final tokensPerSecond, :final cost):
          this.tokensPerSecond = tokensPerSecond;
          if (promptTokens > 0) contextTokens = promptTokens + completionTokens;
          usagePrompt += promptTokens;
          usageCompletion += completionTokens;
          usageTurns++;
          if (cost != null) usageCost += cost;
        case ApprovalEvent(:final requestId, :final command, :final description, :final choices):
          approval = PendingApproval(requestId, command, description, choices);
        case ErrorEvent(:final message):
          error = message;
          cur?.error = message;
        case DoneEvent():
          break;
      }
      notifyListeners();
    }, onDone: () => completer.complete(), onError: (Object e) {
      error = '$e';
      completer.complete();
    });
    await completer.future;
    _sub = null;
    for (final m in messages) {
      m.streaming = false;
      for (final t in m.tools) {
        t.running = false;
      }
    }
    // Drop an empty trailing assistant shell (e.g. stopped before a token).
    if (messages.isNotEmpty &&
        messages.last.role == 'assistant' &&
        messages.last.content.isEmpty &&
        messages.last.tools.isEmpty &&
        messages.last.error == null) {
      messages = messages.sublist(0, messages.length - 1);
    }
    streaming = false;
    s = current ?? s;
    engine.saveTranscript(s, messages);
    final last = messages.lastOrNull;
    if (last != null && last.role == 'assistant' && last.content.isNotEmpty && last.error == null) {
      onReply?.call(last.content);
    }
    notifyListeners();
    if (engine is! LocalChatEngine) unawaited(loadSessions());
    if (queue.isNotEmpty) {
      final next = queue.removeAt(0);
      unawaited(send(next));
    }
  }

  ChatMsg _ensureAssistant() {
    final m = ChatMsg(id: 'a${DateTime.now().microsecondsSinceEpoch}', role: 'assistant', ts: DateTime.now().millisecondsSinceEpoch, streaming: true);
    messages = [...messages, m];
    return m;
  }

  Future<void> stop() async {
    queue.clear();
    final s = current;
    if (s != null) await engine.interrupt(s);
    await _sub?.cancel();
    _sub = null;
    if (streaming) {
      streaming = false;
      for (final m in messages) {
        m.streaming = false;
      }
      if (s != null) engine.saveTranscript(s, messages);
      notifyListeners();
    }
  }

  /// Re-run the last user prompt (error card "Coba lagi").
  Future<void> retry() async {
    final idx = messages.lastIndexWhere((m) => m.role == 'user');
    if (idx < 0) return;
    final u = messages[idx];
    messages = messages.sublist(0, idx);
    notifyListeners();
    await send(u.content, images: u.images);
  }

  Future<void> respondApproval(String choice) async {
    final a = approval;
    final s = current;
    if (a == null || s == null) return;
    approval = null;
    notifyListeners();
    await engine.respondApproval(s, a.requestId, choice);
  }

  Future<String?> rename(ChatSessionInfo s, String title) async {
    try {
      await engine.rename(s, title);
      final i = sessions.indexWhere((x) => x.id == s.id);
      if (i >= 0) sessions[i] = sessions[i].copyWith(title: title);
      if (current?.id == s.id) current = current!.copyWith(title: title);
      notifyListeners();
      return null;
    } catch (e) {
      return '$e';
    }
  }

  Future<String?> delete(ChatSessionInfo s) async {
    // Optimistic: remove now, roll back visibly on failure.
    final before = List<ChatSessionInfo>.of(sessions);
    sessions.removeWhere((x) => x.id == s.id);
    if (current?.id == s.id) closeSession();
    notifyListeners();
    try {
      await engine.delete(s);
      return null;
    } catch (e) {
      sessions = before;
      notifyListeners();
      return '$e';
    }
  }

  Future<void> setProject(ChatSessionInfo s, String? projectId) async {
    await engine.setProject(s, projectId);
    final i = sessions.indexWhere((x) => x.id == s.id);
    if (i >= 0) sessions[i] = sessions[i].copyWith(projectId: projectId, clearProject: projectId == null);
    if (current?.id == s.id) current = sessions[i];
    notifyListeners();
  }

  // ------------------------------------------------- desktop parity actions --

  /// /undo — drop the last exchange; returns the user text so the composer
  /// can offer it again.
  String? undo() {
    if (streaming) return null;
    final idx = messages.lastIndexWhere((m) => m.role == 'user');
    if (idx < 0) return null;
    final text = messages[idx].content;
    messages = messages.sublist(0, idx);
    final s = current;
    if (s != null) engine.saveTranscript(s, messages);
    notifyListeners();
    return text;
  }

  /// Edit a user message: everything after it is discarded, the new text sent.
  Future<void> editAndResend(ChatMsg m, String text) async {
    if (streaming) return;
    final idx = messages.indexWhere((x) => x.id == m.id);
    if (idx < 0) return;
    messages = messages.sublist(0, idx);
    notifyListeners();
    await send(text, images: m.images);
  }

  /// Regenerate an assistant reply (re-run the prompt that produced it).
  Future<void> regenerate(ChatMsg m) async {
    if (streaming) return;
    final idx = messages.indexWhere((x) => x.id == m.id);
    if (idx < 0) return;
    final u = messages.sublist(0, idx).lastIndexWhere((x) => x.role == 'user');
    if (u < 0) return;
    final user = messages[u];
    messages = messages.sublist(0, u);
    notifyListeners();
    await send(user.content, images: user.images);
  }

  /// Branch: a new session that starts with the transcript up to [m].
  Future<ChatSessionInfo?> branch(ChatMsg m) async {
    final src = current;
    final idx = messages.indexWhere((x) => x.id == m.id);
    if (src == null || idx < 0) return null;
    final copy = [for (final x in messages.sublist(0, idx + 1)) ChatMsg.fromJson(x.toJson())];
    final s = await newSession(profile: src.profile, projectId: src.projectId);
    if (s == null) return null;
    final title = 'Cabang · ${src.title}';
    messages = copy;
    engine.saveTranscript(s, messages);
    await rename(s, title.length > 60 ? '${title.substring(0, 60)}…' : title);
    app.settings.setSessionOptions(s.id, app.settings.optionsFor(src.id));
    notifyListeners();
    return current;
  }

  /// /compress — summarise older turns into one note, keep the last few.
  Future<String> compress({int keep = 4}) async {
    if (streaming) return 'Tunggu jawaban selesai dulu.';
    final client = app.settings.llmClient();
    if (client == null || !client.configured) return 'Penyedia model belum diatur.';
    final convo = messages.where((m) => m.role == 'user' || m.role == 'assistant').toList();
    if (convo.length <= keep + 1) return 'Percakapan masih pendek — tidak perlu dikompres.';
    final old = convo.sublist(0, convo.length - keep);
    final tail = convo.sublist(convo.length - keep);
    final text = old.map((m) => '${m.role == 'user' ? 'Pengguna' : 'Asisten'}: ${m.content}').join('\n\n');
    final before = (text.length / 4).round();
    final summary = await client.complete([
      {
        'role': 'system',
        'content': 'Ringkas percakapan berikut menjadi catatan konteks yang padat (poin-poin): fakta, keputusan, preferensi pengguna, '
            'berkas/tugas yang dibuat, dan pertanyaan yang masih terbuka. Bahasa sama dengan percakapan. Maksimal 250 kata.'
      },
      {'role': 'user', 'content': text.length > 60000 ? text.substring(text.length - 60000) : text},
    ], maxTokens: 700);
    final note = ChatMsg(
      id: 'c${DateTime.now().microsecondsSinceEpoch}',
      role: 'assistant',
      content: '**Ringkasan konteks sebelumnya** (/compress, ${old.length} pesan)\n\n$summary',
      ts: DateTime.now().millisecondsSinceEpoch,
    );
    messages = [note, ...tail];
    final s = current;
    if (s != null) engine.saveTranscript(s, messages);
    contextTokens = 0;
    notifyListeners();
    return 'Dikompres: ${old.length} pesan (~${(before / 1000).toStringAsFixed(1)}k token) → ringkasan ~${(summary.length / 4).round()} token.';
  }

  /// Markdown export of the open session.
  String exportMarkdown() {
    final s = current;
    final b = StringBuffer('# ${s?.title ?? 'Percakapan'}\n\n');
    b.writeln('_Diekspor dari Neovarch Agent ${DateTime.now().toIso8601String().substring(0, 16)} · agent ${s?.profile ?? '-'}_\n');
    for (final m in messages.where((m) => m.role == 'user' || m.role == 'assistant')) {
      b.writeln(m.role == 'user' ? '## 🧑 Pengguna' : '## ✦ Neovarch');
      if (m.reasoning.trim().isNotEmpty) b.writeln('<details><summary>Penalaran</summary>\n\n${m.reasoning.trim()}\n\n</details>\n');
      for (final t in m.tools) {
        b.writeln('- `${t.name}` — ${t.summary ?? ''}');
      }
      b.writeln('\n${m.content}\n');
    }
    return b.toString();
  }

  /// Save the export into the workspace (Berkas → exports/).
  String exportToWorkspace() {
    final slug = (current?.title ?? 'percakapan').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    final path = 'exports/${slug.isEmpty ? 'percakapan' : slug}-${DateTime.now().millisecondsSinceEpoch ~/ 1000}.md';
    app.store.writeFile(path, exportMarkdown());
    return path;
  }

  /// In-chat search: (message index, snippet).
  List<(int, String)> search(String q) {
    final needle = q.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    final out = <(int, String)>[];
    for (var i = 0; i < messages.length; i++) {
      final c = messages[i].content;
      final at = c.toLowerCase().indexOf(needle);
      if (at < 0) continue;
      final a = (at - 40).clamp(0, c.length);
      final b = (at + needle.length + 60).clamp(0, c.length);
      out.add((i, '${a > 0 ? '…' : ''}${c.substring(a, b).replaceAll('\n', ' ')}${b < c.length ? '…' : ''}'));
    }
    return out;
  }

  void removeQueued(int i) {
    if (i >= 0 && i < queue.length) queue.removeAt(i);
    notifyListeners();
  }
}
