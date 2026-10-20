import 'package:aves/bird_companion/features/connection/domain/ble_pairing_progress.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_attempt_failure.dart';
import 'dart:async';
import 'dart:convert';

import 'package:aves/bird_companion/features/connection/data/ble/birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_fragment_codec.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_message_codec.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/data/ble/pairing_preflight_platform.dart';
import 'package:aves/bird_companion/features/connection/data/ble/pairing_preflight_codec.dart';
import 'package:aves/bird_companion/features/connection/domain/pairing_preflight_models.dart';
import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_connection_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_scan_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract interface class BirdBoxBlePlatform {
  Stream<Map<String, dynamic>> get scanResults;
  Stream<Map<String, dynamic>> get notifications;
  Stream<Map<String, dynamic>> get diagnostics;
  Stream<BleDisconnectEvent> get disconnects;

  Future<BleScanEnvironment> readScanEnvironment();
  Future<bool> ensurePermissions();
  Future<void> startScan(
    Duration timeout, {
    required String scanSessionId,
  });
  Future<void> stopScan();
  Future<int> connect(
    String platformDeviceId, {
    required String traceId,
  });
  Future<void> disconnect();
  Future<int> requestMtu(int mtu);
  Future<Uint8List> readCharacteristic(String characteristicUuid);
  Future<void> setNotify(String characteristicUuid, {required bool enabled});
  Future<void> writeWithResponse(String characteristicUuid, Uint8List value);
  Future<void> beginSecurityWrite(
    String requestId, {
    required String commandType,
  });
  Future<bool> awaitSecurityReady(String requestId);
  Future<void> beginSecurityRetry(String requestId);
  Future<void> markSecurityWriteSent(String requestId);
  Future<void> completeSecurityWrite(
    String requestId, {
    required String responseType,
  });
  Future<void> failSecurityWrite(String requestId, {required String errorCode});
  Future<void> dispose();
}

abstract interface class BirdBoxPairingPlatform {
  Future<BlePairingReady> preparePairing(String requestId, String commandType);
  Future<BlePairingReady> recoverPairing(String requestId);
  Future<void> disconnectOwned(String? requestId, BlePairingReady? ready, int? connectionGeneration);
  Future<void> openLocationSettings();
}

/// Native connect owns stale-client park/disconnect/close and completes only
/// after its replacement is ready. A Dart pre-disconnect would bypass that gate.
abstract interface class BirdBoxNativeConnectReset {}

final class BlePairingReady {
  const BlePairingReady({required this.requestId, required this.attemptId, required this.connectionGeneration, required this.gattGeneration, required this.mtu});
  final String requestId;
  final String attemptId;
  final int connectionGeneration;
  final int gattGeneration;
  final int mtu;
  factory BlePairingReady.fromPlatform(Map<Object?, Object?> value) {
    final request = value['requestId'], attempt = value['attemptId'];
    final connection = value['connectionGeneration'], gatt = value['gattGeneration'], mtu = value['mtu'];
    if (request is! String || request.isEmpty || attempt is! String || attempt.isEmpty || connection is! int || gatt is! int || mtu is! int || mtu < 23 || mtu > 517 || value['notificationsReady'] != true) {
      throw const ProvisioningProtocolException('preparePairing', 'invalid secure GATT readiness');
    }
    return BlePairingReady(requestId: request, attemptId: attempt, connectionGeneration: connection, gattGeneration: gatt, mtu: mtu);
  }
  Map<String, Object> get owner => {'requestId': requestId, 'attemptId': attemptId, 'connectionGeneration': connectionGeneration};
}

final class BleDisconnectEvent {
  const BleDisconnectEvent({
    required this.reason,
    required this.gattStatus,
    required this.unexpected,
    this.connectionGeneration,
  });

  final String reason;
  final int gattStatus;
  final bool unexpected;
  final int? connectionGeneration;

  @override
  String toString() => 'BleDisconnectEvent(reason: $reason, gattStatus: $gattStatus, unexpected: $unexpected, connectionGeneration: $connectionGeneration)';
}

final class MethodChannelBirdBoxBlePlatform implements BirdBoxBlePlatform, BirdBoxPairingPlatform, BirdBoxPairingPreflightPlatform, BirdBoxNativeConnectReset {
  MethodChannelBirdBoxBlePlatform()
    : _methodChannel = const MethodChannel(_methodChannelName),
      _scanResults = const EventChannel(_scanChannelName).receiveBroadcastStream().map(_eventMap).asBroadcastStream(),
      _notifications = const EventChannel(_notificationChannelName).receiveBroadcastStream().map(_eventMap).asBroadcastStream(),
      _diagnostics = const EventChannel(_diagnosticChannelName).receiveBroadcastStream().map(_eventMap).asBroadcastStream(),
      _disconnects = const EventChannel(_disconnectChannelName).receiveBroadcastStream().map(_disconnectEvent).asBroadcastStream();

  static const _methodChannelName = 'bird_companion/birdbox_ble/methods';
  static const _scanChannelName = 'bird_companion/birdbox_ble/scan';
  static const _notificationChannelName = 'bird_companion/birdbox_ble/notifications';
  static const _diagnosticChannelName = 'bird_companion/birdbox_ble/diagnostics';
  static const _disconnectChannelName = 'bird_companion/birdbox_ble/disconnects';

  final MethodChannel _methodChannel;
  final Map<String, BlePairingReady> _securityOwners = {};
  final Stream<Map<String, dynamic>> _scanResults;
  final Stream<Map<String, dynamic>> _notifications;
  final Stream<Map<String, dynamic>> _diagnostics;
  final Stream<BleDisconnectEvent> _disconnects;

  @override
  Future<NativeBondSnapshot> getNativeBondState(int connectionGeneration, {required String platformDeviceId}) async {
    final before = await getGattOwnershipState(connectionGeneration);
    _requirePublicOwner(before, connectionGeneration);
    final value = await _publicInvoke('getNativeBondState', {'deviceId': platformDeviceId});
    if (value is! String) throw const ProvisioningProtocolException('bond_state', 'invalid native bond state');
    final state = NativeBondState.fromPlatform(value);
    final after = await getGattOwnershipState(connectionGeneration);
    _requirePublicOwner(after, connectionGeneration, before.gattInstanceId);
    return NativeBondSnapshot(state: state, connectionGeneration: after.connectionGeneration, gattInstanceId: after.gattInstanceId);
  }

  @override
  Future<PublicGattSnapshot> getGattOwnershipState(int connectionGeneration) async {
    final value = await _publicInvoke('getGattOwnershipState');
    if (value is! Map) throw const ProvisioningProtocolException('gatt_ownership', 'invalid native result');
    return PublicGattSnapshot.fromPlatform(Map<Object?, Object?>.from(value));
  }

  static void _requirePublicOwner(PublicGattSnapshot state, int generation, [int? instance]) {
    if (!state.connected || !state.linkReady || state.connectionGeneration != generation || instance != null && state.gattInstanceId != instance) {
      throw const ProvisioningException(code: ProvisioningErrorCode.bleGattNotReady, retryable: true);
    }
    if (state.preparing || state.inflightRequest != null) throw const ProvisioningException(code: ProvisioningErrorCode.bleOperationBusy, retryable: true);
  }

  @override
  Future<void> writePairingPreflight({required String requestId, required int connectionGeneration, required int gattInstanceId, required Uint8List fragmentBytes}) async {
    _requirePublicOwner(await getGattOwnershipState(connectionGeneration), connectionGeneration, gattInstanceId);
    final value = await _publicInvoke('writePairingPreflight', {'value': fragmentBytes});
    if (value != null) throw const ProvisioningProtocolException('writePairingPreflight', 'invalid ATT receipt');
  }

  @override
  Future<void> prepareControlledReconnect({required String requestId, required int connectionGeneration, required int gattInstanceId, required String reason}) async {
    final before = await getGattOwnershipState(connectionGeneration);
    if (before.connectionGeneration != connectionGeneration || before.connected && before.gattInstanceId != gattInstanceId || before.preparing || before.inflightRequest != null) {
      throw const ProvisioningException(code: ProvisioningErrorCode.bleGattRecoveryFailed, retryable: false);
    }
    // A peer reset may have already closed the old GATT before this call.
    if (!before.connected) return;
    final receipt = await _publicInvoke('prepareControlledReconnect');
    final after = await getGattOwnershipState(connectionGeneration);
    // e160043ef closes synchronously and emits no disconnect event here.
    // null alone is insufficient evidence; verify local native retirement.
    if (receipt != null || after.connected || after.linkReady || after.preparing || after.inflightRequest != null || after.connectionGeneration != connectionGeneration || after.gattInstanceId != 0) {
      throw const ProvisioningException(code: ProvisioningErrorCode.bleGattRecoveryFailed, retryable: false);
    }
  }

  Future<Object?> _publicInvoke(String method, [Map<String, dynamic>? args]) async {
    try {
      return await _methodChannel.invokeMethod<Object?>(method, args);
    } on MissingPluginException {
      throw const ProvisioningException(code: ProvisioningErrorCode.blePairingPreflightUnavailable, retryable: false);
    } on PlatformException catch (error) {
      // Never retain peer/native free text or details from a token-bearing call.
      final code = switch (error.code.toLowerCase()) {
        'pairing_preflight_busy' || 'gatt_busy' => ProvisioningErrorCode.pairingPreflightBusy,
        'pairing_preflight_expired' => ProvisioningErrorCode.pairingPreflightExpired,
        'pairing_preflight_invalid_peer' => ProvisioningErrorCode.pairingPreflightInvalidPeer,
        'pairing_preflight_confirmation_rejected' => ProvisioningErrorCode.pairingPreflightConfirmationRejected,
        'request_id_conflict' => ProvisioningErrorCode.requestIdConflict,
        'pairing_preflight_command_unsupported' || 'pairing_preflight_unsupported' => ProvisioningErrorCode.pairingPreflightCommandUnsupported,
        'bluetooth_permission_denied' => ProvisioningErrorCode.bluetoothPermissionDenied,
        'bluetooth_unavailable' => ProvisioningErrorCode.bluetoothUnavailable,
        'bond_state_unknown' => ProvisioningErrorCode.bleBondStateUnknown,
        'ble_gatt_not_ready' => ProvisioningErrorCode.bleGattNotReady,
        'ble_gatt_operation_failed' || 'gatt_operation_failed' => ProvisioningErrorCode.bleGattOperationFailed,
        'invalid_request' || 'invalid_state' => ProvisioningErrorCode.invalidRequest,
        _ => ProvisioningErrorCode.blePairingPreflightUnavailable,
      };
      throw ProvisioningException(
        code: code,
        retryable: code.pairingPreflightDisposition == PairingPreflightErrorDisposition.boundedRetryAfterRelease,
        diagnosticMessage: error.code == 'pairing_preflight_unsupported' ? 'native_preflight_characteristic_missing' : null,
      );
    }
  }

  @override
  Stream<Map<String, dynamic>> get scanResults => _scanResults;
  @override
  Stream<Map<String, dynamic>> get notifications => _notifications;
  @override
  Stream<Map<String, dynamic>> get diagnostics => _diagnostics;
  @override
  Stream<BleDisconnectEvent> get disconnects => _disconnects;

  @override
  Future<bool> ensurePermissions() async => (await _invoke<bool>('ensurePermissions')) ?? false;

  @override
  Future<BleScanEnvironment> readScanEnvironment() async {
    final value = await _invoke<Map<Object?, Object?>>('getScanEnvironment');
    return BleScanEnvironment.fromPlatform(
      Map<String, dynamic>.from(value ?? const {}),
    );
  }

  @override
  Future<void> startScan(
    Duration timeout, {
    required String scanSessionId,
  }) => _invoke<void>('startScan', {
    'timeoutMs': timeout.inMilliseconds,
    'scanSessionId': scanSessionId,
  });

  @override
  Future<void> stopScan() => _invoke<void>('stopScan');

  @override
  Future<int> connect(
    String platformDeviceId, {
    required String traceId,
  }) async =>
      (await _invoke<int>('connect', {
        'deviceId': platformDeviceId,
        'traceId': traceId,
      })) ??
      0;

  @override
  Future<void> disconnect() => _invoke<void>('disconnect');

  @override
  Future<int> requestMtu(int mtu) async => (await _invoke<int>('requestMtu', {'mtu': mtu})) ?? 23;

  @override
  Future<Uint8List> readCharacteristic(String characteristicUuid) async {
    final value = await _invoke<Uint8List>('readCharacteristic', {'characteristicUuid': characteristicUuid});
    if (value == null) throw const ProvisioningProtocolException('characteristic', 'read returned no bytes');
    return value;
  }

  @override
  Future<void> setNotify(String characteristicUuid, {required bool enabled}) => _invoke<void>('setNotify', {'characteristicUuid': characteristicUuid, 'enabled': enabled});

  @override
  Future<void> writeWithResponse(String characteristicUuid, Uint8List value) => _invoke<void>('writeWithResponse', {'characteristicUuid': characteristicUuid, 'value': value});

  @override
  Future<BlePairingReady> preparePairing(String requestId, String commandType) => _ready('preparePairing', {'requestId': requestId, 'commandType': commandType});
  @override
  Future<BlePairingReady> recoverPairing(String requestId) => _ready('recoverPairing', {'requestId': requestId});
  Future<BlePairingReady> _ready(String method, Map<String, dynamic> args) async {
    final requestId = args['requestId'] as String;
    final value = await _invoke<Map<Object?, Object?>>(method, {...?_securityOwners[requestId]?.owner, ...args});
    final ready = BlePairingReady.fromPlatform(value ?? const {});
    if (ready.requestId != requestId) throw const ProvisioningProtocolException('requestId', 'readiness belongs to another request');
    _securityOwners[requestId] = ready;
    return ready;
  }

  @override
  Future<void> disconnectOwned(String? requestId, BlePairingReady? ready, int? connectionGeneration) => _invoke<void>('disconnect', {
    'requestId': ?requestId,
    if (ready != null) 'attemptId': ready.attemptId,
    'connectionGeneration': ?connectionGeneration,
  });
  @override
  Future<void> openLocationSettings() => _invoke<void>('openLocationSettings');

  @override
  Future<void> beginSecurityWrite(
    String requestId, {
    required String commandType,
  }) => _invoke<void>('beginSecurityWrite', {
    'requestId': requestId,
    'commandType': commandType,
  });

  @override
  Future<bool> awaitSecurityReady(String requestId) async => (await _invoke<bool>('awaitSecurityReady', {'requestId': requestId})) ?? false;

  @override
  Future<void> beginSecurityRetry(String requestId) => _invoke<void>('beginSecurityRetry', _ownerArgs(requestId));

  @override
  Future<void> markSecurityWriteSent(String requestId) => _invoke<void>('markSecurityWriteSent', _ownerArgs(requestId));

  @override
  Future<void> completeSecurityWrite(
    String requestId, {
    required String responseType,
  }) => _finishSecurityRequest('completeSecurityWrite', requestId, {
    'responseType': responseType,
  });

  @override
  Future<void> failSecurityWrite(
    String requestId, {
    required String errorCode,
  }) => _finishSecurityRequest('failSecurityWrite', requestId, {
    'errorCode': errorCode,
  });

  Map<String, dynamic> _ownerArgs(String requestId) => {'requestId': requestId, ...?_securityOwners[requestId]?.owner};
  Future<void> _finishSecurityRequest(String method, String requestId, Map<String, dynamic> args) async {
    try {
      await _invoke<void>(method, {..._ownerArgs(requestId), ...args});
    } finally {
      _securityOwners.remove(requestId);
    }
  }

  @override
  Future<void> dispose() => _invoke<void>('dispose');

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? arguments]) async {
    try {
      return await _methodChannel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw _platformError(error);
    }
  }

  static Map<String, dynamic> _eventMap(Object? event) {
    if (event is! Map) throw const ProvisioningProtocolException('platform_event', 'must be a map');
    return Map<String, dynamic>.from(event);
  }

  static BleDisconnectEvent _disconnectEvent(Object? raw) {
    final event = _eventMap(raw);
    final reason = event['reason'];
    final gattStatus = event['gattStatus'];
    final unexpected = event['unexpected'];
    final connectionGeneration = event['connectionGeneration'];
    if (reason is! String || reason.isEmpty || gattStatus is! int || unexpected is! bool) {
      throw const ProvisioningProtocolException('platform_disconnect_event', 'contains invalid fields');
    }
    return BleDisconnectEvent(
      reason: reason,
      gattStatus: gattStatus,
      unexpected: unexpected,
      connectionGeneration: connectionGeneration is int ? connectionGeneration : null,
    );
  }

  static ProvisioningException _platformError(PlatformException error) {
    final details = error.details is Map ? Map<String, dynamic>.from(error.details as Map) : const <String, dynamic>{};
    final sanitizedMessage = _sanitizePlatformMessage(
      details['sanitizedMessage'] as String? ?? error.message,
    );
    final diagnosticFields = <String>[
      'platformExceptionCode=${error.code}',
      if (details['platformMethod'] != null) 'platformMethod=${details['platformMethod']}',
      if (details['nativeState'] != null) 'nativeState=${details['nativeState']}',
      if (details['securityPhase'] != null) 'securityPhase=${details['securityPhase']}',
      if (details['pendingOperation'] != null) 'pendingOperation=${details['pendingOperation']}',
      if (details['gattPresent'] != null) 'gattPresent=${details['gattPresent']}',
      if (details['linkReady'] != null) 'linkReady=${details['linkReady']}',
      if (details['scanning'] != null) 'scanning=${details['scanning']}',
      if (details['connectionGeneration'] != null) 'connectionGeneration=${details['connectionGeneration']}',
      if (details['gattInstanceId'] != null) 'gattInstanceId=${details['gattInstanceId']}',
      if (details['gattGeneration'] != null) 'gattGeneration=${details['gattGeneration']}',
      if (details['gattStatus'] != null) 'gattStatus=${details['gattStatus']}',
      if (details['bondState'] != null) 'bondState=${details['bondState']}',
      if (details['actualBondState'] != null) 'actualBondState=${details['actualBondState']}',
      if (details['characteristicUuid'] != null) 'characteristicUuid=${details['characteristicUuid']}',
      if (details['attemptId'] != null) 'attemptId=${details['attemptId']}',
      if (details['writeApiAccepted'] != null) 'writeApiAccepted=${details['writeApiAccepted']}',
      if (details['writeCallbackReceived'] != null) 'writeCallbackReceived=${details['writeCallbackReceived']}',
      if (details['securityWriteElapsedMs'] != null) 'securityWriteElapsedMs=${details['securityWriteElapsedMs']}',
      if (details['fallbackTrigger'] != null) 'fallbackTrigger=${details['fallbackTrigger']}',
      if (details['bondStateAtTrigger'] != null) 'bondStateAtTrigger=${details['bondStateAtTrigger']}',
      if (details['createBondInvoked'] != null) 'createBondInvoked=${details['createBondInvoked']}',
      if (details['createBondReturned'] != null) 'createBondReturned=${details['createBondReturned']}',
      for (final key in const [
        'systemBondAttempted',
        'bondInitiationSource',
        'createBondCallCount',
        'bondElapsedMs',
        'securityWriteAttemptCount',
        'securityWriteResult',
        'thread',
        'callSource',
        'teardownReason',
        'preparationStep',
        'failurePhase',
      ])
        if (details[key] != null) '$key=${details[key]}',
      if (details['operationName'] != null) 'operation=${details['operationName']}',
      if (details['deviceAddressHash'] != null) 'deviceAddressHash=${details['deviceAddressHash']}',
      if (details['traceId'] != null) 'traceId=${details['traceId']}',
      if (details['androidScanErrorCode'] != null) 'Android scan error ${details['androidScanErrorCode']}',
      if (details['scanSessionId'] != null) 'scanSession=${details['scanSessionId']}',
      if (sanitizedMessage != null) 'message=$sanitizedMessage',
    ];
    return ProvisioningException(
      code: switch (error.code) {
        'bluetooth_permission_denied' => ProvisioningErrorCode.bluetoothPermissionDenied,
        'location_service_disabled' => ProvisioningErrorCode.locationServicesDisabled,
        'bond_start_failed' => ProvisioningErrorCode.bleBondStartFailed,
        'bond_lost' || 'bond_lost_during_bonding' => ProvisioningErrorCode.bleBondLost,
        'bond_state_unknown' => ProvisioningErrorCode.bleBondStateUnknown,
        'location_settings_unavailable' => ProvisioningErrorCode.locationSettingsUnavailable,
        'gatt_busy' => ProvisioningErrorCode.bleOperationBusy,
        'ble_session_ended' => ProvisioningErrorCode.bleSessionEnded,
        'ble_host_unavailable' => ProvisioningErrorCode.bleHostUnavailable,
        'ble_gatt_not_ready' => ProvisioningErrorCode.bleGattNotReady,
        'ble_le_pairing_not_started' => ProvisioningErrorCode.bleLePairingNotStarted,
        'bond_timeout' || 'ble_pairing_timeout' || 'ble_bond_timeout' => ProvisioningErrorCode.blePairingTimeout,
        'bond_rejected' || 'ble_pairing_rejected' || 'ble_bond_rejected' => ProvisioningErrorCode.blePairingRejected,
        'ble_gatt_operation_failed' || 'gatt_operation_failed' => ProvisioningErrorCode.bleGattOperationFailed,
        'ble_gatt_recovery_failed' => ProvisioningErrorCode.bleGattRecoveryFailed,
        'ble_security_recovery_failed' || 'ble_bond_failed' => ProvisioningErrorCode.bleSecurityRecoveryFailed,
        'ble_encrypted_retry_failed' => ProvisioningErrorCode.bleEncryptedRetryFailed,
        'pairing_open_timeout' => ProvisioningErrorCode.pairingOpenTimeout,
        'ble_link_not_encrypted' => ProvisioningErrorCode.authorizationRequired,
        'invalid_request' || 'invalid_state' => ProvisioningErrorCode.invalidRequest,
        'bluetooth_unavailable' => ProvisioningErrorCode.bluetoothUnavailable,
        _ => ProvisioningErrorCode.bleGattOperationFailed,
      },
      retryable: const {
        'bluetooth_unavailable',
        'gatt_busy',
        'ble_session_ended',
        'ble_host_unavailable',
        'bond_start_failed',
        'bond_timeout',
        'bond_rejected',
        'bond_lost',
        'bond_lost_during_bonding',
        'bond_state_unknown',
        'gatt_operation_failed',
        'ble_gatt_operation_failed',
        'ble_link_not_encrypted',
        'ble_gatt_not_ready',
        'ble_le_pairing_not_started',
        'ble_pairing_rejected',
        'ble_pairing_timeout',
        'ble_bond_timeout',
        'ble_bond_rejected',
        'ble_gatt_recovery_failed',
        'ble_security_recovery_failed',
        'ble_bond_failed',
        'ble_encrypted_retry_failed',
        'pairing_open_timeout',
      }.contains(error.code),
      diagnosticMessage: 'Android BLE platform error: ${diagnosticFields.join(', ')}',
    );
  }

  static String? _sanitizePlatformMessage(String? message) {
    if (message == null) return null;
    var safe = message.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    safe = safe.replaceAll(
      RegExp(r'(?:[0-9a-f]{2}:){5}[0-9a-f]{2}', caseSensitive: false),
      '[REDACTED_MAC]',
    );
    safe = safe.replaceAllMapped(
      RegExp(
        r'(password|passphrase|token|secret|authorization|pairing[_ -]?code)\s*[:=]\s*[^,;\s]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}=[REDACTED]',
    );
    safe = safe.replaceAll(
      RegExp(r'dpp:\S+', caseSensitive: false),
      '[REDACTED_DPP_URI]',
    );
    if (safe.isEmpty) return null;
    return safe.length <= 240 ? safe : safe.substring(0, 240);
  }
}

final class PlatformBirdBoxBleDataSource implements BirdBoxBleDataSource, BleScanDiagnosticSource, BleProvisioningControl, BirdBoxPairingPreparation, BleFailureDiagnostics {
  PlatformBirdBoxBleDataSource({
    BirdBoxBlePlatform? platform,
    this._diagnosticSink,
    this._connectionDiagnosticSink,
    DateTime Function()? clock,
    this._scanSessionIdFactory,
    this._maximumWriteFragmentBytes = 512,
    this.preparationTimeout = const Duration(seconds: 45),
    this.preflightResponseTimeout = const Duration(seconds: 3),
    this.freshAdvertisementTimeout = const Duration(seconds: 12),
  }) : _platform = platform ?? MethodChannelBirdBoxBlePlatform(),
       _clock = clock ?? DateTime.now,
       _fragmentCodec = const BleFragmentCodec(),
       _messageCodec = const BleMessageCodec() {
    _notificationSubscription = _platform.notifications.listen(_handleNotification, onError: _events.addError);
    _disconnectSubscription = _platform.disconnects.listen(_handleDisconnect, onError: _disconnects.addError);
    _diagnosticSubscription = _platform.diagnostics.listen(
      _handleNativeDiagnostic,
      onError: (Object error) => debugPrint(
        'BLE native diagnostic stream failed: ${error.runtimeType}',
      ),
    );
  }

  final BirdBoxBlePlatform _platform;
  final Duration preparationTimeout, preflightResponseTimeout, freshAdvertisementTimeout;
  _PublicPreparation? _publicPreparation;
  _PublicRequest? _publicRequest;
  _ExpectedReset? _expectedReset;
  int? _controlledReleaseGeneration;
  int? _preparedConnectionGeneration;
  int? _preparedGattGeneration;
  String? _preparedDeviceId;
  bool _preparedAllowsBond = false;
  final _preflightCodec = const PairingPreflightCodec();
  final RequestIdFactory _preflightIds = SecureRequestIdFactory();
  final Set<String> _publicRequestIds = {};
  final Set<int> _retiredPublicGenerations = {};
  final BleScanDiagnosticSink? _diagnosticSink;
  final BleConnectionDiagnosticSink? _connectionDiagnosticSink;
  final DateTime Function() _clock;
  final String Function()? _scanSessionIdFactory;
  final BleFragmentCodec _fragmentCodec;
  final BleMessageCodec _messageCodec;
  // Integration tests can use smaller legal ATT fragments without faking MTU,
  // native pairing results, or the platform transport. Production uses 512.
  final int _maximumWriteFragmentBytes;
  int _writeFragmentBytes() =>
      (_negotiatedMtu - 3).clamp(BleProtocolConstants.fragmentHeaderLength + 1, 512).clamp(BleProtocolConstants.fragmentHeaderLength + 1, _maximumWriteFragmentBytes.clamp(BleProtocolConstants.fragmentHeaderLength + 1, 512));
  final StreamController<ProvisioningEvent> _events = StreamController<ProvisioningEvent>.broadcast(sync: true);
  final StreamController<void> _disconnects = StreamController<void>.broadcast(sync: true);
  final StreamController<BleScanDiagnosticSession> _scanDiagnostics = StreamController<BleScanDiagnosticSession>.broadcast(sync: true);
  final Map<String, BleFragmentReassembler> _notificationReassemblers = {};
  final Map<String, Completer<ProvisioningEvent>> _pendingCommands = {};

  late final StreamSubscription<Map<String, dynamic>> _notificationSubscription;
  late final StreamSubscription<BleDisconnectEvent> _disconnectSubscription;
  late final StreamSubscription<Map<String, dynamic>> _diagnosticSubscription;
  StreamSubscription<Map<String, dynamic>>? _scanSubscription;
  StreamController<BirdBoxAdvertisement>? _scanController;
  StreamController<BirdBoxAdvertisement>? _scanPreflightController;
  bool _discoveryPaused = false;
  _BleScanSessionBuilder? _activeScanDiagnostic;
  final Map<String, BirdBoxAdvertisement> _scanCandidates = {};
  Timer? _scanTimer;
  bool _connected = false;
  bool _connectInProgress = false;
  bool _platformConnectPending = false;
  bool _requiredNotificationsSubscribed = false;
  bool _publicStatusSubscribed = false;
  bool _disposed = false;
  Future<void>? _disconnectFuture;
  BleDisconnectEvent? _connectInterruptedBy;
  final List<BleDisconnectEvent> _deferredConnectDisconnects = [];
  int _negotiatedMtu = 23;
  int _nextMessageId = 0;
  int _scanSessionSequence = 0;
  int? _activeConnectionGeneration;
  String? _activePlatformDeviceId;
  int _transportEpoch = 0;
  String? _lastTraceId;
  String? _activeTraceId;

  String? _flowId;
  String _nextScanTrigger = 'user_scan';
  final Map<String, String> _traceFlowIds = {};
  void _associateTrace(String traceId) {
    _traceFlowIds[traceId] = _flowId ??= traceId;
    if (_traceFlowIds.length > 64) _traceFlowIds.remove(_traceFlowIds.keys.first);
  }

  Object? _sessionOwner;
  String? _activeSecurityRequest;
  BleAttemptFailure? _activeCommandFailure;
  bool _nativePreparationStarted = false;
  BlePairingReady? _pairingReady;
  int? _activeGattGeneration;
  final _pairingProgress = StreamController<BlePairingProgress>.broadcast(sync: true);
  @override
  Object claimSession() {
    _cancelPublicPreparation();
    _flowId = 'flow-${_clock().microsecondsSinceEpoch}-${_scanSessionSequence++}';
    _nextScanTrigger = 'user_scan';
    return _sessionOwner = Object();
  }

  @override
  bool ownsSession(Object owner) => identical(owner, _sessionOwner) && !_disposed;
  @override
  Future<void> endSession(Object owner) async {
    if (!ownsSession(owner)) return;
    _cancelPublicPreparation();
    await stopScan();
    if (!ownsSession(owner)) return;
    await disconnect();
  }

  @override
  Future<void> pauseDiscovery(Object owner) async {
    if (!ownsSession(owner)) return;
    _discoveryPaused = true;
    // Runtime permission dialogs pause the Activity before returning their result.
    // Keep this preflight alive so denial reaches the page as a permission error.
    if (!identical(_scanController, _scanPreflightController)) await stopScan();
  }

  @override
  Future<void> resumeDiscovery(Object owner) async {
    if (!ownsSession(owner)) return;
    _discoveryPaused = false;
    final generation = _activeConnectionGeneration, instance = _activeGattGeneration, epoch = _transportEpoch;
    // During bond/recovery the owned native attempt supplies readiness and may
    // change GATT. Do not race it or create a second attempt on Activity resume.
    if (!_connected || generation == null || _activeSecurityRequest != null || _publicPreparation != null || _disconnectFuture != null || _platform is! BirdBoxPairingPreflightPlatform) return;
    bool stillCurrent() =>
        ownsSession(owner) && epoch == _transportEpoch && _activeConnectionGeneration == generation && _activeGattGeneration == instance && _activeSecurityRequest == null && _publicPreparation == null && _disconnectFuture == null;
    PublicGattSnapshot state;
    try {
      state = await _publicPlatform.getGattOwnershipState(generation);
    } catch (_) {
      if (stillCurrent()) {
        _handleDisconnect(BleDisconnectEvent(reason: 'native_snapshot_unavailable', gattStatus: 0, unexpected: true, connectionGeneration: generation));
      }
      rethrow;
    }
    if (!stillCurrent()) return;
    final sameOwner = state.connected && state.linkReady && state.connectionGeneration == generation && (instance == null || state.gattInstanceId == instance) && !state.preparing && state.inflightRequest == null;
    await _recordConnectionDiagnostic(eventType: 'gatt_foreground_sync', operationName: 'getGattOwnershipState', resultCode: sameOwner ? 'reuse_owned_gatt' : 'ownership_lost');
    if (!stillCurrent()) return;
    if (sameOwner) {
      _activeGattGeneration = state.gattInstanceId;
    } else {
      _handleDisconnect(BleDisconnectEvent(reason: 'native_ownership_lost', gattStatus: 0, unexpected: true, connectionGeneration: generation));
    }
  }

  bool _currentScan(StreamController<BirdBoxAdvertisement> controller) => !_disposed && !controller.isClosed && identical(controller, _scanController);

  @override
  Future<void> openLocationSettings(Object owner) async {
    if (!ownsSession(owner)) return;
    await _recordConnectionDiagnostic(eventType: 'location_settings_open_requested', operationName: 'open_location_settings');
    if (!ownsSession(owner)) return;
    final platform = _platform;
    if (platform is BirdBoxPairingPlatform) {
      try {
        await (platform as BirdBoxPairingPlatform).openLocationSettings();
        if (ownsSession(owner)) await _recordConnectionDiagnostic(eventType: 'location_settings_opened', operationName: 'open_location_settings', resultCode: 'opened');
      } catch (error) {
        await _recordConnectionDiagnostic(eventType: 'location_settings_open_failed', operationName: 'open_location_settings', errorCode: _resultCode(error));
        rethrow;
      }
    } else {
      throw const ProvisioningException(code: ProvisioningErrorCode.locationSettingsUnavailable, retryable: false);
    }
  }

  @override
  Future<void> locationSettingsReturned(Object owner, {required bool enabled}) async {
    if (!ownsSession(owner)) return;
    if (enabled) _nextScanTrigger = 'location_settings_return';
    await _recordConnectionDiagnostic(eventType: 'location_settings_returned', operationName: 'location_settings_return', resultCode: enabled ? 'enabled' : 'disabled');
  }

  @override
  Future<BleScanEnvironment> readScanEnvironment() => _platform.readScanEnvironment();
  @override
  Stream<BlePairingProgress> get pairingProgress => _pairingProgress.stream;
  void _adoptReady(BlePairingReady ready, String requestId) {
    if (_activeSecurityRequest != requestId || ready.requestId != requestId || !_connected) {
      throw const ProvisioningException(code: ProvisioningErrorCode.bleGattOperationFailed, retryable: true, diagnosticMessage: 'Stale pairing preparation result');
    }
    _pairingReady = ready;
    _activeConnectionGeneration = ready.connectionGeneration;
    _activeGattGeneration = ready.gattGeneration;
    _negotiatedMtu = ready.mtu;
    _requiredNotificationsSubscribed = true;
    for (final reassembler in _notificationReassemblers.values) {
      reassembler.reset();
    }
    _notificationReassemblers.clear();
  }

  @override
  Stream<BirdBoxAdvertisement> scan({Duration? timeout}) {
    if (_disposed) return Stream.error(const ProvisioningException(code: ProvisioningErrorCode.bleSessionEnded, retryable: true));
    if (_scanController != null) return Stream.error(const ProvisioningException(code: ProvisioningErrorCode.bleOperationBusy, retryable: true));
    _discoveryPaused = false;
    var scanTimeout = timeout ?? const Duration(seconds: 10);
    final usesDefaultTimeout = timeout == null;
    final scanId = _newScanSessionId();
    _associateTrace(scanId);
    final scanDiagnostic = _BleScanSessionBuilder(
      scanSessionId: scanId,
      flowId: _flowId,
      scanTrigger: _nextScanTrigger,
      previousScanSessionId: _lastTraceId,
      startedAt: _clock(),
    );
    _lastTraceId = scanDiagnostic.scanSessionId;
    _nextScanTrigger = 'user_scan';
    _activeTraceId = null;
    late final StreamController<BirdBoxAdvertisement> controller;
    controller = StreamController<BirdBoxAdvertisement>(
      onListen: () async {
        _scanCandidates.clear();
        _activeScanDiagnostic = scanDiagnostic;
        _scanPreflightController = controller;
        try {
          scanDiagnostic.environmentBefore = await _readScanEnvironment();
          if (!_currentScan(controller)) return;
          final permitted = await _platform.ensurePermissions();
          if (!_currentScan(controller)) return;
          if (!permitted) {
            scanDiagnostic.environmentAfter = await _readScanEnvironment();
            if (!_currentScan(controller)) return;
            throw _permissionDenied();
          }
          scanDiagnostic.environmentAfter = await _readScanEnvironment();
          if (!_currentScan(controller)) return;
          if (_discoveryPaused) {
            await _finishScan(controller, reason: BleScanEndReason.stopped);
            return;
          }
          if (identical(_scanPreflightController, controller)) _scanPreflightController = null;
          if (usesDefaultTimeout && scanDiagnostic.environmentAfter.scanStrategyFallbackEnabled) {
            // Three four-second strategy windows plus a complete final observation margin.
            scanTimeout = const Duration(seconds: 15);
          }
          _scanSubscription = _platform.scanResults.listen(
            (event) => _handleScanEvent(controller, event),
            onError: (Object error, StackTrace stackTrace) {
              final mapped = error is PlatformException ? MethodChannelBirdBoxBlePlatform._platformError(error) : error;
              controller.addError(mapped, stackTrace);
              unawaited(
                _finishScan(
                  controller,
                  reason: BleScanEndReason.platformError,
                ),
              );
            },
          );
          await _platform.startScan(
            scanTimeout,
            scanSessionId: scanDiagnostic.scanSessionId,
          );
          if (!_currentScan(controller)) return;
          scanDiagnostic.nativeStartedAt = _clock();
          _scanTimer = Timer(
            scanTimeout,
            () => unawaited(
              _finishScan(controller, reason: BleScanEndReason.timeout),
            ),
          );
        } catch (error, stackTrace) {
          if (!_currentScan(controller)) return;
          controller.addError(error, stackTrace);
          await _finishScan(
            controller,
            reason: _endReasonFor(error, scanDiagnostic),
          );
        } finally {
          if (identical(_scanPreflightController, controller)) _scanPreflightController = null;
        }
      },
      onCancel: () => _finishScan(
        controller,
        reason: BleScanEndReason.cancelled,
      ),
    );
    _scanController = controller;
    return controller.stream;
  }

  @override
  Future<void> stopScan() async {
    final controller = _scanController;
    if (controller != null) {
      await _finishScan(controller, reason: BleScanEndReason.stopped);
    }
  }

  Future<void> _finishScan(
    StreamController<BirdBoxAdvertisement> controller, {
    required BleScanEndReason reason,
  }) async {
    if (!identical(controller, _scanController)) return;
    _scanTimer?.cancel();
    _scanTimer = null;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    try {
      await _platform.stopScan();
    } catch (_) {
      // Scan shutdown is best effort; discovery errors have already reached the stream.
    }
    _scanController = null;
    _scanCandidates.clear();
    await _completeScanDiagnostic(reason);
    if (!controller.isClosed) await controller.close();
  }

  void _handleScanEvent(
    StreamController<BirdBoxAdvertisement> controller,
    Map<String, dynamic> event,
  ) {
    final diagnostic = _activeScanDiagnostic;
    final eventSessionId = event['scanSessionId'];
    if (eventSessionId is String && diagnostic != null && eventSessionId != diagnostic.scanSessionId) {
      return;
    }
    if (event['eventType'] == 'scanFailure') {
      final errorCode = event['androidScanErrorCode'];
      if (errorCode is int) diagnostic?.androidScanErrorCode = errorCode;
      return;
    }
    if (event['eventType'] == 'scanStrategy') {
      diagnostic?.observeStrategy(at: _clock(), event: event);
      return;
    }

    final acceptedField = event['accepted'];
    final accepted = acceptedField is bool ? acceptedField : true;
    final reason = event['decisionReason'] is String ? event['decisionReason'] as String : 'legacy_candidate';
    diagnostic?.observe(
      at: _clock(),
      accepted: accepted,
      reason: reason,
      event: event,
    );
    if (!accepted) return;

    try {
      final advertisement = advertisementFromPlatform(event);
      if (advertisement.hasBirdBoxService || advertisement.hasValidLocalName) {
        diagnostic?.firstCandidateAt ??= _clock();
        final deviceId = advertisement.platformDeviceId!;
        final merged = _mergeAdvertisement(
          _scanCandidates[deviceId],
          advertisement,
        );
        _scanCandidates[deviceId] = merged;
        controller.add(merged);
      }
    } catch (error, stackTrace) {
      diagnostic?.addReason('dart_parse_error');
      controller.addError(error, stackTrace);
      unawaited(
        _finishScan(
          controller,
          reason: BleScanEndReason.platformError,
        ),
      );
    }
  }

  static BirdBoxAdvertisement _mergeAdvertisement(
    BirdBoxAdvertisement? previous,
    BirdBoxAdvertisement current,
  ) {
    if (previous == null) return current;
    return BirdBoxAdvertisement(
      localName: current.localName.isNotEmpty ? current.localName : previous.localName,
      serviceUuids: {...previous.serviceUuids, ...current.serviceUuids},
      rssi: current.rssi,
      platformDeviceId: current.platformDeviceId,
      companyIdentifier: current.companyIdentifier ?? previous.companyIdentifier,
      manufacturerPayload: current.manufacturerPayload ?? previous.manufacturerPayload,
    );
  }

  Future<BleScanEnvironment> _readScanEnvironment() async {
    try {
      return await _platform.readScanEnvironment();
    } catch (_) {
      return const BleScanEnvironment.unknown();
    }
  }

  String _newScanSessionId() {
    final custom = _scanSessionIdFactory?.call();
    if (custom != null && custom.trim().isNotEmpty) return custom.trim();
    final sequence = _scanSessionSequence++;
    return 'ble-scan-${_clock().toUtc().microsecondsSinceEpoch}-$sequence';
  }

  BleScanEndReason _endReasonFor(
    Object error,
    _BleScanSessionBuilder diagnostic,
  ) {
    if (error is ProvisioningException) {
      if (error.code == ProvisioningErrorCode.bluetoothPermissionDenied) {
        return BleScanEndReason.permissionDenied;
      }
      if (error.code == ProvisioningErrorCode.bluetoothUnavailable || diagnostic.environmentAfter.adapter == BleAdapterState.disabled || diagnostic.environmentAfter.adapter == BleAdapterState.unavailable) {
        return BleScanEndReason.bluetoothUnavailable;
      }
    }
    return BleScanEndReason.platformError;
  }

  Future<void> _completeScanDiagnostic(BleScanEndReason reason) async {
    final builder = _activeScanDiagnostic;
    _activeScanDiagnostic = null;
    if (builder == null) return;
    try {
      builder.environmentAfter = await _readScanEnvironment();
    } catch (_) {
      // Preserve the last environment snapshot if teardown races the platform.
    }
    final session = builder.complete(endedAt: _clock(), endReason: reason);
    if (!_scanDiagnostics.isClosed) _scanDiagnostics.add(session);
    debugPrint('BLE_SCAN_DIAGNOSTIC ${jsonEncode(session.toJson())}');
    try {
      await _diagnosticSink?.record(session);
    } catch (error) {
      debugPrint('BLE scan diagnostic persistence failed: ${error.runtimeType}');
    }
  }

  @override
  Stream<BleScanDiagnosticSession> get scanDiagnostics => _scanDiagnostics.stream;

  @override
  Future<void> connect(BirdBoxAdvertisement advertisement) async {
    _checkNotDisposed();
    final sessionOwner = _sessionOwner;
    final initialEpoch = _transportEpoch;
    if (_connectInProgress || _disconnectFuture != null || _activeSecurityRequest != null) {
      throw const ProvisioningException(
        code: ProvisioningErrorCode.bleOperationBusy,
        retryable: true,
        diagnosticMessage: 'A BLE connection attempt is already active.',
      );
    }
    _connectInProgress = true;
    _connectInterruptedBy = null;
    _deferredConnectDisconnects.clear();
    try {
      if (!await _platform.ensurePermissions()) throw _permissionDenied();
      if (_disposed || !identical(sessionOwner, _sessionOwner) || initialEpoch != _transportEpoch) throw const ProvisioningException(code: ProvisioningErrorCode.bleGattOperationFailed, retryable: true);
      final platformDeviceId = advertisement.platformDeviceId;
      if (platformDeviceId == null || platformDeviceId.isEmpty) {
        throw const ProvisioningProtocolException('platform_device_id', 'scan result cannot be connected');
      }
      final traceId = _lastTraceId ?? _newScanSessionId();
      _activeTraceId = traceId;
      _associateTrace(traceId);
      await _recordConnectionDiagnostic(
        eventType: 'connect_requested',
        operationName: 'connect',
      );
      await stopScan();
      if (_platform is BirdBoxNativeConnectReset) {
        final previous = _activeConnectionGeneration;
        ++_transportEpoch;
        _markDisconnected('pre_connect_reset');
        if (previous != null) {
          _retiredPublicGenerations.add(previous);
          if (_retiredPublicGenerations.length > 32) _retiredPublicGenerations.remove(_retiredPublicGenerations.first);
        }
      } else {
        await _teardownPlatformSession(reason: 'pre_connect_reset');
      }
      final connectEpoch = _transportEpoch;
      // A controlled disconnect acknowledgement may be delivered while the
      // pre-connect teardown is awaiting its platform result. It belongs to
      // the old session and must not abort the replacement connection.
      _connectInterruptedBy = null;
      try {
        _platformConnectPending = true;
        final connectionGeneration = await _platform.connect(
          platformDeviceId,
          traceId: traceId,
        );
        if (_disposed || connectEpoch != _transportEpoch || !identical(sessionOwner, _sessionOwner)) throw const ProvisioningException(code: ProvisioningErrorCode.bleGattOperationFailed, retryable: true);
        _platformConnectPending = false;
        _activeConnectionGeneration = connectionGeneration;
        _activePlatformDeviceId = platformDeviceId;
        final deferredDisconnects = List<BleDisconnectEvent>.of(
          _deferredConnectDisconnects,
        );
        _deferredConnectDisconnects.clear();
        for (final event in deferredDisconnects) {
          _handleDisconnect(event);
        }
        _throwIfConnectInterrupted();
        _negotiatedMtu = (await _platform.requestMtu(517)).clamp(23, 517);
        if (_disposed || connectEpoch != _transportEpoch || !identical(sessionOwner, _sessionOwner)) throw const ProvisioningException(code: ProvisioningErrorCode.bleGattOperationFailed, retryable: true);
        _throwIfConnectInterrupted();
        await _recordConnectionDiagnostic(
          eventType: 'connect_ready',
          operationName: 'connect',
          resultCode: 'success',
        );
        _throwIfConnectInterrupted();
      } catch (error, stack) {
        final failure = BleAttemptFailure(
          attemptId: _publicPreparation?.id ?? 'connect-$connectEpoch',
          connectionGeneration: _activeConnectionGeneration,
          gattGeneration: _activeGattGeneration,
          traceId: traceId,
          flowId: _traceFlowIds[traceId],
        )..capture(error, stack, method: 'connect', expectedState: 'gatt_ready', currentState: 'connecting');
        await _recordConnectionDiagnostic(
          eventType: 'connect_failed',
          operationName: 'connect',
          resultCode: failure.exception.code.wireValue,
          failure: failure,
        );
        try {
          await _teardownPlatformSession(reason: 'connect_failed');
        } catch (cleanupError, cleanupStack) {
          failure.capture(cleanupError, cleanupStack, method: 'connect.teardown', expectedState: 'gatt_closed', currentState: 'cleanup_failed');
          await _recordConnectionDiagnostic(
            eventType: 'teardown_failed',
            operationName: 'disconnect',
            resultCode: failure.exception.code.wireValue,
            failure: failure,
          );
        }
        Error.throwWithStackTrace(failure.exception, stack);
      }
      _connected = true;
      _requiredNotificationsSubscribed = false;
    } finally {
      _platformConnectPending = false;
      _connectInterruptedBy = null;
      _deferredConnectDisconnects.clear();
      _connectInProgress = false;
    }
  }

  void _throwIfConnectInterrupted() {
    final event = _connectInterruptedBy;
    if (event == null) return;
    throw ProvisioningException(
      code: ProvisioningErrorCode.bleGattOperationFailed,
      retryable: true,
      diagnosticMessage:
          'BLE disconnected while the connection was becoming ready: '
          '${event.reason}; gattStatus=${event.gattStatus}',
    );
  }

  @override
  Future<void> disconnect() {
    if (_disposed) return Future<void>.value();
    _cancelPublicPreparation();
    return _teardownPlatformSession(reason: 'requested');
  }

  Future<void> _teardownPlatformSession({required String reason}) {
    final active = _disconnectFuture;
    if (active != null) return active;
    late final Future<void> operation;
    operation = _performPlatformTeardown(reason).whenComplete(() {
      if (identical(_disconnectFuture, operation)) _disconnectFuture = null;
    });
    _disconnectFuture = operation;
    return operation;
  }

  Future<void> _performPlatformTeardown(String reason) async {
    ++_transportEpoch;
    final requestId = _nativePreparationStarted ? _activeSecurityRequest : null, ready = _pairingReady;
    final generation = _activeConnectionGeneration;
    if (reason == 'pre_connect_reset' && _publicPreparation != null) _controlledReleaseGeneration = generation;
    await _recordConnectionDiagnostic(
      eventType: 'teardown_started',
      operationName: 'disconnect',
      resultCode: reason,
    );
    try {
      final platform = _platform;
      if (platform is BirdBoxPairingPlatform) {
        await (platform as BirdBoxPairingPlatform).disconnectOwned(requestId, ready, generation);
      } else {
        await platform.disconnect();
      }
    } finally {
      _markDisconnected(reason);
      if (reason == 'pre_connect_reset' && _publicPreparation != null && generation != null) _retiredPublicGenerations.add(generation);
      if (_controlledReleaseGeneration == generation) _controlledReleaseGeneration = null;
      await _recordConnectionDiagnostic(
        eventType: 'teardown_completed',
        operationName: 'disconnect',
        resultCode: reason,
      );
    }
  }

  @override
  bool get isConnected => _connected;

  BirdBoxPairingPreflightPlatform get _publicPlatform {
    final platform = _platform;
    if (platform is! BirdBoxPairingPreflightPlatform) throw const ProvisioningException(code: ProvisioningErrorCode.blePairingPreflightUnavailable, retryable: false);
    return platform as BirdBoxPairingPreflightPlatform;
  }

  @override
  Future<ProvisioningDeviceInfo> prepareConnection(BirdBoxAdvertisement advertisement, {required String clientId}) async {
    if (_publicPreparation != null || _activeSecurityRequest != null) throw const ProvisioningException(code: ProvisioningErrorCode.bleOperationBusy, retryable: true);
    // An unknown native state is never a reason to use the old pairing path.
    if (_platform is! BirdBoxPairingPreflightPlatform) {
      throw const ProvisioningException(code: ProvisioningErrorCode.blePairingPreflightUnavailable, retryable: false);
    }
    final run = _PublicPreparation(_sessionOwner, _preflightIds.create());
    final failure = BleAttemptFailure(attemptId: run.id, traceId: _lastTraceId ?? _activeTraceId, flowId: _flowId);
    _publicPreparation = run;
    _preparedConnectionGeneration = null;
    _preparedGattGeneration = null;
    _preparedDeviceId = null;
    final deadline = Timer(preparationTimeout, () => run.cancel(const ProvisioningException(code: ProvisioningErrorCode.bleCommandResponseTimeout, retryable: true)));
    String? expectedDeviceId;
    var advertisementToUse = advertisement;
    var retries = 0, resets = 0, cacheRefreshes = 0;
    int? previousGeneration;
    try {
      if (_connected && _activeConnectionGeneration != null) {
        final previous = await run.wait(_readNativeBond());
        previousGeneration = previous.connectionGeneration;
        if (_platform is! BirdBoxNativeConnectReset) {
          await run.wait(_releasePublicGatt(run, previous.connectionGeneration, previous.gattInstanceId, 'preflight_replace_connection'));
        }
      }
      while (true) {
        _checkPublicRun(run);
        await run.wait(connect(advertisementToUse));
        _checkPublicRun(run);
        final generation = _activeConnectionGeneration;
        if (generation == null || previousGeneration != null && generation <= previousGeneration) throw const ProvisioningException(code: ProvisioningErrorCode.bleGattRecoveryFailed, retryable: false);
        previousGeneration = generation;
        var bond = await run.wait(_readNativeBond());
        if (resets > 0 && bond.state != NativeBondState.notBonded) throw const ProvisioningException(code: ProvisioningErrorCode.bleBondStateUnknown, retryable: false);
        while (bond.state == NativeBondState.bonding) {
          _publicProgress(run, BlePairingStage.systemBond);
          await run.wait(Future<void>.delayed(const Duration(milliseconds: 250)));
          _checkPublicRun(run);
          bond = await run.wait(_readNativeBond());
          if (bond.state == NativeBondState.notBonded) throw const ProvisioningException(code: ProvisioningErrorCode.blePairingRejected, retryable: true);
        }
        if (bond.state == NativeBondState.bonded) {
          await run.wait(subscribeRequiredNotifications());
        } else {
          await run.wait(_subscribePublicStatus());
        }
        _checkPublicRun(run);
        final info = await run.wait(readDeviceInfo());
        _checkPublicRun(run);
        if (expectedDeviceId != null && info.deviceId != expectedDeviceId) throw const ProvisioningException(code: ProvisioningErrorCode.deviceIdMismatch, retryable: false);
        expectedDeviceId = info.deviceId;
        bond = await run.wait(_readNativeBond());
        if (bond.state == NativeBondState.bonded) {
          _markPublicReady(info.deviceId, bond);
          return info;
        }
        if (bond.state != NativeBondState.notBonded) throw const ProvisioningException(code: ProvisioningErrorCode.bleOperationBusy, retryable: true);
        if (!info.capabilities.pairingPreflightV1) throw const ProvisioningException(code: ProvisioningErrorCode.pairingPreflightCommandUnsupported, retryable: false);
        final gatt = await run.wait(_readPublicGatt());
        if (gatt.hasCharacteristicInventory && !gatt.characteristicUuids.contains(BleProtocolConstants.pairingPreflightCharacteristicUuid)) {
          if (cacheRefreshes++ != 0) throw const ProvisioningException(code: ProvisioningErrorCode.pairingPreflightCommandUnsupported, retryable: false);
          await run.wait(_releasePublicGatt(run, gatt.connectionGeneration, gatt.gattInstanceId, 'preflight_service_cache'));
          advertisementToUse = await _freshAdvertisement(run, advertisement);
          continue;
        }
        try {
          final request = PrepareSystemPairingRequest(requestId: _preflightIds.create(), clientId: clientId, phoneBondState: bond.state);
          _publicProgress(run, BlePairingStage.preflightPending, requestId: request.requestId);
          final response = await run.wait(_exchangePublic(run, request, info.deviceId));
          _checkPublicRun(run);
          if (response is PairingPreflightFailure) throw response.error;
          if (response is PairingPreflightNone) {
            _markPublicReady(info.deviceId, await run.wait(_readNativeBond()));
            return info;
          }
          if (response is! PairingPreflightResetRequired) throw const ProvisioningProtocolException('preflight', 'prepare response is not a result');
          ConfirmPairingResetRequest? confirm;
          try {
            if (resets != 0) throw const ProvisioningException(code: ProvisioningErrorCode.pairingPreflightConfirmationRejected, retryable: false);
            confirm = response.confirm(requestId: _preflightIds.create(), now: _clock());
            _publicProgress(run, BlePairingStage.resetConfirming, requestId: confirm.requestId);
            final scheduled = await run.wait(_exchangePublic(run, confirm, info.deviceId));
            if (scheduled is PairingPreflightFailure) throw scheduled.error;
            if (scheduled is! PairingResetScheduled) throw const ProvisioningProtocolException('preflight', 'reset was not acknowledged');
            resets++;
            _publicProgress(run, BlePairingStage.resetPending, requestId: confirm.requestId);
            final reset = _expectedReset;
            if (reset == null) throw const ProvisioningProtocolException('preflight', 'expected disconnect is not armed');
            await run.wait(reset.disconnected.future.timeout(freshAdvertisementTimeout, onTimeout: () => throw const ProvisioningException(code: ProvisioningErrorCode.bleGattRecoveryFailed, retryable: true)));
            _checkPublicRun(run);
            await run.wait(_releasePublicGatt(run, reset.connectionGeneration, reset.gattInstanceId, 'pairing_reset'));
          } finally {
            response.clearSecret();
            confirm?.clearSecret();
          }
          advertisementToUse = await _freshAdvertisement(run, advertisement);
        } on ProvisioningException catch (error) {
          // Current native ABI has no characteristic inventory. Missing 0007 is
          // learned from its stable write error, with the same one-refresh cap.
          if (!gatt.hasCharacteristicInventory && error.code == ProvisioningErrorCode.pairingPreflightCommandUnsupported && error.diagnosticMessage == 'native_preflight_characteristic_missing' && cacheRefreshes++ == 0) {
            await run.wait(_releasePublicGatt(run, gatt.connectionGeneration, gatt.gattInstanceId, 'preflight_service_cache'));
            advertisementToUse = await _freshAdvertisement(run, advertisement);
            continue;
          }
          if (!error.retryable || error.code.pairingPreflightDisposition != PairingPreflightErrorDisposition.boundedRetryAfterRelease || retries++ >= 1) rethrow;
          if (error.retryAfter > const Duration(seconds: 2)) rethrow;
          _checkPublicRun(run);
          final generation = _activeConnectionGeneration, instance = _activeGattGeneration;
          if (generation == null || instance == null) rethrow;
          await run.wait(_releasePublicGatt(run, generation, instance, 'preflight_retry'));
          if (error.retryAfter > Duration.zero) await run.wait(Future<void>.delayed(error.retryAfter));
          advertisementToUse = await _freshAdvertisement(run, advertisement);
        }
      }
    } catch (error, stack) {
      // Teardown is secondary; preserve the original cause and never bond as a fallback.
      failure.capture(error, stack, method: 'prepareConnection', expectedState: 'preflight_ready', currentState: run.stage.name);
      await _recordConnectionDiagnostic(
        eventType: 'pairing_preflight_failed',
        operationName: 'pairing_preflight',
        requestId: run.id,
        errorCode: failure.exception.code.wireValue,
        terminalOutcome: failure.exception.code.wireValue,
        resultCode: run.stage.name,
        failure: failure,
      );
      if (identical(_publicPreparation, run) && identical(run.owner, _sessionOwner)) {
        try {
          await _teardownPlatformSession(reason: 'preflight_failed');
        } catch (cleanupError, cleanupStack) {
          failure.capture(cleanupError, cleanupStack, method: 'prepareConnection.teardown', expectedState: 'gatt_closed', currentState: 'cleanup_failed');
          await _recordConnectionDiagnostic(eventType: 'teardown_failed', operationName: 'pairing_preflight', requestId: run.id, failure: failure);
        }
      }
      Error.throwWithStackTrace(failure.exception, stack);
    } finally {
      deadline.cancel();
      if (identical(_publicPreparation, run)) {
        _publicPreparation = null;
        _expectedReset = null;
        _controlledReleaseGeneration = null;
      }
    }
  }

  void _markPublicReady(String deviceId, NativeBondSnapshot bond) {
    if (bond.state == NativeBondState.bonding) throw const ProvisioningException(code: ProvisioningErrorCode.bleOperationBusy, retryable: true);
    _preparedConnectionGeneration = bond.connectionGeneration;
    _preparedGattGeneration = bond.gattInstanceId;
    _preparedDeviceId = deviceId;
    _preparedAllowsBond = bond.state == NativeBondState.notBonded;
  }

  Future<NativeBondSnapshot> _readNativeBond() async {
    final generation = _activeConnectionGeneration, epoch = _transportEpoch, owner = _sessionOwner;
    if (!_connected || generation == null) throw const ProvisioningException(code: ProvisioningErrorCode.bleGattNotReady, retryable: true);
    final deviceId = _activePlatformDeviceId;
    if (deviceId == null) throw const ProvisioningException(code: ProvisioningErrorCode.bleGattNotReady, retryable: true);
    final snapshot = await _publicPlatform.getNativeBondState(generation, platformDeviceId: deviceId);
    if (!_connected || _transportEpoch != epoch || !identical(owner, _sessionOwner) || snapshot.connectionGeneration != generation || (_activeGattGeneration != null && snapshot.gattInstanceId != _activeGattGeneration)) {
      throw const ProvisioningException(code: ProvisioningErrorCode.bleGattOperationFailed, retryable: true);
    }
    _activeGattGeneration = snapshot.gattInstanceId;
    return snapshot;
  }

  Future<PublicGattSnapshot> _readPublicGatt() async {
    final generation = _activeConnectionGeneration, instance = _activeGattGeneration, epoch = _transportEpoch;
    if (!_connected || generation == null || instance == null) throw const ProvisioningException(code: ProvisioningErrorCode.bleGattNotReady, retryable: true);
    final value = await _publicPlatform.getGattOwnershipState(generation);
    if (!_connected || epoch != _transportEpoch || !value.connected || !value.linkReady || value.connectionGeneration != generation || value.gattInstanceId != instance) {
      throw const ProvisioningException(code: ProvisioningErrorCode.bleGattOperationFailed, retryable: true);
    }
    if (value.preparing || value.inflightRequest != null) throw const ProvisioningException(code: ProvisioningErrorCode.bleOperationBusy, retryable: true);
    return value;
  }

  Future<PairingPreflightResponse> _exchangePublic(_PublicPreparation run, PairingPreflightRequest request, String deviceId) async {
    _checkPublicRun(run);
    if (_publicRequest != null || _activeSecurityRequest != null || !_publicStatusSubscribed) throw const ProvisioningException(code: ProvisioningErrorCode.bleOperationBusy, retryable: true);
    final bond = await run.wait(_readNativeBond());
    if (bond.state != NativeBondState.notBonded) throw const ProvisioningException(code: ProvisioningErrorCode.bleBondStateUnknown, retryable: false);
    _checkPublicRun(run);
    final pending = _PublicRequest(request, deviceId, bond.connectionGeneration, bond.gattInstanceId);
    final message = _preflightCodec.encodeRequest(request);
    List<Uint8List> packets = const [];
    Timer? timer;
    _publicRequest = pending;
    _publicRequestIds.add(request.requestId);
    if (_publicRequestIds.length > 32) _publicRequestIds.remove(_publicRequestIds.first);
    try {
      packets = _fragmentCodec.fragment(message, messageId: _allocateMessageId(), maximumFragmentBytes: _writeFragmentBytes());
      await _recordConnectionDiagnostic(eventType: 'pairing_preflight_request', operationName: 'pairing_preflight', commandType: request.wireType, requestId: request.requestId, resultCode: 'started');
      for (final packet in packets) {
        _checkPublicRun(run);
        if (!_connected || _activeConnectionGeneration != pending.connectionGeneration || _activeGattGeneration != pending.gattInstanceId) {
          throw const ProvisioningException(code: ProvisioningErrorCode.bleGattOperationFailed, retryable: true);
        }
        await run.wait(_publicPlatform.writePairingPreflight(requestId: request.requestId, connectionGeneration: pending.connectionGeneration, gattInstanceId: pending.gattInstanceId, fragmentBytes: packet));
      }
      timer = Timer(preflightResponseTimeout, () {
        if (!pending.response.isCompleted) pending.response.completeError(const ProvisioningException(code: ProvisioningErrorCode.bleCommandResponseTimeout, retryable: true));
      });
      final result = await run.wait(pending.response.future);
      await _recordConnectionDiagnostic(
        eventType: 'pairing_preflight_result',
        operationName: 'pairing_preflight',
        requestId: request.requestId,
        errorCode: result is PairingPreflightFailure ? result.error.code.wireValue : null,
        sanitizedMessage: result is PairingPreflightResult
            ? jsonEncode({
                'action': result.action,
                'board_bond_before': {'paired': result.boardBondBefore.paired, 'bonded': result.boardBondBefore.bonded},
              })
            : null,
        resultCode: switch (result) {
          PairingPreflightResult() => result.action,
          PairingResetScheduled() => result.action,
          PairingPreflightFailure() => result.error.code.wireValue,
        },
      );
      return result;
    } finally {
      timer?.cancel();
      message.fillRange(0, message.length, 0);
      for (final packet in packets) {
        packet.fillRange(0, packet.length, 0);
      }
      if (identical(_publicRequest, pending)) _publicRequest = null;
      if (run.error != null) {
        unawaited(
          pending.response.future.then<void>((response) {
            if (response is PairingPreflightResetRequired) response.clearSecret();
          }, onError: (Object _, StackTrace _) {}),
        );
      }
    }
  }

  Future<void> _releasePublicGatt(_PublicPreparation run, int generation, int instance, String reason) async {
    _checkPublicRun(run);
    _controlledReleaseGeneration = generation;
    try {
      await _publicPlatform.prepareControlledReconnect(requestId: run.id, connectionGeneration: generation, gattInstanceId: instance, reason: reason);
      _checkPublicRun(run);
      _retiredPublicGenerations.add(generation);
      if (_retiredPublicGenerations.length > 32) _retiredPublicGenerations.remove(_retiredPublicGenerations.first);
      ++_transportEpoch;
      _markDisconnected('controlled_preflight_release');
    } finally {
      _controlledReleaseGeneration = null;
      _expectedReset = null;
    }
  }

  Future<BirdBoxAdvertisement> _freshAdvertisement(_PublicPreparation run, BirdBoxAdvertisement original) async {
    _checkPublicRun(run);
    _publicProgress(run, BlePairingStage.waitingFreshAdvertisement);
    final stream = scan(timeout: freshAdvertisementTimeout);
    final controller = _scanController;
    try {
      final candidate = await run.wait(
        stream
            .firstWhere((candidate) => candidate.hasBirdBoxService && (candidate.platformDeviceId == original.platformDeviceId && original.platformDeviceId != null || candidate.localName == original.localName))
            .timeout(freshAdvertisementTimeout),
      );
      _checkPublicRun(run);
      _publicProgress(run, BlePairingStage.freshGattReconnecting);
      return candidate;
    } on TimeoutException {
      if (run.error != null) throw run.error!;
      throw const ProvisioningException(code: ProvisioningErrorCode.bleGattRecoveryFailed, retryable: true);
    } on StateError {
      if (run.error != null) throw run.error!;
      throw const ProvisioningException(code: ProvisioningErrorCode.bleGattRecoveryFailed, retryable: true);
    } finally {
      if (controller != null && identical(controller, _scanController)) await _finishScan(controller, reason: BleScanEndReason.cancelled);
    }
  }

  void _checkPublicRun(_PublicPreparation run) {
    if (run.error != null) throw run.error!;
    if (_disposed || !identical(_publicPreparation, run) || !identical(run.owner, _sessionOwner)) throw const ProvisioningException(code: ProvisioningErrorCode.bleSessionEnded, retryable: true);
  }

  void _cancelPublicPreparation() {
    const error = ProvisioningException(code: ProvisioningErrorCode.bleSessionEnded, retryable: true);
    _publicPreparation?.cancel(error);
    final pending = _publicRequest;
    if (pending != null && !pending.response.isCompleted) pending.response.completeError(error);
    final reset = _expectedReset;
    if (reset != null && !reset.disconnected.isCompleted) reset.disconnected.completeError(error);
  }

  void _publicProgress(_PublicPreparation run, BlePairingStage stage, {String? requestId}) {
    _checkPublicRun(run);
    run.stage = stage;
    _pairingProgress.add(BlePairingProgress(requestId: requestId ?? run.id, attemptId: run.id, stage: stage, connectionGeneration: _activeConnectionGeneration));
    unawaited(_recordConnectionDiagnostic(eventType: 'pairing_preflight_state', operationName: 'pairing_preflight', requestId: requestId ?? run.id, resultCode: stage.name));
  }

  @override
  Future<ProvisioningDeviceInfo> readDeviceInfo() async {
    final message = await _readMessage(BleProtocolConstants.deviceInfoCharacteristicUuid);
    try {
      final info = _messageCodec.decodeDeviceInfo(message);
      _trustedResponseDeviceId = info.deviceId;
      return info;
    } finally {
      message.fillRange(0, message.length, 0);
    }
  }

  String? _trustedResponseDeviceId;

  @override
  Future<ProvisioningNetworkStatus> readNetworkStatus() async {
    final message = await _readMessage(BleProtocolConstants.networkStatusCharacteristicUuid);
    try {
      return _messageCodec.decodeNetworkStatus(message);
    } finally {
      message.fillRange(0, message.length, 0);
    }
  }

  Future<Uint8List> _readMessage(String characteristicUuid) async {
    _checkConnected();
    final reassembler = BleFragmentReassembler();
    for (var attempt = 0; attempt < BleProtocolConstants.maximumFragmentCount; attempt++) {
      final rawRead = await _platform.readCharacteristic(characteristicUuid);
      for (final packet in _fragmentCodec.splitPackets(rawRead)) {
        final message = reassembler.add(packet);
        if (message != null) return message;
      }
    }
    reassembler.reset();
    throw const ProvisioningException(code: ProvisioningErrorCode.bleFragmentInvalid, retryable: false, diagnosticMessage: 'Characteristic read ended before all fragments arrived');
  }

  @override
  Future<void> subscribeRequiredNotifications() async {
    _checkConnected();
    await _platform.setNotify(BleProtocolConstants.networkStatusCharacteristicUuid, enabled: true);
    _publicStatusSubscribed = true;
    try {
      await _platform.setNotify(BleProtocolConstants.scanResultsCharacteristicUuid, enabled: true);
    } catch (_) {
      await _platform.setNotify(BleProtocolConstants.networkStatusCharacteristicUuid, enabled: false);
      _publicStatusSubscribed = false;
      rethrow;
    }
    _requiredNotificationsSubscribed = true;
    await _recordConnectionDiagnostic(
      eventType: 'notifications_ready',
      operationName: 'restore_notifications',
      resultCode: 'success',
    );
  }

  @override
  bool get requiredNotificationsSubscribed => _requiredNotificationsSubscribed;

  Future<void> _subscribePublicStatus() async {
    _checkConnected();
    await _platform.setNotify(BleProtocolConstants.networkStatusCharacteristicUuid, enabled: true);
    _publicStatusSubscribed = true;
    await _recordConnectionDiagnostic(eventType: 'pairing_preflight_notifications_ready', operationName: 'pairing_preflight', resultCode: 'public_network_status_only');
  }

  @override
  Future<ProvisioningEvent> writeCommand(BleCommandRequest request) async {
    _checkConnected();
    if (_publicPreparation != null || _publicRequest != null) throw const ProvisioningException(code: ProvisioningErrorCode.bleOperationBusy, retryable: true);
    if (!_requiredNotificationsSubscribed && !(_platform is BirdBoxPairingPreflightPlatform && _publicStatusSubscribed && request.type == BleCommandType.openPairing)) {
      if (_platform is BirdBoxPairingPreflightPlatform && _publicStatusSubscribed) throw const ProvisioningException(code: ProvisioningErrorCode.authorizationRequired, retryable: false);
      throw const ProvisioningException(code: ProvisioningErrorCode.bleGattNotReady, retryable: true);
    }
    if (_activeSecurityRequest != null || _pendingCommands.containsKey(request.requestId)) {
      throw const ProvisioningException(code: ProvisioningErrorCode.requestIdConflict, retryable: false);
    }
    // Admit one request before any asynchronous persistence or platform call.
    final message = _messageCodec.encodeRequest(request);
    final commandEpoch = _transportEpoch;
    _activeSecurityRequest = request.requestId;
    _pairingReady = null;
    List<Uint8List> packets = const [];
    final completer = Completer<ProvisioningEvent>();
    _pendingCommands[request.requestId] = completer;
    unawaited(completer.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    var securitySessionStarted = false;
    final failure = BleAttemptFailure(
      attemptId: request.requestId,
      requestId: request.requestId,
      connectionGeneration: _activeConnectionGeneration,
      gattGeneration: _activeGattGeneration,
      traceId: _activeTraceId ?? _lastTraceId,
      flowId: _flowId,
    );
    _activeCommandFailure = failure;
    try {
      await _recordConnectionDiagnostic(eventType: 'command_started', operationName: 'write_command', commandType: request.type.wireValue, requestId: request.requestId);
      if (commandEpoch != _transportEpoch || !_connected || _disposed) throw const ProvisioningException(code: ProvisioningErrorCode.bleGattOperationFailed, retryable: true);
      if (_platform is BirdBoxPairingPreflightPlatform) {
        if (_preparedConnectionGeneration != _activeConnectionGeneration || _preparedDeviceId != _trustedResponseDeviceId) throw const ProvisioningException(code: ProvisioningErrorCode.blePairingPreflightUnavailable, retryable: false);
        final bond = await _readNativeBond();
        if (bond.state == NativeBondState.bonding) throw const ProvisioningException(code: ProvisioningErrorCode.bleOperationBusy, retryable: true);
        if (bond.state == NativeBondState.notBonded && request.type != BleCommandType.openPairing) throw const ProvisioningException(code: ProvisioningErrorCode.authorizationRequired, retryable: false);
        if (bond.state == NativeBondState.notBonded && (!_preparedAllowsBond || _preparedGattGeneration != bond.gattInstanceId)) throw const ProvisioningException(code: ProvisioningErrorCode.bleBondLost, retryable: true);
        // One preparation grants at most one attempt that may initiate bonding.
        _preparedAllowsBond = false;
      }
      securitySessionStarted = true;
      _nativePreparationStarted = true;
      final platform = _platform;
      _pairingProgress.add(BlePairingProgress(requestId: request.requestId, stage: BlePairingStage.preparing));
      if (platform is BirdBoxPairingPlatform) {
        final ready = await (platform as BirdBoxPairingPlatform).preparePairing(request.requestId, request.type.wireValue);
        _adoptReady(ready, request.requestId);
      } else {
        await platform.beginSecurityWrite(request.requestId, commandType: request.type.wireValue);
      }
      if (_activeSecurityRequest != request.requestId || !_connected) throw const ProvisioningException(code: ProvisioningErrorCode.bleGattOperationFailed, retryable: true);
      final characteristicUuid = request.writesWifiCredentials ? BleProtocolConstants.wifiConfigCharacteristicUuid : BleProtocolConstants.provisioningCommandCharacteristicUuid;
      final maximumFragmentBytes = _writeFragmentBytes();
      final messageId = _allocateMessageId();
      packets = _fragmentCodec.fragment(message, messageId: messageId, maximumFragmentBytes: maximumFragmentBytes);
      try {
        await _writePackets(request.requestId, characteristicUuid, packets);
      } on ProvisioningException catch (error) {
        if (error.code != ProvisioningErrorCode.authorizationRequired) rethrow;
        // Native recovery is allowed once while still BONDED. Keep the same
        // command and message ID, but obey the replacement GATT's actual MTU.
        _requiredNotificationsSubscribed = false;
        await _recoverSecurityWrite(request);
        if (_platform is BirdBoxPairingPlatform) {
          for (final packet in packets) {
            packet.fillRange(0, packet.length, 0);
          }
          packets = _fragmentCodec.fragment(message, messageId: messageId, maximumFragmentBytes: _writeFragmentBytes());
        }
        await _recordConnectionDiagnostic(
          eventType: 'security_write_retrying',
          operationName: 'write_command',
          commandType: request.type.wireValue,
          requestId: request.requestId,
          retryCount: 1,
          characteristicUuid: characteristicUuid,
          securityTrigger: 'encrypted_characteristic_write',
        );
        await _platform.beginSecurityRetry(request.requestId);
        try {
          await _writePackets(request.requestId, characteristicUuid, packets);
        } catch (error) {
          if (error is ProvisioningException && (error.code == ProvisioningErrorCode.bleSessionEnded || error.code == ProvisioningErrorCode.bleHostUnavailable)) {
            rethrow;
          }
          throw ProvisioningException(
            code: ProvisioningErrorCode.bleEncryptedRetryFailed,
            retryable: true,
            diagnosticMessage: 'The exact encrypted request retry failed: ${_resultCode(error)}',
          );
        }
      }
      await _platform.markSecurityWriteSent(request.requestId);
      final response = await completer.future.timeout(
        BleProtocolConstants.commandResponseTimeout,
        onTimeout: () => throw ProvisioningException(
          code: request.type == BleCommandType.openPairing ? ProvisioningErrorCode.pairingOpenTimeout : ProvisioningErrorCode.bleCommandResponseTimeout,
          retryable: true,
          diagnosticMessage: 'BLE command response timed out for matching request_id',
        ),
      );
      if (failure.hasFailure) throw failure.exception;
      try {
        await _platform.completeSecurityWrite(request.requestId, responseType: response.type.wireValue);
      } catch (cleanupError, cleanupStack) {
        failure.capture(cleanupError, cleanupStack, method: 'completeSecurityWrite', expectedState: 'already_completed_or_closed', currentState: 'response_received', secondaryOnly: true);
        await _recordConnectionDiagnostic(eventType: 'security_cleanup_failed', operationName: 'security_write', requestId: request.requestId, terminalOutcome: 'success', cleanupOutcome: 'failed', failure: failure);
      }
      securitySessionStarted = false;
      await _recordConnectionDiagnostic(
        eventType: 'command_succeeded',
        operationName: 'write_command',
        commandType: request.type.wireValue,
        requestId: request.requestId,
        characteristicUuid: characteristicUuid,
        responseType: response.type.wireValue,
        resultCode: 'success',
      );
      return response;
    } catch (error, stack) {
      failure.capture(error, stack, method: 'writeCommand', expectedState: 'matching_response', currentState: 'security_write_failed');
      // Persist the cause before cleanup can throw or emit a disconnect.
      await _recordConnectionDiagnostic(eventType: 'attempt_failed', operationName: 'write_command', requestId: request.requestId, commandType: request.type.wireValue, failure: failure);
      if (securitySessionStarted) {
        try {
          await _platform.failSecurityWrite(
            request.requestId,
            errorCode: failure.exception.code.wireValue.toLowerCase(),
          );
        } catch (cleanupError, cleanupStack) {
          failure.capture(cleanupError, cleanupStack, method: 'failSecurityWrite', expectedState: 'already_completed_or_closed', currentState: 'cleanup_failed');
          await _recordConnectionDiagnostic(
            eventType: 'security_cleanup_failed',
            operationName: 'security_write',
            commandType: request.type.wireValue,
            requestId: request.requestId,
            resultCode: _resultCode(error),
            errorCode: _resultCode(cleanupError),
            terminalOutcome: _resultCode(error),
            cleanupOutcome: 'failed',
            failure: failure,
          );
          debugPrint(
            'BIRDBOX_BLE_SECURITY_CLEANUP_FAILED requestId=${request.requestId} '
            '${cleanupError.runtimeType}',
          );
        }
      }
      await _recordConnectionDiagnostic(
        eventType: 'command_failed',
        operationName: 'write_command',
        commandType: request.type.wireValue,
        requestId: request.requestId,
        resultCode: _resultCode(error),
        errorCode: _resultCode(error),
        terminalOutcome: _resultCode(error),
        failure: failure,
      );
      Error.throwWithStackTrace(failure.exception, stack);
    } finally {
      message.fillRange(0, message.length, 0);
      for (final packet in packets) {
        packet.fillRange(0, packet.length, 0);
      }
      if (identical(_pendingCommands[request.requestId], completer)) _pendingCommands.remove(request.requestId);
      if (_activeSecurityRequest == request.requestId) {
        _activeSecurityRequest = null;
        _activeCommandFailure = null;
        _pairingReady = null;
        _nativePreparationStarted = false;
      }
    }
  }

  Future<void> _recoverSecurityWrite(BleCommandRequest request) async {
    try {
      await _recordConnectionDiagnostic(
        eventType: 'security_recovery_started',
        operationName: 'security_recovery',
        commandType: request.type.wireValue,
        requestId: request.requestId,
        resultCode: 'waiting_for_bond',
        securityTrigger: 'encrypted_characteristic_write',
      );
      final platform = _platform;
      if (platform is BirdBoxPairingPlatform) {
        _adoptReady(await (platform as BirdBoxPairingPlatform).recoverPairing(request.requestId), request.requestId);
      } else {
        final gattRebuilt = await platform.awaitSecurityReady(request.requestId);
        if (_activeCommandFailure?.hasFailure ?? false) throw _activeCommandFailure!.exception;
        if (gattRebuilt) _negotiatedMtu = await platform.requestMtu(517);
        await subscribeRequiredNotifications();
      }
      if (_activeCommandFailure?.hasFailure ?? false) throw _activeCommandFailure!.exception;
      await _recordConnectionDiagnostic(
        eventType: 'security_recovery_completed',
        operationName: 'security_recovery',
        commandType: request.type.wireValue,
        requestId: request.requestId,
        resultCode: 'ready_to_write',
        retryCount: 1,
      );
    } on ProvisioningException catch (error) {
      await _recordConnectionDiagnostic(
        eventType: 'security_recovery_failed',
        operationName: 'security_recovery',
        commandType: request.type.wireValue,
        requestId: request.requestId,
        resultCode: 'failed:${error.code.wireValue}',
      );
      debugPrint(
        'BIRDBOX_BLE_FAILURE operation=${request.type.wireValue} '
        'requestId=${request.requestId} ${error.diagnosticMessage ?? error.code.wireValue}',
      );
      if (error.code == ProvisioningErrorCode.bleBondLost ||
          error.code == ProvisioningErrorCode.bleSessionEnded ||
          error.code == ProvisioningErrorCode.bleHostUnavailable ||
          error.code == ProvisioningErrorCode.bluetoothUnavailable ||
          error.code == ProvisioningErrorCode.bluetoothPermissionDenied ||
          error.code == ProvisioningErrorCode.bleBondStateUnknown ||
          error.code == ProvisioningErrorCode.bleLePairingNotStarted ||
          error.code == ProvisioningErrorCode.blePairingTimeout ||
          error.code == ProvisioningErrorCode.blePairingRejected ||
          error.code == ProvisioningErrorCode.bleGattRecoveryFailed ||
          error.code == ProvisioningErrorCode.bleGattOperationFailed ||
          error.code == ProvisioningErrorCode.bleSecurityRecoveryFailed) {
        rethrow;
      }
      throw ProvisioningException(
        code: ProvisioningErrorCode.bleSecurityRecoveryFailed,
        retryable: true,
        diagnosticMessage: 'Secured GATT restoration failed: ${error.diagnosticMessage ?? error.code.wireValue}',
      );
    } catch (error) {
      throw ProvisioningException(
        code: ProvisioningErrorCode.bleSecurityRecoveryFailed,
        retryable: true,
        diagnosticMessage: 'Secured GATT restoration failed: ${error.runtimeType}',
      );
    }
  }

  Future<void> _writePackets(
    String requestId,
    String characteristicUuid,
    List<Uint8List> packets,
  ) async {
    for (final packet in packets) {
      if (_activeSecurityRequest != requestId || !_connected) throw const ProvisioningException(code: ProvisioningErrorCode.bleGattOperationFailed, retryable: true);
      await _platform.writeWithResponse(characteristicUuid, packet);
    }
  }

  int _allocateMessageId() {
    final value = _nextMessageId;
    _nextMessageId = (_nextMessageId + 1) & 0xFFFF;
    return value;
  }

  void _handleNotification(Map<String, dynamic> raw) {
    try {
      if (_publicPreparation != null && (raw['connectionGeneration'] != _activeConnectionGeneration || raw['gattGeneration'] != _activeGattGeneration || _activeConnectionGeneration == null || _activeGattGeneration == null)) return;
      if (raw['connectionGeneration'] is int && raw['connectionGeneration'] != _activeConnectionGeneration) return;
      if (raw['gattGeneration'] is int && _activeGattGeneration != null && raw['gattGeneration'] != _activeGattGeneration) return;
      final characteristicUuid = BleProtocolConstants.normalizeUuid(_requiredString(raw, 'characteristicUuid'));
      if (!BleProtocolConstants.notifyCharacteristicUuids.contains(characteristicUuid)) {
        throw const ProvisioningProtocolException('characteristicUuid', 'notification came from an unexpected characteristic');
      }
      final packet = raw['value'];
      if (packet is! Uint8List) throw const ProvisioningProtocolException('value', 'notification must contain bytes');
      final reassembler = _notificationReassemblers.putIfAbsent(characteristicUuid, BleFragmentReassembler.new);
      final message = reassembler.add(packet);
      if (message == null) return;
      try {
        if (_handlePublicResponse(message, characteristicUuid)) return;
        final response = _messageCodec.decodeResponse(message);
        if (_trustedResponseDeviceId != null && response.deviceId != _trustedResponseDeviceId) {
          throw const ProvisioningException(code: ProvisioningErrorCode.deviceIdMismatch, retryable: false);
        }
        if (response is BleFailureResponse) {
          final pending = _pendingCommands[response.requestId];
          if (pending != null && !pending.isCompleted) {
            _activeCommandFailure?.capture(response.error, StackTrace.current, method: 'notification.error', expectedState: 'matching_success_response', currentState: 'box_error');
            pending.completeError(response.error);
          } else {
            _events.addError(BleOperationFailure(requestId: response.requestId, deviceId: response.deviceId, error: response.error));
          }
          return;
        }
        final event = (response as BleSuccessResponse).event;
        final pending = _pendingCommands[event.requestId];
        if (pending != null && !pending.isCompleted) pending.complete(event);
        _events.add(event);
      } finally {
        message.fillRange(0, message.length, 0);
      }
    } catch (error, stackTrace) {
      _events.addError(error, stackTrace);
    }
  }

  @override
  Stream<ProvisioningEvent> get events => _events.stream;

  @override
  Stream<void> get disconnects => _disconnects.stream;

  bool _handlePublicResponse(Uint8List message, String characteristicUuid) {
    final pending = _publicRequest;
    try {
      final json = jsonDecode(utf8.decode(message, allowMalformed: false));
      if (json is! Map) return false;
      final id = json['request_id'];
      final type = json['type'];
      final isPublic = type == 'pairing_preflight_result' || type == 'pairing_reset_scheduled' || _publicRequestIds.contains(id);
      if (!isPublic) return false;
      if (pending == null || pending.response.isCompleted || id != pending.request.requestId) return true;
      if (characteristicUuid != BleProtocolConstants.networkStatusCharacteristicUuid) throw const ProvisioningProtocolException('characteristicUuid', 'preflight must arrive on network status');
      final response = _preflightCodec.decodeResponse(message, request: pending.request, expectedDeviceId: pending.deviceId, receivedAt: _clock());
      if (response is PairingResetScheduled) {
        // Arm synchronously before completing the Future: the next native event
        // may be the expected disconnect, before the awaiting Dart code resumes.
        _expectedReset = _ExpectedReset(pending.connectionGeneration, pending.gattInstanceId);
      }
      pending.response.complete(response);
      return true;
    } on FormatException {
      if (pending == null) return false;
      if (!pending.response.isCompleted) pending.response.completeError(const ProvisioningProtocolException('preflight', 'invalid response'));
      return true;
    } catch (_) {
      if (pending == null) return true;
      if (!pending.response.isCompleted) pending.response.completeError(const ProvisioningProtocolException('preflight', 'invalid response'));
      return true;
    }
  }

  void _handleDisconnect([BleDisconnectEvent? event]) {
    final eventGeneration = event?.connectionGeneration;
    final activeGeneration = _activeConnectionGeneration;
    if (eventGeneration != null && eventGeneration != activeGeneration && _retiredPublicGenerations.contains(eventGeneration)) return;
    final reset = _expectedReset;
    final matchingReset =
        reset != null &&
        _publicPreparation != null &&
        eventGeneration == reset.connectionGeneration &&
        (_activeGattGeneration == reset.gattInstanceId || reset.disconnected.isCompleted) &&
        !const {'engine_destroyed', 'bridge_disposed', 'requested'}.contains(event?.reason);
    final controlledRelease = eventGeneration != null && eventGeneration == _controlledReleaseGeneration;
    if (matchingReset || controlledRelease) {
      // Freeze the ownership fields before clearing the live connection.
      final diagnostic = _recordConnectionDiagnostic(eventType: 'pairing_preflight_expected_disconnect', operationName: 'pairing_preflight', gattStatus: event?.gattStatus, resultCode: matchingReset ? 'pairing_reset' : 'controlled_release');
      _markDisconnected('expected_pairing_reset');
      if (matchingReset && !reset.disconnected.isCompleted) reset.disconnected.complete();
      unawaited(diagnostic);
      return;
    }
    if (_connectInProgress && activeGeneration == null && event != null) {
      if (_platformConnectPending) {
        _deferredConnectDisconnects.add(event);
      } else {
        unawaited(
          _recordConnectionDiagnostic(
            eventType: 'stale_disconnect_ignored',
            operationName: 'disconnect',
            gattStatus: event.gattStatus,
            resultCode: event.reason,
          ),
        );
      }
      return;
    }
    if (eventGeneration != null && activeGeneration != null && eventGeneration != activeGeneration) {
      unawaited(
        _recordConnectionDiagnostic(
          eventType: 'stale_disconnect_ignored',
          operationName: 'disconnect',
          gattStatus: event?.gattStatus,
          resultCode: event?.reason ?? 'unknown',
        ),
      );
      return;
    }
    if (_connectInProgress && event != null) {
      _connectInterruptedBy = event;
    }
    final wasConnected = _connected;
    unawaited(
      _recordConnectionDiagnostic(
        eventType: 'disconnected',
        operationName: 'disconnect',
        gattStatus: event?.gattStatus,
        resultCode: event?.reason ?? 'unknown',
      ),
    );
    _markDisconnected(event?.reason ?? 'unknown');
    if (_publicPreparation != null) _publicPreparation!.cancel(const ProvisioningException(code: ProvisioningErrorCode.bleGattOperationFailed, retryable: true));
    if (wasConnected) _disconnects.add(null);
  }

  void _markDisconnected([String reason = 'unknown']) {
    _preparedConnectionGeneration = null;
    _preparedGattGeneration = null;
    _preparedDeviceId = null;
    _preparedAllowsBond = false;
    _trustedResponseDeviceId = null;
    _connected = false;
    _activeConnectionGeneration = null;
    _activePlatformDeviceId = null;
    _activeGattGeneration = null;
    _negotiatedMtu = 23;
    _requiredNotificationsSubscribed = false;
    _publicStatusSubscribed = false;
    for (final reassembler in _notificationReassemblers.values) {
      reassembler.reset();
    }
    _notificationReassemblers.clear();
    final error = ProvisioningException(
      code: const {'engine_destroyed', 'bridge_disposed'}.contains(reason) ? ProvisioningErrorCode.bleSessionEnded : ProvisioningErrorCode.bleGattOperationFailed,
      retryable: true,
      diagnosticMessage: 'BLE disconnected before the command response: $reason',
    );
    final publicRequest = _publicRequest;
    if (publicRequest != null && !publicRequest.response.isCompleted) publicRequest.response.completeError(error);
    for (final completer in _pendingCommands.values) {
      if (!completer.isCompleted) {
        _activeCommandFailure?.capture(error, StackTrace.current, method: 'disconnect', expectedState: 'matching_response', currentState: 'disconnected');
        completer.completeError(error);
      }
    }
    _pendingCommands.clear();
    // No cancel command is sent: accepted box-side network operations continue.
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _cancelPublicPreparation();
    _disposed = true;
    final scanController = _scanController;
    if (scanController != null) {
      await _finishScan(
        scanController,
        reason: BleScanEndReason.disposed,
      );
    }
    try {
      await _teardownPlatformSession(reason: 'disposed');
    } catch (error) {
      debugPrint('BLE teardown during dispose failed: ${error.runtimeType}');
    }
    await _notificationSubscription.cancel();
    await _disconnectSubscription.cancel();
    await _diagnosticSubscription.cancel();
    await _platform.dispose();
    await _events.close();
    await _disconnects.close();
    await _scanDiagnostics.close();
    await _pairingProgress.close();
  }

  void _checkNotDisposed() {
    if (_disposed) throw const ProvisioningException(code: ProvisioningErrorCode.bleSessionEnded, retryable: true);
  }

  void _checkConnected() {
    _checkNotDisposed();
    if (!_connected) throw const ProvisioningException(code: ProvisioningErrorCode.bleGattNotReady, retryable: true);
  }

  static ProvisioningException _permissionDenied() => const ProvisioningException(code: ProvisioningErrorCode.bluetoothPermissionDenied, retryable: false);

  void _handleNativeDiagnostic(Map<String, dynamic> value) {
    try {
      final event = BleConnectionDiagnosticEvent.fromPlatform({...value, 'flowId': _traceFlowIds[value['traceId']]});
      _activeTraceId ??= event.traceId;
      final failure = _activeCommandFailure;
      final outcome = event.terminalOutcome?.toLowerCase();
      if (failure != null &&
          !failure.hasFailure &&
          event.requestId == _activeSecurityRequest &&
          _pendingCommands[event.requestId]?.isCompleted == false &&
          event.eventType == 'security_write_terminal' &&
          event.callbackGattIsCurrent != false &&
          (event.connectionGeneration == null || event.connectionGeneration == _activeConnectionGeneration) &&
          const {
            'ble_pairing_rejected',
            'ble_bond_rejected',
            'bond_rejected',
            'ble_pairing_timeout',
            'ble_bond_timeout',
            'bond_timeout',
            'bond_lost',
            'ble_gatt_operation_failed',
            'ble_gatt_recovery_failed',
            'ble_security_recovery_failed',
            'ble_encrypted_retry_failed',
            'pairing_open_timeout',
          }.contains(outcome)) {
        failure.capture(
          MethodChannelBirdBoxBlePlatform._platformError(PlatformException(code: outcome!)),
          StackTrace.current,
          method: 'native.security_write_terminal',
          expectedState: 'matching_response',
          currentState: event.securityPhase ?? 'native_terminal',
          previousBondState: event.previousBondState,
          currentBondState: event.actualBondState ?? event.bondState,
          nativeAttemptId: event.attemptId,
        );
        unawaited(_recordConnectionDiagnostic(eventType: 'attempt_failed', operationName: 'security_write', requestId: event.requestId, failure: failure));
      }
      if (event.requestId == _activeSecurityRequest && event.securityPhase != null && !_pairingProgress.isClosed) {
        final stage = switch (event.securityPhase) {
          'system_bond_starting' || 'system_bond_waiting' => BlePairingStage.systemBond,
          'bonded_recovering_gatt' => BlePairingStage.reconnecting,
          'restoring_notifications' => BlePairingStage.restoringNotifications,
          'retrying_encrypted_write' => BlePairingStage.retrying,
          'waiting_response' => BlePairingStage.waitingResponse,
          'security_write_starting' || 'security_ready' => BlePairingStage.writing,
          _ => null,
        };
        if (stage != null) _pairingProgress.add(BlePairingProgress(requestId: event.requestId!, stage: stage, attemptId: event.attemptId, connectionGeneration: event.connectionGeneration));
      }
      unawaited(_persistConnectionDiagnostic(event));
    } catch (error) {
      debugPrint('BLE native diagnostic event rejected: ${error.runtimeType}');
    }
  }

  Future<void> _recordConnectionDiagnostic({
    required String eventType,
    String? operationName,
    int? gattStatus,
    String? commandType,
    String? requestId,
    int? retryCount,
    String? characteristicUuid,
    String? securityTrigger,
    String? responseType,
    String? resultCode,
    String? errorCode,
    String? terminalOutcome,
    String? cleanupOutcome,
    String? sanitizedMessage,
    BleAttemptFailure? failure,
  }) async {
    final traceId = failure?.firstTerminalError?['trace_id'] as String? ?? _activeTraceId ?? _lastTraceId;
    if (traceId == null) return;
    await _persistConnectionDiagnostic(
      BleConnectionDiagnosticEvent(
        traceId: traceId,
        flowId: failure?.firstTerminalError?['flow_id'] as String? ?? _traceFlowIds[traceId],
        occurredAt: _clock().toUtc(),
        eventType: eventType,
        source: 'dart',
        operationName: operationName,
        gattStatus: gattStatus,
        commandType: commandType,
        requestId: requestId,
        retryCount: retryCount,
        characteristicUuid: characteristicUuid,
        securityTrigger: securityTrigger,
        responseType: responseType,
        resultCode: resultCode,
        errorCode: failure?.firstTerminalError?['error_code'] as String? ?? errorCode,
        terminalOutcome: failure?.firstTerminalError?['error_code'] as String? ?? terminalOutcome,
        cleanupOutcome: cleanupOutcome,
        sanitizedMessage: sanitizedMessage,
        attemptId: failure?.firstTerminalError?['attempt_id'] as String? ?? _publicPreparation?.id,
        failureDetails: failure?.toJson(),
        connectionGeneration: _activeConnectionGeneration,
        gattGeneration: _activeGattGeneration,
      ),
    );
  }

  Future<void> _persistConnectionDiagnostic(
    BleConnectionDiagnosticEvent event,
  ) async {
    debugPrint('BLE_CONNECTION_DIAGNOSTIC ${jsonEncode(event.toJson())}');
    try {
      await _connectionDiagnosticSink?.record(event);
    } catch (error) {
      debugPrint(
        'BLE connection diagnostic persistence failed: ${error.runtimeType}',
      );
    }
  }

  @override
  Future<void> recordFailureDetails(ProvisioningException error) async {
    final failure = BleAttemptFailure(attemptId: _activeSecurityRequest ?? _publicPreparation?.id ?? 'repository')..capture(error, null, method: 'repository', expectedState: 'connected', currentState: 'failed');
    await _recordConnectionDiagnostic(eventType: 'attempt_failure_finalized', operationName: 'connection', failure: failure);
  }

  static String _resultCode(Object error) => switch (error) {
    ProvisioningException() => error.code.wireValue,
    _ => error.runtimeType.toString(),
  };
}

final class _PublicPreparation {
  _PublicPreparation(this.owner, this.id);
  final Object? owner;
  final String id;
  BlePairingStage stage = BlePairingStage.preparing;
  Object? error;
  final _cancelled = Completer<Object>();
  void cancel(Object cause) {
    error ??= cause;
    if (!_cancelled.isCompleted) _cancelled.complete(error!);
  }

  Future<T> wait<T>(Future<T> work) => Future.any([work, _cancelled.future.then<T>((cause) => throw cause)]);
}

final class _PublicRequest {
  _PublicRequest(this.request, this.deviceId, this.connectionGeneration, this.gattInstanceId) {
    unawaited(response.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  }
  final PairingPreflightRequest request;
  final String deviceId;
  final int connectionGeneration, gattInstanceId;
  final response = Completer<PairingPreflightResponse>();
}

final class _ExpectedReset {
  _ExpectedReset(this.connectionGeneration, this.gattInstanceId) {
    unawaited(disconnected.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  }
  final int connectionGeneration, gattInstanceId;
  final disconnected = Completer<void>();
}

final class _BleScanSessionBuilder {
  _BleScanSessionBuilder({
    required this.scanSessionId,
    this.flowId,
    this.scanTrigger,
    this.previousScanSessionId,
    required this.startedAt,
  });

  final String scanSessionId;
  final String? flowId, scanTrigger, previousScanSessionId;
  final DateTime startedAt;
  BleScanEnvironment environmentBefore = const BleScanEnvironment.unknown();
  BleScanEnvironment environmentAfter = const BleScanEnvironment.unknown();
  DateTime? nativeStartedAt;
  DateTime? firstRawResultAt;
  DateTime? firstCandidateAt;
  int rawResultCount = 0;
  int acceptedCount = 0;
  int filteredCount = 0;
  int? androidScanErrorCode;
  final Map<String, int> reasonCounts = {};
  final Set<String> uniqueAddressHashes = {};
  final List<BleScanObservationDiagnostic> observations = [];
  final List<BleScanStrategyDiagnostic> strategyEvents = [];

  static const int _maximumStoredObservations = 500;

  void observe({
    required DateTime at,
    required bool accepted,
    required String reason,
    required Map<String, dynamic> event,
  }) {
    firstRawResultAt ??= at;
    rawResultCount++;
    if (accepted) {
      acceptedCount++;
    } else {
      filteredCount++;
    }
    addReason(reason);
    final addressHash = event['addressHash'];
    if (addressHash is String && addressHash.isNotEmpty) {
      uniqueAddressHashes.add(addressHash);
    }
    if (observations.length >= _maximumStoredObservations) {
      addReason('diagnostic_observation_limit_reached');
      return;
    }
    final serviceUuids = event['serviceUuids'];
    observations.add(
      BleScanObservationDiagnostic(
        occurredAt: at,
        accepted: accepted,
        reasonCode: reason,
        addressHash: addressHash is String ? addressHash : null,
        name: event['diagnosticName'] as String?,
        alias: event['diagnosticAlias'] as String?,
        rssi: event['rssi'] as int?,
        serviceUuids: serviceUuids is List ? serviceUuids.whereType<String>().toList(growable: false) : const [],
        manufacturerDataPresent: event['manufacturerDataPresent'] as bool? ?? false,
        manufacturerDataLength: event['manufacturerDataLength'] as int? ?? 0,
        scanRecordLength: event['scanRecordLength'] as int?,
        scanRecordSha256: event['scanRecordSha256'] as String?,
        scanRecordRedactedHex: event['scanRecordRedactedHex'] as String?,
        scanRecordTruncated: event['scanRecordTruncated'] as bool? ?? false,
        strategyIndex: event['strategyIndex'] as int?,
        strategyName: event['strategyName'] as String?,
        strategyGeneration: event['strategyGeneration'] as int?,
        deviceNamePresent: event['deviceNamePresent'] as bool? ?? false,
      ),
    );
  }

  void observeStrategy({
    required DateTime at,
    required Map<String, dynamic> event,
  }) {
    final index = event['strategyIndex'];
    final name = event['strategyName'];
    final generation = event['strategyGeneration'];
    if (index is! int || name is! String || generation is! int) {
      addReason('invalid_strategy_diagnostic');
      return;
    }
    final errorCode = event['androidScanErrorCode'];
    if (errorCode is int) androidScanErrorCode = errorCode;
    strategyEvents.add(
      BleScanStrategyDiagnostic(
        occurredAt: at,
        event: event['strategyEvent'] as String? ?? 'unknown',
        index: index,
        name: name,
        generation: generation,
        switchReason: event['strategySwitchReason'] as String? ?? 'unknown',
        rawResultCount: event['strategyRawResultCount'] as int? ?? 0,
        deviceNameResultCount: event['strategyDeviceNameCount'] as int? ?? 0,
        candidateCount: event['strategyCandidateCount'] as int? ?? 0,
        locationService: BleScanEnvironment.fromPlatform({
          'locationService': event['locationService'],
        }).locationService,
        androidScanErrorCode: errorCode is int ? errorCode : null,
      ),
    );
  }

  void addReason(String reason) {
    reasonCounts.update(reason, (value) => value + 1, ifAbsent: () => 1);
  }

  BleScanDiagnosticSession complete({
    required DateTime endedAt,
    required BleScanEndReason endReason,
  }) => BleScanDiagnosticSession(
    scanSessionId: scanSessionId,
    flowId: flowId,
    scanTrigger: scanTrigger,
    previousScanSessionId: previousScanSessionId,
    startedAt: startedAt,
    nativeStartedAt: nativeStartedAt,
    firstRawResultAt: firstRawResultAt,
    firstCandidateAt: firstCandidateAt,
    endedAt: endedAt,
    permissionBefore: environmentBefore.permission,
    permissionAfter: environmentAfter.permission,
    adapterBefore: environmentBefore.adapter,
    adapterAfter: environmentAfter.adapter,
    scanPermissionBefore: environmentBefore.scanPermission,
    scanPermissionAfter: environmentAfter.scanPermission,
    connectPermissionBefore: environmentBefore.connectPermission,
    connectPermissionAfter: environmentAfter.connectPermission,
    locationPermissionBefore: environmentBefore.locationPermission,
    locationPermissionAfter: environmentAfter.locationPermission,
    locationServiceBefore: environmentBefore.locationService,
    locationServiceAfter: environmentAfter.locationService,
    locationRequiredByApp: environmentAfter.locationRequiredByApp ?? environmentBefore.locationRequiredByApp,
    locationPermissionRequiredByPlatform: environmentAfter.locationPermissionRequiredByPlatform ?? environmentBefore.locationPermissionRequiredByPlatform,
    locationRequiredForDeviceCompatibility: environmentAfter.locationRequiredForDeviceCompatibility ?? environmentBefore.locationRequiredForDeviceCompatibility,
    locationCompatibilityRule: environmentAfter.locationCompatibilityRule ?? environmentBefore.locationCompatibilityRule,
    manufacturer: environmentAfter.manufacturer ?? environmentBefore.manufacturer,
    model: environmentAfter.model ?? environmentBefore.model,
    androidRelease: environmentAfter.androidRelease ?? environmentBefore.androidRelease,
    sdkInt: environmentAfter.sdkInt ?? environmentBefore.sdkInt,
    packageId: environmentAfter.packageId ?? environmentBefore.packageId,
    buildFlavor: environmentAfter.buildFlavor ?? environmentBefore.buildFlavor,
    buildType: environmentAfter.buildType ?? environmentBefore.buildType,
    appVersionName: environmentAfter.appVersionName ?? environmentBefore.appVersionName,
    appVersionCode: environmentAfter.appVersionCode ?? environmentBefore.appVersionCode,
    gitCommit: environmentAfter.gitCommit ?? environmentBefore.gitCommit,
    buildDirty: environmentAfter.buildDirty ?? environmentBefore.buildDirty,
    buildId: environmentAfter.buildId ?? environmentBefore.buildId,
    sourceFingerprint: environmentAfter.sourceFingerprint ?? environmentBefore.sourceFingerprint,
    apkSha256: environmentAfter.apkSha256 ?? environmentBefore.apkSha256,
    scanPermissionPolicy: environmentAfter.scanPermissionPolicy ?? environmentBefore.scanPermissionPolicy,
    scanFlavor: environmentAfter.scanFlavor ?? environmentBefore.scanFlavor,
    scanStrategyFallbackEnabled: environmentAfter.scanStrategyFallbackEnabled || environmentBefore.scanStrategyFallbackEnabled,
    scanMode: environmentAfter.scanMode ?? environmentBefore.scanMode ?? 'low_latency',
    rawResultCount: rawResultCount,
    uniqueDeviceCount: uniqueAddressHashes.length,
    acceptedCount: acceptedCount,
    filteredCount: filteredCount,
    reasonCounts: Map.unmodifiable(reasonCounts),
    observations: List.unmodifiable(observations),
    strategyEvents: List.unmodifiable(strategyEvents),
    endReason: endReason,
    androidScanErrorCode: androidScanErrorCode,
  );
}

BirdBoxAdvertisement advertisementFromPlatform(Map<String, dynamic> raw) {
  final serviceUuidsRaw = raw['serviceUuids'];
  if (serviceUuidsRaw is! List) throw const ProvisioningProtocolException('serviceUuids', 'must be a list');
  final serviceUuids = serviceUuidsRaw.map((value) {
    if (value is! String) throw const ProvisioningProtocolException('serviceUuids', 'must contain strings');
    return value;
  });
  final localName = raw['localName'];
  final rssi = raw['rssi'];
  final platformDeviceId = raw['deviceId'];
  final companyIdentifier = raw['companyIdentifier'];
  final manufacturerPayload = raw['manufacturerPayload'];
  if (localName is! String) throw const ProvisioningProtocolException('localName', 'must be a string');
  if (rssi is! int) throw const ProvisioningProtocolException('rssi', 'must be an integer');
  if (platformDeviceId is! String || platformDeviceId.isEmpty) throw const ProvisioningProtocolException('deviceId', 'must be a non-empty string');
  if (companyIdentifier != null && companyIdentifier is! int) throw const ProvisioningProtocolException('companyIdentifier', 'must be an integer or null');
  if (manufacturerPayload != null && manufacturerPayload is! Uint8List) throw const ProvisioningProtocolException('manufacturerPayload', 'must contain bytes or null');
  return BirdBoxAdvertisement(
    localName: localName,
    serviceUuids: serviceUuids,
    rssi: rssi,
    platformDeviceId: platformDeviceId,
    companyIdentifier: companyIdentifier as int?,
    manufacturerPayload: manufacturerPayload as Uint8List?,
  );
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) throw ProvisioningProtocolException(key, 'must be a non-empty string');
  return value;
}
