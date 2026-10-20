import 'dart:convert';
import 'dart:typed_data';

import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/domain/pairing_preflight_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';

/// Codec for the public 0007 protocol only, never the encrypted command path.
/// Supports the documented minimal envelope and validates optional rc4 identity
/// fields if present. Live transport integration remains a later batch.
final class PairingPreflightCodec {
  const PairingPreflightCodec();

  Uint8List encodeRequest(PairingPreflightRequest request) {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(request.toProtocolJson())));
    if (bytes.length > BleProtocolConstants.maximumMessageBytes) {
      bytes.fillRange(0, bytes.length, 0);
      throw const ProvisioningProtocolException('message', 'exceeds 4096 bytes');
    }
    return bytes;
  }

  PairingPreflightResponse decodeResponse(Uint8List message, {required PairingPreflightRequest request, required String expectedDeviceId, required DateTime receivedAt}) {
    if (!RegExp(r'^bbx-[0-9a-f]{32}$').hasMatch(expectedDeviceId)) {
      throw const ProvisioningProtocolException('device_id', 'invalid expected device identity');
    }
    final json = _decodeObject(message);
    final ok = json['ok'];
    if (ok is! bool) throw const ProvisioningProtocolException('ok', 'must be a boolean');
    _keys(json, {'type', 'request_id', 'ok', ok ? 'payload' : 'error'}, 'envelope', optional: {'protocol_version', 'device_id'});
    if (json.containsKey('protocol_version') && json['protocol_version'] != BleProtocolConstants.protocolVersion) {
      throw const ProvisioningProtocolException('protocol_version', 'unsupported preflight version');
    }
    if (json.containsKey('device_id') && json['device_id'] != expectedDeviceId) {
      throw const ProvisioningProtocolException('device_id', 'preflight response identity mismatch');
    }
    if (_string(json, 'request_id') != request.requestId) {
      throw const ProvisioningProtocolException('request_id', 'preflight response belongs to another request');
    }
    final type = _string(json, 'type');
    if (!ok) {
      if (type != 'error') throw const ProvisioningProtocolException('type', 'failure must use error');
      return _failure(_map(json, 'error'), request.requestId);
    }
    final payload = _map(json, 'payload');
    if (request is PrepareSystemPairingRequest && type == 'pairing_preflight_result') {
      final action = _string(payload, 'action');
      switch (action) {
        case 'none':
          _keys(payload, {'action', 'board_bond_before'}, 'payload');
          return PairingPreflightNone(requestId: request.requestId, boardBondBefore: _boardBond(payload));
        case 'reset_required':
          _keys(payload, {'action', 'board_bond_before', 'reset_token', 'expires_in_ms'}, 'payload');
          return PairingPreflightResetRequired(
            requestId: request.requestId,
            clientId: request.clientId,
            boardBondBefore: _boardBond(payload),
            resetToken: _string(payload, 'reset_token'),
            expiresIn: Duration(milliseconds: _nonNegativeInt(payload, 'expires_in_ms')),
            receivedAt: receivedAt,
          );
        default:
          throw const ProvisioningProtocolException('action', 'unknown prepare action');
      }
    }
    if (request is ConfirmPairingResetRequest && type == 'pairing_reset_scheduled') {
      _keys(payload, {'action', 'prepare_request_id', 'board_bond_before', 'disconnect_expected', 'remove_after_ms'}, 'payload');
      if (payload['action'] != 'remove_scheduled' || payload['disconnect_expected'] != true) {
        throw const ProvisioningProtocolException('payload', 'reset must schedule an expected disconnect');
      }
      if (_string(payload, 'prepare_request_id') != request.prepareRequestId) {
        throw const ProvisioningProtocolException('prepare_request_id', 'reset belongs to another prepare');
      }
      return PairingResetScheduled(
        requestId: request.requestId,
        prepareRequestId: request.prepareRequestId,
        boardBondBefore: _boardBond(payload),
        removeAfter: Duration(milliseconds: _nonNegativeInt(payload, 'remove_after_ms')),
      );
    }
    throw const ProvisioningProtocolException('type', 'response does not match preflight command');
  }

  PairingPreflightFailure _failure(Map<String, dynamic> json, String requestId) {
    _keys(json, {'code', 'message', 'retryable', 'retry_after_ms'}, 'error');
    // Never echo arbitrary peer-supplied error messages/values into diagnostics.
    final rawCode = _string(json, 'code');
    final matching = ProvisioningErrorCode.values.where((code) => code.wireValue == rawCode && code.pairingPreflightDisposition != null);
    if (matching.isEmpty) throw const ProvisioningProtocolException('error.code', 'unknown preflight error');
    final code = matching.single;
    if (json['message'] is! String || json['retryable'] is! bool) {
      throw const ProvisioningProtocolException('error', 'invalid error field types');
    }
    final retryAfter = _nonNegativeInt(json, 'retry_after_ms');
    return PairingPreflightFailure(
      requestId: requestId,
      error: ProvisioningException(
        code: code,
        retryable: json['retryable'] == true && code.pairingPreflightDisposition == PairingPreflightErrorDisposition.boundedRetryAfterRelease,
        retryAfter: Duration(milliseconds: retryAfter),
      ),
    );
  }
}

Map<String, dynamic> _decodeObject(Uint8List message) {
  if (message.length > BleProtocolConstants.maximumMessageBytes) throw const ProvisioningProtocolException('message', 'exceeds 4096 bytes');
  try {
    final json = jsonDecode(utf8.decode(message, allowMalformed: false));
    if (json is Map<String, dynamic>) return json;
  } on FormatException {
    // FormatException.source may contain reset_token. Do not retain it.
    throw const ProvisioningProtocolException('message', 'invalid preflight JSON or UTF-8');
  }
  throw const ProvisioningProtocolException('message', 'must be an object');
}

void _keys(Map<String, dynamic> json, Set<String> required, String field, {Set<String> optional = const {}}) {
  if (!json.keys.toSet().containsAll(required) || json.keys.any((key) => !required.contains(key) && !optional.contains(key))) {
    // Even unknown key names may contain secrets: do not interpolate them.
    throw ProvisioningProtocolException(field, 'unexpected or missing preflight fields');
  }
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) throw ProvisioningProtocolException(key, 'must be a non-empty string');
  return value;
}

Map<String, dynamic> _map(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! Map<String, dynamic>) throw ProvisioningProtocolException(key, 'must be an object');
  return value;
}

int _nonNegativeInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int || value < 0) throw ProvisioningProtocolException(key, 'must be a non-negative integer');
  return value;
}

BoardBondBefore _boardBond(Map<String, dynamic> payload) {
  final json = _map(payload, 'board_bond_before');
  _keys(json, {'paired', 'bonded'}, 'board_bond_before');
  final paired = json['paired'], bonded = json['bonded'];
  if (paired is! bool || bonded is! bool) throw const ProvisioningProtocolException('board_bond_before', 'must contain booleans');
  return BoardBondBefore(paired: paired, bonded: bonded);
}
