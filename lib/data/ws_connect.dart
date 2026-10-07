import 'package:web_socket_channel/web_socket_channel.dart';

import 'ws_connect_stub.dart' if (dart.library.io) 'ws_connect_io.dart' as impl;

/// Headers can only be sent from native platforms; the web build falls back
/// to query-string auth.
WebSocketChannel connectWs(Uri uri, Map<String, String> headers) => impl.connectWs(uri, headers);
