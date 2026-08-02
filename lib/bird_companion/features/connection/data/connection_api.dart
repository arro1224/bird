import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/core/session/session_coordinator.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_address.dart';
import 'package:aves/bird_companion/features/connection/data/pairing_api.dart';
import 'package:dio/dio.dart';

class PairingRequiredException implements Exception {
  const PairingRequiredException(this.status);
  final DeviceStatus status;

  @override
  String toString() => '该设备需要先完成配对。';
}

class ConnectionApi {
  ConnectionApi(this._apiClient, this._pairingApi, this._sessionCoordinator);
  final ApiClient _apiClient;
  final PairingApi _pairingApi;
  final SessionCoordinator _sessionCoordinator;

  Future<DeviceStatus> handshake(
    Uri baseUri,
    NetworkMode networkMode, {
    CancelToken? cancelToken,
  }) async {
    final normalized = _normalizeBaseUri(baseUri);
    final status = await _publicStatus(
      normalized,
      networkMode,
      cancelToken: cancelToken,
    );
    if (cancelToken?.isCancelled == true) {
      throw StateError('Connection cancelled before the device session was configured.');
    }
    final restored = await _sessionCoordinator.restore(
      deviceId: status.connection.id,
      baseUri: normalized,
    );
    if (!restored) throw PairingRequiredException(status);
    if (cancelToken?.isCancelled == true) {
      throw StateError('Connection cancelled before the device session was configured.');
    }
    return _publicStatus(
      normalized,
      networkMode,
      cancelToken: cancelToken,
    );
  }

  Future<DeviceStatus> pair(
    Uri baseUri,
    NetworkMode networkMode, {
    required String pairingCode,
    CancelToken? cancelToken,
  }) async {
    final normalized = _normalizeBaseUri(baseUri);
    final publicStatus = await _publicStatus(
      normalized,
      networkMode,
      cancelToken: cancelToken,
    );
    final credential = await _pairingApi.pair(
      normalized,
      pairingCode: pairingCode,
    );
    if (credential.deviceId != publicStatus.connection.id) {
      throw const ProtocolCompatibilityException(
        'device_id',
        '配对响应与当前设备不一致',
      );
    }
    if (cancelToken?.isCancelled == true) {
      throw StateError('Connection cancelled before the device session was configured.');
    }
    await _sessionCoordinator.activate(credential);
    return _publicStatus(
      normalized,
      networkMode,
      cancelToken: cancelToken,
    );
  }

  Future<DeviceStatus> _publicStatus(
    Uri normalized,
    NetworkMode networkMode, {
    CancelToken? cancelToken,
  }) async {
    final payload = await _apiClient.getUri(
      normalized.resolve(ApiEndpoints.deviceStatus),
      cancelToken: cancelToken,
    );
    return DeviceStatus.fromJson(
      payload,
      fallbackBaseUri: normalized,
      fallbackNetworkMode: networkMode,
    );
  }

  Future<void> disconnect() async {
    await _sessionCoordinator.clearMemory();
  }

  Future<void> forget(String deviceId) => _sessionCoordinator.forget(deviceId);

  Uri _normalizeBaseUri(Uri value) {
    final normalized = ConnectionAddress.normalize(value.hasScheme ? value : value.replace(scheme: 'http'));
    if (normalized == null) throw ArgumentError.value(value, 'baseUri', 'A local box address is required.');
    return normalized;
  }
}
