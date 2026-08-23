import 'dart:convert';
import 'dart:typed_data';

import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';

sealed class BleDecodedResponse {
  const BleDecodedResponse({required this.requestId, required this.deviceId});

  final String requestId;
  final String deviceId;
}

final class BleSuccessResponse extends BleDecodedResponse {
  BleSuccessResponse(this.event) : super(requestId: event.requestId, deviceId: event.deviceId);

  final ProvisioningEvent event;
}

final class BleFailureResponse extends BleDecodedResponse {
  const BleFailureResponse({required super.requestId, required super.deviceId, required this.error});

  final ProvisioningException error;
}

/// Converts between UTF-8 JSON messages and the strict rc4 domain models.
final class BleMessageCodec {
  const BleMessageCodec();

  Uint8List encodeRequest(BleCommandRequest request) {
    if (!isUuidV4(request.requestId)) {
      throw const ProvisioningProtocolException('request_id', 'must be a UUID v4');
    }
    if (!isUuidV4(request.clientId)) {
      throw const ProvisioningProtocolException('client_id', 'must be a UUID v4');
    }
    try {
      return Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'protocol_version': BleProtocolConstants.protocolVersion,
            'type': request.type.wireValue,
            'request_id': request.requestId,
            'client_id': request.clientId,
            'payload': request.payload,
          }),
        ),
      );
    } on JsonUnsupportedObjectError catch (error) {
      throw ProvisioningProtocolException('payload', 'must contain JSON values', error);
    }
  }

  ProvisioningDeviceInfo decodeDeviceInfo(Uint8List message) => ProvisioningDeviceInfo.fromJson(_decodeObject(message));

  ProvisioningNetworkStatus decodeNetworkStatus(Uint8List message) {
    final response = decodeResponse(message);
    if (response is BleFailureResponse) throw response.error;
    final event = (response as BleSuccessResponse).event;
    if (event.type != ProvisioningEventType.networkStatus || event.payload is! ProvisioningNetworkStatus) {
      throw const ProvisioningProtocolException('type', 'expected network_status');
    }
    return event.payload as ProvisioningNetworkStatus;
  }

  BleDecodedResponse decodeResponse(Uint8List message) {
    final json = _decodeObject(message);
    final ok = json['ok'];
    if (ok is! bool) throw const ProvisioningProtocolException('ok', 'must be a boolean');
    if (ok) {
      _requireExactKeys(json, const {'protocol_version', 'type', 'request_id', 'device_id', 'ok', 'payload'}, 'success_envelope');
      return BleSuccessResponse(ProvisioningEvent.fromJson(json));
    }

    _requireExactKeys(json, const {'protocol_version', 'type', 'request_id', 'device_id', 'ok', 'error'}, 'error_envelope');
    if (_requiredString(json, 'protocol_version') != BleProtocolConstants.protocolVersion) {
      throw const ProvisioningProtocolException('protocol_version', 'unsupported value');
    }
    if (_requiredString(json, 'type') != 'error') {
      throw const ProvisioningProtocolException('type', 'failure envelope must use error');
    }
    final requestId = _requiredString(json, 'request_id');
    final deviceId = _requiredString(json, 'device_id');
    if (!RegExp(r'^bbx-[0-9a-f]{32}$').hasMatch(deviceId)) {
      throw const ProvisioningProtocolException('device_id', 'invalid format');
    }
    final errorJson = _requiredMap(json, 'error');
    _requireExactKeys(errorJson, const {'code', 'message', 'retryable', 'retry_after_ms'}, 'error');
    return BleFailureResponse(requestId: requestId, deviceId: deviceId, error: ProvisioningException.fromJson(errorJson));
  }

  Map<String, dynamic> _decodeObject(Uint8List message) {
    if (message.length > BleProtocolConstants.maximumMessageBytes) {
      throw const ProvisioningProtocolException('message', 'exceeds 4096 bytes');
    }
    try {
      final decoded = jsonDecode(utf8.decode(message, allowMalformed: false));
      if (decoded is! Map) throw const ProvisioningProtocolException('message', 'must be a JSON object');
      return Map<String, dynamic>.from(decoded);
    } on FormatException catch (error) {
      if (error is ProvisioningProtocolException) rethrow;
      throw ProvisioningProtocolException('message', 'must be valid JSON', error);
    }
  }
}

void _requireExactKeys(Map<String, dynamic> json, Set<String> expected, String context) {
  final actual = json.keys.toSet();
  final missing = expected.difference(actual);
  final unknown = actual.difference(expected);
  if (missing.isNotEmpty || unknown.isNotEmpty) {
    throw ProvisioningProtocolException(context, 'missing=${missing.join(',')} unknown=${unknown.join(',')}');
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) throw ProvisioningProtocolException(key, 'must be a non-empty string');
  return value;
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! Map) throw ProvisioningProtocolException(key, 'must be an object');
  return Map<String, dynamic>.from(value);
}
