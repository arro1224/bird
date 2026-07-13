import 'dart:async';

import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';

class ConnectionApi {
  ConnectionApi(this._apiClient, this._eventClient);
  final ApiClient _apiClient;
  final EventClient _eventClient;

  Future<DeviceStatus> handshake(Uri baseUri, NetworkMode networkMode) async {
    final normalized = _normalizeBaseUri(baseUri);
    final payload = await _apiClient.getUri(normalized.resolve(ApiEndpoints.deviceStatus));
    final status = DeviceStatus.fromJson(payload, fallbackBaseUri: normalized, fallbackNetworkMode: networkMode);
    _apiClient.configure(normalized);
    final eventUri = normalized.replace(scheme: normalized.scheme == 'https' ? 'wss' : 'ws', path: ApiEndpoints.events);
    // The mock server and some legacy boxes do not expose WebSocket. A failed
    // event channel must never make an otherwise successful HTTP reconnect fail.
    unawaited(_eventClient.connect(eventUri));
    return status;
  }

  Future<void> disconnect() async {
    await _eventClient.disconnect();
    _apiClient.clearSession();
  }

  Uri _normalizeBaseUri(Uri value) => value.hasScheme ? value : value.replace(scheme: 'http');
}
