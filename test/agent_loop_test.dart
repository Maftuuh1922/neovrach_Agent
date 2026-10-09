// End-to-end agent loop against tool/mock_llm_tools.py (127.0.0.1:8898):
// office tools are registered + on, the office summary is in the system
// prompt, a risky device tool waits for approval, reasoning params are sent.
import 'package:flutter_test/flutter_test.dart';
import 'package:neovarch_agent/data/agent_runtime.dart';
import 'package:neovarch_agent/data/kv_store.dart';
import 'package:neovarch_agent/data/llm_client.dart';
import 'package:neovarch_agent/data/local_backend.dart';
import 'package:neovarch_agent/data/local_store.dart';
import 'package:neovarch_agent/models/chat_options.dart';
import 'package:neovarch_agent/models/models.dart';

void main() {
  test('agent sees and drives the office; risky tool goes through approval', () async {
    final store = LocalStore(KvStore.memory());
    await store.load();
    final all = allTools.map((t) => t.name).toSet();
    final runtime = AgentRuntime(
      store: store,
      llm: () => LlmClient(baseUrl: 'http://127.0.0.1:8898/v1', apiKey: 'x', model: 'neovarch-mock'),
      enabledTools: () => all,
    );
    final backend = LocalBackend(store: store, runtime: runtime, autoRun: () => false);
    expect(store.profiles.first.name, 'neovarch');
    final user = ChatMsg(id: 'u1', role: 'user', content: 'cek kantor dan jadwalkan laporan', ts: 0);
    final events = <ChatEvent>[];
    await for (final e in runtime.run(
      profile: store.profiles.first,
      history: [user],
      interactive: true,
      options: const ChatOptions(effort: 'high', temperature: 0.4),
    )) {
      events.add(e);
      if (e is ApprovalEvent) {
        // the user taps "Izinkan sekali"
        Future.microtask(() => runtime.resolveApproval(e.requestId, 'once'));
      }
    }
    final done = events.whereType<ToolDoneEvent>().toList();
    for (final d in done) {
      // ignore: avoid_print
      print('${d.name}: ${d.failed ? 'GAGAL ' : ''}${d.summary}');
    }
    expect(done.map((d) => d.name), containsAll(['office_status', 'create_task', 'create_cron', 'list_cron', 'device_info', 'storage_write']));
    expect(done.firstWhere((d) => d.name == 'office_status').failed, isFalse);
    expect(done.firstWhere((d) => d.name == 'create_task').failed, isFalse);
    expect(done.firstWhere((d) => d.name == 'create_cron').failed, isFalse);
    expect(store.tasks.any((t) => t.title == 'Riset harga GPU'), isTrue);
    expect(store.jobs.any((j) => j.name == 'laporan pagi' && !j.enabled), isTrue);
    expect(events.whereType<ApprovalEvent>().length, 1); // storage_write
    expect(events.whereType<ReasoningEvent>(), isNotEmpty);
    expect(events.whereType<DeltaEvent>().map((e) => e.text).join(), contains('Selesai'));
    backend.dispose();
  });
}
