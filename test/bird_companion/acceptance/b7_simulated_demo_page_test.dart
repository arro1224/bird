import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/connection/presentation/pages/b7_simulated_demo_page.dart';
import 'package:aves/bird_companion/features/connection/presentation/b7_simulated_provisioning_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> settleSimulatedEvent(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('B7 simulated demo is a runnable Bluetooth-to-network flow', (tester) async {
    final repository = B7SimulatedProvisioningRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: B7SimulatedDemoPage(repository: repository),
      ),
    );
    addTearDown(repository.dispose);

    await settleSimulatedEvent(tester);
    expect(find.text('附近的盒子'), findsOneWidget);
    expect(find.text('B7 模拟 · 查找盒子'), findsOneWidget);
    await tester.tap(find.text('连接此盒子'));
    await settleSimulatedEvent(tester);
    expect(find.text('设备验证完成'), findsOneWidget);
    expect(repository.calls, contains('connect:demo-b7'));

    await tester.tap(find.text('开始配对'));
    await settleSimulatedEvent(tester);
    final code = find.byType(TextField);
    await tester.enterText(code, '123456');
    await tester.tap(find.text('安全配对并连接'));
    await settleSimulatedEvent(tester);
    expect(find.text('选择连接方式'), findsOneWidget);
    expect(repository.calls, contains('authorizePairing'));

    await tester.tap(find.text('直连盒子'));
    await tester.pump();
    expect(find.text('正在启动盒子直连'), findsOneWidget);
    expect(repository.calls, contains('startDirectAp'));

    await settleSimulatedEvent(tester);
    expect(find.text('盒子直连已就绪'), findsOneWidget);
    expect(repository.calls, contains('getNetworkStatus'));
  });

  testWidgets('B7 simulated demo exposes the real Wi-Fi method state flow', (tester) async {
    final repository = B7SimulatedProvisioningRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: B7SimulatedDemoPage(repository: repository),
      ),
    );
    addTearDown(repository.dispose);
    await settleSimulatedEvent(tester);

    await tester.tap(find.text('连接此盒子'));
    await settleSimulatedEvent(tester);
    await tester.tap(find.text('开始配对'));
    await settleSimulatedEvent(tester);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('安全配对并连接'));
    await settleSimulatedEvent(tester);
    await tester.tap(find.text('加入现有 Wi-Fi'));
    await settleSimulatedEvent(tester);

    expect(find.text('B7 模拟 · Wi-Fi 配网'), findsOneWidget);
    expect(find.text('选择 Wi-Fi 配网方式'), findsOneWidget);
    expect(repository.calls, contains('connect:demo-b7'));
  });
}
