import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  bool _connected = false;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  final List<Map<String, dynamic>> _realtimeAttacks = [];
  Map<String, dynamic> _liveMetrics = {};
  String? _lastUrl;
  String? _lastToken;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;

  bool get connected => _connected;
  List<Map<String, dynamic>> get realtimeAttacks => List.unmodifiable(_realtimeAttacks);
  Map<String, dynamic> get liveMetrics => Map.unmodifiable(_liveMetrics);
  int get attackCount => _realtimeAttacks.length;

  void connect(String baseUrl, String token) {
    _lastUrl = baseUrl;
    _lastToken = token;
    _reconnectAttempts = 0;
    _doConnect();
  }

  void _doConnect() {
    if (_lastUrl == null || _lastToken == null) return;
    final wsUrl = '${_lastUrl!.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://')}/ws';
    try {
      _channel?.sink.close();
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _connected = true;
      _reconnectAttempts = 0;
      notifyListeners();

      _channel!.stream.listen(
        (data) => _handleMessage(data),
        onError: (_) => _onDisconnect(),
        onDone: () => _onDisconnect(),
      );

      _channel!.sink.add(jsonEncode({'type': 'auth', 'token': _lastToken}));

      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
        if (_connected) {
          _channel?.sink.add(jsonEncode({'type': 'ping', 't': DateTime.now().millisecondsSinceEpoch}));
        }
      });
    } catch (_) {
      _onDisconnect();
    }
  }

  void _handleMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = data['type'] as String?;
      switch (type) {
        case 'auth_ok':
          _connected = true;
          break;
        case 'attack_alert':
          _realtimeAttacks.insert(0, data);
          if (_realtimeAttacks.length > 200) _realtimeAttacks.removeLast();
          break;
        case 'TRAFFIC_METRICS':
        case 'metrics':
          _liveMetrics = data['data'] is Map ? data['data'] as Map<String, dynamic> : data;
          break;
        case 'rule_update':
        case 'sync_complete':
          break;
        case 'pong':
          break;
      }
      notifyListeners();
    } catch (_) {}
  }

  void _onDisconnect() {
    _connected = false;
    notifyListeners();
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    if (_reconnectAttempts < _maxReconnectAttempts) {
      _reconnectAttempts++;
      final delay = Duration(seconds: 2 * _reconnectAttempts);
      _reconnectTimer = Timer(delay, () => _doConnect());
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channel?.sink.close();
    _connected = false;
    _lastUrl = null;
    _lastToken = null;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
