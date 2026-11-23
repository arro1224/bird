import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/features/connection/presentation/connection_page.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/discovered_device_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/reusable_provisioning_repository.dart';

/// Shared production-widget scenarios. The BLE transport is simulated on both
/// the host and Android; this does not verify native scanning or a real box.
void registerTask1UiScenarios() {
  testWidgets('T1 A15 current and candidate sections fit a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = ReusableProvisioningRepository(current: firstBleDevice, advertisements: [secondBleDevice]);
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ConnectionPage(provisioningRepository: repository),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('current-ble-device')), findsOneWidget);
    await tester.ensureVisible(find.text('连接此盒子'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets('T1 A15 current trusted box survives rescan, reentry and foreground without advertising', (tester) async {
    final repository = ReusableProvisioningRepository(current: firstBleDevice);
    addTearDown(repository.dispose);
    for (var i = 0; i < 3; i++) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: ConnectionPage(provisioningRepository: repository),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('current-ble-device')), findsOneWidget);
      expect(find.text('BirdBox-Current'), findsOneWidget);
      expect(find.text('暂未发现盒子'), findsNothing);
      await tester.ensureVisible(find.text('重新搜索'));
      await tester.tap(find.text('重新搜索'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('current-ble-device')), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      // A real integration binding suspends frames while paused. Drain the
      // repository's async cleanup without awaiting a frame until resumed.
      await tester.idle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('current-ble-device')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
    expect(repository.claims, 0);
    expect(repository.endedSessions, 0);
    expect(repository.calls, isNot(contains('disconnect')));
  });

  testWidgets('T1 A15 current advertisement is not duplicated and lost control is removed', (tester) async {
    final repository = ReusableProvisioningRepository(current: firstBleDevice, advertisements: [firstBleDevice, secondBleDevice, secondBleDevice]);
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ConnectionPage(provisioningRepository: repository),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('BirdBox-Current'), findsOneWidget);
    expect(find.text('BirdBox-Other'), findsOneWidget);
    expect(find.text('连接此盒子'), findsOneWidget);
    repository.emitDisconnect();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('current-ble-device')), findsNothing);
    expect(find.text('当前蓝牙盒子'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('T1 A15 history stays unverified and current business card is explicit', (tester) async {
    final device = DeviceConnection(id: firstBleInfo.deviceId, name: firstBleInfo.deviceName, baseUri: Uri.parse('http://192.0.2.1:8080'), networkMode: NetworkMode.directAp, isPaired: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ListView(
            children: [
              DiscoveredDeviceCard(device: device, isRecent: true, onConnect: () {}),
              DiscoveredDeviceCard(device: device, isConnected: true, onConnect: () {}),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('最近使用 · 状态待确认'), findsOneWidget);
    expect(find.textContaining('业务已验证'), findsOneWidget);
    expect(find.text('返回此盒子'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
