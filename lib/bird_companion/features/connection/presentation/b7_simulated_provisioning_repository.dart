import 'dart:async';

import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';

/// Deterministic repository used only by the B7 simulated acceptance page.
/// It exercises the same presentation contract as a real BirdBox transport.
final class B7SimulatedProvisioningRepository implements ProvisioningRepository, DppAvailabilityRepository, ProvisioningSessionRepository {
  B7SimulatedProvisioningRepository({
    Uri? baseUri,
    this.deviceId = simulatedBirdBoxDeviceId,
  }) : baseUri = baseUri ?? simulatedBirdBoxBaseUri,
       _networkStatus = _directApStatusFor(
         baseUri ?? simulatedBirdBoxBaseUri,
       ) {
    if (!RegExp(r'^bbx-[0-9a-f]{32}$').hasMatch(deviceId)) {
      throw ArgumentError.value(
        deviceId,
        'deviceId',
        'must match bbx- followed by 32 lowercase hex characters',
      );
    }
  }

  final Uri baseUri;
  final String deviceId;

  final _events = StreamController<ProvisioningEvent>.broadcast();
  final calls = <String>[];
  var _disposed = false;
  ProvisioningNetworkStatus _networkStatus;
  ProvisioningDeviceInfo? _connectedDeviceInfo;
  final _disconnects = StreamController<void>.broadcast();
  late final ProvisioningDeviceInfo _deviceInfo = _deviceInfoFor(deviceId);
  late final ProvisioningDevice _device = _deviceFor(_deviceInfo);

  @override
  ProvisioningDeviceInfo? get connectedDeviceInfo => _connectedDeviceInfo;

  @override
  Stream<void> get disconnects => _disconnects.stream;

  @override
  bool get networkStatusResumeRequired => false;

  @override
  Stream<ProvisioningDevice> discoverDevices({Duration? timeout}) async* {
    calls.add('discover');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (_disposed) return;
    yield _device;
  }

  @override
  Future<void> stopDiscovery() async => calls.add('stopDiscovery');

  @override
  Future<ProvisioningDeviceInfo> connect(ProvisioningDevice device) async {
    calls.add('connect:${device.scanId}');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    _connectedDeviceInfo = _deviceInfo;
    return _deviceInfo;
  }

  @override
  Future<void> disconnect() async {
    calls.add('disconnect');
    _connectedDeviceInfo = null;
    if (!_disposed) _disconnects.add(null);
  }

  @override
  Stream<ProvisioningEvent> get events => _events.stream;

  @override
  Future<DppAvailability> checkDppAvailability() async => const DppAvailability(
    boxSupported: true,
    apiLevelSupported: true,
    easyConnectSupported: true,
    activityAvailable: true,
    sessionReady: true,
  );

  @override
  Future<PairingWindow> openPairing() async {
    calls.add('openPairing');
    return const PairingWindow(
      mode: PairingCodeMode.sessionRandom,
      codeExpiresIn: Duration(minutes: 2),
      attemptsRemaining: 3,
    );
  }

  @override
  Future<PairingAuthorization> authorizePairing(String pairingCode) async {
    calls.add('authorizePairing');
    if (pairingCode.length != 6) throw StateError('demo pairing code must have six digits');
    return PairingAuthorization.fromJson(const {
      'pairing_session_id': simulatedBirdBoxPairingSessionId,
      'expires_in': 120,
    });
  }

  @override
  Future<ProvisioningNetworkStatus> getNetworkStatus() async {
    calls.add('getNetworkStatus');
    return _networkStatus;
  }

  @override
  Future<CommandAccepted> startDirectAp() async {
    calls.add('startDirectAp');
    const accepted = CommandAccepted(
      operationId: 'op_b7_direct_ap',
      desiredMode: ProvisioningNetworkMode.directAp,
    );
    _emitLater(
      ProvisioningEvent(
        type: ProvisioningEventType.directApReady,
        requestId: 'request-b7-direct-ap',
        deviceId: _deviceInfo.deviceId,
        payload: DirectApReady.fromJson({
          'operation_id': 'op_b7_direct_ap',
          'active_mode': 'direct_ap',
          'ssid': 'BirdBox-B7B7B7B7',
          'security': 'wpa2_personal',
          'passphrase': 'synthetic-only',
          'gateway_ipv4': '192.0.2.1',
          'prefix_length': 24,
          'base_uri': baseUri.toString(),
        }),
      ),
    );
    return accepted;
  }

  @override
  Future<CommandAccepted> stopDirectAp() async {
    calls.add('stopDirectAp');
    const accepted = CommandAccepted(operationId: 'op_b7_stop_ap', desiredMode: ProvisioningNetworkMode.none);
    _emitLater(
      ProvisioningEvent(
        type: ProvisioningEventType.directApStopped,
        requestId: 'request-b7-stop-ap',
        deviceId: deviceId,
        payload: const DirectApStopped(
          operationId: 'op_b7_stop_ap',
          activeMode: ProvisioningNetworkMode.none,
          operationState: NetworkOperationState.idle,
          restoredSta: false,
          reason: 'user_requested',
        ),
      ),
    );
    return accepted;
  }

  @override
  Future<CommandAccepted> scanWifi() async {
    calls.add('scanWifi');
    const accepted = CommandAccepted(operationId: 'op_b7_scan_wifi', desiredMode: ProvisioningNetworkMode.infrastructureSta);
    _emitLater(
      ProvisioningEvent(
        type: ProvisioningEventType.wifiScanResults,
        requestId: 'request-b7-scan-wifi',
        deviceId: _deviceInfo.deviceId,
        payload: WifiScanBatch.fromJson(const {
          'batch_index': 0,
          'batch_count': 1,
          'complete': true,
          'networks': [
            {
              'ssid': 'BirdLab-5G',
              'bssid': '02:00:00:00:00:07',
              'rssi_dbm': -38,
              'frequency_mhz': 5180,
              'security': 'wpa2_personal',
              'unsupported': false,
            },
          ],
        }),
      ),
    );
    return accepted;
  }

  @override
  Future<CommandAccepted> setStaConfig(StaNetworkConfiguration configuration) async {
    calls.add('setStaConfig');
    _networkStatus = _staStatusFor(
      baseUri,
      provisioningMethod: configuration.provisioningMethod,
    );
    _emitLater(
      ProvisioningEvent(
        type: ProvisioningEventType.staConnected,
        requestId: 'request-b7-sta',
        deviceId: _deviceInfo.deviceId,
        payload: StaConnected.fromJson({
          'operation_id': 'op_b7_sta',
          'active_mode': 'infrastructure_sta',
          'ssid': 'BirdLab-5G',
          'bssid': '02:00:00:00:00:07',
          'ipv4': '192.0.2.20',
          'prefix_length': 24,
          'gateway_ipv4': '192.0.2.1',
          'base_uri': baseUri.toString(),
          'network_kind': 'router',
          'provisioning_method': configuration.provisioningMethod.wireValue,
        }),
      ),
    );
    return const CommandAccepted(operationId: 'op_b7_sta', desiredMode: ProvisioningNetworkMode.infrastructureSta);
  }

  @override
  Future<CommandAccepted> startDppProvisioning() async {
    calls.add('startDppProvisioning');
    const accepted = CommandAccepted(
      operationId: 'op_b7_dpp',
      desiredMode: ProvisioningNetworkMode.infrastructureSta,
      provisioningMethod: ProvisioningMethod.androidDpp,
    );
    _networkStatus = _staStatusFor(
      baseUri,
      provisioningMethod: ProvisioningMethod.androidDpp,
    );
    _emitLater(
      ProvisioningEvent(
        type: ProvisioningEventType.dppBootstrapReady,
        requestId: 'request-b7-dpp',
        deviceId: deviceId,
        payload: DppBootstrapReady.fromJson(const {
          'operation_id': 'op_b7_dpp',
          'operation_state': 'waiting_dpp_configurator',
          'dpp_uri': 'DPP:K:SIMULATED_PUBLIC_KEY;M:001122334455;;',
          'expires_in_seconds': 120,
        }),
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 40), () {
      if (_disposed) return;
      _networkStatus = _staStatusFor(
        baseUri,
        provisioningMethod: ProvisioningMethod.androidDpp,
      );
      _events.add(
        ProvisioningEvent(
          type: ProvisioningEventType.staConnected,
          requestId: 'request-b7-dpp',
          deviceId: deviceId,
          payload: StaConnected.fromJson({
            'operation_id': 'op_b7_dpp',
            'active_mode': 'infrastructure_sta',
            'ssid': 'BirdLab-DPP',
            'bssid': '02:00:00:00:00:08',
            'ipv4': '192.0.2.21',
            'prefix_length': 24,
            'gateway_ipv4': '192.0.2.1',
            'base_uri': baseUri.toString(),
            'network_kind': 'router',
            'provisioning_method': 'android_dpp',
          }),
        ),
      );
    });
    return accepted;
  }

  @override
  Future<CommandAccepted> cancelNetworkOperation(String operationId) async {
    calls.add('cancelNetworkOperation:$operationId');
    return const CommandAccepted(operationId: 'op_b7_cancel', desiredMode: ProvisioningNetworkMode.none);
  }

  void _emitLater(ProvisioningEvent event) {
    Future<void>.delayed(const Duration(milliseconds: 1), () {
      if (!_disposed) _events.add(event);
    });
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _events.close();
    await _disconnects.close();
  }
}

final simulatedBirdBoxBaseUri = Uri.parse('http://127.0.0.1:8787');
const simulatedBirdBoxDeviceId = 'bbx-b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7';
const simulatedBirdBoxPairingSessionId = 'ps_mock_pairing_session';

ProvisioningDevice _deviceFor(ProvisioningDeviceInfo info) => ProvisioningDevice(
  scanId: 'demo-b7',
  advertisement: BirdBoxAdvertisement(
    localName: info.deviceName,
    serviceUuids: const {BleProtocolConstants.serviceUuid},
    rssi: -44,
  ),
);

ProvisioningDeviceInfo _deviceInfoFor(String deviceId) => ProvisioningDeviceInfo(
  protocolVersion: '1.0-rc4',
  minAppProtocolVersion: '1.0-rc4',
  deviceId: deviceId,
  deviceName: 'BirdBox-B7B7B7B7',
  firmwareVersion: '1.0.0-simulated',
  apiVersion: 'v1',
  pairingCodeMode: PairingCodeMode.sessionRandom,
  pairingCodeLength: 6,
  pairingCodeTtl: const Duration(minutes: 2),
  displayAvailable: false,
  capabilities: const DeviceCapabilities(
    directAp: true,
    infrastructureSta: true,
    wifiScan: true,
    wifiManual: true,
    dppEnrolleeSupported: true,
    dppSupportedAkm: {'psk'},
    modeSwitch: true,
    networkRecovery: true,
    bleFragmentationV1: true,
    wifiApStaConcurrency: false,
    apBand24Ghz: true,
    apBand5Ghz: true,
  ),
);

ProvisioningNetworkStatus _directApStatusFor(Uri baseUri) => ProvisioningNetworkStatus(
  activeMode: ProvisioningNetworkMode.directAp,
  desiredMode: ProvisioningNetworkMode.directAp,
  operationState: NetworkOperationState.apReady,
  operationId: 'op_b7_direct_ap',
  busy: false,
  baseUri: baseUri,
  directAp: const DirectApSnapshot(ssid: 'BirdBox-B7B7B7B7', security: WifiSecurity.wpa2Personal, gatewayIpv4: '192.0.2.1', prefixLength: 24, clientCount: 1),
  infrastructureSta: const InfrastructureStaSnapshot(saved: true),
  updatedAt: DateTime.utc(2026, 8, 27),
);

ProvisioningNetworkStatus _staStatusFor(
  Uri baseUri, {
  required ProvisioningMethod provisioningMethod,
}) => ProvisioningNetworkStatus(
  activeMode: ProvisioningNetworkMode.infrastructureSta,
  desiredMode: ProvisioningNetworkMode.infrastructureSta,
  operationState: NetworkOperationState.staConnected,
  operationId: 'op_b7_sta',
  busy: false,
  baseUri: baseUri,
  directAp: const DirectApSnapshot(),
  infrastructureSta: InfrastructureStaSnapshot(
    ssid: provisioningMethod == ProvisioningMethod.androidDpp ? 'BirdLab-DPP' : 'BirdLab-5G',
    ipv4: '192.0.2.20',
    prefixLength: 24,
    gatewayIpv4: '192.0.2.1',
    networkKind: StaNetworkKind.router,
    provisioningMethod: provisioningMethod,
    saved: true,
  ),
  updatedAt: DateTime.utc(2026, 8, 27),
);
