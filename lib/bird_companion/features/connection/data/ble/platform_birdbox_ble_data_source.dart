import 'dart:async';

import 'package:aves/bird_companion/features/connection/data/ble/birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_fragment_codec.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_message_codec.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:flutter/services.dart';

abstract interface class BirdBoxBlePlatform {
  Stream<Map<String, dynamic>> get scanResults;
  Stream<Map<String, dynamic>> get notifications;
  Stream<void> get disconnects;

  Future<bool> ensurePermissions();
  Future<void> startScan(Duration timeout);
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

final class MethodChannelBirdBoxBlePlatform implements BirdBoxBlePlatform {
  MethodChannelBirdBoxBlePlatform()
    : _methodChannel = const MethodChannel(_methodChannelName),
      _scanResults = const EventChannel(_scanChannelName).receiveBroadcastStream().map(_eventMap).asBroadcastStream(),
      _notifications = const EventChannel(_notificationChannelName).receiveBroadcastStream().map(_eventMap).asBroadcastStream(),
      _disconnects = const EventChannel(_disconnectChannelName).receiveBroadcastStream().map((_) {}).asBroadcastStream();

  static const _methodChannelName = 'bird_companion/birdbox_ble/methods';
  static const _scanChannelName = 'bird_companion/birdbox_ble/scan';
  static const _notificationChannelName = 'bird_companion/birdbox_ble/notifications';
  static const _disconnectChannelName = 'bird_companion/birdbox_ble/disconnects';

  final MethodChannel _methodChannel;
  final Stream<Map<String, dynamic>> _scanResults;
  final Stream<Map<String, dynamic>> _notifications;
  final Stream<void> _disconnects;

  @override
  Stream<Map<String, dynamic>> get scanResults => _scanResults;
  @override
  Stream<Map<String, dynamic>> get notifications => _notifications;
  @override
  Stream<void> get disconnects => _disconnects;

  @override
  Future<bool> ensurePermissions() async => (await _invoke<bool>('ensurePermissions')) ?? false;

  @override
  Future<void> startScan(Duration timeout) => _invoke<void>('startScan', {'timeoutMs': timeout.inMilliseconds});

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
      throw _platformError(error.code);
    }
  }

  static Map<String, dynamic> _eventMap(Object? event) {
    if (event is! Map) throw const ProvisioningProtocolException('platform_event', 'must be a map');
    return Map<String, dynamic>.from(event);
  }

  static ProvisioningException _platformError(String code) => ProvisioningException(
    code: switch (code) {
      'bluetooth_permission_denied' => ProvisioningErrorCode.bluetoothPermissionDenied,
      'ble_link_not_encrypted' => ProvisioningErrorCode.authorizationRequired,
      'invalid_request' || 'invalid_state' => ProvisioningErrorCode.invalidRequest,
      _ => ProvisioningErrorCode.networkInternalError,
    },
    retryable: code == 'gatt_busy' || code == 'gatt_operation_failed',
    diagnosticMessage: 'Android BLE platform error: $code',
  );
}

final class PlatformBirdBoxBleDataSource implements BirdBoxBleDataSource {
  PlatformBirdBoxBleDataSource({BirdBoxBlePlatform? platform}) : _platform = platform ?? MethodChannelBirdBoxBlePlatform(), _fragmentCodec = const BleFragmentCodec(), _messageCodec = const BleMessageCodec() {
    _notificationSubscription = _platform.notifications.listen(_handleNotification, onError: _events.addError);
    _disconnectSubscription = _platform.disconnects.listen((_) => _handleDisconnect(), onError: _disconnects.addError);
  }

  final BirdBoxBlePlatform _platform;
  final BleFragmentCodec _fragmentCodec;
  final BleMessageCodec _messageCodec;
  final StreamController<ProvisioningEvent> _events = StreamController<ProvisioningEvent>.broadcast(sync: true);
  final StreamController<void> _disconnects = StreamController<void>.broadcast(sync: true);
  final Map<String, BleFragmentReassembler> _notificationReassemblers = {};
  final Map<String, Completer<ProvisioningEvent>> _pendingCommands = {};

  late final StreamSubscription<Map<String, dynamic>> _notificationSubscription;
  late final StreamSubscription<void> _disconnectSubscription;
  StreamSubscription<Map<String, dynamic>>? _scanSubscription;
  StreamController<BirdBoxAdvertisement>? _scanController;
  Timer? _scanTimer;
  bool _connected = false;
  bool _requiredNotificationsSubscribed = false;
  bool _disposed = false;
  int _negotiatedMtu = 23;
  int _nextMessageId = 0;

  @override
  Stream<BirdBoxAdvertisement> scan({Duration? timeout}) {
    if (_disposed) return Stream.error(StateError('BLE data source is disposed'));
    if (_scanController != null) return Stream.error(StateError('BLE scan is already active'));
    final scanTimeout = timeout ?? const Duration(seconds: 10);
    late final StreamController<BirdBoxAdvertisement> controller;
    controller = StreamController<BirdBoxAdvertisement>(
      onListen: () async {
        try {
          if (!await _platform.ensurePermissions()) throw _permissionDenied();
          _scanSubscription = _platform.scanResults.listen(
            (event) {
              try {
                final advertisement = advertisementFromPlatform(event);
                if (advertisement.hasBirdBoxService || advertisement.hasValidLocalName) controller.add(advertisement);
              } catch (error, stackTrace) {
                controller.addError(error, stackTrace);
              }
            },
            onError: controller.addError,
          );
          await _platform.startScan(scanTimeout);
          _scanTimer = Timer(scanTimeout, () => _finishScan(controller));
        } catch (error, stackTrace) {
          controller.addError(error, stackTrace);
          await _finishScan(controller);
        }
      },
      onCancel: () => _finishScan(controller),
    );
    _scanController = controller;
    return controller.stream;
  }

  @override
  Future<void> stopScan() async {
    final controller = _scanController;
    if (controller != null) await _finishScan(controller);
  }

  Future<void> _finishScan(StreamController<BirdBoxAdvertisement> controller) async {
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
    if (!controller.isClosed) await controller.close();
  }

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
      final packet = await _platform.readCharacteristic(characteristicUuid);
      final message = reassembler.add(packet);
      if (message != null) return message;
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

  void _handleDisconnect() {
    if (!_connected) return;
    _markDisconnected();
    _disconnects.add(null);
  }

  void _markDisconnected() {
    _connected = false;
    _requiredNotificationsSubscribed = false;
    for (final reassembler in _notificationReassemblers.values) {
      reassembler.reset();
    }
    _notificationReassemblers.clear();
    const error = ProvisioningException(code: ProvisioningErrorCode.networkInternalError, retryable: true, diagnosticMessage: 'BLE disconnected before the command response');
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
    await stopScan();
    if (_connected) await _platform.disconnect();
    _markDisconnected();
    await _notificationSubscription.cancel();
    await _disconnectSubscription.cancel();
    await _platform.dispose();
    await _events.close();
    await _disconnects.close();
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
