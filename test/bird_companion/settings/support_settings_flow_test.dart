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
    expect(find.text('演示模式不会生成真实诊断文件'), findsNothing);
    final button = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const Key('logs-export-package')),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('system logs follows the complete v1 page 12 structure', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(const SystemLogsPage()));

    for (final section in const [
      '版本信息',
      '日志与诊断',
      '存储与缓存',
      '隐私与说明',
    ]) {
      expect(find.text(section), findsOneWidget);
    }

    for (final entry in const [
      '软件版本',
      '固件版本',
      '模型版本',
      '导出设备日志',
      '错误记录',
      '最近崩溃记录',
      '清理缓存',
      '查看离线缩略图占用',
      '隐私说明',
      '开源许可',
      '关于应用',
    ]) {
      expect(find.text(entry), findsOneWidget);
    }
    expect(find.text('导出诊断包'), findsNWidgets(2));
    expect(find.byKey(const Key('logs-export-package')), findsOneWidget);
    expect(find.textContaining('无法连接盒子'), findsNothing);
    expect(find.text('2.1.0'), findsOneWidget);
    expect(find.text('1.2.4'), findsOneWidget);
    expect(find.text('BirdAI 3.0.2'), findsOneWidget);
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

  testWidgets('help center opens the real diagnostic export page', (tester) async {
    await tester.pumpWidget(_app(const HelpCenterPage()));

    await tester.scrollUntilVisible(
      find.byKey(const Key('help-send-diagnostics')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const Key('help-send-diagnostics')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('help-send-diagnostics')));
    await tester.pumpAndSettle();

    expect(find.text('系统与日志'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('logs-export-package')),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byKey(const Key('logs-export-package')), findsOneWidget);
  });
}
