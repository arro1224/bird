import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/copy_backup_settings_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/help_center_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/network_diagnostics_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/system_logs_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('network diagnostic secondary entries open styled targets', (
    tester,
  ) async {
    await _pump(tester, const NetworkDiagnosticsPage());

    await tester.tap(find.text('查看热点信息'));
    await tester.pumpAndSettle();
    expect(find.text('热点信息'), findsOneWidget);
    expect(find.text('安全类型'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('帮助'));
    await tester.pumpAndSettle();
    expect(find.text('帮助中心'), findsOneWidget);
  });

  testWidgets('network actions navigate in the isolated demo app', (
    tester,
  ) async {
    await _pump(tester, const NetworkDiagnosticsPage());

    await tester.tap(find.text('切换网络'));
    await tester.pumpAndSettle();
    expect(find.text('更换设备'), findsOneWidget);
    await _tapSettingsBack(tester);

    await tester.tap(find.text('导出诊断结果'));
    await tester.pumpAndSettle();
    expect(find.text('系统与日志'), findsOneWidget);
  });

  testWidgets('system logs arrows open complete detail experiences', (
    tester,
  ) async {
    await _pump(tester, const SystemLogsPage());

    await tester.tap(find.text('软件版本'));
    await tester.pumpAndSettle();
    expect(find.text('版本详情'), findsOneWidget);
    expect(find.text('设备协议'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('错误记录'));
    await tester.pumpAndSettle();
    expect(find.text('诊断记录'), findsOneWidget);
    expect(find.text('暂无错误记录'), findsOneWidget);
    await _tapSettingsBack(tester);

    await tester.tap(find.text('清理缓存'));
    await tester.pumpAndSettle();
    expect(find.text('存储与缓存'), findsOneWidget);
    expect(find.text('缓存明细'), findsOneWidget);
  });

  testWidgets('system support entries use styled in-module pages', (
    tester,
  ) async {
    await _pump(tester, const SystemLogsPage());

    await tester.scrollUntilVisible(
      find.text('隐私说明'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('隐私说明'));
    await tester.pumpAndSettle();
    expect(find.text('本地优先'), findsOneWidget);
    await _tapSettingsBack(tester);

    await tester.scrollUntilVisible(
      find.text('开源许可'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('开源许可'));
    await tester.pumpAndSettle();
    expect(find.text('第三方组件'), findsOneWidget);
    await _tapSettingsBack(tester);

    await tester.scrollUntilVisible(
      find.text('关于应用'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('关于应用'));
    await tester.pumpAndSettle();
    expect(find.text('产品定位'), findsOneWidget);
  });

  testWidgets('help entries open FAQ feedback and guide pages', (tester) async {
    await _pump(tester, const HelpCenterPage());

    await tester.tap(find.text('连接不上设备'));
    await tester.pumpAndSettle();
    expect(find.text('先检查这些项目'), findsOneWidget);
    await _tapSettingsBack(tester);

    await tester.tap(find.text('提交问题反馈'));
    await tester.pumpAndSettle();
    expect(find.text('问题描述'), findsOneWidget);
    expect(find.text('提交反馈'), findsOneWidget);
    await _tapSettingsBack(tester);

    await tester.tap(find.text('查看用户指南'));
    await tester.pumpAndSettle();
    expect(find.text('快速开始'), findsOneWidget);
  });

  testWidgets('copy naming policy keeps its styled information sheet', (
    tester,
  ) async {
    final controller = BirdSettingsController();
    addTearDown(controller.dispose);

    await _pump(tester, CopyBackupSettingsPage(controller: controller));
    await tester.tap(find.text('命名与目录规则'));
    await tester.pumpAndSettle();
    expect(find.text('保留原始文件名'), findsOneWidget);
    expect(find.text('固定目录规则'), findsOneWidget);
    expect(find.text('协议限制'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('复制与备份'), findsOneWidget);
  });
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      onGenerateRoute: BirdAppRouter.onGenerateRoute,
      home: home,
    ),
  );
  await tester.pump();
}

Future<void> _tapSettingsBack(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('settings-back')));
  await tester.pumpAndSettle();
}
