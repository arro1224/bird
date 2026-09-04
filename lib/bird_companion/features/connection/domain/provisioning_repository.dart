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

/// Optional production capability implemented by repositories that can merge
/// the authenticated BLE/box state with the current phone's DPP support.
abstract interface class DppAvailabilityRepository {
  Future<DppAvailability> checkDppAvailability();
}

/// Optional lifecycle view exposed by long-lived provisioning repositories.
///
/// Settings pages use it to inspect the currently trusted BLE peer and to
/// react to transport loss without cancelling an operation already accepted
/// by the box.
abstract interface class ProvisioningSessionRepository {
  ProvisioningDeviceInfo? get connectedDeviceInfo;
  Stream<void> get disconnects;
  bool get networkStatusResumeRequired;
}

/// Optional production verifier used before a status restored after BLE loss
/// is presented as a reachable terminal network.
abstract interface class ProvisioningNetworkStatusVerifier {
  Future<void> verifyNetworkStatus(ProvisioningNetworkStatus status);
}
