// Port of src/lib/offline-mock.ts — the offline demo board.
//
// Answers every `/api/neovarch/*` route from an in-memory board persisted to
// the KV store. Meetings are simulated with scripted turns every 4 s, then
// archived with minutes. Chat answers with a clearly-labelled demo reply.
import 'dart:async';
import 'dart:math';

import '../models/models.dart';
import 'api_result.dart';
import 'kv_store.dart';
import 'office_backend.dart';

const _key = 'hvo-offline-v1';

class DemoBackend extends OfficeBackend {
  DemoBackend(this.kv);
  final KvStore kv;
  Map<String, dynamic>? _s;
  final List<Map<String, dynamic>> _live = [];
  final Map<String, Timer> _timers = {};
  final _rnd = Random();

  @override
  String get kind => 'demo';

  String _uid(String p) =>
      '$p${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_rnd.nextInt(10000)}';

  Map<String, dynamic> _seed() {
    final now = DateTime.now().toIso8601String();
    Map<String, dynamic> t(String id, String title, String status, String a,
            int p, [String? body]) =>
        {
          'id': id,
          'title': title,
          'status': status,
          'assignee': a,
          'priority': p,
          'body': ?body,
          'createdAt': now,
          'updatedAt': now
        };
    return {
      'tasks': [
        t('t1', 'Rancang skema cache offline', 'ready', 'jun', 1,
            'Simpan snapshot papan di localStorage.'),
        t('t2', 'Implementasi mock driver offline', 'running', 'jun', 0,
            'Intersepsi fetchJson.'),
        t('t3', 'Perbaiki layout panel HP', 'running', 'sari', 1,
            'Panel aman untuk layar kecil.'),
        t('t4', 'Uji WebGL di WebView', 'review', 'bimo', 1,
            'Pastikan 3D tampil di HP.'),
        t('t5', 'Riset sinkronisasi latar', 'todo', 'rani', 2),
        t('t6', 'Setup build APK rilis', 'blocked', 'dewi', 2,
            'Terhalang: keystore rilis belum ada.'),
        t('t7', 'Rilis remote v1.2', 'done', 'jun', 1),
      ],
      'agents': [
        {'name': 'jun', 'displayName': 'jun', 'role': 'backend', 'deskIndex': 0, 'status': 'working', 'currentTaskId': 't2'},
        {'name': 'sari', 'displayName': 'sari', 'role': 'frontend', 'deskIndex': 1, 'status': 'working', 'currentTaskId': 't3'},
        {'name': 'bimo', 'displayName': 'bimo', 'role': 'qa', 'deskIndex': 2, 'status': 'review', 'currentTaskId': 't4'},
        {'name': 'rani', 'displayName': 'rani', 'role': 'researcher', 'deskIndex': 4, 'status': 'idle', 'currentTaskId': null},
        {'name': 'dewi', 'displayName': 'dewi', 'role': 'devops', 'deskIndex': 5, 'status': 'blocked', 'currentTaskId': 't6'},
      ],
      'threads': <String, dynamic>{},
      'jobs': [
        {
          'id': 'j1', 'name': 'cek-kesehatan-demo', 'prompt': 'Lapor status papan demo.',
          'schedule': '0 9 * * *', 'scheduleKind': 'cron', 'enabled': false, 'state': 'paused',
          'nextRunAt': null, 'lastRunAt': null, 'lastStatus': null, 'lastError': null, 'failureStreak': 0,
        }
      ],
      'archived': <dynamic>[],
      'bodies': <String, dynamic>{},
      'logs': {
        't2': ['\$ neovarch kanban show t2', '[worker] menulis src/lib/offline-mock.ts ...', '[worker] 3 berkas berubah, typecheck hijau'],
        't3': ['\$ neovarch kanban show t3', '[worker] menyesuaikan panel untuk viewport 360px ...'],
        't4': ['\$ neovarch kanban show t4', '[review] membuka APK di perangkat ...', '[review] WebGL: OK, 60fps'],
      },
    };
  }

  Future<Map<String, dynamic>> _state() async {
    if (_s != null) return _s!;
    final v = await kv.get(_key);
    if (v is Map && v['tasks'] is List) {
      _s = Map<String, dynamic>.from(v);
    } else {
      _s = _seed();
      _save();
    }
    return _s!;
  }

  void _save() {
    if (_s != null) kv.put(_key, _s);
  }

  List<Map<String, dynamic>> _list(String k) => ((_s![k] as List?) ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  static const _lines = [
    'Setuju — untuk mode offline, data harus hidup di perangkat, bukan di server.',
    'Aku usulkan batasnya jelas: demo ini untuk pantau dan coba alur, bukan eksekusi asli.',
    'Risikonya satu: pengguna mengira worker-nya nyata. Balasan chat harus selalu berlabel demo.',
    'Kalau alur rapatnya mulus di HP kecil, sisanya tinggal ganti driver ke API sungguhan.',
    'Aku ambil bagian notulen: Keputusan, Aksi, Risiko — formatnya tetap markdown.',
    'Terakhir dari aku: jaga polling tetap ringan, HP kentang tidak boleh panas.',
  ];

  String _minutesFor(Map<String, dynamic> m) {
    final names = (m['participants'] as List).join(', ');
    return '# Notulen (demo): ${m['topic']}\n\n'
        'Peserta: $names — Moderator: ${m['moderator'] ?? '-'}\n\n'
        '## Keputusan\n\n- Mode offline disetujui untuk build Android mandiri.\n- Seluruh status papan tersimpan lokal di perangkat.\n\n'
        '## TINDAK LANJUT\n\n- [ ] Uji tampilan kantor di HP fisik (pemilik: bimo)\n- [ ] Siapkan keystore untuk APK rilis (pemilik: dewi)\n\n'
        '## Risiko\n\n- Balasan agent adalah simulasi dan harus selalu berlabel demo.\n';
  }

  void _startSim(Map<String, dynamic> m) {
    var i = 0;
    final order = (m['participants'] as List).cast<String>();
    _timers[m['id']] = Timer.periodic(const Duration(seconds: 4), (timer) {
      final speaker = order.isEmpty ? 'jun' : order[i % order.length];
      final round = order.isEmpty ? 1 : i ~/ order.length + 1;
      final text = i == 0
          ? 'Membuka rapat "${m['topic']}". ${_lines[0]}'
          : _lines[(i % (_lines.length - 1)) + 1];
      (m['turns'] as List).add({
        'round': round,
        'speaker': speaker,
        'kind': i == 0 ? 'opening' : 'speech',
        'text': text,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
      m['currentSpeaker'] = speaker;
      m['phase'] = 'ronde $round';
      i++;
      if (i >= 6) {
        timer.cancel();
        _timers.remove(m['id']);
        m['state'] = 'done';
        m['phase'] = 'selesai';
        m['currentSpeaker'] = null;
        m['minutes'] = _minutesFor(m);
        final turns = (m['turns'] as List)
            .map((t) => '**${t['speaker']}** (ronde ${t['round']}): ${t['text']}')
            .join('\n\n');
        final body =
            '# Transkrip rapat (demo): ${m['topic']}\n\nPeserta: ${order.join(', ')}\n\n$turns\n\n---\n\n${m['minutes']}';
        (_s!['bodies'] as Map)[m['id']] = body;
        (_s!['archived'] as List).insert(0, {
          'id': m['id'],
          'topic': m['topic'],
          'file': 'rapat-${m['id']}.md',
          'startedAt': DateTime.now().toIso8601String().substring(0, 10),
          'participants': order,
          'moderator': m['moderator'],
          'mode': m['mode'],
          'turnCount': (m['turns'] as List).length,
          'preview': (m['turns'] as List).isNotEmpty
              ? (m['turns'] as List).first['text']
              : m['topic'],
          'archived': true,
        });
        _save();
      }
    });
  }

  @override
  Future<ApiResult> request(String method, String path,
      {Map<String, String>? query,
      Map<String, dynamic>? body,
      Duration? timeout}) async {
    final s = await _state();
    final b = body ?? const <String, dynamic>{};
    final q = query ?? const <String, String>{};
    method = method.toUpperCase();
    final now = DateTime.now().toIso8601String();

    if (path == '/api/neovarch/tasks') {
      if (method == 'GET') {
        return ApiResult.success({'tasks': s['tasks'], 'agents': s['agents']});
      }
      final agents = _list('agents');
      final firstAgent = agents.isNotEmpty ? agents.first['name'] : 'jun';
      if (b['items'] is List) {
        final created = <Map<String, dynamic>>[];
        for (final it in (b['items'] as List).cast<Map>()) {
          final t = {
            'id': _uid('t'),
            'title': '${it['title'] ?? 'Tanpa judul'}',
            'status': 'todo',
            'assignee': '${it['assignee'] ?? firstAgent}',
            'priority': 2,
            'body': it['body'],
            'origin': b['origin'],
            'createdAt': now,
            'updatedAt': now,
          };
          (s['tasks'] as List).insert(0, t);
          created.add({'id': t['id']});
        }
        _save();
        return ApiResult.success({'success': true, 'created': created, 'failed': []}, 201);
      }
      final title = '${b['title'] ?? ''}'.trim();
      if (title.isEmpty) return ApiResult.fail(400, 'judul tugas wajib diisi');
      final t = {
        'id': _uid('t'),
        'title': title,
        'status': 'todo',
        'assignee': '${b['assignee'] ?? firstAgent}',
        'priority': (b['priority'] as num?)?.toInt() ?? 2,
        if (b['body'] != null && '${b['body']}'.isNotEmpty) 'body': '${b['body']}',
        'createdAt': now,
        'updatedAt': now,
      };
      (s['tasks'] as List).insert(0, t);
      _save();
      return ApiResult.success({'success': true, 'task': {'id': t['id']}}, 201);
    }

    final taskHit = RegExp(r'^/api/neovarch/tasks/([^/]+)$').firstMatch(path);
    if (taskHit != null) {
      final id = Uri.decodeComponent(taskHit.group(1)!);
      final tasks = (s['tasks'] as List);
      final t = tasks.cast<Map>().where((x) => x['id'] == id).firstOrNull;
      if (t == null) return ApiResult.fail(404, 'tugas tidak ditemukan');
      final logs = s['logs'] as Map;
      if (method == 'GET') {
        final lines = (logs[id] as List?)?.cast<String>() ??
            ['\$ neovarch kanban show $id', '(demo) belum ada output worker.'];
        return ApiResult.success({'taskId': id, 'log': lines.join('\n'), 'runs': []});
      }
      final action = '${b['action'] ?? ''}';
      if (action == 'steer') {
        final msg = '${b['message'] ?? ''}';
        logs[id] = [...((logs[id] as List?) ?? []), '[arahan] ${msg.isEmpty ? '(kosong)' : msg}'];
        _save();
        return ApiResult.success({'success': true, 'steered': true});
      }
      if (action == 'cancel') {
        if (t['status'] == 'running') t['status'] = 'ready';
        for (final a in (s['agents'] as List).cast<Map>()) {
          if (a['currentTaskId'] == id) a['currentTaskId'] = null;
        }
        _save();
        return ApiResult.success({'success': true, 'released': true});
      }
      return ApiResult.fail(400, 'aksi tidak dikenal');
    }

    if (path == '/api/neovarch/agents') {
      if (method == 'GET') {
        return ApiResult.success({
          'available': _list('agents')
              .map((a) => {
                    'name': a['name'],
                    'total': (s['tasks'] as List).where((t) => (t as Map)['assignee'] == a['name']).length,
                    'profile': true,
                    'inOffice': true,
                    'reason': null,
                  })
              .toList(),
          'killed': [],
        });
      }
      final action = '${b['action'] ?? ''}';
      final name = '${b['name'] ?? ''}'.trim().toLowerCase();
      if (name.isEmpty) return ApiResult.fail(400, 'nama agent wajib diisi');
      if (action == 'kill') {
        final n = (s['tasks'] as List).where((t) => (t as Map)['assignee'] == name).length;
        (s['tasks'] as List).removeWhere((t) => (t as Map)['assignee'] == name);
        (s['agents'] as List).removeWhere((a) => (a as Map)['name'] == name);
        _save();
        return ApiResult.success({'success': true, 'action': 'kill', 'name': name, 'purged': n});
      }
      if (action == 'create' || action == 'spawn') {
        if ((s['agents'] as List).any((a) => (a as Map)['name'] == name)) {
          return ApiResult.fail(409, '"$name" sudah ada di kantor');
        }
        final used = (s['agents'] as List).map((a) => (a as Map)['deskIndex']).toSet();
        final desk = [0, 1, 2, 3, 4, 5, 6, 7].where((d) => !used.contains(d)).firstOrNull;
        (s['agents'] as List).add({'name': name, 'displayName': name, 'role': roleFor(name), 'deskIndex': desk, 'status': 'idle', 'currentTaskId': null});
        _save();
        return ApiResult.success({'success': true, 'action': action, 'name': name}, 201);
      }
      return ApiResult.fail(400, 'aksi tidak dikenal');
    }

    if (path == '/api/neovarch/chat') {
      final agent = q['agent'];
      final threads = s['threads'] as Map;
      if (method == 'DELETE') {
        if (agent != null) threads.remove(agent);
        _save();
        return ApiResult.success({'success': true});
      }
      if (method == 'POST') {
        final who = '${b['agent'] ?? ''}'.trim();
        final text = '${b['message'] ?? ''}'.trim();
        if (who.isEmpty || text.isEmpty) return ApiResult.fail(400, 'agent dan pesan wajib diisi');
        final th = Map<String, dynamic>.from((threads[who] as Map?) ??
            {
              'session': {'id': _uid('s'), 'agent': who, 'profile': who, 'title': 'Obrolan dengan $who', 'updatedAt': now, 'messageCount': 0},
              'messages': [],
            });
        final msgs = List<dynamic>.from(th['messages'] as List);
        msgs.add({'role': 'user', 'content': text, 'ts': DateTime.now().millisecondsSinceEpoch});
        final clip = text.length > 80 ? text.substring(0, 80) : text;
        final reply = '[mode offline — demo] $who: pesanmu kuterima (“$clip”). '
            'Aku jalan murni di HP tanpa server, jadi ini balasan simulasi, bukan agent sungguhan.';
        msgs.add({'role': 'assistant', 'content': reply, 'ts': DateTime.now().millisecondsSinceEpoch});
        final session = Map<String, dynamic>.from(th['session'] as Map);
        session['messageCount'] = msgs.length;
        session['updatedAt'] = now;
        threads[who] = {'session': session, 'messages': msgs};
        _save();
        await Future.delayed(const Duration(milliseconds: 600));
        return ApiResult.success({'success': true, 'session': session, 'reply': reply});
      }
      if (agent != null) {
        final th = threads[agent] as Map?;
        return ApiResult.success({'agent': agent, 'session': th?['session'], 'messages': th?['messages'] ?? []});
      }
      final names = _list('agents').map((a) => a['name']).toList();
      return ApiResult.success({
        'sessions': threads.values.map((t) => (t as Map)['session']).toList(),
        'agents': names,
        'profiles': names,
      });
    }

    if (path == '/api/neovarch/cron') {
      if (method == 'GET') return ApiResult.success({'jobs': s['jobs'], 'runs': []});
      final action = '${b['action'] ?? ''}';
      if (action == 'create') {
        final paused = b['paused'] != false;
        final j = {
          'id': _uid('j'), 'name': '${b['name'] ?? ''}'.isEmpty ? 'job-demo' : '${b['name']}',
          'prompt': '${b['prompt'] ?? ''}', 'schedule': '${b['schedule'] ?? ''}', 'scheduleKind': 'cron',
          'enabled': !paused, 'state': paused ? 'paused' : 'scheduled',
          'nextRunAt': null, 'lastRunAt': null, 'lastStatus': null, 'lastError': null, 'failureStreak': 0,
        };
        (s['jobs'] as List).insert(0, j);
        _save();
        return ApiResult.success({'success': true, 'id': j['id'], 'job': j}, 201);
      }
      final id = '${b['id'] ?? ''}';
      final jobs = s['jobs'] as List;
      final j = jobs.cast<Map>().where((x) => x['id'] == id).firstOrNull;
      if (j == null) return ApiResult.fail(404, 'job tidak ditemukan');
      if (action == 'remove') {
        jobs.removeWhere((x) => (x as Map)['id'] == id);
      } else if (action == 'pause') {
        j['enabled'] = false;
        j['state'] = 'paused';
      } else if (action == 'resume') {
        j['enabled'] = true;
        j['state'] = 'scheduled';
      } else if (action != 'run') {
        return ApiResult.fail(400, 'aksi tidak dikenal');
      }
      _save();
      return ApiResult.success({'success': true, 'action': action, 'id': id, 'job': action == 'remove' ? null : j});
    }
    if (path == '/api/neovarch/cron/actions') {
      return ApiResult.success({'items': [], 'roster': _list('agents').map((a) => a['name']).toList()});
    }

    if (path == '/api/neovarch/meeting') {
      if (method == 'POST') {
        final topic = '${b['topic'] ?? ''}'.trim();
        final participants = ((b['participants'] as List?) ?? []).map((e) => '$e').toList();
        if (topic.isEmpty) return ApiResult.fail(400, 'topik rapat wajib diisi');
        if (participants.length < 2) return ApiResult.fail(400, 'pilih minimal 2 peserta yang dikenal');
        final m = <String, dynamic>{
          'id': _uid('m'), 'topic': topic, 'participants': participants,
          'moderator': '${b['moderator'] ?? participants.first}', 'mode': '${b['mode'] ?? 'auto'}',
          'state': 'running', 'phase': 'pembuka', 'currentSpeaker': participants.first,
          'turns': <dynamic>[], 'minutes': '',
        };
        _live.insert(0, m);
        _startSim(m);
        return ApiResult.success({'meeting': m});
      }
      final id = q['id'];
      if (id != null) {
        final found = (s['archived'] as List).cast<Map>().where((a) => a['id'] == id).firstOrNull;
        if (found == null) return ApiResult.fail(404, 'transkrip tidak ditemukan');
        return ApiResult.success({'id': id, 'body': (s['bodies'] as Map)[id] ?? '(demo) transkrip kosong.'});
      }
      final active = _live.where((m) => m['state'] == 'running').firstOrNull;
      return ApiResult.success({'configured': true, 'live': _live, 'active': active?['id'], 'archived': s['archived']});
    }
    if (path == '/api/neovarch/meeting/actions') {
      final from = q['from'] ?? '';
      final m = _live.where((x) => x['id'] == from).firstOrNull;
      final roster = m != null
          ? (m['participants'] as List).cast<String>()
          : _list('agents').map((a) => '${a['name']}').toList();
      return ApiResult.success({
        'meeting': {'id': from, 'topic': m?['topic'] ?? ''},
        'items': [
          {'text': 'Uji tampilan kantor di HP fisik', 'owner': 'bimo', 'suggested': roster.contains('bimo') ? 'bimo' : null},
          {'text': 'Siapkan keystore untuk APK rilis', 'owner': 'dewi', 'suggested': roster.contains('dewi') ? 'dewi' : null},
        ],
        'roster': roster,
      });
    }
    return ApiResult.fail(404, 'endpoint demo tidak dikenal');
  }

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
  }
}
