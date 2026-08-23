import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';

/// The sole boundary used by presentation code for rc4 provisioning.
///
/// Implementations own client/request identifiers, authorization material,
/// retries and filtering stale operation events. Presentation must not call
/// Android MethodChannels or BLE data sources directly.
abstract interface class ProvisioningRepository {
  Stream<ProvisioningDevice> discoverDevices({Duration? timeout});
  Future<void> stopDiscovery();
  Future<ProvisioningDeviceInfo> connect(ProvisioningDevice device);
  Future<void> disconnect();

  Stream<ProvisioningEvent> get events;

  Future<PairingWindow> openPairing();
  Future<PairingAuthorization> authorizePairing(String pairingCode);
  Future<ProvisioningNetworkStatus> getNetworkStatus();
  Future<CommandAccepted> startDirectAp();
  Future<CommandAccepted> stopDirectAp();
  Future<CommandAccepted> scanWifi();
  Future<CommandAccepted> setStaConfig(StaNetworkConfiguration configuration);
  Future<CommandAccepted> startDppProvisioning();
  Future<CommandAccepted> cancelNetworkOperation(String operationId);

  Future<void> dispose();
}
