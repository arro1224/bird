import 'package:aves/bird_companion/app/theme/app_theme.dart';
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
