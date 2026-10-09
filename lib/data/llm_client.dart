// OpenAI-compatible Chat Completions client with SSE streaming and tool
// calls. Works with OpenRouter, Nous Portal, OpenAI, Ollama, LM Studio and
// any server that speaks /v1/chat/completions.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

sealed class LlmChunk {
  const LlmChunk();
}

class LlmText extends LlmChunk {
  final String text;
  const LlmText(this.text);
}

class LlmReasoning extends LlmChunk {
  final String text;
  const LlmReasoning(this.text);
}

class LlmToolCallDelta extends LlmChunk {
  final int index;
  final String? id;
  final String? name;
  final String argsDelta;
  const LlmToolCallDelta(this.index, this.id, this.name, this.argsDelta);
}

class LlmFinish extends LlmChunk {
  final String? reason;
  final int promptTokens;
  final int completionTokens;
  /// USD cost when the provider reports it (OpenRouter `usage.cost`).
  final double? cost;
  const LlmFinish(this.reason, this.promptTokens, this.completionTokens, [this.cost]);
}

class LlmException implements Exception {
  final String message;
  final int status;
  const LlmException(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

/// Lets a caller abort a streaming request (Stop button, task cancel).
class CancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];
  bool get isCancelled => _cancelled;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in _listeners) {
      l();
    }
  }

  void onCancel(void Function() f) {
    if (_cancelled) {
      f();
    } else {
      _listeners.add(f);
    }
  }
}

class LlmClient {
  LlmClient({required String baseUrl, this.apiKey, required this.model})
      : baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  final String baseUrl;
  final String? apiKey;
  final String model;

  bool get configured => baseUrl.startsWith('http') && model.isNotEmpty;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (apiKey != null && apiKey!.isNotEmpty) 'Authorization': 'Bearer $apiKey',
        // OpenRouter attribution headers; harmless elsewhere.
        'HTTP-Referer': 'https://github.com/Maftuuh1922/neovrach_Agent',
        'X-Title': 'Neovarch Agent',
      };

  static String _errorFrom(int status, String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        final e = j['error'];
        if (e is Map && e['message'] != null) return '${e['message']} (HTTP $status)';
        if (e is String) return '$e (HTTP $status)';
        if (j['message'] != null) return '${j['message']} (HTTP $status)';
      }
    } catch (_) {}
    if (status == 401) return 'kunci API ditolak (HTTP 401)';
    if (status == 404) return 'endpoint atau model tidak ditemukan (HTTP 404)';
    final clip = body.length > 200 ? '${body.substring(0, 200)}…' : body;
    return 'penyedia membalas HTTP $status${clip.trim().isEmpty ? '' : ': $clip'}';
  }

  Future<List<String>> listModels() async {
    final r = await http
        .get(Uri.parse('$baseUrl/models'), headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw LlmException(_errorFrom(r.statusCode, r.body), r.statusCode);
    final j = jsonDecode(r.body);
    final data = j is Map ? (j['data'] ?? j['models']) : j;
    if (data is! List) return [];
    final ids = data
        .map((e) => e is Map ? '${e['id'] ?? e['name'] ?? ''}' : '$e')
        .where((s) => s.isNotEmpty)
        .toList()
      ..sort();
    return ids;
  }

  /// One-token request against the route we will actually use.
  Future<String> test() async {
    final sb = StringBuffer();
    await for (final c in stream([
      {'role': 'user', 'content': 'Balas dengan satu kata: siap'}
    ], maxTokens: 8)) {
      if (c is LlmText) sb.write(c.text);
    }
    return sb.toString().trim();
  }

  Stream<LlmChunk> stream(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
    String? modelOverride,
    double? temperature,
    int? maxTokens,
    double? topP,
    bool streaming = true,
    Map<String, dynamic>? extra,
    CancelToken? cancel,
  }) async* {
    final client = http.Client();
    cancel?.onCancel(client.close);
    final body = <String, dynamic>{
      'model': modelOverride ?? model,
      'messages': messages,
      'stream': streaming,
      if (streaming && (baseUrl.contains('openai.com') || baseUrl.contains('openrouter.ai') || baseUrl.contains('nousresearch.com'))) 'stream_options': {'include_usage': true},
      if (baseUrl.contains('openrouter.ai')) 'usage': {'include': true},
      if (tools != null && tools.isNotEmpty) 'tools': tools,
      if (tools != null && tools.isNotEmpty) 'tool_choice': 'auto',
      'temperature': ?temperature,
      'max_tokens': ?maxTokens,
      'top_p': ?topP,
      ...?extra,
    };
    final req = http.Request('POST', Uri.parse('$baseUrl/chat/completions'))
      ..headers.addAll(_headers)
      ..body = jsonEncode(body);
    http.StreamedResponse resp;
    try {
      resp = await client.send(req).timeout(const Duration(seconds: 90));
    } on TimeoutException {
      client.close();
      throw const LlmException('penyedia tidak menjawab dalam 90 detik');
    } catch (e) {
      client.close();
      if (cancel?.isCancelled == true) return;
      throw LlmException('tidak bisa menghubungi penyedia: $e');
    }
    if (resp.statusCode != 200) {
      final text = await resp.stream.bytesToString();
      client.close();
      throw LlmException(_errorFrom(resp.statusCode, text), resp.statusCode);
    }

    var prompt = 0, completion = 0;
    double? cost;
    String? finish;
    final contentType = resp.headers['content-type'] ?? '';
    try {
      if (!contentType.contains('event-stream') && !contentType.contains('ndjson')) {
        // Server ignored stream:true and sent one JSON body.
        final text = await resp.stream.bytesToString();
        final j = jsonDecode(text) as Map;
        final choice = (j['choices'] as List).first as Map;
        final msg = choice['message'] as Map;
        if (msg['reasoning'] is String) yield LlmReasoning(msg['reasoning']);
        if (msg['content'] is String) yield LlmText(msg['content']);
        final calls = msg['tool_calls'];
        if (calls is List) {
          for (var i = 0; i < calls.length; i++) {
            final c = calls[i] as Map;
            final f = c['function'] as Map;
            yield LlmToolCallDelta(i, '${c['id']}', '${f['name']}', '${f['arguments'] ?? ''}');
          }
        }
        final u = j['usage'];
        if (u is Map) {
          prompt = (u['prompt_tokens'] as num?)?.toInt() ?? 0;
          completion = (u['completion_tokens'] as num?)?.toInt() ?? 0;
          cost = (u['cost'] as num?)?.toDouble();
        }
        final rc = msg['reasoning_content'];
        if (rc is String && msg['reasoning'] is! String) yield LlmReasoning(rc);
        yield LlmFinish('${choice['finish_reason']}', prompt, completion, cost);
        return;
      }
      final lines = resp.stream.transform(utf8.decoder).transform(const LineSplitter());
      await for (final line in lines) {
        if (cancel?.isCancelled == true) break;
        final l = line.trim();
        if (!l.startsWith('data:')) continue;
        final data = l.substring(5).trim();
        if (data == '[DONE]') break;
        Map j;
        try {
          j = jsonDecode(data) as Map;
        } catch (_) {
          continue;
        }
        if (j['error'] != null) {
          final e = j['error'];
          throw LlmException(e is Map ? '${e['message']}' : '$e');
        }
        final u = j['usage'];
        if (u is Map) {
          prompt = (u['prompt_tokens'] as num?)?.toInt() ?? prompt;
          completion = (u['completion_tokens'] as num?)?.toInt() ?? completion;
          cost = (u['cost'] as num?)?.toDouble() ?? cost;
        }
        final choices = j['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final ch = choices.first as Map;
        if (ch['finish_reason'] != null) finish = '${ch['finish_reason']}';
        final d = ch['delta'];
        if (d is! Map) continue;
        final r = d['reasoning'] ?? d['reasoning_content'];
        if (r is String && r.isNotEmpty) yield LlmReasoning(r);
        final c = d['content'];
        if (c is String && c.isNotEmpty) yield LlmText(c);
        final tc = d['tool_calls'];
        if (tc is List) {
          for (final t in tc) {
            if (t is! Map) continue;
            final f = t['function'] is Map ? t['function'] as Map : const {};
            yield LlmToolCallDelta(
              (t['index'] as num?)?.toInt() ?? 0,
              t['id'] as String?,
              f['name'] as String?,
              (f['arguments'] as String?) ?? '',
            );
          }
        }
      }
    } catch (e) {
      if (cancel?.isCancelled == true) return;
      if (e is LlmException) rethrow;
      throw LlmException('aliran balasan terputus: $e');
    } finally {
      client.close();
    }
    yield LlmFinish(cancel?.isCancelled == true ? 'cancelled' : finish, prompt, completion, cost);
  }

  /// Non-streaming convenience used by meetings and background runs.
  Future<String> complete(List<Map<String, dynamic>> messages,
      {double? temperature, int? maxTokens, String? modelOverride, CancelToken? cancel}) async {
    final sb = StringBuffer();
    await for (final c in stream(messages,
        temperature: temperature,
        maxTokens: maxTokens,
        modelOverride: modelOverride,
        cancel: cancel)) {
      if (c is LlmText) sb.write(c.text);
    }
    return stripThink(sb.toString()).trim();
  }
}

/// Some reasoning models (DeepSeek-style) inline `<think>…</think>`; split it out.
String stripThink(String s) =>
    s.replaceAll(RegExp(r'<think>[\s\S]*?</think>', multiLine: true), '').trim();
