import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';

/// Local provenance for a box error after command_accepted; no wire fields added.
final class BleOperationFailure implements Exception {
  const BleOperationFailure({required this.requestId, required this.deviceId, required this.error});
  final String requestId;
  final String deviceId;
  final ProvisioningException error;
  @override
  String toString() => 'BleOperationFailure(${error.code.wireValue})';
}

abstract interface class BirdBoxPairingPreparation {
  Future<ProvisioningDeviceInfo> prepareConnection(BirdBoxAdvertisement advertisement, {required String clientId});
}

/// Allows repository error cleanup to preserve a native release failure instead
/// of silently turning that cleanup into a user-authorized recovery attempt.
abstract interface class BleNativeReleaseState {
  bool get nativeReleaseBlocked;
}

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
