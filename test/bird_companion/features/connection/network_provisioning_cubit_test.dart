import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/presentation/network_provisioning_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_provisioning_repository.dart';

void main() {
  group('NetworkProvisioningCubit direct AP', () {
    test('gates unsupported direct AP without issuing a command', () async {
      final repository = FakeProvisioningRepository();
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);

      await cubit.startDirectAp(_deviceInfo(directAp: false));

      expect(cubit.state.phase, NetworkProvisioningPhase.methodUnavailable);
      expect(repository.calls, isNot(contains('startDirectAp')));
    });

    test('starts direct AP once and tracks the accepted operation', () async {
      final repository = FakeProvisioningRepository(
        startDirectApResult: const CommandAccepted(
          operationId: 'op_direct',
          desiredMode: ProvisioningNetworkMode.directAp,
        ),
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);

      await cubit.startDirectAp(_deviceInfo());

      expect(cubit.state.phase, NetworkProvisioningPhase.startingDirectAp);
      expect(cubit.state.activeOperationId, 'op_direct');
      expect(
        repository.calls.where((call) => call == 'startDirectAp'),
        hasLength(1),
      );
    });

    test(
      'ignores stale events and confirms matching Direct AP readiness',
      () async {
        final repository = FakeProvisioningRepository(
          startDirectApResult: const CommandAccepted(
            operationId: 'op_direct',
            desiredMode: ProvisioningNetworkMode.directAp,
          ),
          networkStatus: _networkStatus(
            mode: ProvisioningNetworkMode.directAp,
            operationState: NetworkOperationState.apReady,
            operationId: 'op_direct',
            baseUri: Uri.parse('http://192.168.8.1'),
          ),
        );
        final cubit = NetworkProvisioningCubit(repository);
        addTearDown(cubit.close);
        await cubit.startDirectAp(_deviceInfo());

        repository.emitEvent(
          _directApReady(
            deviceId: 'bbx-ffffffffffffffffffffffffffffffff',
            operationId: 'op_direct',
          ),
        );
        repository.emitEvent(
          _directApReady(
            deviceId: _deviceInfo().deviceId,
            operationId: 'op_stale',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(cubit.state.phase, NetworkProvisioningPhase.startingDirectAp);
        expect(repository.calls, isNot(contains('getNetworkStatus')));

        repository.emitEvent(
          _directApReady(
            deviceId: _deviceInfo().deviceId,
            operationId: 'op_direct',
          ),
        );
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(cubit.state.phase, NetworkProvisioningPhase.success);
        expect(cubit.state.baseUri, Uri.parse('http://192.168.8.1'));
        expect(repository.calls.where((call) => call == 'getNetworkStatus'), hasLength(1));
      },
    );

    test('stops a confirmed Direct AP and can return to method choice', () async {
      final repository = FakeProvisioningRepository(
        startDirectApResult: const CommandAccepted(
          operationId: 'op_direct',
          desiredMode: ProvisioningNetworkMode.directAp,
        ),
        stopDirectApResult: const CommandAccepted(
          operationId: 'op_stop',
          desiredMode: ProvisioningNetworkMode.none,
        ),
        networkStatus: _networkStatus(
          mode: ProvisioningNetworkMode.directAp,
          operationState: NetworkOperationState.apReady,
          operationId: 'op_direct',
          baseUri: Uri.parse('http://192.168.8.1'),
        ),
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);
      await cubit.startDirectAp(_deviceInfo());
      repository.emitEvent(
        _directApReady(
          deviceId: _deviceInfo().deviceId,
          operationId: 'op_direct',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      await cubit.stopDirectAp();
      expect(cubit.state.phase, NetworkProvisioningPhase.stoppingDirectAp);
      expect(cubit.state.activeOperationId, 'op_stop');

      cubit.backToMethodSelection();
      expect(cubit.state.phase, NetworkProvisioningPhase.idle);
      expect(cubit.state.activeOperationId, isNull);
      expect(cubit.state.baseUri, isNull);
    });
  });

  group('NetworkProvisioningCubit Wi-Fi scan', () {
    test('gates scan capability and starts one scan operation', () async {
      final unsupportedRepository = FakeProvisioningRepository();
      final unsupportedCubit = NetworkProvisioningCubit(unsupportedRepository);
      addTearDown(unsupportedCubit.close);
      unsupportedCubit.openWifiProvisioning(_deviceInfo(wifiScan: false));

      await unsupportedCubit.scanWifi();

      expect(
        unsupportedCubit.state.phase,
        NetworkProvisioningPhase.methodUnavailable,
      );
      expect(unsupportedRepository.calls, isNot(contains('scanWifi')));

      final repository = FakeProvisioningRepository(
        scanWifiResult: const CommandAccepted(
          operationId: 'op_scan',
          desiredMode: ProvisioningNetworkMode.infrastructureSta,
          provisioningMethod: ProvisioningMethod.bleScanSelection,
        ),
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);
      cubit.openWifiProvisioning(_deviceInfo());

      await cubit.scanWifi();

      expect(cubit.state.phase, NetworkProvisioningPhase.scanningWifi);
      expect(cubit.state.activeOperationId, 'op_scan');
      expect(repository.calls.where((call) => call == 'scanWifi'), hasLength(1));
    });

    test('collects out-of-order batches, deduplicates and sorts safely', () async {
      final repository = FakeProvisioningRepository(
        scanWifiResult: const CommandAccepted(
          operationId: 'op_scan',
          desiredMode: ProvisioningNetworkMode.infrastructureSta,
          provisioningMethod: ProvisioningMethod.bleScanSelection,
        ),
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);
      cubit.openWifiProvisioning(_deviceInfo());
      await cubit.scanWifi();

      repository.emitEvent(
        ProvisioningEvent(
          type: ProvisioningEventType.wifiScanResults,
          requestId: 'request-scan',
          deviceId: _deviceInfo().deviceId,
          payload: const WifiScanBatch(
            batchIndex: 1,
            batchCount: 2,
            complete: true,
            networks: [
              WifiScanNetwork(
                ssid: 'Studio',
                bssid: 'AA:00:00:00:00:01',
                rssiDbm: -40,
                frequencyMhz: 2412,
                security: WifiSecurity.wpa2Personal,
                unsupported: false,
              ),
              WifiScanNetwork(
                ssid: 'Legacy',
                bssid: 'AA:00:00:00:00:02',
                rssiDbm: -20,
                frequencyMhz: 2412,
                security: WifiSecurity.wpa2Personal,
                unsupported: true,
              ),
            ],
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.phase, NetworkProvisioningPhase.scanningWifi);

      repository.emitEvent(
        ProvisioningEvent(
          type: ProvisioningEventType.wifiScanResults,
          requestId: 'request-scan',
          deviceId: _deviceInfo().deviceId,
          payload: const WifiScanBatch(
            batchIndex: 0,
            batchCount: 2,
            complete: false,
            networks: [
              WifiScanNetwork(
                ssid: 'Studio-old',
                bssid: 'AA:00:00:00:00:01',
                rssiDbm: -70,
                frequencyMhz: 2412,
                security: WifiSecurity.wpa2Personal,
                unsupported: false,
              ),
              WifiScanNetwork(
                ssid: 'Field',
                bssid: 'AA:00:00:00:00:03',
                rssiDbm: -55,
                frequencyMhz: 5180,
                security: WifiSecurity.wpa3Personal,
                unsupported: false,
              ),
            ],
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, NetworkProvisioningPhase.choosingWifiNetwork);
      expect(
        cubit.state.wifiNetworks.map((network) => network.ssid),
        ['Studio', 'Field', 'Legacy'],
      );
    });
  });

  group('NetworkProvisioningCubit STA and DPP', () {
    test('submits STA configuration without retaining credentials', () async {
      final repository = FakeProvisioningRepository(
        setStaConfigResult: const CommandAccepted(
          operationId: 'op_sta',
          desiredMode: ProvisioningNetworkMode.infrastructureSta,
          provisioningMethod: ProvisioningMethod.bleManual,
        ),
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);
      cubit.openWifiProvisioning(_deviceInfo());

      await cubit.submitStaConfiguration(
        StaNetworkConfiguration(
          provisioningMethod: ProvisioningMethod.bleManual,
          selectionMethod: WifiSelectionMethod.manual,
          ssid: 'Studio',
          security: WifiSecurity.wpa2Personal,
          password: 'synthetic-value',
          hidden: false,
          networkKind: StaNetworkKind.router,
        ),
      );

      expect(cubit.state.phase, NetworkProvisioningPhase.configuringSta);
      expect(cubit.state.activeOperationId, 'op_sta');
      expect(repository.lastStaObservation?.selectionMethod, WifiSelectionMethod.manual);
      expect(repository.lastStaObservation?.passwordProvided, isTrue);
    });

    test('confirms matching STA completion before success', () async {
      final repository = FakeProvisioningRepository(
        setStaConfigResult: const CommandAccepted(
          operationId: 'op_sta',
          desiredMode: ProvisioningNetworkMode.infrastructureSta,
          provisioningMethod: ProvisioningMethod.bleManual,
        ),
        networkStatus: _networkStatus(
          mode: ProvisioningNetworkMode.infrastructureSta,
          operationState: NetworkOperationState.staConnected,
          operationId: 'op_sta',
          baseUri: Uri.parse('http://192.168.1.20'),
        ),
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);
      cubit.openWifiProvisioning(_deviceInfo());
      await cubit.submitStaConfiguration(
        StaNetworkConfiguration(
          provisioningMethod: ProvisioningMethod.bleManual,
          selectionMethod: WifiSelectionMethod.manual,
          ssid: 'Studio',
          security: WifiSecurity.open,
          hidden: false,
          networkKind: StaNetworkKind.router,
        ),
      );

      repository.emitEvent(
        ProvisioningEvent(
          type: ProvisioningEventType.staConnected,
          requestId: 'request-sta',
          deviceId: _deviceInfo().deviceId,
          payload: StaConnected(
            operationId: 'op_sta',
            ssid: 'Studio',
            ipv4: '192.168.1.20',
            prefixLength: 24,
            gatewayIpv4: '192.168.1.1',
            baseUri: Uri.parse('http://192.168.1.20'),
            networkKind: StaNetworkKind.router,
            provisioningMethod: ProvisioningMethod.bleManual,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, NetworkProvisioningPhase.success);
      expect(cubit.state.baseUri, Uri.parse('http://192.168.1.20'));
    });

    test('starts DPP only when supported and cancels the active operation', () async {
      final repository = FakeProvisioningRepository(
        startDppResult: const CommandAccepted(
          operationId: 'op_dpp',
          desiredMode: ProvisioningNetworkMode.infrastructureSta,
          provisioningMethod: ProvisioningMethod.androidDpp,
        ),
        cancelResult: const CommandAccepted(
          operationId: 'op_cancel',
          desiredMode: ProvisioningNetworkMode.none,
        ),
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);
      cubit.openWifiProvisioning(_deviceInfo());

      await cubit.startDppProvisioning();
      expect(cubit.state.phase, NetworkProvisioningPhase.preparingDpp);
      expect(cubit.state.activeOperationId, 'op_dpp');
      expect(cubit.state.canCancel, isTrue);

      await cubit.cancelActiveOperation();
      expect(
        repository.calls,
        contains('cancelNetworkOperation:op_dpp'),
      );
      expect(cubit.state.activeOperationId, 'op_cancel');
    });
  });
}

ProvisioningEvent _directApReady({
  required String deviceId,
  required String operationId,
}) => ProvisioningEvent.fromJson({
  'protocol_version': '1.0-rc4',
  'type': 'direct_ap_ready',
  'request_id': 'request-direct',
  'device_id': deviceId,
  'ok': true,
  'payload': {
    'operation_id': operationId,
    'active_mode': 'direct_ap',
    'ssid': 'BirdBox-Test',
    'security': 'wpa2_personal',
    'passphrase': 'synthetic-value',
    'gateway_ipv4': '192.168.8.1',
    'prefix_length': 24,
    'base_uri': 'http://192.168.8.1',
  },
});

ProvisioningNetworkStatus _networkStatus({
  required ProvisioningNetworkMode mode,
  required NetworkOperationState operationState,
  required String operationId,
  required Uri baseUri,
}) => ProvisioningNetworkStatus(
  activeMode: mode,
  desiredMode: mode,
  operationState: operationState,
  operationId: operationId,
  busy: false,
  baseUri: baseUri,
  directAp: const DirectApSnapshot(),
  infrastructureSta: const InfrastructureStaSnapshot(saved: false),
  updatedAt: DateTime.utc(2026, 8, 24),
);

ProvisioningDeviceInfo _deviceInfo({
  bool directAp = true,
  bool wifiScan = true,
}) => ProvisioningDeviceInfo(
  protocolVersion: '1.0-rc4',
  minAppProtocolVersion: '1.0-rc4',
  deviceId: 'bbx-0123456789abcdef0123456789abcdef',
  deviceName: 'BirdBox-1A2B3C4D',
  firmwareVersion: '1.0.0',
  apiVersion: '1.0',
  pairingCodeMode: PairingCodeMode.sessionRandom,
  pairingCodeLength: 6,
  pairingCodeTtl: const Duration(minutes: 2),
  displayAvailable: true,
  capabilities: DeviceCapabilities(
    directAp: directAp,
    infrastructureSta: true,
    wifiScan: wifiScan,
    wifiManual: true,
    dppEnrolleeSupported: true,
    dppSupportedAkm: const {'psk'},
    modeSwitch: true,
    networkRecovery: true,
    bleFragmentationV1: true,
    wifiApStaConcurrency: false,
    apBand24Ghz: true,
    apBand5Ghz: false,
  ),
);
