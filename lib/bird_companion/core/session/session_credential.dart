import 'package:aves/bird_companion/core/models/protocol_validation.dart';

class SessionCredential {
  const SessionCredential({
    required this.deviceId,
    required this.baseUri,
    required this.accessToken,
    required this.expiresAt,
    required this.apiVersion,
    this.clientId,
  });

  final String deviceId;
  final Uri baseUri;
  final String accessToken;
  final DateTime expiresAt;
  final String apiVersion;
  final String? clientId;

  bool isUsableAt(
    DateTime now, {
    Duration clockSkew = const Duration(seconds: 30),
  }) => accessToken.isNotEmpty && expiresAt.isAfter(now.toUtc().add(clockSkew));

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'base_uri': baseUri.toString(),
    'access_token': accessToken,
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'api_version': apiVersion,
    if (clientId != null) 'client_id': clientId,
  };

  factory SessionCredential.fromJson(Map<String, dynamic> json) {
    final deviceId = ProtocolValidation.requiredId(json, 'device_id');
    final accessToken = ProtocolValidation.requiredId(json, 'access_token');
    final apiVersion = ProtocolValidation.requiredId(json, 'api_version');
    final expiresAt = ProtocolValidation.optionalDateTime(json, 'expires_at');
    if (expiresAt == null) {
      throw const ProtocolCompatibilityException(
        'expires_at',
        '必须是 ISO-8601 时间',
      );
    }
    final baseUri = Uri.tryParse(
      ProtocolValidation.requiredId(json, 'base_uri'),
    );
    if (baseUri == null || !baseUri.hasScheme || baseUri.host.isEmpty) {
      throw const ProtocolCompatibilityException(
        'base_uri',
        '必须是完整的设备服务地址',
      );
    }
    return SessionCredential(
      deviceId: deviceId,
      baseUri: baseUri,
      accessToken: accessToken,
      expiresAt: expiresAt,
      apiVersion: apiVersion,
      clientId: json['client_id'] == null ? null : ProtocolValidation.requiredId(json, 'client_id'),
    );
  }

  @override
  String toString() => 'SessionCredential(deviceId: $deviceId, baseUri: $baseUri, accessToken: <redacted>, expiresAt: $expiresAt, apiVersion: $apiVersion, clientId: ${clientId == null ? 'legacy' : '<installation>'})';
}
