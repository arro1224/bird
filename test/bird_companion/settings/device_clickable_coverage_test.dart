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
  testWidgets('network diagnostics avoids duplicate hotspot and switch entries', (
    tester,
  ) async {
    await _pump(tester, const NetworkDiagnosticsPage());

    expect(find.text('查看热点信息'), findsNothing);
    expect(find.text('切换网络'), findsNothing);
    expect(find.text('当前 IP'), findsNothing);
    expect(find.text('设备名称'), findsNothing);
    expect(find.byKey(const Key('network-recheck')), findsOneWidget);
    expect(find.byKey(const Key('network-export-diagnostics')), findsOneWidget);

    await tester.tap(find.byTooltip('帮助'));
    await tester.pumpAndSettle();
    expect(find.text('帮助中心'), findsOneWidget);
  });

  testWidgets('system logs arrows open complete detail experiences', (
    tester,
  ) async {
    await _pump(tester, const SystemLogsPage());

    await tester.tap(find.text('导出盒子运行日志'));
    await tester.pumpAndSettle();
    expect(find.text('请先连接拍鸟盒子后再导出诊断信息'), findsOneWidget);

    await tester.tap(find.text('异常说明'));
    await tester.pumpAndSettle();
    expect(find.text('操作失败'), findsOneWidget);
    expect(find.textContaining('不提供历史崩溃列表'), findsOneWidget);
    await _tapSettingsBack(tester);
  });

  testWidgets('system support entries use styled in-module pages', (
    tester,
  ) async {
    await _pump(tester, const SystemLogsPage());

    await tester.scrollUntilVisible(
      find.byKey(const Key('logs-privacy')),
      700,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logs-privacy')));
    await tester.pumpAndSettle();
    expect(find.text('本地优先'), findsOneWidget);
    await _tapSettingsBack(tester);

    await tester.scrollUntilVisible(
      find.byKey(const Key('logs-licenses')),
      700,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('logs-licenses')));
    await tester.pumpAndSettle();
    expect(find.text('本应用使用的开源组件及其许可文本由 Flutter 根据实际依赖生成。'), findsOneWidget);
    await _tapSettingsBack(tester);

    await tester.scrollUntilVisible(
      find.byKey(const Key('logs-about')),
      700,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('logs-about')));
    await tester.pumpAndSettle();
    expect(find.text('拍鸟伴侣'), findsOneWidget);
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
    expect(find.text('返回'), findsOneWidget);
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
