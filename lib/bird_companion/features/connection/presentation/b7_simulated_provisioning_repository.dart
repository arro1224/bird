import 'dart:async';

import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';

/// Deterministic repository used only by the B7 simulated acceptance page.
/// It exercises the same presentation contract as a real BirdBox transport.
final class B7SimulatedProvisioningRepository implements ProvisioningRepository, DppAvailabilityRepository, ProvisioningSessionRepository {
  B7SimulatedProvisioningRepository({
    Uri? baseUri,
    this.deviceId = simulatedBirdBoxDeviceId,
    DateTime Function()? clock,
  }) : baseUri = baseUri ?? simulatedBirdBoxBaseUri,
       _clock = clock ?? DateTime.now,
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
  final DateTime Function() _clock;
  DateTime? _windowExpiresAt;
  DateTime? _sessionExpiresAt;
  int _attempts = 0;
  int _operationSequence = 0;
  int _epoch = 0;
  bool _httpSessionUsed = false;
  String takePairingSessionForHttp() {
    _requireAuthorization();
    if (_httpSessionUsed) throw const ProvisioningException(code: ProvisioningErrorCode.pairingSessionUsed, retryable: false);
    _httpSessionUsed = true;
    return simulatedBirdBoxPairingSessionId;
  }

  String? _activeOperation;
  String _operation(String type) {
    final id = 'op_b7_${type}_${++_operationSequence}';
    _activeOperation = id;
    _networkStatus = ProvisioningNetworkStatus(
      activeMode: _networkStatus.activeMode,
      desiredMode: type == 'direct_ap' ? ProvisioningNetworkMode.directAp : ProvisioningNetworkMode.infrastructureSta,
      operationState: type == 'direct_ap'
          ? NetworkOperationState.startingAp
          : type == 'scan_wifi'
          ? NetworkOperationState.scanning
          : NetworkOperationState.connectingSta,
      operationId: id,
      busy: true,
      baseUri: _networkStatus.baseUri,
      directAp: _networkStatus.directAp,
      infrastructureSta: _networkStatus.infrastructureSta,
      updatedAt: _clock(),
    );
    return id;
  }

  void _requireAuthorization() {
    if (_connectedDeviceInfo == null || _sessionExpiresAt == null) {
      throw const ProvisioningException(code: ProvisioningErrorCode.authorizationRequired, retryable: false);
    }
    if (!_sessionExpiresAt!.isAfter(_clock())) {
      throw const ProvisioningException(code: ProvisioningErrorCode.pairingSessionExpired, retryable: false);
    }
  }

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
    _epoch++;
    _activeOperation = null;
    _sessionExpiresAt = null;
    _windowExpiresAt = null;
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
    if (_connectedDeviceInfo == null) throw const ProvisioningException(code: ProvisioningErrorCode.pairingNotOpen, retryable: false);
    if (_attempts == 0 && _windowExpiresAt?.isAfter(_clock()) == true) {
      throw const ProvisioningException(code: ProvisioningErrorCode.pairingRateLimited, retryable: true);
    }
    if (_windowExpiresAt?.isAfter(_clock()) != true) {
      _windowExpiresAt = _clock().add(const Duration(minutes: 2));
      _sessionExpiresAt = null;
      _attempts = 3;
    }
    return PairingWindow(
      mode: PairingCodeMode.fixedDev,
      codeExpiresIn: _windowExpiresAt!.difference(_clock()),
      attemptsRemaining: _attempts,
    );
  }

  @override
  Future<PairingAuthorization> authorizePairing(String pairingCode) async {
    calls.add('authorizePairing');
    final expiry = _windowExpiresAt;
    if (expiry == null) throw const ProvisioningException(code: ProvisioningErrorCode.pairingNotOpen, retryable: false);
    if (!expiry.isAfter(_clock())) throw const ProvisioningException(code: ProvisioningErrorCode.pairingCodeExpired, retryable: false);
    if (_attempts == 0) throw const ProvisioningException(code: ProvisioningErrorCode.pairingRateLimited, retryable: true);
    if (pairingCode.trim() != '123456') {
      _attempts--;
      throw const ProvisioningException(code: ProvisioningErrorCode.pairingCodeInvalid, retryable: true);
    }
    _windowExpiresAt = null;
    _sessionExpiresAt = _clock().add(const Duration(minutes: 2));
    _httpSessionUsed = false;
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
    _requireAuthorization();
    calls.add('startDirectAp');
    final operationId = _operation('direct_ap');
    final accepted = CommandAccepted(
      operationId: operationId,
      desiredMode: ProvisioningNetworkMode.directAp,
    );
    _emitLater(
      ProvisioningEvent(
        type: ProvisioningEventType.directApReady,
        requestId: 'request-b7-direct-ap',
        deviceId: _deviceInfo.deviceId,
        payload: DirectApReady.fromJson({
          'operation_id': operationId,
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
    _requireAuthorization();
    calls.add('stopDirectAp');
    final operationId = _operation('stop_ap');
    final accepted = CommandAccepted(operationId: operationId, desiredMode: ProvisioningNetworkMode.none);
    _emitLater(
      ProvisioningEvent(
        type: ProvisioningEventType.directApStopped,
        requestId: 'request-b7-stop-ap',
        deviceId: deviceId,
        payload: DirectApStopped(
          operationId: operationId,
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
    _requireAuthorization();
    calls.add('scanWifi');
    final accepted = CommandAccepted(operationId: _operation('scan_wifi'), desiredMode: ProvisioningNetworkMode.infrastructureSta);
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
    _requireAuthorization();
    calls.add('setStaConfig');
    final operationId = _operation('sta');
    _emitLater(
      ProvisioningEvent(
        type: ProvisioningEventType.staConnected,
        requestId: 'request-b7-sta',
        deviceId: _deviceInfo.deviceId,
        payload: StaConnected.fromJson({
          'operation_id': operationId,
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
    return CommandAccepted(operationId: operationId, desiredMode: ProvisioningNetworkMode.infrastructureSta);
  }

  @override
  Future<CommandAccepted> startDppProvisioning() async {
    _requireAuthorization();
    calls.add('startDppProvisioning');
    final operationId = _operation('dpp');
    final epoch = _epoch;
    final accepted = CommandAccepted(
      operationId: operationId,
      desiredMode: ProvisioningNetworkMode.infrastructureSta,
      provisioningMethod: ProvisioningMethod.androidDpp,
    );
    _emitLater(
      ProvisioningEvent(
        type: ProvisioningEventType.dppBootstrapReady,
        requestId: 'request-b7-dpp',
        deviceId: deviceId,
        payload: DppBootstrapReady.fromJson({
          'operation_id': operationId,
          'operation_state': 'waiting_dpp_configurator',
          'dpp_uri': 'DPP:K:SIMULATED_PUBLIC_KEY;M:001122334455;;',
          'expires_in_seconds': 120,
        }),
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 40), () {
      if (_disposed || epoch != _epoch || _activeOperation != operationId) return;
      _networkStatus = _staStatusFor(
        baseUri,
        provisioningMethod: ProvisioningMethod.androidDpp,
        operationId: operationId,
      );
      _events.add(
        ProvisioningEvent(
          type: ProvisioningEventType.staConnected,
          requestId: 'request-b7-dpp',
          deviceId: deviceId,
          payload: StaConnected.fromJson({
            'operation_id': operationId,
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
    _requireAuthorization();
    calls.add('cancelNetworkOperation:$operationId');
    return CommandAccepted(operationId: _operation('cancel'), desiredMode: ProvisioningNetworkMode.none);
  }

  void _emitLater(ProvisioningEvent event) {
    final epoch = _epoch;
    final operation = _activeOperation;
    Future<void>.delayed(const Duration(milliseconds: 1), () {
      if (_disposed || epoch != _epoch || operation != _activeOperation) return;
      if (event.payload is DirectApReady) _networkStatus = _directApStatusFor(baseUri, operationId: event.operationId!);
      if (event.payload case final StaConnected connected) {
        _networkStatus = _staStatusFor(baseUri, provisioningMethod: connected.provisioningMethod, operationId: connected.operationId);
      }
      if (event.payload is DirectApStopped) {
        _networkStatus = ProvisioningNetworkStatus(
          activeMode: ProvisioningNetworkMode.none,
          desiredMode: ProvisioningNetworkMode.none,
          operationState: NetworkOperationState.idle,
          operationId: event.operationId,
          busy: false,
          directAp: const DirectApSnapshot(),
          infrastructureSta: const InfrastructureStaSnapshot(saved: false),
          updatedAt: _clock(),
        );
      }
      _events.add(event);
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
  pairingCodeMode: PairingCodeMode.fixedDev,
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

ProvisioningNetworkStatus _directApStatusFor(Uri baseUri, {String operationId = 'op_b7_direct_ap'}) => ProvisioningNetworkStatus(
  activeMode: ProvisioningNetworkMode.directAp,
  desiredMode: ProvisioningNetworkMode.directAp,
  operationState: NetworkOperationState.apReady,
  operationId: operationId,
  busy: false,
  baseUri: baseUri,
  directAp: const DirectApSnapshot(ssid: 'BirdBox-B7B7B7B7', security: WifiSecurity.wpa2Personal, gatewayIpv4: '192.0.2.1', prefixLength: 24, clientCount: 1),
  infrastructureSta: const InfrastructureStaSnapshot(saved: true),
  updatedAt: DateTime.utc(2026, 8, 27),
);

ProvisioningNetworkStatus _staStatusFor(
  Uri baseUri, {
  required ProvisioningMethod provisioningMethod,
  String operationId = 'op_b7_sta',
}) => ProvisioningNetworkStatus(
  activeMode: ProvisioningNetworkMode.infrastructureSta,
  desiredMode: ProvisioningNetworkMode.infrastructureSta,
  operationState: NetworkOperationState.staConnected,
  operationId: operationId,
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
