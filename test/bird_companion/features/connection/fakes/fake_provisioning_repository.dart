import 'dart:async';

import 'package:aves/bird_companion/features/connection/domain/ble_scan_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';

final class FakeStaConfigObservation {
  const FakeStaConfigObservation({
    required this.provisioningMethod,
    required this.selectionMethod,
    required this.hidden,
    required this.networkKind,
    required this.hasBssid,
    required this.passwordProvided,
  });

  final ProvisioningMethod provisioningMethod;
  final WifiSelectionMethod selectionMethod;
  final bool hidden;
  final StaNetworkKind networkKind;
  final bool hasBssid;
  final bool passwordProvided;
}

final class FakeProvisioningRepository implements ProvisioningRepository, DppAvailabilityRepository, ProvisioningSessionRepository, BleScanDiagnosticsRepository {
  FakeProvisioningRepository({
    Iterable<ProvisioningDevice> devices = const [],
    this.deviceInfo,
    this.pairingWindow,
    this.discoverError,
    this.connectError,
    this.openPairingError,
    this.authorizeError,
    this.networkStatus,
    this.startDirectApResult,
    this.stopDirectApResult,
    this.scanWifiResult,
    this.setStaConfigResult,
    this.startDppResult,
    this.cancelResult,
    this.networkStatusError,
    this.startDirectApError,
    this.stopDirectApError,
    this.scanWifiError,
    this.setStaConfigError,
    this.startDppError,
    this.cancelError,
    this.dppAvailability = const DppAvailability(
      boxSupported: true,
      apiLevelSupported: true,
      easyConnectSupported: true,
      activityAvailable: true,
      sessionReady: true,
    ),
    this.networkStatusResumeRequired = false,
  }) : _devices = List.of(devices);

  final List<ProvisioningDevice> _devices;
  final ProvisioningDeviceInfo? deviceInfo;
  final PairingWindow? pairingWindow;
  final Object? discoverError;
  final Object? connectError;
  final Object? openPairingError;
  final Object? authorizeError;
  ProvisioningNetworkStatus? networkStatus;
  final CommandAccepted? startDirectApResult;
  final CommandAccepted? stopDirectApResult;
  final CommandAccepted? scanWifiResult;
  final CommandAccepted? setStaConfigResult;
  final CommandAccepted? startDppResult;
  final CommandAccepted? cancelResult;
  final Object? networkStatusError;
  final Object? startDirectApError;
  final Object? stopDirectApError;
  final Object? scanWifiError;
  final Object? setStaConfigError;
  final Object? startDppError;
  final Object? cancelError;
  final DppAvailability dppAvailability;
  @override
  final bool networkStatusResumeRequired;
  final StreamController<ProvisioningEvent> _events = StreamController.broadcast();
  final StreamController<void> _disconnects = StreamController.broadcast();
  final StreamController<BleScanDiagnosticSession> _scanDiagnostics = StreamController.broadcast();
  final List<String> calls = [];
  FakeStaConfigObservation? lastStaObservation;
  ProvisioningDeviceInfo? _connectedDeviceInfo;

  @override
  ProvisioningDeviceInfo? get connectedDeviceInfo => _connectedDeviceInfo ?? deviceInfo;

  @override
  Stream<void> get disconnects => _disconnects.stream;

  @override
  Stream<BleScanDiagnosticSession> get scanDiagnostics => _scanDiagnostics.stream;

  @override
  Stream<ProvisioningDevice> discoverDevices({Duration? timeout}) {
    calls.add('discover');
    if (discoverError != null) return Stream.error(discoverError!);
    return Stream.fromIterable(_devices);
  }

  @override
  Future<void> stopDiscovery() async => calls.add('stopDiscovery');

  @override
  Future<ProvisioningDeviceInfo> connect(ProvisioningDevice device) async {
    calls.add('connect:${device.scanId}');
    if (connectError != null) throw connectError!;
    final info = deviceInfo ?? (throw StateError('deviceInfo must be configured'));
    _connectedDeviceInfo = info;
    return info;
  }

  @override
  Future<void> disconnect() async {
    calls.add('disconnect');
    _connectedDeviceInfo = null;
    if (!_disconnects.isClosed) _disconnects.add(null);
  }

  @override
  Stream<ProvisioningEvent> get events => _events.stream;

  @override
  Future<PairingWindow> openPairing() async {
    calls.add('openPairing');
    if (openPairingError != null) throw openPairingError!;
    return pairingWindow ?? (throw StateError('pairingWindow must be configured'));
  }

  @override
  Future<PairingAuthorization> authorizePairing(String pairingCode) async {
    calls.add('authorizePairing');
    if (authorizeError != null) throw authorizeError!;
    return PairingAuthorization.fromJson(const {
      'pairing_session_id': 'pairing-session-test',
      'expires_in': 60,
    });
  }

  @override
  Future<ProvisioningNetworkStatus> getNetworkStatus() async {
    calls.add('getNetworkStatus');
    if (networkStatusError != null) throw networkStatusError!;
    return networkStatus ?? (throw StateError('networkStatus must be configured'));
  }

  @override
  Future<CommandAccepted> startDirectAp() async {
    calls.add('startDirectAp');
    if (startDirectApError != null) throw startDirectApError!;
    return startDirectApResult ?? (throw StateError('startDirectApResult must be configured'));
  }

  @override
  Future<CommandAccepted> stopDirectAp() async {
    calls.add('stopDirectAp');
    if (stopDirectApError != null) throw stopDirectApError!;
    return stopDirectApResult ?? (throw StateError('stopDirectApResult must be configured'));
  }

  @override
  Future<CommandAccepted> scanWifi() async {
    calls.add('scanWifi');
    if (scanWifiError != null) throw scanWifiError!;
    return scanWifiResult ?? (throw StateError('scanWifiResult must be configured'));
  }

  @override
  Future<CommandAccepted> setStaConfig(StaNetworkConfiguration configuration) async {
    calls.add('setStaConfig');
    lastStaObservation = FakeStaConfigObservation(
      provisioningMethod: configuration.provisioningMethod,
      selectionMethod: configuration.selectionMethod,
      hidden: configuration.hidden,
      networkKind: configuration.networkKind,
      hasBssid: configuration.bssid != null,
      passwordProvided: configuration.password != null,
    );
    if (setStaConfigError != null) throw setStaConfigError!;
    return setStaConfigResult ?? (throw StateError('setStaConfigResult must be configured'));
  }

  @override
  Future<CommandAccepted> startDppProvisioning() async {
    calls.add('startDppProvisioning');
    if (startDppError != null) throw startDppError!;
    return startDppResult ?? (throw StateError('startDppResult must be configured'));
  }

  @override
  Future<DppAvailability> checkDppAvailability() async {
    calls.add('checkDppAvailability');
    return dppAvailability;
  }

  @override
  Future<CommandAccepted> cancelNetworkOperation(String operationId) async {
    calls.add('cancelNetworkOperation:$operationId');
    if (cancelError != null) throw cancelError!;
    return cancelResult ?? (throw StateError('cancelResult must be configured'));
  }

  void emitEvent(ProvisioningEvent event) => _events.add(event);

  void emitError(Object error) => _events.addError(error);

  void emitScanDiagnostic(BleScanDiagnosticSession diagnostic) => _scanDiagnostics.add(diagnostic);

  @override
  Future<void> dispose() async {
    await _events.close();
    await _disconnects.close();
    await _scanDiagnostics.close();
  }

  void emitDisconnect() {
    _connectedDeviceInfo = null;
    if (!_disconnects.isClosed) _disconnects.add(null);
  }
}
