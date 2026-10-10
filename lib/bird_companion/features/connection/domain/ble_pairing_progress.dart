import 'package:aves/bird_companion/features/connection/domain/ble_scan_diagnostics.dart';

enum BlePairingStage { preparing, systemBond, reconnecting, restoringNotifications, writing, retrying, waitingResponse }

final class BlePairingProgress {
  const BlePairingProgress({required this.requestId, required this.stage, this.attemptId, this.connectionGeneration});
  final String requestId;
  final BlePairingStage stage;
  final String? attemptId;
  final int? connectionGeneration;
}

/// App-only ownership and presentation capabilities; never part of box RC4.
abstract interface class BleProvisioningControl {
  Object claimSession();
  bool ownsSession(Object owner);
  Future<void> endSession(Object owner);
  Future<void> pauseDiscovery(Object owner);
  Future<void> resumeDiscovery(Object owner);
  Future<void> openLocationSettings(Object owner);
  Future<void> locationSettingsReturned(Object owner, {required bool enabled});
  Future<BleScanEnvironment> readScanEnvironment();
  Stream<BlePairingProgress> get pairingProgress;
}
