import 'dart:async';

import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';
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

    test('ignores matching events that arrive after success', () async {
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
          deviceId: _deviceInfo().deviceId,
          operationId: 'op_direct',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      repository.emitEvent(
        const ProvisioningEvent(
          type: ProvisioningEventType.networkProgress,
          requestId: 'request-late-progress',
          deviceId: 'bbx-0123456789abcdef0123456789abcdef',
          payload: NetworkProgress(
            operationId: 'op_direct',
            operationState: NetworkOperationState.scanning,
          ),
        ),
      );
      repository.emitEvent(
        const ProvisioningEvent(
          type: ProvisioningEventType.cancelled,
          requestId: 'request-late-cancelled',
          deviceId: 'bbx-0123456789abcdef0123456789abcdef',
          payload: CancelledOperation(operationId: 'op_direct'),
        ),
      );
      repository.emitEvent(
        const ProvisioningEvent(
          type: ProvisioningEventType.networkRecovered,
          requestId: 'request-late-recovery',
          deviceId: 'bbx-0123456789abcdef0123456789abcdef',
          payload: NetworkRecovered(
            operationId: 'op_direct',
            activeMode: ProvisioningNetworkMode.infrastructureSta,
            operationState: NetworkOperationState.idle,
            recoveredMode: ProvisioningNetworkMode.infrastructureSta,
            recoveryReason: 'previous_sta_connect_failed',
          ),
        ),
      );
      repository.emitError(StateError('late stream error'));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, NetworkProvisioningPhase.success);
      expect(cubit.state.operationState, NetworkOperationState.apReady);
      expect(cubit.state.canCancel, isFalse);
    });

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

      repository.emitEvent(
        const ProvisioningEvent(
          type: ProvisioningEventType.directApStopped,
          requestId: 'request-stop',
          deviceId: 'bbx-0123456789abcdef0123456789abcdef',
          payload: DirectApStopped(
            operationId: 'op_stop',
            activeMode: ProvisioningNetworkMode.none,
            operationState: NetworkOperationState.idle,
            restoredSta: false,
            reason: 'user_requested',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.phase, NetworkProvisioningPhase.stopped);

      cubit.backToMethodSelection();
      expect(cubit.state.phase, NetworkProvisioningPhase.idle);
      expect(cubit.state.activeOperationId, isNull);
      expect(cubit.state.baseUri, isNull);
    });

    test('confirms restored STA before reporting stop-direct success', () async {
      final repository = FakeProvisioningRepository(
        networkStatus: _networkStatus(
          mode: ProvisioningNetworkMode.directAp,
          operationState: NetworkOperationState.apReady,
          operationId: 'op_direct',
          baseUri: Uri.parse('http://192.168.8.1'),
        ),
        stopDirectApResult: const CommandAccepted(
          operationId: 'op_stop',
          desiredMode: ProvisioningNetworkMode.infrastructureSta,
        ),
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);

      await cubit.resumeAfterBleReconnect(_deviceInfo());
      await cubit.stopDirectAp();
      repository.networkStatus = _networkStatus(
        mode: ProvisioningNetworkMode.infrastructureSta,
        operationState: NetworkOperationState.staConnected,
        operationId: 'op_stop',
        baseUri: Uri.parse('http://192.0.2.40:8080'),
      );
      repository.emitEvent(
        ProvisioningEvent(
          type: ProvisioningEventType.staConnected,
          requestId: 'request-stop-restored',
          deviceId: _deviceInfo().deviceId,
          payload: StaConnected(
            operationId: 'op_stop',
            ssid: 'Studio-WiFi',
            ipv4: '192.0.2.40',
            prefixLength: 24,
            gatewayIpv4: '192.0.2.1',
            baseUri: Uri.parse('http://192.0.2.40:8080'),
            networkKind: StaNetworkKind.router,
            provisioningMethod: ProvisioningMethod.bleManual,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, NetworkProvisioningPhase.success);
      expect(
        cubit.state.confirmedMode,
        ProvisioningNetworkMode.infrastructureSta,
      );
      expect(cubit.state.baseUri, Uri.parse('http://192.0.2.40:8080'));
    });

    test('preserves no-saved-profile reason in the stopped terminal', () async {
      final repository = FakeProvisioningRepository(
        networkStatus: _networkStatus(
          mode: ProvisioningNetworkMode.directAp,
          operationState: NetworkOperationState.apReady,
          operationId: 'op_direct',
          baseUri: Uri.parse('http://192.168.8.1'),
        ),
        stopDirectApResult: const CommandAccepted(
          operationId: 'op_stop',
          desiredMode: ProvisioningNetworkMode.none,
        ),
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);

      await cubit.resumeAfterBleReconnect(_deviceInfo());
      await cubit.stopDirectAp();
      repository.emitEvent(
        ProvisioningEvent(
          type: ProvisioningEventType.directApStopped,
          requestId: 'request-no-profile',
          deviceId: _deviceInfo().deviceId,
          payload: const DirectApStopped(
            operationId: 'op_stop',
            activeMode: ProvisioningNetworkMode.none,
            operationState: NetworkOperationState.idle,
            restoredSta: false,
            reason: 'no_saved_sta_profile',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, NetworkProvisioningPhase.stopped);
      expect(cubit.state.directApStopReason, 'no_saved_sta_profile');
    });

    test('resumes an accepted stop operation from authoritative status', () async {
      final repository = FakeProvisioningRepository(
        networkStatus: ProvisioningNetworkStatus(
          activeMode: ProvisioningNetworkMode.directAp,
          desiredMode: ProvisioningNetworkMode.infrastructureSta,
          operationState: NetworkOperationState.stoppingAp,
          operationId: 'op_stop_after_reconnect',
          busy: true,
          baseUri: Uri.parse('http://192.168.8.1'),
          directAp: const DirectApSnapshot(ssid: 'BirdBox-Test'),
          infrastructureSta: const InfrastructureStaSnapshot(saved: true),
          updatedAt: DateTime.utc(2026, 9, 2),
        ),
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);

      await cubit.resumeAfterBleReconnect(_deviceInfo());

      expect(cubit.state.phase, NetworkProvisioningPhase.stoppingDirectAp);
      expect(cubit.state.activeOperationId, 'op_stop_after_reconnect');
      expect(repository.calls, contains('getNetworkStatus'));

      repository.emitEvent(
        const ProvisioningEvent(
          type: ProvisioningEventType.networkProgress,
          requestId: 'request-stale',
          deviceId: 'bbx-0123456789abcdef0123456789abcdef',
          payload: NetworkProgress(
            operationId: 'op_stale',
            operationState: NetworkOperationState.recovering,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.operationState, NetworkOperationState.stoppingAp);
    });

    test('maps a matching failed progress event to a safe failure', () async {
      final repository = FakeProvisioningRepository(
        startDirectApResult: const CommandAccepted(
          operationId: 'op_direct',
          desiredMode: ProvisioningNetworkMode.directAp,
        ),
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);
      await cubit.startDirectAp(_deviceInfo());

      repository.emitEvent(
        const ProvisioningEvent(
          type: ProvisioningEventType.networkProgress,
          requestId: 'request-progress',
          deviceId: 'bbx-0123456789abcdef0123456789abcdef',
          payload: NetworkProgress(
            operationId: 'op_direct',
            operationState: NetworkOperationState.failed,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, NetworkProvisioningPhase.failure);
      expect(cubit.state.error, isA<NetworkOperationFailedException>());
    });

    test('reports recovery without claiming the requested mode succeeded', () async {
      final repository = FakeProvisioningRepository(
        startDirectApResult: const CommandAccepted(
          operationId: 'op_direct',
          desiredMode: ProvisioningNetworkMode.directAp,
        ),
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);
      await cubit.startDirectAp(_deviceInfo());

      repository.emitEvent(
        ProvisioningEvent(
          type: ProvisioningEventType.networkRecovered,
          requestId: 'request-recovery',
          deviceId: 'bbx-0123456789abcdef0123456789abcdef',
          payload: NetworkRecovered(
            operationId: 'op_direct',
            activeMode: ProvisioningNetworkMode.infrastructureSta,
            operationState: NetworkOperationState.idle,
            recoveredMode: ProvisioningNetworkMode.infrastructureSta,
            recoveryReason: 'previous_sta_connect_failed',
            baseUri: Uri.parse('http://192.0.2.1'),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, NetworkProvisioningPhase.recovered);
      expect(
        cubit.state.recoveredMode,
        ProvisioningNetworkMode.infrastructureSta,
      );
      expect(cubit.state.confirmedMode, isNull);
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
                bssid: 'aa:00:00:00:00:01',
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

    test('surfaces a Wi-Fi scan command failure safely', () async {
      final repository = FakeProvisioningRepository(
        scanWifiError: const ProvisioningException(
          code: ProvisioningErrorCode.wifiScanFailed,
          retryable: true,
          diagnosticMessage: 'password=must-not-enter-state',
        ),
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);
      cubit.openWifiProvisioning(_deviceInfo());

      await cubit.scanWifi();

      expect(cubit.state.phase, NetworkProvisioningPhase.failure);
      expect(
        (cubit.state.error as ProvisioningException).code,
        ProvisioningErrorCode.wifiScanFailed,
      );
      expect(
        (cubit.state.error as ProvisioningException).diagnosticMessage,
        isNull,
      );
    });

    test('sanitizes provisioning errors emitted by the event stream', () async {
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

      repository.emitError(
        const ProvisioningException(
          code: ProvisioningErrorCode.networkInternalError,
          retryable: true,
          diagnosticMessage: 'token=must-not-enter-state',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, NetworkProvisioningPhase.failure);
      expect(
        (cubit.state.error as ProvisioningException).diagnosticMessage,
        isNull,
      );
    });

    test('replaces unknown event stream errors with a safe failure', () async {
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

      repository.emitError(StateError('password=must-not-enter-state'));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, NetworkProvisioningPhase.failure);
      expect(cubit.state.error, isA<NetworkOperationFailedException>());
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

    test('submits a scanned network as BLE scan selection', () async {
      final repository = FakeProvisioningRepository(
        setStaConfigResult: const CommandAccepted(
          operationId: 'op_sta',
          desiredMode: ProvisioningNetworkMode.infrastructureSta,
          provisioningMethod: ProvisioningMethod.bleScanSelection,
        ),
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);
      cubit.openWifiProvisioning(_deviceInfo());

      await cubit.submitStaConfiguration(
        StaNetworkConfiguration(
          provisioningMethod: ProvisioningMethod.bleScanSelection,
          selectionMethod: WifiSelectionMethod.scanResult,
          ssid: 'Studio',
          bssid: 'AA:00:00:00:00:01',
          security: WifiSecurity.open,
          hidden: false,
          networkKind: StaNetworkKind.router,
        ),
      );

      expect(
        repository.lastStaObservation?.selectionMethod,
        WifiSelectionMethod.scanResult,
      );
      expect(repository.lastStaObservation?.hasBssid, isTrue);
      expect(repository.lastStaObservation?.passwordProvided, isFalse);
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

      repository.emitEvent(
        const ProvisioningEvent(
          type: ProvisioningEventType.cancelled,
          requestId: 'request-cancel',
          deviceId: 'bbx-0123456789abcdef0123456789abcdef',
          payload: CancelledOperation(operationId: 'op_cancel'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.phase, NetworkProvisioningPhase.cancelled);
    });

    test('sends only one cancel command while cancellation is pending', () async {
      final cancelCompleter = Completer<CommandAccepted>();
      final fakeRepository = FakeProvisioningRepository(
        startDppResult: const CommandAccepted(
          operationId: 'op_dpp',
          desiredMode: ProvisioningNetworkMode.infrastructureSta,
          provisioningMethod: ProvisioningMethod.androidDpp,
        ),
      );
      final repository = _PendingCancelRepository(
        fakeRepository,
        cancelCompleter.future,
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);
      cubit.openWifiProvisioning(_deviceInfo());
      await cubit.startDppProvisioning();

      final firstCancel = cubit.cancelActiveOperation();
      final secondCancel = cubit.cancelActiveOperation();

      expect(repository.cancelCalls, 1);
      expect(cubit.state.canCancel, isFalse);

      cancelCompleter.complete(
        const CommandAccepted(
          operationId: 'op_cancel',
          desiredMode: ProvisioningNetworkMode.none,
        ),
      );
      await Future.wait([firstCancel, secondCancel]);

      expect(cubit.state.activeOperationId, 'op_cancel');
    });

    test('ignores cancellable progress while cancellation is pending', () async {
      final cancelCompleter = Completer<CommandAccepted>();
      final fakeRepository = FakeProvisioningRepository(
        startDppResult: const CommandAccepted(
          operationId: 'op_dpp',
          desiredMode: ProvisioningNetworkMode.infrastructureSta,
          provisioningMethod: ProvisioningMethod.androidDpp,
        ),
      );
      final repository = _PendingCancelRepository(
        fakeRepository,
        cancelCompleter.future,
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);
      cubit.openWifiProvisioning(_deviceInfo());
      await cubit.startDppProvisioning();

      final firstCancel = cubit.cancelActiveOperation();
      fakeRepository.emitEvent(
        const ProvisioningEvent(
          type: ProvisioningEventType.networkProgress,
          requestId: 'request-late-progress',
          deviceId: 'bbx-0123456789abcdef0123456789abcdef',
          payload: NetworkProgress(
            operationId: 'op_dpp',
            operationState: NetworkOperationState.waitingDppConfigurator,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.canCancel, isFalse);
      final secondCancel = cubit.cancelActiveOperation();
      expect(repository.cancelCalls, 1);

      cancelCompleter.complete(
        const CommandAccepted(
          operationId: 'op_cancel',
          desiredMode: ProvisioningNetworkMode.none,
        ),
      );
      await Future.wait([firstCancel, secondCancel]);
    });

    test('ignores stream errors while cancellation is pending', () async {
      final cancelCompleter = Completer<CommandAccepted>();
      final fakeRepository = FakeProvisioningRepository(
        startDppResult: const CommandAccepted(
          operationId: 'op_dpp',
          desiredMode: ProvisioningNetworkMode.infrastructureSta,
          provisioningMethod: ProvisioningMethod.androidDpp,
        ),
      );
      final repository = _PendingCancelRepository(
        fakeRepository,
        cancelCompleter.future,
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);
      cubit.openWifiProvisioning(_deviceInfo());
      await cubit.startDppProvisioning();

      final cancel = cubit.cancelActiveOperation();
      fakeRepository.emitError(StateError('late cancellation stream error'));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, NetworkProvisioningPhase.preparingDpp);
      expect(cubit.state.error, isNull);

      cancelCompleter.complete(
        const CommandAccepted(
          operationId: 'op_cancel',
          desiredMode: ProvisioningNetworkMode.none,
        ),
      );
      await cancel;
      fakeRepository.emitEvent(
        const ProvisioningEvent(
          type: ProvisioningEventType.cancelled,
          requestId: 'request-cancelled',
          deviceId: 'bbx-0123456789abcdef0123456789abcdef',
          payload: CancelledOperation(operationId: 'op_cancel'),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, NetworkProvisioningPhase.cancelled);
    });

    test('starts only one DPP command while the first request is pending', () async {
      final startCompleter = Completer<CommandAccepted>();
      final fakeRepository = FakeProvisioningRepository();
      final repository = _PendingStartDppRepository(
        fakeRepository,
        startCompleter.future,
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);
      cubit.openWifiProvisioning(_deviceInfo());

      final firstStart = cubit.startDppProvisioning();
      final secondStart = cubit.startDppProvisioning();

      expect(repository.startDppCalls, 1);
      expect(cubit.state.phase, NetworkProvisioningPhase.preparingDpp);
      expect(cubit.state.canCancel, isFalse);

      startCompleter.complete(
        const CommandAccepted(
          operationId: 'op_dpp_single_flight',
          desiredMode: ProvisioningNetworkMode.infrastructureSta,
          provisioningMethod: ProvisioningMethod.androidDpp,
        ),
      );
      await Future.wait([firstStart, secondStart]);

      expect(cubit.state.activeOperationId, 'op_dpp_single_flight');
      expect(cubit.state.canCancel, isTrue);
    });

    test('does not start DPP when the box capability is unavailable', () async {
      final repository = FakeProvisioningRepository();
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);
      cubit.openWifiProvisioning(_deviceInfo(dppSupported: false));

      await cubit.startDppProvisioning();

      expect(cubit.state.phase, NetworkProvisioningPhase.methodUnavailable);
      expect(repository.calls, isNot(contains('startDppProvisioning')));
    });

    test('maps unavailable phone DPP to a dedicated safe phase', () async {
      final repository = FakeProvisioningRepository(
        startDppError: const ProvisioningException(
          code: ProvisioningErrorCode.phoneDppNotSupported,
          retryable: false,
          diagnosticMessage: 'DPP:K:SYNTHETIC_PRIVATE_DIAGNOSTIC;;',
        ),
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);
      cubit.openWifiProvisioning(_deviceInfo());

      await cubit.startDppProvisioning();

      expect(cubit.state.phase, NetworkProvisioningPhase.dppUnavailable);
      expect(cubit.state.activeOperationId, isNull);
      expect(cubit.state.canCancel, isFalse);
      expect(cubit.state.error, isNull);
      expect(
        repository.calls.where((call) => call == 'startDppProvisioning'),
        hasLength(1),
      );
    });

    test('keeps unavailable DPP settled after a late stream error', () async {
      final repository = FakeProvisioningRepository(
        startDppError: const ProvisioningException(
          code: ProvisioningErrorCode.phoneDppNotSupported,
          retryable: false,
          diagnosticMessage: 'private initial diagnostic',
        ),
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);
      final emittedStates = <NetworkProvisioningState>[];
      final stateSubscription = cubit.stream.listen(emittedStates.add);
      addTearDown(stateSubscription.cancel);
      cubit.openWifiProvisioning(_deviceInfo());
      await cubit.startDppProvisioning();
      expect(cubit.state.phase, NetworkProvisioningPhase.dppUnavailable);

      repository.emitError(
        const ProvisioningException(
          code: ProvisioningErrorCode.systemDppFailed,
          retryable: true,
          diagnosticMessage: 'private late diagnostic',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, NetworkProvisioningPhase.dppUnavailable);
      expect(cubit.state.error, isNull);
      expect(cubit.state.activeOperationId, isNull);
      expect(cubit.state.canCancel, isFalse);
      for (final emittedState in emittedStates) {
        final error = emittedState.error;
        if (error is ProvisioningException) {
          expect(error.diagnosticMessage, isNull);
        }
      }
    });

    test('ignores a late DPP stream error after returning to method choice', () async {
      final repository = FakeProvisioningRepository(
        startDppError: const ProvisioningException(
          code: ProvisioningErrorCode.phoneDppNotSupported,
          retryable: false,
          diagnosticMessage: 'private initial diagnostic',
        ),
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);
      cubit.openWifiProvisioning(_deviceInfo());
      await cubit.startDppProvisioning();
      expect(cubit.state.phase, NetworkProvisioningPhase.dppUnavailable);

      cubit.returnToWifiMethodSelection();
      expect(cubit.state.phase, NetworkProvisioningPhase.choosingWifiMethod);

      repository.emitError(
        const ProvisioningException(
          code: ProvisioningErrorCode.systemDppFailed,
          retryable: true,
          diagnosticMessage: 'private late diagnostic',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, NetworkProvisioningPhase.choosingWifiMethod);
      expect(cubit.state.error, isNull);
      expect(cubit.state.activeOperationId, isNull);
      expect(cubit.state.canCancel, isFalse);
    });

    test('maps a system DPP cancellation to the cancelled result', () async {
      final repository = FakeProvisioningRepository(
        startDppResult: const CommandAccepted(
          operationId: 'op_dpp_cancelled',
          desiredMode: ProvisioningNetworkMode.infrastructureSta,
          provisioningMethod: ProvisioningMethod.androidDpp,
        ),
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);
      cubit.openWifiProvisioning(_deviceInfo());
      await cubit.startDppProvisioning();

      repository.emitError(
        const ProvisioningException(
          code: ProvisioningErrorCode.userCancelledDppDialog,
          retryable: false,
          diagnosticMessage: 'private system result',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, NetworkProvisioningPhase.cancelled);
      expect(cubit.state.error, isNull);
      expect(cubit.state.activeOperationId, isNull);
      expect(cubit.state.canCancel, isFalse);
    });

    test('keeps retryable DPP failures sanitized', () async {
      final repository = FakeProvisioningRepository(
        startDppError: const ProvisioningException(
          code: ProvisioningErrorCode.systemDppFailed,
          retryable: true,
          diagnosticMessage: 'platform result contains private data',
        ),
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);
      cubit.openWifiProvisioning(_deviceInfo());

      await cubit.startDppProvisioning();

      expect(cubit.state.phase, NetworkProvisioningPhase.failure);
      expect(cubit.state.error, isA<ProvisioningException>());
      final error = cubit.state.error! as ProvisioningException;
      expect(error.code, ProvisioningErrorCode.systemDppFailed);
      expect(error.retryable, isTrue);
      expect(error.diagnosticMessage, isNull);
    });

    test('system DPP handoff waits for box confirmation before success', () async {
      final statusCompleter = Completer<ProvisioningNetworkStatus>();
      final fakeRepository = FakeProvisioningRepository(
        startDppResult: const CommandAccepted(
          operationId: 'op_dpp_success',
          desiredMode: ProvisioningNetworkMode.infrastructureSta,
          provisioningMethod: ProvisioningMethod.androidDpp,
        ),
      );
      final repository = _PendingNetworkStatusRepository(
        fakeRepository,
        statusCompleter.future,
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);
      cubit.openWifiProvisioning(_deviceInfo());
      await cubit.startDppProvisioning();

      fakeRepository.emitEvent(
        ProvisioningEvent.fromJson({
          'protocol_version': '1.0-rc4',
          'type': 'dpp_bootstrap_ready',
          'request_id': 'request-dpp-bootstrap',
          'device_id': _deviceInfo().deviceId,
          'ok': true,
          'payload': {
            'operation_id': 'op_dpp_success',
            'operation_state': 'waiting_dpp_configurator',
            'dpp_uri': 'DPP:K:SYNTHETIC_PUBLIC_BOOTSTRAP;;',
            'expires_in_seconds': 120,
          },
        }),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, NetworkProvisioningPhase.preparingDpp);
      expect(
        cubit.state.operationState,
        NetworkOperationState.waitingDppConfigurator,
      );
      expect(cubit.state.baseUri, isNull);

      fakeRepository.emitEvent(
        ProvisioningEvent(
          type: ProvisioningEventType.staConnected,
          requestId: 'request-dpp-sta-connected',
          deviceId: _deviceInfo().deviceId,
          payload: StaConnected(
            operationId: 'op_dpp_success',
            ssid: 'Studio',
            ipv4: '192.0.2.20',
            prefixLength: 24,
            gatewayIpv4: '192.0.2.1',
            baseUri: Uri.parse('http://192.0.2.20'),
            networkKind: StaNetworkKind.router,
            provisioningMethod: ProvisioningMethod.androidDpp,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, NetworkProvisioningPhase.confirmingNetwork);
      expect(cubit.state.phase, isNot(NetworkProvisioningPhase.success));
      expect(cubit.state.baseUri, isNull);

      statusCompleter.complete(
        _networkStatus(
          mode: ProvisioningNetworkMode.infrastructureSta,
          operationState: NetworkOperationState.staConnected,
          operationId: 'op_dpp_success',
          baseUri: Uri.parse('http://192.0.2.20'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, NetworkProvisioningPhase.success);
      expect(cubit.state.baseUri, Uri.parse('http://192.0.2.20'));
    });

    test('fails DPP confirmation when the status operation does not match', () async {
      final repository = FakeProvisioningRepository(
        startDppResult: const CommandAccepted(
          operationId: 'op_dpp_expected',
          desiredMode: ProvisioningNetworkMode.infrastructureSta,
          provisioningMethod: ProvisioningMethod.androidDpp,
        ),
        networkStatus: _networkStatus(
          mode: ProvisioningNetworkMode.infrastructureSta,
          operationState: NetworkOperationState.staConnected,
          operationId: 'op_dpp_stale',
          baseUri: Uri.parse('http://192.0.2.20'),
        ),
      );
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);
      cubit.openWifiProvisioning(_deviceInfo());
      await cubit.startDppProvisioning();

      repository.emitEvent(
        ProvisioningEvent(
          type: ProvisioningEventType.staConnected,
          requestId: 'request-dpp-sta-mismatch',
          deviceId: _deviceInfo().deviceId,
          payload: StaConnected(
            operationId: 'op_dpp_expected',
            ssid: 'Studio',
            ipv4: '192.0.2.20',
            prefixLength: 24,
            gatewayIpv4: '192.0.2.1',
            baseUri: Uri.parse('http://192.0.2.20'),
            networkKind: StaNetworkKind.router,
            provisioningMethod: ProvisioningMethod.androidDpp,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, NetworkProvisioningPhase.failure);
      expect(cubit.state.error, isA<NetworkStatusConfirmationException>());
      expect(cubit.state.baseUri, isNull);
    });
  });
}

final class _PendingNetworkStatusRepository implements ProvisioningRepository {
  _PendingNetworkStatusRepository(this._delegate, this._networkStatus);

  final FakeProvisioningRepository _delegate;
  final Future<ProvisioningNetworkStatus> _networkStatus;

  @override
  Stream<ProvisioningEvent> get events => _delegate.events;

  @override
  Future<ProvisioningNetworkStatus> getNetworkStatus() => _networkStatus;

  @override
  Future<CommandAccepted> startDppProvisioning() => _delegate.startDppProvisioning();

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError('Unexpected repository call: ${invocation.memberName}');
}

final class _PendingStartDppRepository implements ProvisioningRepository {
  _PendingStartDppRepository(this._delegate, this._startDppResult);

  final FakeProvisioningRepository _delegate;
  final Future<CommandAccepted> _startDppResult;
  var startDppCalls = 0;

  @override
  Stream<ProvisioningEvent> get events => _delegate.events;

  @override
  Future<CommandAccepted> startDppProvisioning() {
    startDppCalls++;
    return _startDppResult;
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError('Unexpected repository call: ${invocation.memberName}');
}

final class _PendingCancelRepository implements ProvisioningRepository {
  _PendingCancelRepository(this._delegate, this._cancelResult);

  final FakeProvisioningRepository _delegate;
  final Future<CommandAccepted> _cancelResult;
  var cancelCalls = 0;

  @override
  Stream<ProvisioningEvent> get events => _delegate.events;

  @override
  Future<CommandAccepted> startDppProvisioning() => _delegate.startDppProvisioning();

  @override
  Future<CommandAccepted> cancelNetworkOperation(String operationId) {
    cancelCalls++;
    return _cancelResult;
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError('Unexpected repository call: ${invocation.memberName}');
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
  bool dppSupported = true,
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
    dppEnrolleeSupported: dppSupported,
    dppSupportedAkm: dppSupported ? const {'psk'} : const {},
    modeSwitch: true,
    networkRecovery: true,
    bleFragmentationV1: true,
    wifiApStaConcurrency: false,
    apBand24Ghz: true,
    apBand5Ghz: false,
  ),
);
