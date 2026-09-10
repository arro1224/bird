import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/app_shell.dart';
import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/storage_target_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/settings_showcase_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('all settings named routes build their approved page', (tester) async {
    final expectations = <String, String>{
      BirdRoutes.settingsDeviceManagement: '更换设备',
      BirdRoutes.settingsDeviceDetails: '设备详情',
      BirdRoutes.settingsDisplay: '显示设置',
      BirdRoutes.settingsPhotos: '照片设置',
      BirdRoutes.settingsCopyBackup: '复制与备份',
      BirdRoutes.settingsStorageTarget: '存储设备',
      BirdRoutes.settingsNetworkDiagnostics: '网络诊断',
      BirdRoutes.settingsSystemLogs: '系统与日志',
      BirdRoutes.settingsHelp: '帮助中心',
    };

    for (final entry in expectations.entries) {
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          theme: AppTheme.light(),
          initialRoute: entry.key,
          onGenerateRoute: BirdAppRouter.onGenerateRoute,
          onGenerateInitialRoutes: (initialRoute) => [
            BirdAppRouter.onGenerateRoute(RouteSettings(name: initialRoute)),
          ],
        ),
      );
      await tester.pump();
      expect(find.text(entry.value), findsWidgets, reason: entry.key);
    }
  });

  testWidgets('settings showcase follows the device information architecture', (tester) async {
    _useTallViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const SettingsShowcasePage(),
      ),
    );

    expect(find.text('设备'), findsNWidgets(2));
    expect(find.text('我的'), findsNothing);
    expect(find.byKey(const Key('showcase-device-card')), findsOneWidget);

    for (final section in const ['当前工作', '设备与连接', '照片与审阅', '复制与导出', '系统支持']) {
      expect(find.text(section), findsOneWidget);
    }

    for (final entry in const [
      '连接设备',
      '设备详情',
      '网络诊断',
      '浏览与显示',
      '照片处理默认值',
      '复制默认设置',
      '存储设备',
      '系统与日志',
      '帮助中心',
    ]) {
      expect(
        find.text(entry),
        entry == '连接设备' ? findsNWidgets(2) : findsOneWidget,
      );
    }

    expect(find.text('更换设备'), findsNothing);
    expect(find.text('偏好设置'), findsNothing);
    expect(find.text('支持与关于'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('all nine device entries open their existing secondary pages', (tester) async {
    _useTallViewport(tester);
    final expectations = <Key, String>{
      const Key('showcase-device-management'): '更换设备',
      const Key('showcase-device-details'): '设备详情',
      const Key('showcase-network-diagnostics'): '网络诊断',
      const Key('showcase-display-settings'): '显示设置',
      const Key('showcase-photo-settings'): '照片设置',
      const Key('showcase-copy-settings'): '复制与备份',
      const Key('showcase-storage-target'): '存储设备',
      const Key('showcase-system-logs'): '系统与日志',
      const Key('showcase-help-center'): '帮助中心',
    };

    for (final entry in expectations.entries) {
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          theme: AppTheme.light(),
          home: const SettingsShowcasePage(embedded: true),
        ),
      );
      expect(find.byKey(entry.key), findsOneWidget, reason: entry.key.toString());
      expect(
        tester.getSize(find.byKey(entry.key)).height,
        greaterThanOrEqualTo(40),
      );
      await tester.tap(find.byKey(entry.key));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsWidgets, reason: entry.key.toString());
    }
  });

  testWidgets('storage device page renders a box-offline fallback without a session', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: StorageTargetPage(controller: BirdSettingsController()),
      ),
    );
    await tester.pump();

    expect(find.text('存储设备'), findsOneWidget);
    expect(find.textContaining('连接盒子后可查看'), findsOneWidget);
  });

  testWidgets('secondary device pages hide the shell navigation until returning', (
    tester,
  ) async {
    _useTallViewport(tester);
    final visibility = <bool>[];
    await tester.pumpWidget(
      BirdShellNavigation(
        selectTab: (_) {},
        openTabRoute: (_, _, [_]) {},
        setBottomNavigationVisible: visibility.add,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SettingsShowcasePage(embedded: true),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('showcase-device-details')));
    await tester.pumpAndSettle();
    expect(visibility.last, isFalse);

    await tester.tap(find.byKey(const Key('settings-back')));
    await tester.pumpAndSettle();
    expect(visibility.last, isTrue);
  });
}

void _useTallViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 1600);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
