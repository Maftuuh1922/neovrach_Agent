// Wires storage, runtime, the office backend and the chat engine together
// and rebuilds the remote pieces when the connection mode changes (a soft
// re-home: the shell stays, connection-bound state is reset explicitly).
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/agent_runtime.dart';
import '../data/chat_engine.dart';
import '../data/demo_backend.dart';
import '../data/gateway_client.dart';
import '../data/kv_store.dart';
import '../data/local_backend.dart';
import '../data/local_store.dart';
import '../data/office_backend.dart';
import '../models/models.dart';
import 'chat_controller.dart';
import 'office_controller.dart';
import 'settings_controller.dart';

class AppController extends ChangeNotifier {
  AppController({required this.kv, required this.store, required this.settings}) {
    runtime = AgentRuntime(
      store: store,
      llm: settings.llmClient,
      enabledTools: () => settings.enabledTools,
    )..llmById = settings.llmClientFor;
    local = LocalBackend(store: store, runtime: runtime, autoRun: () => settings.autoRunTasks);
    _rebuild();
    _lastMode = settings.mode;
    _lastSig = _sig();
    settings.addListener(_onSettings);
  }

  final KvStore kv;
  final LocalStore store;
  final SettingsController settings;
  late final AgentRuntime runtime;
  late final LocalBackend local;

  late OfficeBackend office;
  late ChatEngine chat;
  DemoBackend? _demo;
  ServerBackend? _server;
  GatewayClient? _gateway;

  late final OfficeController officeCtl = OfficeController(this);
  late final ChatController chatCtl = ChatController(this);

  ConnectionMode? _lastMode;
  String _lastSig = '';

  String _sig() =>
      '${settings.mode}|${settings.serverUrl}|${settings.gatewayUrl}|${settings.gatewayToken}|${settings.gatewayHeaders}|${settings.gatewayProfile}';

  void _onSettings() {
    final sig = _sig();
    if (sig != _lastSig) {
      _lastSig = sig;
      _rebuild();
      _lastMode = settings.mode;
      officeCtl.reset();
      chatCtl.reset();
      notifyListeners();
    }
    // A provider may have just been configured: queued tasks can start.
    local.kick();
  }

  void _rebuild() {
    _server?.dispose();
    _server = null;
    _demo?.dispose();
    _demo = null;
    _gateway?.close();
    _gateway = null;
    switch (settings.mode) {
      case ConnectionMode.local:
        office = local;
        chat = LocalChatEngine(store, runtime, optionsFor: settings.optionsFor);
      case ConnectionMode.gateway:
        _gateway = GatewayClient(
          baseUrl: settings.gatewayUrl,
          token: settings.gatewayToken,
          headers: settings.gatewayHeaders,
        );
        chat = GatewayChatEngine(_gateway!, profile: settings.gatewayProfile.isEmpty ? null : settings.gatewayProfile);
        // The office board stays on-device: the gateway has its own kanban,
        // but the office floor reflects this phone's agents.
        office = local;
      case ConnectionMode.server:
        _server = ServerBackend(settings.serverUrl);
        office = _server!;
        chat = OfficeChatEngine(_server!);
      case ConnectionMode.demo:
        _demo = DemoBackend(kv);
        office = _demo!;
        chat = OfficeChatEngine(_demo!);
    }
  }

  ConnectionMode get mode => _lastMode ?? settings.mode;

  @override
  void dispose() {
    settings.removeListener(_onSettings);
    local.dispose();
    _demo?.dispose();
    _server?.dispose();
    _gateway?.close();
    super.dispose();
  }
}

// Riverpod providers. The instances are created in main() and injected
// with overrides (see main.dart), so every screen reads the same objects
// and no provider ever rebuilds (which would dispose a shared notifier).
final appProvider = ChangeNotifierProvider<AppController>((ref) => throw UnimplementedError());
final settingsProvider = ChangeNotifierProvider<SettingsController>((ref) => throw UnimplementedError());
final storeProvider = ChangeNotifierProvider<LocalStore>((ref) => throw UnimplementedError());
final officeProvider = ChangeNotifierProvider<OfficeController>((ref) => throw UnimplementedError());
final chatProvider = ChangeNotifierProvider<ChatController>((ref) => throw UnimplementedError());
