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

import '../office_scene_state.dart';

/// Tests / screenshots: replaces the WebView with any widget, given the
/// latest scene state and the tap callback. Null in the app.
@visibleForTesting
Widget Function(Map<String, Object?> state, ValueChanged<String> onTap)? debugOfficeSceneBuilder;

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
  WebViewController? _c;
  bool _ready = false;
  String? _pushed;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
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
    unawaited(c.runJavaScript(js).catchError((Object _) {}));
  }

  @override
  void didUpdateWidget(RemoteOffice3D old) {
    super.didUpdateWidget(old);
    _push(); // every office.update rebuild lands here; unchanged states are skipped
  }

  @override
  void dispose() {
    _watchdog?.cancel();
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
