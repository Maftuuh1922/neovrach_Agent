// Per-session chat options (Desktop: the session settings panel + /model,
// /reasoning, /tools, /personality). Defaults live in Settings; a session
// stores only what the user changed for it.
import 'dart:convert';

/// Reasoning effort levels shown in the UI.
const reasoningLevels = ['off', 'low', 'medium', 'high', 'max'];

String reasoningLabel(String l) => switch (l) {
      'off' => 'Mati',
      'low' => 'Rendah',
      'medium' => 'Sedang',
      'high' => 'Tinggi',
      'max' => 'Maksimum',
      _ => l,
    };

/// Approval policy for risky tools (device actions, deletes).
const approvalModes = ['ask', 'auto', 'deny'];
String approvalLabel(String m) => switch (m) {
      'ask' => 'Tanya dulu',
      'auto' => 'Izinkan otomatis',
      'deny' => 'Tolak semua',
      _ => m,
    };

class ChatOptions {
  final String effort; // off | low | medium | high | max
  final int? reasoningBudget; // max reasoning tokens (null = provider default)
  final bool showReasoning;
  final bool autoCollapseReasoning;
  final String? providerId; // null = active provider
  final String? model; // null = profile/provider model
  final double? temperature;
  final double? topP;
  final int? maxTokens;
  final String persona; // extra system prompt for this session
  final bool tools;
  final Set<String> toolGroups; // app, office, device
  final String approval; // ask | auto | deny
  final bool memory;
  final bool streaming;

  const ChatOptions({
    this.effort = 'medium',
    this.reasoningBudget,
    this.showReasoning = true,
    this.autoCollapseReasoning = true,
    this.providerId,
    this.model,
    this.temperature,
    this.topP,
    this.maxTokens,
    this.persona = '',
    this.tools = true,
    this.toolGroups = const {'app', 'office', 'device'},
    this.approval = 'ask',
    this.memory = true,
    this.streaming = true,
  });

  bool get reasoningOn => effort != 'off';

  ChatOptions copyWith({
    String? effort,
    int? reasoningBudget,
    bool clearBudget = false,
    bool? showReasoning,
    bool? autoCollapseReasoning,
    String? providerId,
    String? model,
    bool clearModel = false,
    double? temperature,
    bool clearTemperature = false,
    double? topP,
    bool clearTopP = false,
    int? maxTokens,
    bool clearMaxTokens = false,
    String? persona,
    bool? tools,
    Set<String>? toolGroups,
    String? approval,
    bool? memory,
    bool? streaming,
  }) =>
      ChatOptions(
        effort: effort ?? this.effort,
        reasoningBudget: clearBudget ? null : (reasoningBudget ?? this.reasoningBudget),
        showReasoning: showReasoning ?? this.showReasoning,
        autoCollapseReasoning: autoCollapseReasoning ?? this.autoCollapseReasoning,
        providerId: clearModel ? null : (providerId ?? this.providerId),
        model: clearModel ? null : (model ?? this.model),
        temperature: clearTemperature ? null : (temperature ?? this.temperature),
        topP: clearTopP ? null : (topP ?? this.topP),
        maxTokens: clearMaxTokens ? null : (maxTokens ?? this.maxTokens),
        persona: persona ?? this.persona,
        tools: tools ?? this.tools,
        toolGroups: toolGroups ?? this.toolGroups,
        approval: approval ?? this.approval,
        memory: memory ?? this.memory,
        streaming: streaming ?? this.streaming,
      );

  Map<String, dynamic> toJson() => {
        'effort': effort,
        'reasoningBudget': reasoningBudget,
        'showReasoning': showReasoning,
        'autoCollapse': autoCollapseReasoning,
        'providerId': providerId,
        'model': model,
        'temperature': temperature,
        'topP': topP,
        'maxTokens': maxTokens,
        'persona': persona,
        'tools': tools,
        'toolGroups': toolGroups.toList(),
        'approval': approval,
        'memory': memory,
        'streaming': streaming,
      };

  factory ChatOptions.fromJson(Map<String, dynamic> j, [ChatOptions base = const ChatOptions()]) => ChatOptions(
        effort: reasoningLevels.contains(j['effort']) ? j['effort'] as String : base.effort,
        reasoningBudget: (j['reasoningBudget'] as num?)?.toInt() ?? base.reasoningBudget,
        showReasoning: j['showReasoning'] as bool? ?? base.showReasoning,
        autoCollapseReasoning: j['autoCollapse'] as bool? ?? base.autoCollapseReasoning,
        providerId: j['providerId'] as String? ?? base.providerId,
        model: j['model'] as String? ?? base.model,
        temperature: (j['temperature'] as num?)?.toDouble() ?? base.temperature,
        topP: (j['topP'] as num?)?.toDouble() ?? base.topP,
        maxTokens: (j['maxTokens'] as num?)?.toInt() ?? base.maxTokens,
        persona: j['persona'] as String? ?? base.persona,
        tools: j['tools'] as bool? ?? base.tools,
        toolGroups: j['toolGroups'] is List ? (j['toolGroups'] as List).map((e) => '$e').toSet() : base.toolGroups,
        approval: approvalModes.contains(j['approval']) ? j['approval'] as String : base.approval,
        memory: j['memory'] as bool? ?? base.memory,
        streaming: j['streaming'] as bool? ?? base.streaming,
      );

  String encode() => jsonEncode(toJson());
}

/// Heuristic: does this model expose a reasoning / thinking mode?
bool modelSupportsReasoning(String model) {
  final m = model.toLowerCase();
  if (m.isEmpty) return false;
  const hints = [
    'o1', 'o3', 'o4', 'gpt-5', 'gpt-oss', 'r1', 'reason', 'think', 'qwen3', 'qwq',
    'claude-3.7', 'claude-3-7', 'sonnet-4', 'opus-4', 'claude-4', 'gemini-2.5', 'gemini-3', 'grok-3-mini', 'grok-4',
    'deepseek', 'magistral', 'glm-4.5', 'glm-4.6', 'kimi-k2', 'minimax-m', 'phi-4-reasoning', 'mock',
  ];
  return hints.any(m.contains);
}

/// Which wire format a provider uses for reasoning controls.
enum ReasoningWire { openRouter, openAi, ollama, nous, generic }

ReasoningWire reasoningWireFor(String baseUrl) {
  final u = baseUrl.toLowerCase();
  if (u.contains('openrouter.ai')) return ReasoningWire.openRouter;
  if (u.contains('api.openai.com')) return ReasoningWire.openAi;
  if (u.contains('nousresearch.com')) return ReasoningWire.nous;
  if (u.contains(':11434') || u.contains('ollama')) return ReasoningWire.ollama;
  return ReasoningWire.generic;
}

/// Extra request-body fields for the chosen effort/budget.
Map<String, dynamic> reasoningBody(ReasoningWire wire, String effort, int? budget) {
  final on = effort != 'off';
  final e = effort == 'max' ? 'high' : effort;
  switch (wire) {
    case ReasoningWire.openRouter:
      // https://openrouter.ai/docs/use-cases/reasoning-tokens
      if (!on) return {'reasoning': {'enabled': false}};
      if (budget != null && budget > 0) return {'reasoning': {'max_tokens': budget}};
      return {'reasoning': {'effort': e}};
    case ReasoningWire.openAi:
      return {'reasoning_effort': on ? e : 'minimal'};
    case ReasoningWire.ollama:
      // Ollama's OpenAI-compatible endpoint accepts reasoning_effort; `think`
      // is the native switch (ignored where unknown).
      return on ? {'reasoning_effort': e, 'think': true} : {'think': false};
    case ReasoningWire.nous:
      // The Portal is OpenAI-compatible: pass the generic field.
      return on ? {'reasoning_effort': e} : {};
    case ReasoningWire.generic:
      return on ? {'reasoning_effort': e} : {};
  }
}

