// Kantor 3D: the PC's office as the semi-Japanese low-poly three.js room
// (assets/office3d/index.html), rendered in a WebView. The page holds no data
// of its own: every state comes from Flutter over the JS bridge, built from
// the live Office snapshot (`office.update` pushes), so a change on the PC
// shows here as soon as the push lands. Taps on a figure come back on the
// `NvOffice` channel and open the Flutter "Kasih tugas" sheet.
//
// Falls back (calls [onUnavailable]) when there is no WebView on the platform
// (tests, desktop builds), the page reports no WebGL / a lost context, or it
// does not say "ready" in time.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../home_widget.dart' show KantorSnapshotThrottle, decodeSnapshotDataUrl, kantorWidgetPlaced, saveKantorSnapshot;
import '../office_scene_state.dart';

/// Tests / screenshots: replaces the WebView with any widget, given the
/// latest scene state and the tap callback. Null in the app.
@visibleForTesting
Widget Function(Map<String, Object?> state, ValueChanged<String> onTap)? debugOfficeSceneBuilder;

/// Tests: called with every render on/off decision the scene receives
/// (`nvOffice.setActive`). Null in the app.
@visibleForTesting
ValueChanged<bool>? debugOfficeActiveChanged;

/// Kartu Neovarch: a JPEG of the live Kantor 3D scene (WebGL canvas via
/// `nvOffice.snapshot()`), or null when no scene is on screen / ready.
/// Tests can replace it with [debugOfficeSnapshot].
Future<Uint8List?> captureOfficeSnapshot() async {
  final d = debugOfficeSnapshot;
  if (d != null) return d();
  final s = _RemoteOffice3DState._live;
  if (s == null) return null;
  return s._snapshot();
}

@visibleForTesting
Future<Uint8List?> Function()? debugOfficeSnapshot;

/// "data:image/jpeg;base64,…" (possibly JSON-quoted by the WebView) -> bytes.
Uint8List? decodeDataUrl(Object? raw) {
  var s = '$raw'.trim();
  if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
    try {
      s = jsonDecode(s) as String;
    } catch (_) {
      s = s.substring(1, s.length - 1);
    }
  }
  final i = s.indexOf('base64,');
  if (!s.startsWith('data:image/') || i < 0) return null;
  try {
    final b = base64Decode(s.substring(i + 7));
    return b.length < 64 ? null : b;
  } catch (_) {
    return null;
  }
}

class RemoteOffice3D extends StatefulWidget {
  const RemoteOffice3D({super.key, required this.state, required this.onAgentTap, required this.onUnavailable});
  final Map<String, Object?> state;
  final ValueChanged<String> onAgentTap;
  final ValueChanged<String> onUnavailable;

  static const asset = 'assets/office3d/index.html';

  @override
  State<RemoteOffice3D> createState() => _RemoteOffice3DState();
}

class _RemoteOffice3DState extends State<RemoteOffice3D> {
  static _RemoteOffice3DState? _live;

  Future<Uint8List?> _snapshot() async {
    final c = _c;
    if (c == null || !_ready) return null;
    try {
      return decodeDataUrl(await c.runJavaScriptReturningResult('window.nvOffice&&window.nvOffice.snapshot?window.nvOffice.snapshot():""'));
    } catch (_) {
      return null;
    }
  }

  WebViewController? _c;
  bool _ready = false;
  String? _pushed;
  Timer? _watchdog;
  // Render loop on/off: off while the Kantor tab is offstage (IndexedStack
  // reports it through Visibility.of; muted tickers count too) or the app is not resumed, so the GPU idles.
  ValueListenable<TickerModeData>? _tickerMode;
  AppLifecycleListener? _life;
  bool _resumed = true;
  bool _visible = true; // IndexedStack / Visibility ancestors
  bool? _activeSent;
  // Home-screen widget: a Kantor snapshot now and then while the scene is on screen.
  final _snap = KantorSnapshotThrottle();
  Timer? _snapTimer;
  bool _snapBusy = false;

  bool get _wantActive => _resumed && _visible && (_tickerMode?.value.enabled ?? true);

  void _syncActive() {
    if (!mounted) return;
    final on = _wantActive;
    if (on == _activeSent) return;
    final c = _c;
    if (debugOfficeSceneBuilder == null && (c == null || !_ready)) return; // sent on 'ready'
    _activeSent = on;
    debugOfficeActiveChanged?.call(on);
    if (c != null) unawaited(c.runJavaScript('window.nvOffice&&window.nvOffice.setActive(${on ? 'true' : 'false'})').catchError((Object _) {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = Visibility.of(context);
    final tm = TickerMode.getValuesNotifier(context);
    if (tm != _tickerMode) {
      _tickerMode?.removeListener(_syncActive);
      _tickerMode = tm..addListener(_syncActive);
    }
    _syncActive();
  }

  @override
  void initState() {
    super.initState();
    _live = this;
    final st = WidgetsBinding.instance.lifecycleState;
    _resumed = st == null || st == AppLifecycleState.resumed;
    _life = AppLifecycleListener(onStateChange: (s) {
      _resumed = s == AppLifecycleState.resumed;
      _syncActive();
    });
    if (debugOfficeSceneBuilder != null) return;
    if (WebViewPlatform.instance == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onUnavailable('webview'));
      return;
    }
    try {
      final c = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..addJavaScriptChannel('NvOffice', onMessageReceived: (m) => _onMessage(m.message))
        ..setNavigationDelegate(NavigationDelegate(
          onWebResourceError: (e) {
            if (e.isForMainFrame ?? true) _fail('load: ${e.description}');
          },
          // The scene is a local asset; nothing navigates anywhere else.
          onNavigationRequest: (r) => r.url.startsWith('file:') ? NavigationDecision.navigate : NavigationDecision.prevent,
        ));
      _c = c;
      unawaited(c.loadFlutterAsset(RemoteOffice3D.asset).catchError((Object e) => _fail('load: $e')));
      _watchdog = Timer(const Duration(seconds: 12), () {
        if (!_ready) _fail('timeout');
      });
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fail('$e'));
    }
  }

  void _fail(String why) {
    if (!mounted) return;
    _watchdog?.cancel();
    widget.onUnavailable(why);
  }

  void _onMessage(String raw) {
    Map<String, dynamic> m;
    try {
      m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return;
    }
    switch (m['type']) {
      case 'ready':
        _ready = true;
        _watchdog?.cancel();
        _pushed = null;
        _push();
        _activeSent = null;
        _syncActive();
        _snap.sceneReady(DateTime.now());
        _snapTimer?.cancel();
        _snapTimer = Timer.periodic(const Duration(seconds: 5), (_) => _maybeSnapshot());
      case 'snapshot':
        final bytes = decodeSnapshotDataUrl(m['data'] as String?);
        if (bytes != null) unawaited(saveKantorSnapshot(bytes));
      case 'tap':
        final id = m['id'];
        if (id is String) widget.onAgentTap(id);
      case 'error':
        _fail('${m['reason']}');
    }
  }

  void _push() {
    final c = _c;
    if (c == null || !_ready) return;
    final js = officeSceneScript(widget.state);
    if (js == _pushed) return;
    _pushed = js;
    _snap.sceneChanged();
    unawaited(c.runJavaScript(js).catchError((Object _) {}));
  }

  Future<void> _maybeSnapshot() async {
    final c = _c;
    if (c == null || !_ready || _snapBusy || !mounted) return;
    final now = DateTime.now();
    if (!_snap.shouldCapture(now, visible: _wantActive)) return;
    _snapBusy = true;
    try {
      _snap.captured(now); // also when no widget is placed: ask again later, not every tick
      if (!await kantorWidgetPlaced()) return;
      await c.runJavaScript('window.nvOffice&&window.nvOffice.widgetSnapshot&&window.nvOffice.widgetSnapshot(480,500)');
    } catch (_) {
      // scene busy / gone: next interval
    } finally {
      _snapBusy = false;
    }
  }

  @override
  void didUpdateWidget(RemoteOffice3D old) {
    super.didUpdateWidget(old);
    _push(); // every office.update rebuild lands here; unchanged states are skipped
  }

  @override
  void dispose() {
    if (_live == this) _live = null;
    _watchdog?.cancel();
    _tickerMode?.removeListener(_syncActive);
    _life?.dispose();
    _snapTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = debugOfficeSceneBuilder;
    if (b != null) return b(widget.state, widget.onAgentTap);
    final c = _c;
    if (c == null) return const SizedBox.expand();
    return WebViewWidget(
      key: const ValueKey('office-3d-webview'),
      controller: c,
      // orbit / pinch inside the scene win over the page scroll
      gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
    );
  }
}
