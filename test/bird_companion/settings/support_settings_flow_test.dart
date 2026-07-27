import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/help_center_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/network_diagnostics_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/system_logs_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(theme: AppTheme.light(), home: child);

void main() {
  testWidgets('network diagnostics recheck has visible local progress', (tester) async {
    tester.view.physicalSize = const Size(426, 923);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(const NetworkDiagnosticsPage()));
    expect(find.text('网络连接正常'), findsOneWidget);

    await tester.tap(find.byKey(const Key('network-recheck')));
    await tester.pump();
    expect(find.text('正在重新检测网络…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('网络连接正常'), findsOneWidget);
  });

  testWidgets('system logs exposes local export feedback', (tester) async {
    await tester.pumpWidget(_app(const SystemLogsPage()));
    await tester.scrollUntilVisible(
      find.byKey(const Key('logs-export-package')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('logs-export-package')));
    await tester.pump();
    expect(find.text('演示模式不会生成真实诊断文件'), findsOneWidget);
  });

  testWidgets('help search filters the approved FAQ list', (tester) async {
    await tester.pumpWidget(_app(const HelpCenterPage()));
    expect(find.text('连接不上设备'), findsOneWidget);
    expect(find.text('如何导出 XMP'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('help-search')), 'XMP');
    await tester.pump();
    expect(find.text('连接不上设备'), findsNothing);
    expect(find.text('如何导出 XMP'), findsOneWidget);
  });
}
