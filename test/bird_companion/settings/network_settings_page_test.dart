import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/network_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/connection/fakes/fake_provisioning_repository.dart';

void main() {
  testWidgets('requires BLE reconnect when there is no trusted BLE session', (
    tester,
  ) async {
    final repository = FakeProvisioningRepository();
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NetworkSettingsPage(repository: repository),
      ),
    );

    expect(
      find.byKey(const Key('network-settings-ble-reconnect')),
      findsOneWidget,
    );
    expect(find.text('需要重新连接蓝牙'), findsOneWidget);
    expect(find.textContaining('不会把蓝牙断开或热点消失当作成功'), findsOneWidget);
  });

  testWidgets('loads Direct AP state and treats BLE loss as resumable', (
    tester,
  ) async {
    final repository = FakeProvisioningRepository(
      deviceInfo: _deviceInfo,
      networkStatus: _directApStatus,
      stopDirectApResult: const CommandAccepted(
        operationId: 'op_stop_settings',
        desiredMode: ProvisioningNetworkMode.infrastructureSta,
      ),
    );
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NetworkSettingsPage(repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('盒子直连已就绪'), findsOneWidget);
    expect(find.text('停止盒子直连'), findsOneWidget);

    await tester.tap(find.text('停止盒子直连'));
    await tester.pump();
    expect(find.text('断开盒子直连？'), findsOneWidget);
    expect(repository.calls, isNot(contains('stopDirectAp')));
    await tester.tap(find.text('断开并恢复 Wi-Fi'));
    await tester.pump();
    await tester.pump();
    expect(repository.calls, contains('stopDirectAp'));
    expect(find.text('正在停止盒子直连'), findsOneWidget);

    repository.emitDisconnect();
    await tester.pump();

    expect(find.text('需要重新连接蓝牙'), findsOneWidget);
    expect(find.text('重新连接并恢复状态'), findsOneWidget);
  });
}

const _deviceInfo = ProvisioningDeviceInfo(
  protocolVersion: '1.0-rc4',
  minAppProtocolVersion: '1.0-rc4',
  deviceId: 'bbx-0123456789abcdef0123456789abcdef',
  deviceName: 'BirdBox-Test',
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
    dppEnrolleeSupported: true,
    dppSupportedAkm: {'psk'},
    modeSwitch: true,
    networkRecovery: true,
    bleFragmentationV1: true,
    wifiApStaConcurrency: false,
    apBand24Ghz: true,
    apBand5Ghz: false,
  ),
);

final _directApStatus = ProvisioningNetworkStatus(
  activeMode: ProvisioningNetworkMode.directAp,
  desiredMode: ProvisioningNetworkMode.directAp,
  operationState: NetworkOperationState.apReady,
  operationId: 'op_direct_settings',
  busy: false,
  baseUri: Uri.parse('http://192.168.8.1:8080'),
  directAp: const DirectApSnapshot(ssid: 'BirdBox-Test'),
  infrastructureSta: const InfrastructureStaSnapshot(saved: true),
  updatedAt: DateTime.utc(2026, 9, 2),
);
