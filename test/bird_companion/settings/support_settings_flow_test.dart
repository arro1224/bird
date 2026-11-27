import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/help_center_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/device_information_pages.dart';
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
    expect(find.text('页面演示模式'), findsOneWidget);

    await tester.tap(find.byKey(const Key('network-recheck')));
    await tester.pump();
    expect(find.text('正在重新检测网络…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('页面演示模式'), findsOneWidget);
  });

  testWidgets('system logs phone diagnostics entry responds when tapped', (tester) async {
    await tester.pumpWidget(_app(const SystemLogsPage()));
    await tester.scrollUntilVisible(
      find.byKey(const Key('logs-export-package')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('logs-export-package')));
    await tester.pumpAndSettle();
    expect(find.text('暂未能准备手机诊断，请重试。'), findsOneWidget);
  });

  testWidgets('system logs follows the complete v1 page 12 structure', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(const SystemLogsPage()));

    for (final section in const ['日志与诊断', '应用信息']) {
      expect(find.text(section), findsOneWidget);
    }

    for (final entry in const [
      '导出盒子运行日志',
      '异常说明',
      '隐私说明',
      '开源许可',
      '关于应用',
    ]) {
      expect(find.text(entry), findsOneWidget);
    }
    expect(find.text('存储与缓存'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('logs-export-package')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('导出手机诊断包'), findsOneWidget);
    expect(find.byKey(const Key('logs-export-package')), findsOneWidget);
    expect(find.textContaining('两类文件来源不同'), findsOneWidget);
    expect(find.text('导出诊断包'), findsNothing);
    expect(find.text('最近崩溃记录'), findsNothing);
    expect(find.textContaining('无法连接盒子'), findsNothing);
    expect(find.text('2.1.0'), findsNothing);
    expect(find.text('1.2.4'), findsNothing);
    expect(find.text('BirdAI 3.0.2'), findsNothing);
    expect(find.text('未读取'), findsNothing);
  });

  testWidgets('exception explanation distinguishes failures from crashes without pretending to show records', (tester) async {
    await tester.pumpWidget(_app(const DiagnosticRecordsPage()));

    expect(find.text('异常说明'), findsOneWidget);
    expect(find.text('操作失败'), findsOneWidget);
    expect(find.text('应用崩溃'), findsOneWidget);
    expect(find.textContaining('某项功能未能完成，但应用仍可继续使用'), findsOneWidget);
    expect(find.textContaining('崩溃记录由手机系统管理'), findsOneWidget);
    expect(find.textContaining('不是错误/崩溃历史记录'), findsOneWidget);
    expect(find.byType(SegmentedButton<bool>), findsNothing);
  });

  testWidgets('about page does not repeat privacy and support destinations', (tester) async {
    await tester.pumpWidget(_app(const AboutBirdAppPage()));

    expect(find.text('拍鸟伴侣'), findsOneWidget);
    expect(find.textContaining('版本'), findsOneWidget);
    expect(find.text('隐私说明'), findsNothing);
    expect(find.text('开源许可'), findsNothing);
    expect(find.text('帮助中心'), findsNothing);
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

  testWidgets('help center opens the system and logs page', (tester) async {
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
