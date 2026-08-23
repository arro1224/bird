import 'dart:async';

import 'package:aves/bird_companion/features/connection/data/ble/birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';

final class FakeBirdBoxBleDataSource implements BirdBoxBleDataSource {
  FakeBirdBoxBleDataSource({required this.deviceInfo, required this.networkStatus, Iterable<BirdBoxAdvertisement> advertisements = const []}) : _advertisements = List.of(advertisements);

  final ProvisioningDeviceInfo deviceInfo;
  ProvisioningNetworkStatus networkStatus;
  final List<BirdBoxAdvertisement> _advertisements;
  final Map<BleCommandType, List<ProvisioningEvent>> _responses = {};
  final StreamController<ProvisioningEvent> _eventController = StreamController.broadcast();
  final StreamController<void> _disconnectController = StreamController.broadcast();
  final List<BleCommandRequest> requests = [];

  bool _connected = false;
  bool _subscribed = false;
  bool _disposed = false;

  void addAdvertisement(BirdBoxAdvertisement advertisement) => _advertisements.add(advertisement);

  void queueResponse(BleCommandType type, ProvisioningEvent response) => _responses.putIfAbsent(type, () => []).add(response);

  void emitEvent(ProvisioningEvent event) => _eventController.add(event);

  void emitLateEvent(ProvisioningEvent event) => _eventController.add(event);

  void simulateDisconnect() {
    _connected = false;
    _subscribed = false;
    _disconnectController.add(null);
  }

  @override
  Stream<BirdBoxAdvertisement> scan({Duration? timeout}) async* {
    _ensureNotDisposed();
    for (final advertisement in _advertisements) {
      yield advertisement;
    }
  }

  @override
  Future<void> stopScan() async => _ensureNotDisposed();

  @override
  Future<void> connect(BirdBoxAdvertisement advertisement) async {
    _ensureNotDisposed();
    if (!advertisement.hasBirdBoxService) throw StateError('BirdBox Service UUID is required');
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _ensureNotDisposed();
    if (_connected) simulateDisconnect();
  }

  @override
  bool get isConnected => _connected;

  @override
  Future<ProvisioningDeviceInfo> readDeviceInfo() async {
    _ensureConnected();
    return deviceInfo;
  }

  @override
  Future<ProvisioningNetworkStatus> readNetworkStatus() async {
    _ensureConnected();
    return networkStatus;
  }

  @override
  Future<void> subscribeRequiredNotifications() async {
    _ensureConnected();
    _subscribed = true;
  }

  @override
  bool get requiredNotificationsSubscribed => _subscribed;

  @override
  Future<ProvisioningEvent> writeCommand(BleCommandRequest request) async {
    _ensureConnected();
    if (request.isAsynchronous && !_subscribed) throw StateError('Required notifications must be subscribed before asynchronous commands');
    requests.add(request);
    final queued = _responses[request.type];
    if (queued == null || queued.isEmpty) throw StateError('No fake response queued for ${request.type.wireValue}');
    return queued.removeAt(0);
  }

  @override
  Stream<ProvisioningEvent> get events => _eventController.stream;

  @override
  Stream<void> get disconnects => _disconnectController.stream;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _eventController.close();
    await _disconnectController.close();
  }

  void _ensureConnected() {
    _ensureNotDisposed();
    if (!_connected) throw StateError('Fake BLE is not connected');
  }

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('Fake BLE has been disposed');
  }
}
