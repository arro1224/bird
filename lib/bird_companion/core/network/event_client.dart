import 'dart:async';
import 'dart:convert';

import 'package:aves/bird_companion/core/network/reconnect_policy.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum EventConnectionState { disconnected, connecting, connected, reconnecting }

typedef EventChannelConnector =
    WebSocketChannel Function(
      Uri endpoint,
      Map<String, dynamic> headers,
    );

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
  EventClient({
    ReconnectPolicy? reconnectPolicy,
    EventChannelConnector? connector,
  }) : _reconnectPolicy = reconnectPolicy ?? const ReconnectPolicy(),
       _connector =
           connector ??
           ((endpoint, headers) => IOWebSocketChannel.connect(
             endpoint,
             headers: headers,
             connectTimeout: const Duration(seconds: 5),
           ));

  final ReconnectPolicy _reconnectPolicy;
  final EventChannelConnector _connector;
  final _events = StreamController<DeviceEvent>.broadcast();
  final _connectionStates = StreamController<EventConnectionState>.broadcast();
  final _authenticationFailures = StreamController<int>.broadcast();
  StreamSubscription<dynamic>? _subscription;
  WebSocketChannel? _channel;
  Uri? _endpoint;
  String? _accessToken;
  String _apiVersion = 'v1';
  Timer? _retryTimer;
  bool _manualDisconnect = false;
  bool _authenticationBlocked = false;
  int _attempt = 0;
  EventConnectionState _currentState = EventConnectionState.disconnected;

  Stream<DeviceEvent> get events => _events.stream;
  Stream<EventConnectionState> get connectionStates => _connectionStates.stream;
  Stream<int> get authenticationFailures => _authenticationFailures.stream;
  EventConnectionState get currentState => _currentState;

  void _emitState(EventConnectionState value) {
    if (_currentState == value) return;
    _currentState = value;
    _connectionStates.add(value);
  }

  Future<void> connect(
    Uri uri, {
    required String accessToken,
    String apiVersion = 'v1',
  }) async {
    _endpoint = uri;
    _accessToken = accessToken;
    _apiVersion = apiVersion;
    _manualDisconnect = false;
    _authenticationBlocked = false;
    _retryTimer?.cancel();
    await _open(isReconnect: false);
  }

  Future<void> _open({required bool isReconnect}) async {
    final endpoint = _endpoint;
    final accessToken = _accessToken;
    if (endpoint == null || accessToken == null || _manualDisconnect || _authenticationBlocked) return;
    _emitState(isReconnect ? EventConnectionState.reconnecting : EventConnectionState.connecting);
    await _subscription?.cancel();
    await _channel?.sink.close();
    try {
      final channel = _connector(endpoint, {
        'Authorization': 'Bearer $accessToken',
        'X-Api-Version': _apiVersion,
      });
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 5));
      _attempt = 0;
      _emitState(EventConnectionState.connected);
      _subscription = channel.stream.listen(
        _onMessage,
        onError: (error, _) => _handleFailure(error),
        onDone: () => _handleClosed(channel),
        cancelOnError: false,
      );
    } catch (error) {
      final statusCode = _authenticationStatus(error);
      if (statusCode != null) {
        _blockForAuthentication(statusCode);
        return;
      }
      _scheduleReconnect();
    }
  }

  void _handleFailure(Object error) {
    final statusCode = _authenticationStatus(error);
    if (statusCode != null) {
      _blockForAuthentication(statusCode);
    } else {
      _scheduleReconnect();
    }
  }

  void _handleClosed(WebSocketChannel channel) {
    final closeCode = channel.closeCode;
    if (closeCode == 4401 || closeCode == 4403) {
      _blockForAuthentication(closeCode == 4401 ? 401 : 403);
    } else {
      _scheduleReconnect();
    }
  }

  int? _authenticationStatus(Object error) {
    final value = error.toString().toLowerCase();
    if (RegExp(r'(status(?: code)?[: ]+|http[/ ]).*401').hasMatch(value)) {
      return 401;
    }
    if (RegExp(r'(status(?: code)?[: ]+|http[/ ]).*403').hasMatch(value)) {
      return 403;
    }
    return null;
  }

  void _blockForAuthentication(int statusCode) {
    _authenticationBlocked = true;
    _retryTimer?.cancel();
    final channel = _channel;
    _channel = null;
    unawaited(channel?.sink.close());
    _emitState(EventConnectionState.disconnected);
    _authenticationFailures.add(statusCode);
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
    _authenticationBlocked = false;
    _retryTimer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _accessToken = null;
    _emitState(EventConnectionState.disconnected);
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
    await _connectionStates.close();
    await _authenticationFailures.close();
  }
}
