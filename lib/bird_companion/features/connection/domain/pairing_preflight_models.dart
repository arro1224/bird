import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';

/// A value returned by the native layer for the current BluetoothDevice.
/// The future transport must recheck its generation and freshness before use.
enum NativeBondState {
  notBonded('BOND_NONE'),
  bonding('BOND_BONDING'),
  bonded('BOND_BONDED');

  const NativeBondState(this.platformValue);
  final String platformValue;

  static NativeBondState fromPlatform(String value) => switch (value) {
    'BOND_NONE' || 'not_bonded' => notBonded,
    'BOND_BONDING' || 'bonding' => bonding,
    'BOND_BONDED' || 'bonded' => bonded,
    _ => throw const ProvisioningProtocolException('bond_state', 'unknown native bond state'),
  };
}

/// Preparation stages, deliberately separate from the existing secure-write flow.
/// No live Cubit or native command is started by these models.
enum PairingPreflightStage {
  pending('PAIRING_PREFLIGHT_PENDING'),
  resetConfirming('STALE_BOND_RESET_CONFIRMING'),
  resetPending('STALE_BOND_RESET_PENDING'),
  waitingForFreshAdvertisement('WAITING_FOR_FRESH_ADVERTISEMENT'),
  freshGattReconnecting('FRESH_GATT_RECONNECTING');

  const PairingPreflightStage(this.diagnosticValue);
  final String diagnosticValue;
}

enum PairingPreflightErrorDisposition { boundedRetryAfterRelease, upgradeRequired, terminal }

extension PairingPreflightErrorPolicy on ProvisioningErrorCode {
  /// This classifies eligibility only; retry budgets belong to the orchestrator.
  /// None of these outcomes permits an automatic createBond fallback.
  PairingPreflightErrorDisposition? get pairingPreflightDisposition => switch (this) {
    ProvisioningErrorCode.pairingPreflightBusy || ProvisioningErrorCode.pairingPreflightExpired => PairingPreflightErrorDisposition.boundedRetryAfterRelease,
    ProvisioningErrorCode.pairingPreflightCommandUnsupported => PairingPreflightErrorDisposition.upgradeRequired,
    ProvisioningErrorCode.pairingPreflightInvalidPeer || ProvisioningErrorCode.pairingPreflightConfirmationRejected || ProvisioningErrorCode.requestIdConflict => PairingPreflightErrorDisposition.terminal,
    _ => null,
  };
}

/// Not a BleCommandRequest: public preflight must never enter preparePairing().
sealed class PairingPreflightRequest {
  PairingPreflightRequest({required this.requestId, required this.clientId}) {
    _requireUuid(requestId, 'request_id');
    _requireUuid(clientId, 'client_id');
  }

  final String requestId;
  final String clientId;
  String get wireType;

  /// Sensitive wire serialization only. Never pass the returned map to logging.
  Map<String, dynamic> toProtocolJson();

  Map<String, dynamic> _envelope(Map<String, dynamic> payload) => {
    'protocol_version': BleProtocolConstants.protocolVersion,
    'type': wireType,
    'request_id': requestId,
    'client_id': clientId,
    'payload': payload,
  };

  @override
  String toString() => 'PairingPreflightRequest(type: $wireType, requestId: $requestId, payload: <redacted>)';
}

final class PrepareSystemPairingRequest extends PairingPreflightRequest {
  PrepareSystemPairingRequest({required super.requestId, required super.clientId, required NativeBondState phoneBondState}) {
    if (phoneBondState != NativeBondState.notBonded) {
      throw const ProvisioningProtocolException('phone_bond_state', 'preflight requires native BOND_NONE');
    }
  }

  @override
  String get wireType => 'prepare_system_pairing';

  @override
  Map<String, dynamic> toProtocolJson() => _envelope({'phone_bond_state': 'not_bonded'});
}

final class ConfirmPairingResetRequest extends PairingPreflightRequest {
  ConfirmPairingResetRequest._(this._resetToken, {required super.requestId, required super.clientId, required this.prepareRequestId});

  final String prepareRequestId;
  String? _resetToken;

  @override
  String get wireType => 'confirm_pairing_reset';

  /// Release the secret after terminal completion/cancellation. Dart strings
  /// cannot be securely zeroed; this drops the model's reference.
  void clearSecret() => _resetToken = null;

  @override
  Map<String, dynamic> toProtocolJson() {
    final token = _resetToken;
    if (token == null) throw const ProvisioningProtocolException('reset_token', 'confirmation secret has been cleared');
    return _envelope({'prepare_request_id': prepareRequestId, 'reset_token': token});
  }
}

final class BoardBondBefore {
  const BoardBondBefore({required this.paired, required this.bonded});
  final bool paired;
  final bool bonded;
  bool get hasOldBond => paired || bonded;

  @override
  String toString() => 'BoardBondBefore(paired: $paired, bonded: $bonded)';
}

sealed class PairingPreflightResponse {
  const PairingPreflightResponse({required this.requestId});
  final String requestId;
}

sealed class PairingPreflightResult extends PairingPreflightResponse {
  const PairingPreflightResult({required super.requestId, required this.boardBondBefore});
  final BoardBondBefore boardBondBefore;
  String get action;

  @override
  String toString() => 'PairingPreflightResult(requestId: $requestId, action: $action, boardBondBefore: $boardBondBefore)';
}

final class PairingPreflightNone extends PairingPreflightResult {
  PairingPreflightNone({required super.requestId, required super.boardBondBefore}) {
    if (boardBondBefore.hasOldBond) throw const ProvisioningProtocolException('board_bond_before', 'action none contradicts old bond');
  }

  @override
  String get action => 'none';
}

final class PairingPreflightResetRequired extends PairingPreflightResult {
  PairingPreflightResetRequired({
    required super.requestId,
    required super.boardBondBefore,
    required this.clientId,
    required String resetToken,
    required this.expiresIn,
    required DateTime receivedAt,
  }) : _resetToken = resetToken,
       expiresAt = receivedAt.add(expiresIn) {
    _requireUuid(requestId, 'request_id');
    _requireUuid(clientId, 'client_id');
    if (!boardBondBefore.hasOldBond) throw const ProvisioningProtocolException('board_bond_before', 'reset requires an old bond');
    if (resetToken.isEmpty) throw const ProvisioningProtocolException('reset_token', 'must be a non-empty opaque string');
    if (expiresIn <= Duration.zero || expiresIn > BleProtocolConstants.pairingPreflightMaximumTokenLifetime) {
      throw const ProvisioningProtocolException('expires_in_ms', 'must be positive and at most 15000');
    }
  }

  final String clientId;
  final Duration expiresIn;
  final DateTime expiresAt;
  String? _resetToken;

  @override
  String get action => 'reset_required';

  void clearSecret() => _resetToken = null;

  /// A new request ID, same installation client, and the unmodified opaque
  /// token. Keep the returned request for an idempotent transport replay.
  ConfirmPairingResetRequest confirm({required String requestId, required DateTime now}) {
    _requireUuid(requestId, 'request_id');
    if (requestId == this.requestId) throw const ProvisioningProtocolException('request_id', 'confirmation needs a new request ID');
    if (!now.isBefore(expiresAt)) {
      clearSecret();
      throw const ProvisioningException(code: ProvisioningErrorCode.pairingPreflightExpired, retryable: true);
    }
    final token = _resetToken;
    if (token == null) throw const ProvisioningProtocolException('reset_token', 'challenge has been cleared or consumed');
    final request = ConfirmPairingResetRequest._(token, requestId: requestId, clientId: clientId, prepareRequestId: this.requestId);
    clearSecret();
    return request;
  }
}

final class PairingResetScheduled extends PairingPreflightResponse {
  PairingResetScheduled({required super.requestId, required this.prepareRequestId, required this.boardBondBefore, required this.removeAfter}) {
    _requireUuid(prepareRequestId, 'prepare_request_id');
    if (!boardBondBefore.hasOldBond) throw const ProvisioningProtocolException('board_bond_before', 'scheduled reset requires an old bond');
    if (removeAfter < Duration.zero) throw const ProvisioningProtocolException('remove_after_ms', 'must be non-negative');
  }

  final String prepareRequestId;
  final BoardBondBefore boardBondBefore;
  final Duration removeAfter;
  String get action => 'remove_scheduled';
  bool get disconnectExpected => true;

  @override
  String toString() => 'PairingResetScheduled(requestId: $requestId, prepareRequestId: $prepareRequestId, disconnectExpected: true)';
}

final class PairingPreflightFailure extends PairingPreflightResponse {
  const PairingPreflightFailure({required super.requestId, required this.error});
  final ProvisioningException error;

  @override
  String toString() => 'PairingPreflightFailure(requestId: $requestId, error: $error)';
}

void _requireUuid(String value, String field) {
  if (!isUuidV4(value)) throw ProvisioningProtocolException(field, 'must be a UUID v4');
}
