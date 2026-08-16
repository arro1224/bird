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
  const DeviceEvent({
    required this.type,
    required this.payload,
    required this.timestamp,
    this.eventId,
  });
  final String type;
  final Map<String, dynamic> payload;
  final DateTime timestamp;
  final String? eventId;

  factory DeviceEvent.fromJson(Map<String, dynamic> json) => DeviceEvent(
    type: json['event_type']?.toString() ?? 'unknown',
    payload: json['payload'] is Map ? Map<String, dynamic>.from(json['payload'] as Map) : json,
    timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
    eventId: json['event_id']?.toString(),
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
  int _connectionGeneration = 0;
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
    final generation = ++_connectionGeneration;
    _endpoint = uri;
    _accessToken = accessToken;
    _apiVersion = apiVersion;
    _manualDisconnect = false;
    _authenticationBlocked = false;
    _retryTimer?.cancel();
    await _open(isReconnect: false, generation: generation);
  }

  Future<void> _open({
    required bool isReconnect,
    required int generation,
  }) async {
    final endpoint = _endpoint;
    final accessToken = _accessToken;
    if (generation != _connectionGeneration || endpoint == null || accessToken == null || _manualDisconnect || _authenticationBlocked) return;
    _emitState(isReconnect ? EventConnectionState.reconnecting : EventConnectionState.connecting);
    try {
      await _subscription?.cancel();
    } catch (_) {
      // A failed old stream must not prevent a new device session opening.
    }
    _subscription = null;
    final previousChannel = _channel;
    _channel = null;
    await _closeChannel(previousChannel);
    if (generation != _connectionGeneration || _manualDisconnect || _authenticationBlocked) return;
    try {
      final channel = _connector(endpoint, {
        'Authorization': 'Bearer $accessToken',
        'X-Api-Version': _apiVersion,
      });
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 5));
      if (generation != _connectionGeneration || !identical(channel, _channel) || _manualDisconnect || _authenticationBlocked) {
        await _closeChannel(channel);
        return;
      }
      _attempt = 0;
      _emitState(EventConnectionState.connected);
      _subscription = channel.stream.listen(
        (message) {
          if (generation == _connectionGeneration && identical(channel, _channel)) {
            _onMessage(message);
          }
        },
        onError: (error, _) => _handleFailure(error, channel, generation),
        onDone: () => _handleClosed(channel, generation),
        cancelOnError: false,
      );
    } catch (error) {
      if (generation != _connectionGeneration || _manualDisconnect) return;
      final statusCode = _authenticationStatus(error);
      if (statusCode != null) {
        _blockForAuthentication(statusCode, generation);
        return;
      }
      _scheduleReconnect(generation);
    }
  }

  void _handleFailure(
    Object error,
    WebSocketChannel channel,
    int generation,
  ) {
    if (generation != _connectionGeneration || !identical(channel, _channel)) return;
    final statusCode = _authenticationStatus(error);
    if (statusCode != null) {
      _blockForAuthentication(statusCode, generation);
    } else {
      _scheduleReconnect(generation);
    }
  }

  void _handleClosed(WebSocketChannel channel, int generation) {
    if (generation != _connectionGeneration || !identical(channel, _channel)) return;
    final closeCode = channel.closeCode;
    if (closeCode == 4401 || closeCode == 4403) {
      _blockForAuthentication(closeCode == 4401 ? 401 : 403, generation);
    } else {
      _scheduleReconnect(generation);
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

  void _blockForAuthentication(int statusCode, int generation) {
    if (generation != _connectionGeneration) return;
    _authenticationBlocked = true;
    _retryTimer?.cancel();
    final channel = _channel;
    _channel = null;
    unawaited(_closeChannel(channel));
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

  void _scheduleReconnect(int generation) {
    if (generation != _connectionGeneration || _manualDisconnect || _endpoint == null || _attempt >= _reconnectPolicy.maxAttempts) {
      _emitState(EventConnectionState.disconnected);
      return;
    }
    final delay = _reconnectPolicy.delayFor(_attempt++);
    _emitState(EventConnectionState.reconnecting);
    _retryTimer?.cancel();
    _retryTimer = Timer(
      delay,
      () => _open(isReconnect: true, generation: generation),
    );
  }

  Future<void> disconnect() async {
    _connectionGeneration++;
    _manualDisconnect = true;
    _authenticationBlocked = false;
    _retryTimer?.cancel();
    try {
      await _subscription?.cancel();
    } catch (_) {
      // The session is still cleared when the old stream failed noisily.
    }
    _subscription = null;
    await _closeChannel(_channel);
    _channel = null;
    _accessToken = null;
    _emitState(EventConnectionState.disconnected);
  }

  Future<void> _closeChannel(WebSocketChannel? channel) async {
    try {
      await channel?.sink.close();
    } catch (_) {
      // Closing is best effort. Connection generations reject late callbacks.
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
    await _connectionStates.close();
    await _authenticationFailures.close();
  }
}
