import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/core/session/session_credential.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';

class PairingApi {
  PairingApi(this._client);
  final ApiClient _client;

  /// Exchanges the transient BLE pairing session for a 30-day Bearer token.
  /// Pairing codes are deliberately not accepted by this endpoint.
  Future<SessionCredential> exchangeSession(
    Uri baseUri, {
    required String deviceId,
    required String clientId,
    required String pairingSessionId,
    String clientName = 'Bird Companion Android',
    DateTime Function()? clock,
  }) async {
    if (!isUuidV4(clientId)) {
      throw const ProvisioningProtocolException(
        'client_id',
        'must be a UUID v4',
      );
    }
    if (pairingSessionId.isEmpty) {
      throw const ProvisioningProtocolException(
        'pairing_session_id',
        'must not be empty',
      );
    }
    final payload = await _client.postUri(
      baseUri.resolve(ApiEndpoints.pairing),
      data: {
        'device_id': deviceId,
        'client_id': clientId,
        'client_name': clientName,
        'pairing_session_id': pairingSessionId,
      },
    );
    const expected = {
      'token_type',
      'access_token',
      'expires_in',
      'device_id',
      'client_id',
    };
    final actual = payload.keys.toSet();
    if (!actual.containsAll(expected) || !expected.containsAll(actual)) {
      throw const ProvisioningProtocolException(
        'pairing_response',
        'must match the frozen rc4 token schema',
      );
    }
    if (payload['token_type'] != 'Bearer') {
      throw const ProvisioningProtocolException(
        'token_type',
        'must be Bearer',
      );
    }
    final expiresIn = payload['expires_in'];
    if (expiresIn != 2592000) {
      throw const ProvisioningProtocolException(
        'expires_in',
        'must be 2592000 seconds',
      );
    }
    final returnedDeviceId = ProtocolValidation.requiredId(
      payload,
      'device_id',
    );
    if (returnedDeviceId != deviceId) {
      throw const ProvisioningException(
        code: ProvisioningErrorCode.deviceIdMismatch,
        retryable: false,
      );
    }
    final returnedClientId = ProtocolValidation.requiredId(
      payload,
      'client_id',
    );
    if (returnedClientId != clientId) {
      throw const ProvisioningProtocolException(
        'client_id',
        'pairing response belongs to another installation',
      );
    }
    return SessionCredential(
      deviceId: returnedDeviceId,
      baseUri: baseUri,
      accessToken: ProtocolValidation.requiredId(payload, 'access_token'),
      expiresAt: (clock ?? DateTime.now)().toUtc().add(
        const Duration(seconds: 2592000),
      ),
      apiVersion: 'v1',
      clientId: returnedClientId,
    );
  }

  /// Legacy v1 compatibility path. The rc4 provisioning flow must use
  /// [exchangeSession] and must never send its pairing code over HTTP.
  Future<SessionCredential> pair(
    Uri baseUri, {
    required String pairingCode,
    String clientName = 'Bird Companion Android',
  }) async {
    final code = pairingCode.trim();
    if (code.length < 4) {
      throw const FormatException('配对码至少需要 4 位。');
    }
    final payload = await _client.postUri(
      baseUri.resolve(ApiEndpoints.devicePair),
      data: {
        'pairing_code': code,
        'client_name': clientName,
      },
    );
    return SessionCredential(
      deviceId: ProtocolValidation.requiredId(payload, 'device_id'),
      baseUri: baseUri,
      accessToken: ProtocolValidation.requiredId(payload, 'access_token'),
      expiresAt:
          ProtocolValidation.optionalDateTime(payload, 'expires_at') ??
          (throw const ProtocolCompatibilityException(
            'expires_at',
            '必须是 ISO-8601 时间',
          )),
      apiVersion: ProtocolValidation.requiredId(payload, 'api_version'),
    );
  }
}
