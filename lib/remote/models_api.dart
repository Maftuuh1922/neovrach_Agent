// Models on the PC (9Router as the default provider; contract:
// /workspace/work/9router-spec.md v1). The phone lists the PC's live models,
// changes the PC's default model and an agent's own model. Pure Dart; the
// gateway implements [ModelsApi] over REST, tests use a fake.

String _s(Object? v, [String d = '']) => v == null ? d : '$v';

class ModelRef {
  const ModelRef(this.model, this.provider);
  final String model, provider;
  factory ModelRef.fromJson(Object? j) {
    final m = j is Map ? j : const {};
    return ModelRef(_s(m['model']), _s(m['provider']));
  }
  static ModelRef? maybe(Object? j) => j is Map && j['model'] != null ? ModelRef.fromJson(j) : null;
  Map<String, dynamic> toJson() => {'model': model, 'provider': provider};
  @override
  bool operator ==(Object other) => other is ModelRef && other.model == model && other.provider == provider;
  @override
  int get hashCode => Object.hash(model, provider);
}

class ModelEntry {
  const ModelEntry({required this.id, required this.label, required this.provider, this.providerLabel = '', this.group = '', this.free = false, this.recommended = false, this.contextLength});
  final String id, label, provider, providerLabel, group;
  final bool free, recommended;
  final int? contextLength;
  factory ModelEntry.fromJson(Map<String, dynamic> j) => ModelEntry(
        id: _s(j['id']),
        label: _s(j['label'], _s(j['id'])),
        provider: _s(j['provider']),
        providerLabel: _s(j['provider_label']),
        group: _s(j['group'], _s(j['provider_label'])),
        free: j['free'] == true,
        recommended: j['recommended'] == true,
        contextLength: (j['context_length'] as num?)?.toInt(),
      );
}

class ModelsSnapshot {
  const ModelsSnapshot({this.models = const [], this.defaultModel = const ModelRef('', ''), this.error, this.routerReady = true, this.routerMessage});
  final List<ModelEntry> models;
  final ModelRef defaultModel;
  final String? error;
  final bool routerReady;
  final String? routerMessage;

  factory ModelsSnapshot.fromJson(Map<String, dynamic> j) {
    final router = j['router'] is Map ? Map<String, dynamic>.from(j['router'] as Map) : const <String, dynamic>{};
    final setup = router['setup'] is Map ? router['setup'] as Map : const {};
    return ModelsSnapshot(
      models: [for (final m in (j['models'] as List? ?? const []).whereType<Map>()) ModelEntry.fromJson(Map<String, dynamic>.from(m))],
      defaultModel: ModelRef.fromJson(j['default']),
      error: j['error'] == null ? null : '${j['error']}',
      routerReady: setup.isEmpty || setup['ready'] != false,
      routerMessage: setup['message'] == null ? null : '${setup['message']}',
    );
  }

  ModelEntry? entry(String id) => models.where((m) => m.id == id).firstOrNull;

  /// Models grouped as the picker shows them (recommended group first).
  List<(String, List<ModelEntry>)> groups({String query = ''}) {
    final q = query.trim().toLowerCase();
    final out = <String, List<ModelEntry>>{};
    for (final m in models) {
      if (q.isNotEmpty && !m.id.toLowerCase().contains(q) && !m.label.toLowerCase().contains(q) && !m.group.toLowerCase().contains(q)) continue;
      out.putIfAbsent(m.group.isEmpty ? m.providerLabel : m.group, () => []).add(m);
    }
    final keys = out.keys.toList()
      ..sort((a, b) {
        final ra = out[a]!.any((m) => m.recommended || m.free) ? 0 : 1, rb = out[b]!.any((m) => m.recommended || m.free) ? 0 : 1;
        return ra != rb ? ra - rb : a.compareTo(b);
      });
    return [for (final k in keys) (k, out[k]!)];
  }

  ModelsSnapshot withDefault(ModelRef d) =>
      ModelsSnapshot(models: models, defaultModel: d, error: error, routerReady: routerReady, routerMessage: routerMessage);
}

class AgentModel {
  const AgentModel({required this.agentId, required this.model, required this.provider, this.override, this.source = 'global'});
  final String agentId, model, provider, source;
  final ModelRef? override;
  factory AgentModel.fromJson(Map<String, dynamic> j) => AgentModel(
        agentId: _s(j['agent_id']),
        model: _s(j['model']),
        provider: _s(j['provider']),
        override: ModelRef.maybe(j['override']),
        source: _s(j['source'], 'global'),
      );
}

/// Short display name of a model id ("oc/big-pickle" -> "big-pickle").
String modelShort(String id) => id.contains('/') ? id.substring(id.lastIndexOf('/') + 1) : id;

abstract class ModelsApi {
  Future<ModelsSnapshot> listModels({bool refresh = false});
  Future<ModelRef> setDefaultModel(String model, {String? provider});
  Future<AgentModel> setAgentModel(String agentId, String? model, {String? provider});
}
