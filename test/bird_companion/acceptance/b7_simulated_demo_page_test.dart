import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/connection/presentation/pages/b7_simulated_demo_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('B7 simulated demo is a runnable Bluetooth-to-network flow', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const B7SimulatedDemoPage()),
    );

    expect(find.text('发现附近盒子'), findsOneWidget);
    final readButton = find.ancestor(of: find.text('读取设备信息'), matching: find.byType(FilledButton));
    await tester.ensureVisible(readButton);
    tester.widget<FilledButton>(readButton).onPressed!();
    await tester.pump();
    expect(find.text('设备配对'), findsOneWidget);

    final pairButton = find.ancestor(of: find.text('安全配对并连接'), matching: find.byType(FilledButton));
    await tester.ensureVisible(pairButton);
    tester.widget<FilledButton>(pairButton).onPressed!();
    await tester.pump();
    expect(find.text('选择连接方式'), findsOneWidget);

    final apButton = find.ancestor(of: find.text('直连盒子'), matching: find.byType(FilledButton));
    await tester.ensureVisible(apButton);
    tester.widget<FilledButton>(apButton).onPressed!();
    await tester.pump();
    expect(find.text('正在启动盒子直连'), findsOneWidget);

    final confirmButton = find.ancestor(of: find.text('确认直连已就绪'), matching: find.byType(FilledButton));
    await tester.ensureVisible(confirmButton);
    tester.widget<FilledButton>(confirmButton).onPressed!();
    await tester.pump();
    expect(find.text('盒子直连已就绪'), findsOneWidget);
    expect(find.textContaining('真实 K7 仍为 pending'), findsOneWidget);
  });
}
