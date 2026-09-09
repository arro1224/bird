import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_scan_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/presentation/connection_page.dart';
import 'package:aves/bird_companion/features/connection/presentation/network_provisioning_cubit.dart';
import 'fakes/fake_provisioning_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'BLE connection page shows discovered boxes before network methods',
    (tester) async {
      final repository = FakeProvisioningRepository(
        devices: [_device()],
        deviceInfo: _deviceInfo(),
        pairingWindow: const PairingWindow(
          mode: PairingCodeMode.sessionRandom,
          codeExpiresIn: Duration(minutes: 2),
          attemptsRemaining: 3,
        ),
      );
      addTearDown(repository.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: ConnectionPage(provisioningRepository: repository),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('附近的盒子'), findsOneWidget);
      expect(find.text('BirdBox-1A2B3C4D'), findsOneWidget);
      expect(find.text('直连盒子'), findsNothing);

      final connectButton = find.text('连接此盒子');
      final filledButton = find.ancestor(
        of: connectButton,
        matching: find.byType(FilledButton),
      );
      expect(tester.widget<FilledButton>(filledButton).onPressed, isNotNull);
      expect(repository.calls, isNot(contains('startDirectAp')));
    },
  );

  testWidgets('empty BLE result exposes a secret-safe support diagnostic id', (
    tester,
  ) async {
    final repository = FakeProvisioningRepository();
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ConnectionPage(provisioningRepository: repository),
      ),
    );
    await tester.pumpAndSettle();
    repository.emitScanDiagnostic(
      BleScanDiagnosticSession(
        scanSessionId: 'scan-b7-page',
        startedAt: DateTime.utc(2026, 9, 8, 1),
        endedAt: DateTime.utc(2026, 9, 8, 1, 0, 10),
        permissionBefore: BleScanPermissionState.granted,
        permissionAfter: BleScanPermissionState.granted,
        adapterBefore: BleAdapterState.enabled,
        adapterAfter: BleAdapterState.enabled,
        rawResultCount: 0,
        acceptedCount: 0,
        filteredCount: 0,
        reasonCounts: const {},
        endReason: BleScanEndReason.timeout,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('本次扫描诊断编号：scan-b7-page'), findsOneWidget);
    expect(find.textContaining('android'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('BLE page provides and renders Direct AP provisioning', (tester) async {
    final repository = FakeProvisioningRepository(
      devices: [_device()],
      deviceInfo: _deviceInfo(),
      pairingWindow: const PairingWindow(
        mode: PairingCodeMode.sessionRandom,
        codeExpiresIn: Duration(minutes: 2),
        attemptsRemaining: 3,
      ),
      startDirectApResult: const CommandAccepted(
        operationId: 'op_direct',
        desiredMode: ProvisioningNetworkMode.directAp,
      ),
    );
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ConnectionPage(provisioningRepository: repository),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    final networkCubit = BlocProvider.of<NetworkProvisioningCubit>(
      tester.element(find.text('附近的盒子')),
    );
    await tester.runAsync(() async {
      await networkCubit.startDirectAp(_deviceInfo());
    });
    await tester.pump();

    expect(repository.calls, contains('startDirectAp'));
    expect(find.text('正在启动盒子直连'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pump();
    expect(networkCubit.state.phase, NetworkProvisioningPhase.idle);
  });

  testWidgets('leaving unfinished BLE provisioning releases transport and network binding', (tester) async {
    final repository = FakeProvisioningRepository(
      devices: [_device()],
      deviceInfo: _deviceInfo(),
    );
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ConnectionPage(provisioningRepository: repository),
      ),
    );
    await tester.pumpAndSettle();
    repository.calls.clear();

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(repository.calls, contains('disconnect'));
  });

  testWidgets('successful Direct AP hand-off keeps binding and opens the app shell', (tester) async {
    final baseUri = Uri.parse('http://192.168.4.1:8080');
    final repository = FakeProvisioningRepository(
      devices: [_device()],
      deviceInfo: _deviceInfo(),
      startDirectApResult: const CommandAccepted(
        operationId: 'op_direct',
        desiredMode: ProvisioningNetworkMode.directAp,
      ),
      networkStatus: ProvisioningNetworkStatus(
        activeMode: ProvisioningNetworkMode.directAp,
        desiredMode: ProvisioningNetworkMode.directAp,
        operationState: NetworkOperationState.apReady,
        operationId: 'op_direct',
        busy: false,
        baseUri: baseUri,
        directAp: const DirectApSnapshot(
          ssid: 'BirdBox-1A2B3C4D',
          security: WifiSecurity.wpa2Personal,
          gatewayIpv4: '192.168.4.1',
          prefixLength: 24,
          clientCount: 1,
        ),
        infrastructureSta: const InfrastructureStaSnapshot(saved: false),
        updatedAt: DateTime.utc(2026, 9, 2),
      ),
    );
    addTearDown(repository.dispose);
    final completions = <ProvisioningCompletion>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ConnectionPage(
          provisioningRepository: repository,
          onProvisioningCompleted: (completion) async {
            completions.add(completion);
          },
        ),
        onGenerateRoute: (settings) {
          if (settings.name == '/shell') {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const Scaffold(body: Text('app-shell')),
            );
          }
          return null;
        },
      ),
    );
    await tester.pumpAndSettle();

    final networkCubit = BlocProvider.of<NetworkProvisioningCubit>(
      tester.element(find.text('附近的盒子')),
    );
    await networkCubit.startDirectAp(_deviceInfo());
    repository.emitEvent(
      ProvisioningEvent(
        type: ProvisioningEventType.directApReady,
        requestId: 'req_direct',
        deviceId: _deviceInfo().deviceId,
        payload: DirectApReady.fromJson({
          'operation_id': 'op_direct',
          'active_mode': 'direct_ap',
          'ssid': 'BirdBox-1A2B3C4D',
          'security': 'wpa2_personal',
          'passphrase': 'test-password',
          'gateway_ipv4': '192.168.4.1',
          'prefix_length': 24,
          'base_uri': baseUri.toString(),
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('盒子直连已就绪'), findsOneWidget);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.text('app-shell'), findsOneWidget);
    expect(completions, hasLength(1));
    expect(completions.single.deviceId, _deviceInfo().deviceId);
    expect(completions.single.baseUri, baseUri);
    expect(
      completions.single.networkMode,
      ProvisioningNetworkMode.directAp,
    );
    expect(repository.calls, isNot(contains('disconnect')));
  });
}

ProvisioningDevice _device() => ProvisioningDevice(
  scanId: 'scan-1',
  advertisement: BirdBoxAdvertisement(
    localName: 'BirdBox-1A2B3C4D',
    serviceUuids: const ['0000bb01-0000-1000-8000-00805f9b34fb'],
    rssi: -48,
  ),
);

ProvisioningDeviceInfo _deviceInfo() => const ProvisioningDeviceInfo(
  protocolVersion: '1.0',
  minAppProtocolVersion: '1.0',
  deviceId: 'bbx-0123456789abcdef0123456789abcdef',
  deviceName: 'BirdBox-1A2B3C4D',
  firmwareVersion: '1.0.0',
  apiVersion: '1.0',
  pairingCodeMode: PairingCodeMode.sessionRandom,
  pairingCodeLength: 6,
  pairingCodeTtl: Duration(minutes: 2),
  displayAvailable: true,
  capabilities: DeviceCapabilities(
    directAp: true,
    infrastructureSta: true,
    wifiScan: true,
    wifiManual: true,
    dppEnrolleeSupported: false,
    dppSupportedAkm: {},
    modeSwitch: true,
    networkRecovery: true,
    bleFragmentationV1: true,
    wifiApStaConcurrency: false,
    apBand24Ghz: true,
    apBand5Ghz: false,
  ),
);
