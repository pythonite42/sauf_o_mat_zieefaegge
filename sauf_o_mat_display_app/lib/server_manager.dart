import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/material.dart';

typedef MessageHandler = void Function(Map<String, dynamic> data);

class ServerManager {
  static final ServerManager _instance = ServerManager._internal();
  factory ServerManager() => _instance;

  ServerManager._internal();

  /// How often a WebSocket ping is sent. If no pong arrives in time, the
  /// connection is treated as dead and closed, which triggers a reconnect.
  static const Duration _pingInterval = Duration(seconds: 10);
  static const Duration _connectTimeout = Duration(seconds: 5);
  static const Duration _maxReconnectDelay = Duration(seconds: 30);

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  String? _url;
  bool _connecting = false;
  bool _disposed = false;
  int _reconnectAttempt = 0;

  final List<MessageHandler> _listeners = [];

  bool get isConnected => _channel != null;

  /// Connects to [url]. Never throws: if the server is unreachable, it keeps
  /// retrying in the background until a connection is established.
  Future<void> connect(String url) async {
    _url = url;
    _disposed = false;
    await _tryConnect();
  }

  Future<void> _tryConnect() async {
    if (_connecting || _disposed || _url == null) return;
    _connecting = true;
    _reconnectTimer?.cancel();

    try {
      final socket = await WebSocket.connect(_url!).timeout(_connectTimeout);
      // Keep-alive: detects silently dropped connections (Wi-Fi hiccup,
      // router/NAT timeout, server restart, sleep) and keeps NAT entries alive.
      socket.pingInterval = _pingInterval;

      final channel = IOWebSocketChannel(socket);
      _channel = channel;
      _reconnectAttempt = 0;
      debugPrint("✅ WebSocket connected to $_url");

      _subscription = channel.stream.listen(
        _handleMessage,
        onError: (error) {
          debugPrint("❌ WebSocket error: $error");
          _handleDisconnect(channel);
        },
        onDone: () {
          debugPrint(
            "⚠️ WebSocket connection closed (code: ${channel.closeCode}).",
          );
          _handleDisconnect(channel);
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint("❌ WebSocket connect failed: $e");
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final String text = message is String
          ? message
          : utf8.decode(message as Uint8List);
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return;
      // Copy the list: listeners may add/remove themselves while being called.
      for (final listener in List<MessageHandler>.of(_listeners)) {
        listener(decoded);
      }
    } catch (e) {
      debugPrint("❌ Error decoding message: $e");
    }
  }

  void _handleDisconnect(WebSocketChannel channel) {
    // Ignore events from an old channel that was already replaced.
    if (!identical(channel, _channel)) return;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _reconnectTimer?.isActive == true) return;
    // Exponential backoff: 1s, 2s, 4s, ... capped at 30s.
    final seconds = 1 << _reconnectAttempt.clamp(0, 5);
    final delay = Duration(seconds: seconds) > _maxReconnectDelay
        ? _maxReconnectDelay
        : Duration(seconds: seconds);
    _reconnectAttempt++;
    debugPrint("🔄 Reconnecting in ${delay.inSeconds}s ...");
    _reconnectTimer = Timer(delay, _tryConnect);
  }

  void addListener(MessageHandler handler) {
    _listeners.add(handler);
  }

  void removeListener(MessageHandler handler) {
    _listeners.remove(handler);
  }

  void send(Map<String, dynamic> data) {
    final channel = _channel;
    if (channel == null) {
      debugPrint("⚠️ Not connected, message dropped: ${data['event']}");
      return;
    }
    channel.sink.add(jsonEncode(data));
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _listeners.clear();
  }
}
