// Opt-in: the phone's gateway client against a REAL Neovarch core.
//
//   HOME=/tmp/nvhome NEOVARCH_SESSION_TOKEN=tok neovarch serve --port 9419 &
//   NV_CORE_URL=http://127.0.0.1:9419 NV_CORE_TOKEN=tok flutter test test/core_integration_test.dart
//
// Skipped when NV_CORE_URL is not set (CI / plain `flutter test`).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:neovarch_agent/remote/remote_gateway.dart';

void main() {
  final url = Platform.environment['NV_CORE_URL'];
  final token = Platform.environment['NV_CORE_TOKEN'] ?? '';
  final skip = url == null ? 'set NV_CORE_URL to run against a real core' : null;
  // LAN target is 300 ms; set higher when testing through a simulated WAN delay.
  final budget = int.tryParse(Platform.environment['NV_LATENCY_BUDGET_MS'] ?? '') ?? 300;

  Future<void> rest(String method, String path, Map<String, dynamic> body) async {
    final req = http.Request(method, Uri.parse('$url$path'))
      ..headers.addAll({'Content-Type': 'application/json', 'Authorization': 'Bearer $token'})
      ..body = jsonEncode(body);
    final res = await http.Client().send(req);
    expect(res.statusCode, inInclusiveRange(200, 299), reason: '$method $path');
    await res.stream.drain<void>();
  }

  test('realtime against the real core: snapshot, pushes, latency, replay after a drop', () async {
    final g = RemoteGateway(baseUrl: url!, token: token, heartbeat: const Duration(seconds: 30));
    await g.connect();
    await g.ping();
    expect(g.bootId, isNotNull, reason: 'core ping returns boot_id');
    expect(g.lastRtt!.inMilliseconds, lessThan(budget));

    final office = await g.office();
    expect(office.agents, isA<List>());
    final look = await g.appearance();
    expect(look!['accent'], startsWith('#'));

    // push latency: appearance.changed after a PUT
    final pushed = g.events.firstWhere((f) => f.type == 'appearance.changed');
    final sw = Stopwatch()..start();
    await rest('PUT', '/api/appearance', {'accent': '#2563EB', 'base': 'dark'});
    final f = await pushed.timeout(const Duration(seconds: 5));
    final ms = sw.elapsedMilliseconds;
    // ignore: avoid_print
    print('ping RTT ${g.lastRtt!.inMilliseconds} ms; appearance.changed push latency: $ms ms (seq ${f.seq})');
    expect(ms, lessThan(budget));
    expect(f.payload['accent'], '#2563EB');
    expect(f.seq, isNotNull);

    // Kanban change → kanban.changed and office.update, pushed
    final kanban = g.events.firstWhere((f) => f.type == 'kanban.changed' || f.type == 'office.update');
    await rest('POST', '/api/plugins/kanban/tasks', {'title': 'Tes realtime HP', 'assignee': 'qa'});
    await kanban.timeout(const Duration(seconds: 5));

    // drop the socket; something happens while the phone is away; it comes back
    final dropped = g.statusStream.firstWhere((s) => s == RemoteStatus.reconnecting);
    final replayed = Completer<GatewayFrameInfo>();
    final sub = g.events.listen((f) {
      if (f.replayed && f.type == 'appearance.changed' && !replayed.isCompleted) replayed.complete(GatewayFrameInfo(f.seq, f.payload));
    });
    g.debugDrop(away: const Duration(seconds: 2));
    await dropped.timeout(const Duration(seconds: 5));
    await rest('PUT', '/api/appearance', {'accent': '#EE1C1C', 'base': 'dark'});
    final r = await replayed.future.timeout(const Duration(seconds: 15));
    expect(r.payload['accent'], '#EE1C1C');
    expect(g.resyncNeeded, isFalse);
    expect(g.status, RemoteStatus.connected);
    await sub.cancel();
    await g.close();
  }, skip: skip, timeout: const Timeout(Duration(seconds: 60)));
}

class GatewayFrameInfo {
  final int? seq;
  final Map<String, dynamic> payload;
  GatewayFrameInfo(this.seq, this.payload);
}
