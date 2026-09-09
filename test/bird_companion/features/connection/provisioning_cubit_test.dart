import 'package:aves/bird_companion/features/connection/domain/ble_scan_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/presentation/provisioning_cubit.dart';
import 'fakes/fake_provisioning_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProvisioningCubit', () {
    test(
      'keeps a compact BirdBox advertisement without manufacturer data visible',
      () async {
        final repository = FakeProvisioningRepository(
          devices: [_compactDevice()],
          deviceInfo: _deviceInfo(),
        );
        final cubit = ProvisioningCubit(repository);
        addTearDown(cubit.close);

        await cubit.discover();
        await Future<void>.delayed(Duration.zero);

        expect(cubit.state.phase, ProvisioningPhase.discovered);
        expect(cubit.state.devices, hasLength(1));
        expect(
          cubit.state.devices.single.advertisement.hasManufacturerExtension,
          isFalse,
        );
      },
    );

    test(
      'does not enter the trusted pairing flow until Device Info has completed',
      () async {
        final repository = FakeProvisioningRepository(
          devices: [_compactDevice()],
          deviceInfo: _deviceInfo(),
        );
        final cubit = ProvisioningCubit(repository);
        addTearDown(cubit.close);

        await cubit.discover();
        await Future<void>.delayed(Duration.zero);
        expect(cubit.state.phase, ProvisioningPhase.discovered);
        expect(cubit.state.deviceInfo, isNull);

        await cubit.selectDevice(_compactDevice());

        expect(cubit.state.phase, ProvisioningPhase.trusted);
        expect(
          cubit.state.deviceInfo?.deviceId,
          'bbx-0123456789abcdef0123456789abcdef',
        );
        expect(repository.calls, contains('connect:scan-1'));
        expect(repository.calls, isNot(contains('startDirectAp')));
      },
    );

    test(
      'only offers connection methods after a pairing code has been authorized',
      () async {
        final repository = FakeProvisioningRepository(
          devices: [_compactDevice()],
          deviceInfo: _deviceInfo(),
          pairingWindow: const PairingWindow(
            mode: PairingCodeMode.sessionRandom,
            codeExpiresIn: Duration(minutes: 2),
            attemptsRemaining: 3,
          ),
        );
        final cubit = ProvisioningCubit(repository);
        addTearDown(cubit.close);

        await cubit.discover();
        await Future<void>.delayed(Duration.zero);
        await cubit.selectDevice(_compactDevice());
        await cubit.openPairing();

        expect(cubit.state.phase, ProvisioningPhase.pairingCode);
        expect(cubit.state.pairingWindow?.mode, PairingCodeMode.sessionRandom);

        await cubit.authorizePairing('246810');

        expect(cubit.state.phase, ProvisioningPhase.methodSelection);
        expect(repository.calls, contains('authorizePairing'));
        expect(
          repository.calls.any((call) => call.contains(RegExp(r'\d{6}'))),
          isFalse,
        );
        expect(repository.calls, isNot(contains('startDirectAp')));
      },
    );

    test('closing the presentation cubit does not tear down the app-wide connection', () async {
      final repository = FakeProvisioningRepository(
        devices: [_compactDevice()],
        deviceInfo: _deviceInfo(),
      );
      final cubit = ProvisioningCubit(repository);

      await cubit.discover();
      await Future<void>.delayed(Duration.zero);
      repository.calls.clear();
      await cubit.close();

      expect(repository.calls, ['stopDiscovery']);
      expect(repository.calls, isNot(contains('disconnect')));
      await repository.dispose();
    });

    test('surfaces the latest secret-safe scan diagnostic for support', () async {
      final repository = FakeProvisioningRepository();
      final cubit = ProvisioningCubit(repository);
      addTearDown(cubit.close);
      final diagnostic = BleScanDiagnosticSession(
        scanSessionId: 'scan-b7-support',
        startedAt: DateTime.utc(2026, 9, 8, 1),
        endedAt: DateTime.utc(2026, 9, 8, 1, 0, 10),
        permissionBefore: BleScanPermissionState.granted,
        permissionAfter: BleScanPermissionState.granted,
        adapterBefore: BleAdapterState.enabled,
        adapterAfter: BleAdapterState.enabled,
        rawResultCount: 3,
        acceptedCount: 0,
        filteredCount: 3,
        reasonCounts: const {'non_birdbox': 3},
        endReason: BleScanEndReason.timeout,
      );

      repository.emitScanDiagnostic(diagnostic);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.latestScanDiagnostic, same(diagnostic));
      expect(cubit.state.phase, ProvisioningPhase.idle);
    });
  });
}

ProvisioningDevice _compactDevice() => ProvisioningDevice(
  scanId: 'scan-1',
  advertisement: BirdBoxAdvertisement(
    localName: 'BirdBox-1A2B3C4D',
    serviceUuids: const ['0000bb01-0000-1000-8000-00805f9b34fb'],
    rssi: -52,
    platformDeviceId: 'android-opaque-id',
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
