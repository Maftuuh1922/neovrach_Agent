// Kantor → Perusahaan on the phone: org chart, tickets, approvals, costs, all
// through a fake `company.*` API (the PC core answers the same in production).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neovarch_agent/remote/appearance.dart';
import 'package:neovarch_agent/remote/company_models.dart';
import 'package:neovarch_agent/remote/remote_controller.dart';
import 'package:neovarch_agent/remote/remote_gateway.dart' show RemoteStatus;
import 'package:neovarch_agent/remote/saved_desktops.dart';
import 'package:neovarch_agent/remote/ui/remote_app.dart' show PaletteScope, themeFor;
import 'package:neovarch_agent/remote/ui/remote_company_screen.dart';
import 'package:neovarch_agent/state/app_controller.dart' show settingsProvider;
import 'package:neovarch_agent/state/settings_controller.dart';
import 'package:neovarch_agent/theme/neovarch_mobile_theme.dart';

class FakeCompany implements CompanyApi {
  FakeCompany({this.exists = true});
  bool exists;
  final calls = <(String, Map<String, dynamic>)>[];

  Map<String, dynamic> agent(int id, String name, String title, int? reportsTo, {String status = 'idle', Map<String, dynamic>? ticket, String? pause}) => {
        'id': id,
        'name': name,
        'title': title,
        'role': 'pegawai',
        'reports_to': reportsTo,
        'status': status,
        'pause_reason': pause,
        'current_ticket': ticket,
        'budget': {'cents': 0, 'tokens': 1200, 'pct': id == 3 ? 85.0 : null, 'level': id == 3 ? 'warning' : 'ok'},
      };

  @override
  Future<dynamic> companyCall(String method, [Map<String, dynamic> params = const {}]) async {
    calls.add((method, params));
    switch (method) {
      case 'snapshot':
        if (!exists) return {'exists': false};
        return {
          'exists': true,
          'company': {'name': 'Neovarch Studio', 'mission': 'Bikin aplikasi yang membantu orang', 'autorun': false},
          'pending_approvals': 1,
          'active_agents': [3],
          'agents': [
            agent(3, 'Raka', 'Engineer', 2, ticket: {'key': 'NV-2', 'title': 'Perbaiki crash', 'status': 'in_progress'}),
            agent(1, 'Dimas', 'CEO', null),
            agent(2, 'Hana', 'CTO', 1, status: 'paused', pause: 'budget'),
          ],
          'ticket_counts': {'in_progress': 1, 'todo': 1},
          'budget': {'cents': 12.5, 'tokens': 4000, 'pct': null, 'level': 'ok'},
        };
      case 'ticket.list':
        return {
          'tickets': [
            {'id': 2, 'key': 'NV-2', 'title': 'Perbaiki crash', 'status': 'in_progress', 'assignee_id': 3, 'assignee_name': 'Raka', 'locked': true, 'blocked_by': 0},
            {'id': 3, 'key': 'NV-3', 'title': 'Tulis catatan rilis', 'status': 'todo', 'assignee_id': null, 'assignee_name': null, 'locked': false, 'blocked_by': 1},
          ],
        };
      case 'ticket.get':
        return {
          'id': 3, 'key': 'NV-3', 'title': 'Tulis catatan rilis', 'status': 'todo', 'description': 'Untuk rilis berikutnya',
          'ancestry': [
            {'type': 'goal', 'title': 'Rilis 1.5 stabil'},
            {'type': 'mission', 'title': 'Bikin aplikasi yang membantu orang'},
          ],
          'comments': [
            {'author_type': 'agent', 'author_name': 'Dimas', 'body': 'Sari, tolong kerjakan ini.'},
          ],
        };
      case 'approval.list':
        return {
          'approvals': [
            {'id': 9, 'kind': 'review', 'title': 'Tinjau hasil NV-2', 'status': 'pending', 'agent_name': 'Raka', 'payload': {'summary': 'Crash sudah hilang'}},
          ],
        };
      case 'costs':
        return {
          'month': '2026-10',
          'total': {'cents': 12.5, 'tokens': 4000, 'pct': 50.0, 'level': 'ok'},
          'by_agent': [
            {'id': 3, 'name': 'Raka', 'cents': 10.0, 'tokens': 3000, 'pct': 85.0},
            {'id': 1, 'name': 'Dimas', 'cents': 2.5, 'tokens': 1000, 'pct': null},
          ],
        };
      case 'seed_demo':
        exists = true;
        return {'exists': true};
      default:
        return {'ok': true};
    }
  }
}

void main() {
  late SharedPreferences prefs;
  late SettingsController settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'remote.desktops': jsonEncode([
        {'id': 'pc1', 'name': 'PC Kantor', 'url': 'http://192.168.1.20:9319', 'addedAt': DateTime.now().toIso8601String()},
      ]),
      'remote.active': 'pc1',
    });
    prefs = await SharedPreferences.getInstance();
    settings = SettingsController(prefs);
    await settings.load();
    NV.palette = NvPalette.red;
  });

  RemoteController controller(FakeCompany fake) {
    final desktops = SavedDesktops(prefs)..load();
    return RemoteController(desktops)
      ..desktop = desktops.items.first
      ..status = RemoteStatus.connected
      ..debugApprovals = []
      ..debugCompanyApi = fake;
  }

  Future<void> pump(WidgetTester tester, RemoteController r, {int segment = companySegOrg}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final look = AppearanceController(prefs);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => settings),
        remoteProvider.overrideWith((ref) => r),
        appearanceProvider.overrideWith((ref) => look),
      ],
      child: MaterialApp(
        theme: themeFor(look),
        builder: (context, child) => PaletteScope(revision: look.revision, child: child!),
        home: RemoteCompanyScreen(initialSegment: segment),
      ),
    ));
    await tester.pumpAndSettle();
  }

  bool called(FakeCompany f, String method, [Map<String, dynamic>? params]) =>
      f.calls.any((c) => c.$1 == method && (params == null || params.entries.every((e) => c.$2[e.key] == e.value)));

  testWidgets('no company yet: offers the sample company and creates it on the PC', (tester) async {
    final fake = FakeCompany(exists: false);
    await pump(tester, controller(fake));
    expect(find.text('Belum ada perusahaan'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('company-seed')));
    await tester.pumpAndSettle();
    expect(called(fake, 'seed_demo'), isTrue);
    expect(find.text('Neovarch Studio'), findsOneWidget);
  });

  testWidgets('org chart: managers first, indented reports, live status and controls', (tester) async {
    final fake = FakeCompany();
    await pump(tester, controller(fake));
    expect(find.text('Neovarch Studio'), findsOneWidget);
    final dimas = tester.getTopLeft(find.descendant(of: find.byKey(const ValueKey('company-agent-1')), matching: find.byType(Material)).first);
    final hana = tester.getTopLeft(find.descendant(of: find.byKey(const ValueKey('company-agent-2')), matching: find.byType(Material)).first);
    final raka = tester.getTopLeft(find.descendant(of: find.byKey(const ValueKey('company-agent-3')), matching: find.byType(Material)).first);
    expect(dimas.dy < hana.dy && hana.dy < raka.dy, isTrue);
    expect(dimas.dx < hana.dx && hana.dx < raka.dx, isTrue);
    expect(find.text('bekerja'), findsOneWidget); // Raka is running on the PC
    expect(find.text('dijeda · anggaran'), findsOneWidget);
    expect(find.textContaining('NV-2 · Perbaiki crash'), findsOneWidget);
    expect(find.text('85%'), findsOneWidget);
    // Dimas: wake; Hana: resume; Raka: stop
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('company-agent-1')), matching: find.text('Bangunkan')));
    await tester.pumpAndSettle();
    expect(called(fake, 'agent.wake', {'id': 1}), isTrue);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('company-agent-2')), matching: find.text('Lanjutkan')));
    await tester.pumpAndSettle();
    expect(called(fake, 'agent.resume', {'id': 2}), isTrue);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('company-agent-3')), matching: find.text('Hentikan')));
    await tester.pumpAndSettle();
    expect(called(fake, 'agent.stop', {'id': 3}), isTrue);
  });

  testWidgets('autorun switch goes to company.update', (tester) async {
    final fake = FakeCompany();
    await pump(tester, controller(fake));
    await tester.tap(find.byKey(const ValueKey('company-autorun')));
    await tester.pumpAndSettle();
    expect(called(fake, 'update', {'autorun': true}), isTrue);
  });

  testWidgets('tickets grouped by status; sheet shows the why and moves / comments', (tester) async {
    final fake = FakeCompany();
    await pump(tester, controller(fake), segment: companySegTickets);
    expect(find.text('DIKERJAKAN'), findsOneWidget);
    expect(find.text('AKAN DIKERJAKAN'), findsOneWidget);
    expect(find.textContaining('Raka · dikerjakan'), findsOneWidget);
    expect(find.textContaining('1 hambatan'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('company-ticket-NV-3')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kenapa: Rilis 1.5 stabil → Bikin aplikasi'), findsOneWidget);
    expect(find.textContaining('Sari, tolong kerjakan ini.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('company-move-blocked')));
    await tester.pumpAndSettle();
    expect(called(fake, 'ticket.move', {'id': 3, 'status': 'blocked'}), isTrue);
    await tester.enterText(find.byKey(const ValueKey('company-comment')), 'Pakai nada santai');
    await tester.tap(find.byTooltip('Kirim'));
    await tester.pumpAndSettle();
    expect(called(fake, 'ticket.comment', {'id': 3, 'body': 'Pakai nada santai'}), isTrue);
  });

  testWidgets('new ticket from the phone', (tester) async {
    final fake = FakeCompany();
    await pump(tester, controller(fake), segment: companySegTickets);
    await tester.tap(find.byKey(const ValueKey('company-new-ticket')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('company-ticket-title')), 'Riset kompetitor');
    await tester.tap(find.byKey(const ValueKey('company-ticket-create')));
    await tester.pumpAndSettle();
    expect(called(fake, 'ticket.save', {'title': 'Riset kompetitor'}), isTrue);
  });

  testWidgets('approvals: approve and reject remotely', (tester) async {
    final fake = FakeCompany();
    await pump(tester, controller(fake), segment: companySegApprovals);
    expect(find.text('Tinjau hasil NV-2'), findsOneWidget);
    expect(find.text('Crash sudah hilang'), findsOneWidget);
    await tester.tap(find.text('Setujui'));
    await tester.pumpAndSettle();
    expect(called(fake, 'approval.decide', {'id': 9, 'decision': 'approve'}), isTrue);
    await tester.tap(find.text('Tolak'));
    await tester.pumpAndSettle();
    expect(called(fake, 'approval.decide', {'id': 9, 'decision': 'reject'}), isTrue);
  });

  testWidgets('costs per agent with budget meters', (tester) async {
    final fake = FakeCompany();
    await pump(tester, controller(fake), segment: companySegCosts);
    expect(find.textContaining(r'$0.13 · 4.0 rb token'), findsOneWidget);
    expect(find.textContaining('3.0 rb token'), findsOneWidget);
    expect(find.text('85%'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('company.changed push re-reads the snapshot', (tester) async {
    final fake = FakeCompany();
    final r = controller(fake);
    await pump(tester, r);
    final before = fake.calls.where((c) => c.$1 == 'snapshot').length;
    r.companyRevision++;
    r.notifyListeners(); // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    await tester.pumpAndSettle();
    expect(fake.calls.where((c) => c.$1 == 'snapshot').length, before + 1);
  });

  test('models parse the core JSON and build the org tree', () async {
    final s = CompanySnapshot.fromJson(Map<String, dynamic>.from(await FakeCompany().companyCall('snapshot') as Map));
    expect(s.orgTree.map((e) => '${e.$1.name}:${e.$2}').toList(), ['Dimas:0', 'Hana:1', 'Raka:2']);
    expect(s.isRunning(s.agents.firstWhere((a) => a.name == 'Raka')), isTrue);
    expect(const CompanySnapshot(exists: false).orgTree, isEmpty);
    expect(formatCents(0.25), r'$0.0025');
    expect(formatTokens(1500000), '1.5 jt token');
  });
}
