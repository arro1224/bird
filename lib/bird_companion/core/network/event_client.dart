import 'dart:async';
import 'dart:convert';

import 'package:aves/bird_companion/core/network/reconnect_policy.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum EventConnectionState { disconnected, connecting, connected, reconnecting }

class DeviceEvent {
  const DeviceEvent({required this.type, required this.payload, required this.timestamp});
  final String type;
  final Map<String, dynamic> payload;
  final DateTime timestamp;

  factory DeviceEvent.fromJson(Map<String, dynamic> json) => DeviceEvent(
    type: json['event_type']?.toString() ?? 'unknown',
    payload: json['payload'] is Map ? Map<String, dynamic>.from(json['payload'] as Map) : json,
    timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
  );
}

class EventClient {
  EventClient({ReconnectPolicy? reconnectPolicy}) : _reconnectPolicy = reconnectPolicy ?? const ReconnectPolicy();

  final ReconnectPolicy _reconnectPolicy;
  final _events = StreamController<DeviceEvent>.broadcast();
  final _connectionStates = StreamController<EventConnectionState>.broadcast();
  StreamSubscription<dynamic>? _subscription;
  WebSocketChannel? _channel;
  Uri? _endpoint;
  Timer? _retryTimer;
  bool _manualDisconnect = false;
  int _attempt = 0;
  EventConnectionState _currentState = EventConnectionState.disconnected;

  Stream<DeviceEvent> get events => _events.stream;
  Stream<EventConnectionState> get connectionStates => _connectionStates.stream;
  EventConnectionState get currentState => _currentState;

  void _emitState(EventConnectionState value) {
    if (_currentState == value) return;
    _currentState = value;
    _connectionStates.add(value);
  }

  Future<void> connect(Uri uri) async {
    _endpoint = uri;
    _manualDisconnect = false;
    _retryTimer?.cancel();
    await _open(isReconnect: false);
  }

  Future<void> _open({required bool isReconnect}) async {
    final endpoint = _endpoint;
    if (endpoint == null || _manualDisconnect) return;
    _emitState(isReconnect ? EventConnectionState.reconnecting : EventConnectionState.connecting);
    await _subscription?.cancel();
    await _channel?.sink.close();
    try {
      final channel = WebSocketChannel.connect(endpoint);
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 5));
      _attempt = 0;
      _emitState(EventConnectionState.connected);
      _subscription = channel.stream.listen(_onMessage, onError: (_, _) => _scheduleReconnect(), onDone: _scheduleReconnect, cancelOnError: false);
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic message) {
    try {
      final decoded = jsonDecode(message.toString());
      if (decoded is Map) _events.add(DeviceEvent.fromJson(Map<String, dynamic>.from(decoded)));
    } catch (_) {
      // 忽略非 JSON 心跳/未知事件；最终协议可在 DTO 层适配。
    }
  }

  void _scheduleReconnect() {
    if (_manualDisconnect || _endpoint == null || _attempt >= _reconnectPolicy.maxAttempts) {
      _emitState(EventConnectionState.disconnected);
      return;
    }
    final delay = _reconnectPolicy.delayFor(_attempt++);
    _emitState(EventConnectionState.reconnecting);
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => _open(isReconnect: true));
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _retryTimer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _emitState(EventConnectionState.disconnected);
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
    await _connectionStates.close();
  }
}
