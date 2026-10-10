// Chat follows the newest message (1.4.5 bug: the phone stayed on an older
// answer): opening a session lands at the bottom with the last reply clear of
// the composer and nav bar, streaming replies keep it there, scrolling up to
// read is never yanked back, and a floating ↓ with the count of new replies
// returns to the newest. Run with --update-goldens and NV_SHOTS_DIR=… to
// write the screenshot.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neovarch_agent/models/models.dart';
import 'package:neovarch_agent/remote/appearance.dart';
import 'package:neovarch_agent/remote/attachments.dart';
import 'package:neovarch_agent/remote/remote_controller.dart';
import 'package:neovarch_agent/remote/remote_gateway.dart' show RemoteStatus;
import 'package:neovarch_agent/remote/remote_transcript.dart';
import 'package:neovarch_agent/remote/saved_desktops.dart';
import 'package:neovarch_agent/remote/ui/glass/glass_chat.dart';
import 'package:neovarch_agent/remote/ui/remote_attachments.dart';
import 'package:neovarch_agent/remote/ui/remote_chat_screen.dart';
import 'package:neovarch_agent/state/app_controller.dart' show settingsProvider;
import 'package:neovarch_agent/state/settings_controller.dart';
import 'package:neovarch_agent/theme/neovarch_mobile_theme.dart';

final _shotsDir = Platform.environment['NV_SHOTS_DIR'] ?? 'build/screenshots/chat_scroll';

const _para = 'Saya cek log build-nya dulu, lalu jalankan tes yang terkait. Kalau ada yang merah, '
    'saya perbaiki satu per satu dan laporkan hasilnya di sini supaya kamu bisa meninjau perubahan sebelum digabung.';

final _png = Uint8List.fromList(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));

List<ChatMsg> _history(int pairs) => [
      for (var i = 0; i < pairs; i++) ...[
        ChatMsg(id: 'u$i', role: 'user', content: 'Pertanyaan nomor $i', ts: 1000 + i * 2),
        ChatMsg(id: 'a$i', role: 'assistant', content: 'Jawaban $i. $_para', ts: 1001 + i * 2),
      ],
    ];

void main() {
  late SharedPreferences prefs;
  late SettingsController settings;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final f in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(f['family'] as String);
      for (final a in (f['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(a['asset'] as String));
      }
      await loader.load();
    }
  });

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
    remoteImageProvider = (url, headers) => const AssetImage('assets/art/feat-remote.webp');
  });
  tearDown(() => NV.palette = NvPalette.red);

  RemoteController controller() {
    final desktops = SavedDesktops(prefs)..load();
    return RemoteController(desktops)
      ..desktop = desktops.items.first
      ..status = RemoteStatus.connected
      ..runtimeId = 'rt-1'
      ..storedId = 's-1'
      ..title = 'halo'
      ..transcript = RemoteTranscript(history: _history(12));
  }

  Widget host(RemoteController r) {
    final look = AppearanceController(prefs);
    NV.palette = NvPalette.red;
    return ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => settings),
        remoteProvider.overrideWith((ref) => r),
        appearanceProvider.overrideWith((ref) => look),
      ],
      child: RepaintBoundary(
        key: const ValueKey('shot'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildNeovarchMobileTheme(),
          home: RemoteChatScreen(onOpenApprovals: () {}),
        ),
      ),
    );
  }

  // A phone whose shell reserves the glass nav bar in padding.bottom (as the
  // real RemoteShell does): 34 dp gesture bar + 76 dp nav pill.
  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 120, bottom: 330);
    tester.view.viewPadding = const FakeViewPadding(top: 120, bottom: 330);
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  ScrollPosition pos(WidgetTester tester) =>
      tester.state<ScrollableState>(find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first).position;

  bool atBottom(WidgetTester tester) {
    final p = pos(tester);
    return p.maxScrollExtent - p.pixels < 1;
  }

  double fabOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(find.ancestor(of: find.byKey(const ValueKey('chat-to-latest')), matching: find.byType(AnimatedOpacity)))
      .opacity;

  void poke(RemoteController r) => r.notifyListeners(); // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

  testWidgets('opening a session lands on the newest reply, fully above the composer and nav bar', (tester) async {
    await phone(tester);
    final r = controller();
    await tester.pumpWidget(host(r));
    await settle(tester);
    expect(pos(tester).maxScrollExtent, greaterThan(500)); // a long chat
    expect(atBottom(tester), isTrue);
    final last = tester.getRect(find.byType(GlassAgentTurn).last);
    final dockTop = tester.getRect(find.byKey(const ValueKey('chat-composer-dock'))).top;
    expect(find.descendant(of: find.byType(GlassAgentTurn).last, matching: find.textContaining('Jawaban 11', findRichText: true)), findsOneWidget);
    expect(last.bottom, lessThanOrEqualTo(dockTop), reason: 'last reply must clear the composer');
    // the composer itself sits above the nav bar the shell reserves
    final view = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(tester.getRect(find.byKey(const ValueKey('chat-composer'))).bottom, lessThanOrEqualTo(view.height - 110 + 0.5));
    expect(fabOpacity(tester), 0);

    // another session opens: again at the newest
    r
      ..storedId = 's-2'
      ..transcript = RemoteTranscript(history: _history(9));
    poke(r);
    await settle(tester);
    expect(atBottom(tester), isTrue);
    expect(find.descendant(of: find.byType(GlassAgentTurn).last, matching: find.textContaining('Jawaban 8', findRichText: true)), findsOneWidget);
  });

  testWidgets('new and streaming replies keep the view at the bottom', (tester) async {
    await phone(tester);
    final r = controller();
    await tester.pumpWidget(host(r));
    await settle(tester);
    r.transcript.messages.add(ChatMsg(id: 'u-new', role: 'user', content: 'kamu bisa apa oi', ts: 5000));
    final live = ChatMsg(id: 'a-new', role: 'assistant', content: 'Saya Neovarch Agent.', ts: 5001)..streaming = true;
    r.transcript.messages.add(live);
    poke(r);
    await settle(tester);
    expect(atBottom(tester), isTrue);
    for (var i = 0; i < 6; i++) {
      live.content += '\n\n- Bisa bantu hal nomor $i: $_para';
      poke(r);
      await settle(tester);
      expect(atBottom(tester), isTrue, reason: 'chunk $i');
    }
    live.streaming = false;
    poke(r);
    await settle(tester);
    expect(atBottom(tester), isTrue);
    expect(fabOpacity(tester), 0);
    final last = tester.getRect(find.byType(GlassAgentTurn).last);
    expect(last.bottom, lessThanOrEqualTo(tester.getRect(find.byKey(const ValueKey('chat-composer-dock'))).top));
  });

  testWidgets('scrolled up: no yank, ↓ shows the unread count and returns to the newest', (tester) async {
    await phone(tester);
    final r = controller();
    await tester.pumpWidget(host(r));
    await settle(tester);
    await tester.drag(find.byType(ListView), const Offset(0, 900));
    await settle(tester);
    expect(atBottom(tester), isFalse);
    expect(fabOpacity(tester), 1);
    expect(find.byKey(const ValueKey('chat-unread-badge')), findsNothing);
    final reading = pos(tester).pixels;

    r.transcript.messages
      ..add(ChatMsg(id: 'a-x1', role: 'assistant', content: 'Balasan baru pertama. $_para', ts: 6000))
      ..add(ChatMsg(id: 'a-x2', role: 'assistant', content: 'Balasan baru kedua. $_para', ts: 6001));
    poke(r);
    await settle(tester);
    expect(pos(tester).pixels, closeTo(reading, 0.5), reason: 'the reader is not yanked');
    expect(find.descendant(of: find.byKey(const ValueKey('chat-unread-badge')), matching: find.text('2')), findsOneWidget);

    // streaming into the newest reply does not move the reader either
    r.transcript.messages.last.content += ' Tambahan.';
    poke(r);
    await settle(tester);
    expect(pos(tester).pixels, closeTo(reading, 0.5));

    if (autoUpdateGoldenFiles) {
      final dir = Directory(_shotsDir).absolute.path;
      Directory(dir).createSync(recursive: true);
      await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('$dir/chat_to_latest.png'));
    }

    await tester.tap(find.byKey(const ValueKey('chat-to-latest')));
    await settle(tester);
    expect(atBottom(tester), isTrue);
    expect(fabOpacity(tester), 0);
    expect(find.byKey(const ValueKey('chat-unread-badge')), findsNothing);
    expect(find.descendant(of: find.byType(GlassAgentTurn).last, matching: find.textContaining('Balasan baru kedua', findRichText: true)), findsOneWidget);
  });

  testWidgets('sending a photo then a reasoning reply: the reply ends above the composer (MIUI report)', (tester) async {
    await phone(tester);
    final r = controller();
    await tester.pumpWidget(host(r));
    await settle(tester);
    // a picked photo grows the dock (thumbnail strip) …
    r.pendingAttachments.add(PendingAttachment(localId: 'att0', name: 'foto.jpg', mime: 'image/jpeg', bytes: _png)
      ..state = AttachState.done
      ..remote = const RemoteAttachment(id: 'a1b2c3d4e5f6', name: 'foto.jpg', mime: 'image/jpeg', size: 70, kind: 'image'));
    poke(r);
    await settle(tester);
    expect(atBottom(tester), isTrue);
    // … send: the strip goes away, the turn shows the photo, the agent thinks then answers
    r.pendingAttachments.clear();
    r.transcript.messages.add(ChatMsg(id: 'u-img', role: 'user', content: 'ini', ts: 7000,
        attachments: [const RemoteAttachment(id: 'a1b2c3d4e5f6', name: 'foto.jpg', mime: 'image/jpeg', size: 70, kind: 'image').toJson()]));
    final live = ChatMsg(id: 'a-img', role: 'assistant', content: '', ts: 7001)..streaming = true;
    r.transcript.messages.add(live);
    poke(r);
    await settle(tester);
    for (var i = 0; i < 4; i++) {
      live.reasoning += 'Menimbang gambar, langkah $i. ';
      poke(r);
      await settle(tester);
    }
    for (var i = 0; i < 4; i++) {
      live.content += 'Bagian $i. $_para\n\n';
      poke(r);
      await settle(tester);
      expect(atBottom(tester), isTrue, reason: 'chunk $i');
    }
    live.streaming = false;
    poke(r);
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(atBottom(tester), isTrue);
    expect(fabOpacity(tester), 0);
    final last = tester.getRect(find.byType(GlassAgentTurn).last);
    expect(last.bottom, lessThanOrEqualTo(tester.getRect(find.byKey(const ValueKey('chat-composer-dock'))).top));
  });

  testWidgets('the window shrinking under a following chat (MIUI after the picker) keeps the newest reply in view', (tester) async {
    await phone(tester);
    final r = controller();
    await tester.pumpWidget(host(r));
    await settle(tester);
    expect(atBottom(tester), isTrue);
    // no new message, no scroll: only the viewport gets shorter, then taller
    tester.view.physicalSize = const Size(1080, 1900);
    await settle(tester);
    expect(atBottom(tester), isTrue, reason: 'shorter viewport');
    expect(fabOpacity(tester), 0);
    var last = tester.getRect(find.byType(GlassAgentTurn).last);
    expect(last.bottom, lessThanOrEqualTo(tester.getRect(find.byKey(const ValueKey('chat-composer-dock'))).top));
    tester.view.physicalSize = const Size(1080, 2400);
    await settle(tester);
    expect(atBottom(tester), isTrue, reason: 'restored viewport');
    last = tester.getRect(find.byType(GlassAgentTurn).last);
    expect(last.bottom, lessThanOrEqualTo(tester.getRect(find.byKey(const ValueKey('chat-composer-dock'))).top));

    // a reader who scrolled up is not pulled down by a resize
    await tester.drag(find.byType(ListView), const Offset(0, 900));
    await settle(tester);
    final reading = pos(tester).pixels;
    tester.view.physicalSize = const Size(1080, 1900);
    await settle(tester);
    expect(pos(tester).pixels, closeTo(reading, 0.5));
    expect(fabOpacity(tester), 1);
  });
}
