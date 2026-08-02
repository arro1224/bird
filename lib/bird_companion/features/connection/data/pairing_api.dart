import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/core/session/session_credential.dart';

class PairingApi {
  PairingApi(this._client);
  final ApiClient _client;

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
