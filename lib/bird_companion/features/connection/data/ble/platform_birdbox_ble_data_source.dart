import 'dart:async';
import 'dart:convert';

import 'package:aves/bird_companion/features/connection/data/ble/birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_fragment_codec.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_message_codec.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_scan_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract interface class BirdBoxBlePlatform {
  Stream<Map<String, dynamic>> get scanResults;
  Stream<Map<String, dynamic>> get notifications;
  Stream<BleDisconnectEvent> get disconnects;

  Future<BleScanEnvironment> readScanEnvironment();
  Future<bool> ensurePermissions();
  Future<void> startScan(
    Duration timeout, {
    required String scanSessionId,
  });
  Future<void> stopScan();
  Future<void> connect(String platformDeviceId);
  Future<void> disconnect();
  Future<int> requestMtu(int mtu);
  Future<Uint8List> readCharacteristic(String characteristicUuid);
  Future<void> setNotify(String characteristicUuid, {required bool enabled});
  Future<void> writeWithResponse(String characteristicUuid, Uint8List value);
  Future<bool> isLinkEncrypted();
  Future<void> dispose();
}

final class BleDisconnectEvent {
  const BleDisconnectEvent({required this.reason, required this.gattStatus, required this.unexpected});

  final String reason;
  final int gattStatus;
  final bool unexpected;

  @override
  String toString() => 'BleDisconnectEvent(reason: $reason, gattStatus: $gattStatus, unexpected: $unexpected)';
}

final class MethodChannelBirdBoxBlePlatform implements BirdBoxBlePlatform {
  MethodChannelBirdBoxBlePlatform()
    : _methodChannel = const MethodChannel(_methodChannelName),
      _scanResults = const EventChannel(_scanChannelName).receiveBroadcastStream().map(_eventMap).asBroadcastStream(),
      _notifications = const EventChannel(_notificationChannelName).receiveBroadcastStream().map(_eventMap).asBroadcastStream(),
      _disconnects = const EventChannel(_disconnectChannelName).receiveBroadcastStream().map(_disconnectEvent).asBroadcastStream();

  static const _methodChannelName = 'bird_companion/birdbox_ble/methods';
  static const _scanChannelName = 'bird_companion/birdbox_ble/scan';
  static const _notificationChannelName = 'bird_companion/birdbox_ble/notifications';
  static const _disconnectChannelName = 'bird_companion/birdbox_ble/disconnects';

  final MethodChannel _methodChannel;
  final Stream<Map<String, dynamic>> _scanResults;
  final Stream<Map<String, dynamic>> _notifications;
  final Stream<BleDisconnectEvent> _disconnects;

  @override
  Stream<Map<String, dynamic>> get scanResults => _scanResults;
  @override
  Stream<Map<String, dynamic>> get notifications => _notifications;
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
  Future<void> connect(String platformDeviceId) => _invoke<void>('connect', {'deviceId': platformDeviceId});

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
  Future<bool> isLinkEncrypted() async => (await _invoke<bool>('isLinkEncrypted')) ?? false;

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
    if (reason is! String || reason.isEmpty || gattStatus is! int || unexpected is! bool) {
      throw const ProvisioningProtocolException('platform_disconnect_event', 'contains invalid fields');
    }
    return BleDisconnectEvent(reason: reason, gattStatus: gattStatus, unexpected: unexpected);
  }

  static ProvisioningException _platformError(PlatformException error) {
    final details = error.details is Map ? Map<String, dynamic>.from(error.details as Map) : const <String, dynamic>{};
    final scanErrorCode = details['androidScanErrorCode'];
    final diagnosticSuffix = scanErrorCode is int ? ' (Android scan error $scanErrorCode)' : '';
    return ProvisioningException(
      code: switch (error.code) {
        'bluetooth_permission_denied' => ProvisioningErrorCode.bluetoothPermissionDenied,
        'ble_link_not_encrypted' => ProvisioningErrorCode.authorizationRequired,
        'invalid_request' || 'invalid_state' => ProvisioningErrorCode.invalidRequest,
        'bluetooth_unavailable' => ProvisioningErrorCode.capabilityUnsupported,
        _ => ProvisioningErrorCode.networkInternalError,
      },
      retryable: error.code == 'gatt_busy' || error.code == 'gatt_operation_failed',
      diagnosticMessage: 'Android BLE platform error: ${error.code}$diagnosticSuffix',
    );
  }
}

final class PlatformBirdBoxBleDataSource implements BirdBoxBleDataSource, BleScanDiagnosticSource {
  PlatformBirdBoxBleDataSource({
    BirdBoxBlePlatform? platform,
    this._diagnosticSink,
    DateTime Function()? clock,
    this._scanSessionIdFactory,
  }) : _platform = platform ?? MethodChannelBirdBoxBlePlatform(),
       _clock = clock ?? DateTime.now,
       _fragmentCodec = const BleFragmentCodec(),
       _messageCodec = const BleMessageCodec() {
    _notificationSubscription = _platform.notifications.listen(_handleNotification, onError: _events.addError);
    _disconnectSubscription = _platform.disconnects.listen(_handleDisconnect, onError: _disconnects.addError);
  }

  final BirdBoxBlePlatform _platform;
  final BleScanDiagnosticSink? _diagnosticSink;
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
  StreamSubscription<Map<String, dynamic>>? _scanSubscription;
  StreamController<BirdBoxAdvertisement>? _scanController;
  _BleScanSessionBuilder? _activeScanDiagnostic;
  Timer? _scanTimer;
  bool _connected = false;
  bool _requiredNotificationsSubscribed = false;
  bool _disposed = false;
  int _negotiatedMtu = 23;
  int _nextMessageId = 0;
  int _scanSessionSequence = 0;

  @override
  Stream<BirdBoxAdvertisement> scan({Duration? timeout}) {
    if (_disposed) return Stream.error(StateError('BLE data source is disposed'));
    if (_scanController != null) return Stream.error(StateError('BLE scan is already active'));
    final scanTimeout = timeout ?? const Duration(seconds: 10);
    final scanDiagnostic = _BleScanSessionBuilder(
      scanSessionId: _newScanSessionId(),
      startedAt: _clock(),
    );
    late final StreamController<BirdBoxAdvertisement> controller;
    controller = StreamController<BirdBoxAdvertisement>(
      onListen: () async {
        _activeScanDiagnostic = scanDiagnostic;
        try {
          scanDiagnostic.environmentBefore = await _readScanEnvironment();
          if (!await _platform.ensurePermissions()) {
            scanDiagnostic.environmentAfter = await _readScanEnvironment();
            throw _permissionDenied();
          }
          scanDiagnostic.environmentAfter = await _readScanEnvironment();
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
          scanDiagnostic.nativeStartedAt = _clock();
          _scanTimer = Timer(
            scanTimeout,
            () => unawaited(
              _finishScan(controller, reason: BleScanEndReason.timeout),
            ),
          );
        } catch (error, stackTrace) {
          controller.addError(error, stackTrace);
          await _finishScan(
            controller,
            reason: _endReasonFor(error, scanDiagnostic),
          );
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

    final acceptedField = event['accepted'];
    final accepted = acceptedField is bool ? acceptedField : true;
    final reason = event['decisionReason'] is String ? event['decisionReason'] as String : 'legacy_candidate';
    diagnostic?.observe(
      at: _clock(),
      accepted: accepted,
      reason: reason,
    );
    if (!accepted) return;

    try {
      final advertisement = advertisementFromPlatform(event);
      if (advertisement.hasBirdBoxService || advertisement.hasValidLocalName) {
        diagnostic?.firstCandidateAt ??= _clock();
        controller.add(advertisement);
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
      if (error.code == ProvisioningErrorCode.capabilityUnsupported || diagnostic.environmentAfter.adapter == BleAdapterState.disabled || diagnostic.environmentAfter.adapter == BleAdapterState.unavailable) {
        return BleScanEndReason.bluetoothUnavailable;
      }
    }
    return BleScanEndReason.platformError;
  }

  Future<void> _completeScanDiagnostic(BleScanEndReason reason) async {
    final builder = _activeScanDiagnostic;
    _activeScanDiagnostic = null;
    if (builder == null) return;
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
    if (!await _platform.ensurePermissions()) throw _permissionDenied();
    final platformDeviceId = advertisement.platformDeviceId;
    if (platformDeviceId == null || platformDeviceId.isEmpty) {
      throw const ProvisioningProtocolException('platform_device_id', 'scan result cannot be connected');
    }
    await stopScan();
    await _platform.connect(platformDeviceId);
    try {
      _negotiatedMtu = (await _platform.requestMtu(517)).clamp(23, 517);
    } catch (_) {
      await _platform.disconnect();
      rethrow;
    }
    _connected = true;
    _requiredNotificationsSubscribed = false;
  }

  @override
  Future<void> disconnect() async {
    if (!_connected) return;
    await _platform.disconnect();
    _markDisconnected();
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
  }

  @override
  bool get requiredNotificationsSubscribed => _requiredNotificationsSubscribed;

  @override
  Future<ProvisioningEvent> writeCommand(BleCommandRequest request) async {
    _checkConnected();
    if (!_requiredNotificationsSubscribed) throw StateError('Required BLE notifications must be subscribed before commands are sent');
    if (_pendingCommands.containsKey(request.requestId)) {
      throw const ProvisioningException(code: ProvisioningErrorCode.requestIdConflict, retryable: false);
    }
    if ((request.writesWifiCredentials || request.payload.containsKey('authorization')) && !await _platform.isLinkEncrypted()) {
      throw const ProvisioningException(code: ProvisioningErrorCode.authorizationRequired, retryable: false, diagnosticMessage: 'Sensitive BLE write requires a bonded encrypted link');
    }

    final message = _messageCodec.encodeRequest(request);
    List<Uint8List> packets = const [];
    final completer = Completer<ProvisioningEvent>();
    _pendingCommands[request.requestId] = completer;
    try {
      final characteristicUuid = request.writesWifiCredentials ? BleProtocolConstants.wifiConfigCharacteristicUuid : BleProtocolConstants.provisioningCommandCharacteristicUuid;
      final maximumFragmentBytes = (_negotiatedMtu - 3).clamp(BleProtocolConstants.fragmentHeaderLength + 1, 514);
      packets = _fragmentCodec.fragment(message, messageId: _allocateMessageId(), maximumFragmentBytes: maximumFragmentBytes);
      for (final packet in packets) {
        await _platform.writeWithResponse(characteristicUuid, packet);
      }
      return await completer.future.timeout(
        BleProtocolConstants.commandResponseTimeout,
        onTimeout: () => throw const ProvisioningException(code: ProvisioningErrorCode.networkInternalError, retryable: true, diagnosticMessage: 'BLE command response timed out'),
      );
    } finally {
      message.fillRange(0, message.length, 0);
      for (final packet in packets) {
        packet.fillRange(0, packet.length, 0);
      }
      _pendingCommands.remove(request.requestId);
    }
  }

  int _allocateMessageId() {
    final value = _nextMessageId;
    _nextMessageId = (_nextMessageId + 1) & 0xFFFF;
    return value;
  }

  void _handleNotification(Map<String, dynamic> raw) {
    try {
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
    if (!_connected) return;
    _markDisconnected(event?.reason ?? 'unknown');
    _disconnects.add(null);
  }

  void _markDisconnected([String reason = 'unknown']) {
    _connected = false;
    _requiredNotificationsSubscribed = false;
    for (final reassembler in _notificationReassemblers.values) {
      reassembler.reset();
    }
    _notificationReassemblers.clear();
    final error = ProvisioningException(code: ProvisioningErrorCode.networkInternalError, retryable: true, diagnosticMessage: 'BLE disconnected before the command response: $reason');
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
    if (_connected) await _platform.disconnect();
    _markDisconnected();
    await _notificationSubscription.cancel();
    await _disconnectSubscription.cancel();
    await _platform.dispose();
    await _events.close();
    await _disconnects.close();
    await _scanDiagnostics.close();
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('BLE data source is disposed');
  }

  void _checkConnected() {
    _checkNotDisposed();
    if (!_connected) throw StateError('BirdBox GATT is not connected');
  }

  static ProvisioningException _permissionDenied() => const ProvisioningException(code: ProvisioningErrorCode.bluetoothPermissionDenied, retryable: false);
}

final class _BleScanSessionBuilder {
  _BleScanSessionBuilder({
    required this.scanSessionId,
    required this.startedAt,
  });

  final String scanSessionId;
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

  void observe({
    required DateTime at,
    required bool accepted,
    required String reason,
  }) {
    firstRawResultAt ??= at;
    rawResultCount++;
    if (accepted) {
      acceptedCount++;
    } else {
      filteredCount++;
    }
    addReason(reason);
  }

  void addReason(String reason) {
    reasonCounts.update(reason, (value) => value + 1, ifAbsent: () => 1);
  }

  BleScanDiagnosticSession complete({
    required DateTime endedAt,
    required BleScanEndReason endReason,
  }) => BleScanDiagnosticSession(
    scanSessionId: scanSessionId,
    startedAt: startedAt,
    nativeStartedAt: nativeStartedAt,
    firstRawResultAt: firstRawResultAt,
    firstCandidateAt: firstCandidateAt,
    endedAt: endedAt,
    permissionBefore: environmentBefore.permission,
    permissionAfter: environmentAfter.permission,
    adapterBefore: environmentBefore.adapter,
    adapterAfter: environmentAfter.adapter,
    rawResultCount: rawResultCount,
    acceptedCount: acceptedCount,
    filteredCount: filteredCount,
    reasonCounts: Map.unmodifiable(reasonCounts),
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
