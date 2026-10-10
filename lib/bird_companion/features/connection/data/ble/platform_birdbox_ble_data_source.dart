import 'package:aves/bird_companion/features/connection/domain/ble_pairing_progress.dart';
import 'dart:async';
import 'dart:convert';

import 'package:aves/bird_companion/features/connection/data/ble/birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_fragment_codec.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_message_codec.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
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

final class MethodChannelBirdBoxBlePlatform implements BirdBoxBlePlatform, BirdBoxPairingPlatform {
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
      for (final key in const ['systemBondAttempted', 'bondInitiationSource', 'createBondCallCount', 'bondElapsedMs', 'securityWriteAttemptCount', 'securityWriteResult', 'thread', 'callSource', 'teardownReason'])
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
        'bond_lost' => ProvisioningErrorCode.bleBondLost,
        'bond_state_unknown' => ProvisioningErrorCode.bleBondStateUnknown,
        'location_settings_unavailable' => ProvisioningErrorCode.locationSettingsUnavailable,
        'gatt_busy' => ProvisioningErrorCode.bleOperationBusy,
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
        'bond_start_failed',
        'bond_timeout',
        'bond_rejected',
        'bond_lost',
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

final class PlatformBirdBoxBleDataSource implements BirdBoxBleDataSource, BleScanDiagnosticSource, BleProvisioningControl {
  PlatformBirdBoxBleDataSource({
    BirdBoxBlePlatform? platform,
    this._diagnosticSink,
    this._connectionDiagnosticSink,
    DateTime Function()? clock,
    this._scanSessionIdFactory,
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
  final BleScanDiagnosticSink? _diagnosticSink;
  final BleConnectionDiagnosticSink? _connectionDiagnosticSink;
  final DateTime Function() _clock;
  final String Function()? _scanSessionIdFactory;
  final BleFragmentCodec _fragmentCodec;
  final BleMessageCodec _messageCodec;
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
  bool _disposed = false;
  Future<void>? _disconnectFuture;
  BleDisconnectEvent? _connectInterruptedBy;
  final List<BleDisconnectEvent> _deferredConnectDisconnects = [];
  int _negotiatedMtu = 23;
  int _nextMessageId = 0;
  int _scanSessionSequence = 0;
  int? _activeConnectionGeneration;
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
  bool _nativePreparationStarted = false;
  BlePairingReady? _pairingReady;
  int? _activeGattGeneration;
  final _pairingProgress = StreamController<BlePairingProgress>.broadcast(sync: true);
  @override
  Object claimSession() {
    _flowId = 'flow-${_clock().microsecondsSinceEpoch}-${_scanSessionSequence++}';
    _nextScanTrigger = 'user_scan';
    return _sessionOwner = Object();
  }

  @override
  bool ownsSession(Object owner) => identical(owner, _sessionOwner) && !_disposed;
  @override
  Future<void> endSession(Object owner) async {
    if (!ownsSession(owner)) return;
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
    if (ownsSession(owner)) _discoveryPaused = false;
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
    if (_disposed) return Stream.error(StateError('BLE data source is disposed'));
    if (_scanController != null) return Stream.error(StateError('BLE scan is already active'));
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
    if (_connectInProgress) {
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
      await _teardownPlatformSession(reason: 'pre_connect_reset');
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
      } catch (error) {
        await _recordConnectionDiagnostic(
          eventType: 'connect_failed',
          operationName: 'connect',
          resultCode: _resultCode(error),
        );
        try {
          await _teardownPlatformSession(reason: 'connect_failed');
        } catch (cleanupError) {
          await _recordConnectionDiagnostic(
            eventType: 'teardown_failed',
            operationName: 'disconnect',
            resultCode: _resultCode(cleanupError),
          );
        }
        rethrow;
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
      await _recordConnectionDiagnostic(
        eventType: 'teardown_completed',
        operationName: 'disconnect',
        resultCode: reason,
      );
    }
  }

  @override
  bool get isConnected => _connected;

  @override
  Future<ProvisioningDeviceInfo> readDeviceInfo() async {
    final message = await _readMessage(BleProtocolConstants.deviceInfoCharacteristicUuid);
    try {
      return _messageCodec.decodeDeviceInfo(message);
    } finally {
      message.fillRange(0, message.length, 0);
    }
  }

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
    try {
      await _platform.setNotify(BleProtocolConstants.scanResultsCharacteristicUuid, enabled: true);
    } catch (_) {
      await _platform.setNotify(BleProtocolConstants.networkStatusCharacteristicUuid, enabled: false);
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

  @override
  Future<ProvisioningEvent> writeCommand(BleCommandRequest request) async {
    _checkConnected();
    if (!_requiredNotificationsSubscribed) throw StateError('Required BLE notifications must be subscribed before commands are sent');
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
    try {
      await _recordConnectionDiagnostic(eventType: 'command_started', operationName: 'write_command', commandType: request.type.wireValue, requestId: request.requestId);
      if (commandEpoch != _transportEpoch || !_connected || _disposed) throw const ProvisioningException(code: ProvisioningErrorCode.bleGattOperationFailed, retryable: true);
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
      final maximumFragmentBytes = (_negotiatedMtu - 3).clamp(BleProtocolConstants.fragmentHeaderLength + 1, 514);
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
          packets = _fragmentCodec.fragment(message, messageId: messageId, maximumFragmentBytes: (_negotiatedMtu - 3).clamp(BleProtocolConstants.fragmentHeaderLength + 1, 514));
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
      await _platform.completeSecurityWrite(
        request.requestId,
        responseType: response.type.wireValue,
      );
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
    } catch (error) {
      if (securitySessionStarted) {
        try {
          await _platform.failSecurityWrite(
            request.requestId,
            errorCode: error is ProvisioningException ? error.code.wireValue.toLowerCase() : 'ble_gatt_operation_failed',
          );
        } catch (cleanupError) {
          await _recordConnectionDiagnostic(
            eventType: 'security_cleanup_failed',
            operationName: 'security_write',
            commandType: request.type.wireValue,
            requestId: request.requestId,
            resultCode: _resultCode(error),
            errorCode: _resultCode(cleanupError),
            terminalOutcome: _resultCode(error),
            cleanupOutcome: 'failed',
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
      );
      rethrow;
    } finally {
      message.fillRange(0, message.length, 0);
      for (final packet in packets) {
        packet.fillRange(0, packet.length, 0);
      }
      if (identical(_pendingCommands[request.requestId], completer)) _pendingCommands.remove(request.requestId);
      if (_activeSecurityRequest == request.requestId) {
        _activeSecurityRequest = null;
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
        if (gattRebuilt) _negotiatedMtu = await platform.requestMtu(517);
        await subscribeRequiredNotifications();
      }
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
        final response = _messageCodec.decodeResponse(message);
        if (response is BleFailureResponse) {
          final pending = _pendingCommands[response.requestId];
          if (pending != null && !pending.isCompleted) {
            pending.completeError(response.error);
          } else {
            _events.addError(response.error);
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

  void _handleDisconnect([BleDisconnectEvent? event]) {
    final eventGeneration = event?.connectionGeneration;
    final activeGeneration = _activeConnectionGeneration;
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
    if (wasConnected) _disconnects.add(null);
  }

  void _markDisconnected([String reason = 'unknown']) {
    _connected = false;
    _activeConnectionGeneration = null;
    _activeGattGeneration = null;
    _negotiatedMtu = 23;
    _requiredNotificationsSubscribed = false;
    for (final reassembler in _notificationReassemblers.values) {
      reassembler.reset();
    }
    _notificationReassemblers.clear();
    final error = ProvisioningException(code: ProvisioningErrorCode.bleGattOperationFailed, retryable: true, diagnosticMessage: 'BLE disconnected before the command response: $reason');
    for (final completer in _pendingCommands.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pendingCommands.clear();
    // No cancel command is sent: accepted box-side network operations continue.
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
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
    if (_disposed) throw StateError('BLE data source is disposed');
  }

  void _checkConnected() {
    _checkNotDisposed();
    if (!_connected) throw StateError('BirdBox GATT is not connected');
  }

  static ProvisioningException _permissionDenied() => const ProvisioningException(code: ProvisioningErrorCode.bluetoothPermissionDenied, retryable: false);

  void _handleNativeDiagnostic(Map<String, dynamic> value) {
    try {
      final event = BleConnectionDiagnosticEvent.fromPlatform({...value, 'flowId': _traceFlowIds[value['traceId']]});
      _activeTraceId ??= event.traceId;
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
  }) async {
    final traceId = _activeTraceId ?? _lastTraceId;
    if (traceId == null) return;
    await _persistConnectionDiagnostic(
      BleConnectionDiagnosticEvent(
        traceId: traceId,
        flowId: _traceFlowIds[traceId],
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
        errorCode: errorCode,
        terminalOutcome: terminalOutcome,
        cleanupOutcome: cleanupOutcome,
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

  static String _resultCode(Object error) => switch (error) {
    ProvisioningException() => error.code.wireValue,
    _ => error.runtimeType.toString(),
  };
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
