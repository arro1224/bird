import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';

abstract interface class BirdBoxBleDataSource {
  Stream<BirdBoxAdvertisement> scan({Duration? timeout});
  Future<void> stopScan();
  Future<void> connect(BirdBoxAdvertisement advertisement);
  Future<void> disconnect();
  bool get isConnected;

  Future<ProvisioningDeviceInfo> readDeviceInfo();
  Future<ProvisioningNetworkStatus> readNetworkStatus();
  Future<void> subscribeRequiredNotifications();
  bool get requiredNotificationsSubscribed;

  Future<ProvisioningEvent> writeCommand(BleCommandRequest request);
  Stream<ProvisioningEvent> get events;
  Stream<void> get disconnects;

  Future<void> dispose();
}
