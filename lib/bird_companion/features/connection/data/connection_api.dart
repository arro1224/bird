import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/core/session/session_coordinator.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_address.dart';
import 'package:aves/bird_companion/features/connection/data/pairing_api.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:dio/dio.dart';
import '../domain/connection_attempt.dart';

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
    String? expectedDeviceId,
  }) async {
    final normalized = _normalizeBaseUri(baseUri);
    final status = await ConnectionAttempt.runFor(
      cancelToken,
      'identity',
      () => _publicStatus(
        normalized,
        networkMode,
        cancelToken: cancelToken,
      ),
    );
    _checkIdentity(status, expectedDeviceId);
    if (cancelToken?.isCancelled == true) {
      throw StateError('Connection cancelled before the device session was configured.');
    }
    final restored = await ConnectionAttempt.runFor(
      cancelToken,
      'credential_restore',
      () => _sessionCoordinator.restore(
        deviceId: status.connection.id,
        baseUri: normalized,
        cancelToken: cancelToken,
      ),
    );
    if (!restored) throw PairingRequiredException(status);
    if (cancelToken?.isCancelled == true) {
      throw StateError('Connection cancelled before the device session was configured.');
    }
    final verified = await ConnectionAttempt.runFor(
      cancelToken,
      'identity_recheck',
      () => _publicStatus(
        normalized,
        networkMode,
        cancelToken: cancelToken,
      ),
    );
    _checkIdentity(verified, expectedDeviceId);
    if (expectedDeviceId != null) {
      await ConnectionAttempt.runFor(cancelToken, 'protected_http', () => _apiClient.verifyAuthenticatedSession(cancelToken));
      await ConnectionAttempt.runFor(cancelToken, 'events', () async => _sessionCoordinator.requireConnectedSession(expectedDeviceId, normalized));
    }
    return verified;
  }

  Future<void> verifyDirectApIdentity(Uri baseUri, String deviceId, CancelToken cancelToken, {NetworkMode networkMode = NetworkMode.directAp}) async {
    final status = await _publicStatus(_normalizeBaseUri(baseUri), networkMode, cancelToken: cancelToken);
    _checkIdentity(status, deviceId);
    if (status.connection.networkMode != networkMode) {
      throw const ProvisioningProtocolException('network_mode', 'Unexpected active network mode');
    }
  }

  void _checkIdentity(DeviceStatus status, String? expectedDeviceId) {
    if (expectedDeviceId != null && status.connection.id != expectedDeviceId) {
      throw const ProvisioningException(code: ProvisioningErrorCode.deviceIdMismatch, retryable: false);
    }
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
    await _sessionCoordinator.activate(credential, cancelToken: cancelToken);
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
