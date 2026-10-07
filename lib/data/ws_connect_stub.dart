import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectWs(Uri uri, Map<String, String> headers) => WebSocketChannel.connect(uri);
