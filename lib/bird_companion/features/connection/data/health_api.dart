import 'dart:async';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:dio/dio.dart';

final class BirdBoxHealth {
  const BirdBoxHealth({
    required this.deviceId,
    required this.protocolVersion,
    required this.apiVersion,
    required this.activeMode,
    required this.serverTime,
  });

  final String deviceId;
  final String protocolVersion;
  final String apiVersion;
  final ProvisioningNetworkMode activeMode;
  final DateTime serverTime;

  factory BirdBoxHealth.fromJson(Map<String, dynamic> json) {
    const expected = {
      'status',
      'device_id',
      'protocol_version',
      'api_version',
      'active_mode',
      'server_time',
    };
    final unknown = json.keys.toSet().difference(expected);
    final missing = expected.difference(json.keys.toSet());
    if (unknown.isNotEmpty || missing.isNotEmpty) {
      throw ProvisioningProtocolException(
        'health',
        'missing=${missing.join(',')} unknown=${unknown.join(',')}',
      );
    }
    if (json['status'] != 'ok') {
      throw const ProvisioningProtocolException('status', 'must be ok');
    }
    final deviceId = _requiredString(json, 'device_id');
    if (!RegExp(r'^bbx-[0-9a-f]{32}$').hasMatch(deviceId)) {
      throw const ProvisioningProtocolException('device_id', 'invalid format');
    }
    final protocolVersion = _requiredString(json, 'protocol_version');
    if (protocolVersion != BleProtocolConstants.protocolVersion) {
      throw const ProvisioningException(
        code: ProvisioningErrorCode.protocolVersionUnsupported,
        retryable: false,
      );
    }
    final apiVersion = _requiredString(json, 'api_version');
    if (apiVersion != 'v1') {
      throw const ProvisioningProtocolException('api_version', 'must be v1');
    }
    final serverTime = DateTime.tryParse(_requiredString(json, 'server_time'));
    if (serverTime == null) {
      throw const ProvisioningProtocolException(
        'server_time',
        'must be ISO-8601',
      );
    }
    return BirdBoxHealth(
      deviceId: deviceId,
      protocolVersion: protocolVersion,
      apiVersion: apiVersion,
      activeMode: ProvisioningNetworkModeWireValue.parse(
        _requiredString(json, 'active_mode'),
      ),
      serverTime: serverTime,
    );
  }
}

final class HealthApi {
  const HealthApi(this._client);

  final ApiClient _client;

  Future<BirdBoxHealth> read(
    Uri baseUri, {
    Duration timeout = BleProtocolConstants.healthRequestTimeout,
  }) async {
    final cancelToken = CancelToken();
    try {
      final payload = await _client
          .getUri(baseUri.resolve(ApiEndpoints.health), cancelToken: cancelToken)
          .timeout(
            timeout,
            onTimeout: () {
              cancelToken.cancel('health attempt timed out');
              throw TimeoutException('BirdBox health attempt timed out');
            },
          );
      return BirdBoxHealth.fromJson(payload);
    } finally {
      if (!cancelToken.isCancelled) cancelToken.cancel('health attempt ended');
    }
  }

  Future<BirdBoxHealth> waitForDevice(
    Uri baseUri, {
    required String expectedDeviceId,
    Duration requestTimeout = BleProtocolConstants.healthRequestTimeout,
    Duration retryInterval = BleProtocolConstants.healthRetryInterval,
    Duration retryWindow = BleProtocolConstants.healthRetryWindow,
  }) async {
    final stopwatch = Stopwatch()..start();
    Object? lastError;
    while (stopwatch.elapsed < retryWindow) {
      try {
        final health = await read(baseUri, timeout: requestTimeout);
        if (health.deviceId != expectedDeviceId) {
          throw const ProvisioningException(
            code: ProvisioningErrorCode.deviceIdMismatch,
            retryable: false,
          );
        }
        return health;
      } on ProvisioningException catch (error) {
        if (error.code == ProvisioningErrorCode.deviceIdMismatch || error.code == ProvisioningErrorCode.protocolVersionUnsupported) {
          rethrow;
        }
        lastError = error;
      } catch (error) {
        lastError = error;
      }
      final remaining = retryWindow - stopwatch.elapsed;
      if (remaining <= Duration.zero) break;
      await Future<void>.delayed(
        remaining < retryInterval ? remaining : retryInterval,
      );
    }
    throw ProvisioningException(
      code: ProvisioningErrorCode.healthCheckFailed,
      retryable: true,
      diagnosticMessage: lastError?.runtimeType.toString(),
    );
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw ProvisioningProtocolException(key, 'must be a non-empty string');
  }
  return value;
}
