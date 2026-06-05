import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef WsMessageHandler = void Function(Map<String, dynamic> message);

class WsService {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  bool get isConnected => _channel != null;

  void connect({
    required String apiBaseUrl,
    required String token,
    required WsMessageHandler onMessage,
    void Function(Object error)? onError,
    void Function()? onDone,
  }) {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;

    final uri = _buildWsUri(apiBaseUrl: apiBaseUrl, token: token);
    debugPrint('[WsService] Connecting to: $uri');
    _channel = WebSocketChannel.connect(uri);

    _subscription = _channel!.stream.listen(
      (dynamic rawMessage) {
        debugPrint(
            '[WsService] Raw message received: ${rawMessage.runtimeType}');
        if (rawMessage is! String) {
          debugPrint('[WsService] Ignoring non-string message');
          return;
        }
        debugPrint(
          '[WsService] Raw string: ${rawMessage.length > 200 ? rawMessage.substring(0, 200) : rawMessage}',
        );
        try {
          final decoded = jsonDecode(rawMessage);
          if (decoded is Map<String, dynamic>) {
            onMessage(decoded);
          } else if (decoded is Map) {
            onMessage(Map<String, dynamic>.from(decoded));
          }
        } catch (e) {
          debugPrint('[WsService] JSON decode error: $e');
        }
      },
      onError: (e) {
        debugPrint('[WsService] Stream error: $e');
        onError?.call(e);
      },
      onDone: () {
        debugPrint('[WsService] Stream done (connection closed)');
        onDone?.call();
      },
      cancelOnError: false,
    );
  }

  void send(Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel == null) {
      return;
    }
    channel.sink.add(jsonEncode(payload));
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  Uri _buildWsUri({
    required String apiBaseUrl,
    required String token,
  }) {
    final baseUri = Uri.parse(apiBaseUrl);
    final scheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
    return Uri(
      scheme: scheme,
      host: baseUri.host,
      port: baseUri.hasPort ? baseUri.port : null,
      path: '/ws',
      queryParameters: {'token': token},
    );
  }
}
