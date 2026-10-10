import 'dart:async';
import 'package:aves/bird_companion/features/connection/domain/ble_pairing_progress.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_scan_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'fake_provisioning_repository.dart';

class ControlledProvisioningRepository extends FakeProvisioningRepository implements BleProvisioningControl {
  ControlledProvisioningRepository({super.devices, super.deviceInfo, super.pairingWindow, super.discoverError});
  Object? owner;
  int settingsCalls = 0, environmentReads = 0, endedSessions = 0;
  Object? settingsError;
  Completer<PairingWindow>? pendingPairing;
  Completer<void>? pendingEnd;
  BleScanEnvironment environment = const BleScanEnvironment(permission: BleScanPermissionState.granted, adapter: BleAdapterState.enabled, locationService: BleLocationServiceState.enabled);
  final progress = StreamController<BlePairingProgress>.broadcast(sync: true);
  @override
  Object claimSession() => owner = Object();
  @override
  bool ownsSession(Object candidate) => identical(owner, candidate);
  @override
  Future<void> endSession(Object candidate) async {
    if (!ownsSession(candidate)) return;
    if (pendingEnd != null) await pendingEnd!.future;
    if (!ownsSession(candidate)) return;
    endedSessions++;
    await stopDiscovery();
    await disconnect();
  }

  @override
  Future<void> pauseDiscovery(Object candidate) async {
    if (ownsSession(candidate)) await stopDiscovery();
  }

  @override
  Future<void> resumeDiscovery(Object candidate) async {}

  @override
  Future<void> openLocationSettings(Object candidate) async {
    if (!ownsSession(candidate)) return;
    settingsCalls++;
    if (settingsError != null) throw settingsError!;
  }

  @override
  Future<BleScanEnvironment> readScanEnvironment() async {
    environmentReads++;
    return environment;
  }

  @override
  Future<void> locationSettingsReturned(Object candidate, {required bool enabled}) async {}

  @override
  Stream<BlePairingProgress> get pairingProgress => progress.stream;
  @override
  Future<PairingWindow> openPairing() async {
    if (pendingPairing == null) return super.openPairing();
    calls.add('openPairing');
    return pendingPairing!.future;
  }

  @override
  Future<void> dispose() async {
    await progress.close();
    await super.dispose();
  }
}
