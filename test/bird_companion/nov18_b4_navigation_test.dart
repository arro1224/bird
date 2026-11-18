import 'dart:async';

import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/app_shell.dart';
import 'package:aves/bird_companion/core/widgets/navigation_guard.dart';
import 'package:aves/bird_companion/features/gallery/presentation/gallery_page.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/photo_tile.dart';
import 'package:aves/bird_companion/features/device/presentation/widgets/device_status_sheet.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/device_details_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/network_diagnostics_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/settings_showcase_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'nov18_navigation_test_support.dart';

void main() {
  testWidgets('导航保护覆盖慢读取、目标页停留及返回，再次进入可用', (tester) async {
    final ready = Completer<void>();
    final observer = B4RouteObserver();
    late BuildContext source;
    var reads = 0;
    Future<void> open() => guardBirdNavigation<void>(source, () async {
      reads++;
      await ready.future;
      if (source.mounted) await Navigator.of(source).pushNamed('/target');
    });
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        routes: {'/target': (_) => const Scaffold(body: Text('target'))},
        home: Builder(
          builder: (context) {
            source = context;
            return const Scaffold();
          },
        ),
      ),
    );
    unawaited(open());
    unawaited(open());
    await tester.pump(const Duration(seconds: 3));
    unawaited(open());
    expect(reads, 1, reason: '保护不因固定延时结束');
    ready.complete();
    await tester.pumpAndSettle();
    unawaited(open());
    expect(observer.count('/target'), 1);
    Navigator.of(source).pop();
    await tester.pumpAndSettle();
    unawaited(open());
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(observer.count('/target'), 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('读取失败释放保护，子页面仍能打开自己的详情', (tester) async {
    late BuildContext source;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            source = context;
            return const Scaffold();
          },
        ),
      ),
    );
    await expectLater(guardBirdNavigation<void>(source, () async => throw StateError('read failed')), throwsStateError);
    unawaited(
      guardBirdNavigation<void>(
        source,
        () => Navigator.of(source).push(
          MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => guardBirdNavigation<void>(context, () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('nested detail'))))),
                child: const Text('open nested'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open nested'));
    await tester.pumpAndSettle();
    expect(find.text('nested detail'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('设置真实入口连点和交叉点击只开一页，底部栏保持隐藏至返回', (tester) async {
    final observer = B4RouteObserver();
    final visibility = <bool>[];
    await tester.pumpWidget(
      BirdShellNavigation(
        selectTab: (_) {},
        openTabRoute: (_, _, [_]) {},
        setBottomNavigationVisible: visibility.add,
        child: MaterialApp(navigatorObservers: [observer], home: const SettingsShowcasePage(embedded: true)),
      ),
    );
    final details = tester.widget<InkWell>(find.byKey(const Key('showcase-device-details'))).onTap!;
    final network = tester.widget<InkWell>(find.byKey(const Key('showcase-network-diagnostics'))).onTap!;
    details();
    details();
    network();
    await tester.pumpAndSettle();
    expect(observer.pushes.length, 2);
    expect(find.byType(DeviceDetailsPage), findsOneWidget);
    expect(visibility, [false]);
    await tester.tap(find.byKey(const Key('settings-back')));
    await tester.pumpAndSettle();
    expect(visibility.last, true);
    network();
    await tester.pumpAndSettle();
    expect(find.byType(NetworkDiagnosticsPage), findsOneWidget);
    expect(observer.pushes.length, 3);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('设备详情导出日志入口只开一页，返回后可重开', (tester) async {
    final observer = B4RouteObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: DeviceDetailsPage(controller: BirdSettingsController()),
      ),
    );
    final open = tester.widget<TextButton>(find.widgetWithText(TextButton, '导出日志')).onPressed!;
    open();
    open();
    open();
    await tester.pumpAndSettle();
    expect(observer.pushes.length, 2);
    await tester.tap(find.byKey(const Key('settings-back')));
    await tester.pumpAndSettle();
    open();
    await tester.pumpAndSettle();
    expect(observer.pushes.length, 3);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('网络诊断热点弹层连点只开一个，关闭后可重开', (tester) async {
    final observer = B4RouteObserver();
    await tester.pumpWidget(MaterialApp(navigatorObservers: [observer], home: const NetworkDiagnosticsPage()));
    final open = tester.widget<BirdSettingsRow>(find.byKey(const Key('network-hotspot-details'))).onTap!;
    open();
    open();
    open();
    await tester.pumpAndSettle();
    expect(observer.pushes.whereType<PopupRoute>(), hasLength(1));
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    open();
    await tester.pumpAndSettle();
    expect(observer.pushes.whereType<PopupRoute>(), hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('图库图片真实入口连点只打开一次详情，返回后可再开', (tester) async {
    final deps = B4Dependencies();
    addTearDown(deps.close);
    final observer = B4RouteObserver();
    await pumpB4(
      tester,
      const GalleryPage(batchId: 'project-1', totalCount: 14),
      deps,
      observers: [observer],
      routes: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const Scaffold(body: Text('photo detail')),
      ),
    );
    final tile = tester.widget<PhotoTile>(find.byType(PhotoTile).first);
    tile.onTap();
    tile.onTap();
    await tester.pumpAndSettle();
    expect(observer.count(BirdRoutes.photoDetail), 1);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    tester.widget<PhotoTile>(find.byType(PhotoTile).first).onTap();
    await tester.pumpAndSettle();
    expect(observer.count(BirdRoutes.photoDetail), 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final outcome in ['success', 'failure', 'device_switch']) {
    testWidgets('图库复制入口慢读取连点：$outcome', (tester) async {
      final deps = B4Dependencies();
      addTearDown(deps.close);
      final observer = B4RouteObserver();
      final read = Completer<void>();
      await pumpB4(
        tester,
        const GalleryPage(batchId: 'project-1', totalCount: 14, rootMode: true),
        deps,
        observers: [observer],
        routes: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const Scaffold(body: Text('copy config')),
        ),
      );
      deps.batchRepository.readCurrent = () async {
        await read.future;
        if (outcome == 'failure') throw StateError('temporary read failure');
        return B4Batches.batch;
      };
      final copy = tester.widget<IconButton>(find.byKey(const Key('album-copy-project-button'))).onPressed!;
      copy();
      copy();
      await tester.pump(const Duration(seconds: 3));
      copy();
      expect(deps.batchRepository.reads, 1);
      expect(deps.jobRepository.reads, 1);
      if (outcome == 'device_switch') deps.deviceSessionCubit.switchDevice();
      read.complete();
      await tester.pumpAndSettle();
      expect(observer.count(BirdRoutes.copyConfirmation), outcome == 'success' ? 1 : 0);
      if (outcome == 'failure') {
        deps.batchRepository.readCurrent = null;
        copy();
        await tester.pumpAndSettle();
        expect(observer.count(BirdRoutes.copyConfirmation), 1);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final target in ['details', 'reconnect']) {
    testWidgets('设备状态弹层退出动作只执行一次：$target', (tester) async {
      final deps = B4Dependencies();
      addTearDown(deps.close);
      final observer = B4RouteObserver();
      await pumpB4(
        tester,
        const GalleryPage(batchId: 'project-1', totalCount: 14, rootMode: true),
        deps,
        observers: [observer],
        routes: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const Scaffold(body: Text('destination')),
        ),
      );
      final status = find.byKey(const ValueKey('album-device-status'));
      await tester.tap(status);
      await tester.pumpAndSettle();
      final sheet = tester.widget<DeviceStatusSheet>(find.byType(DeviceStatusSheet));
      final action = target == 'details' ? sheet.onOpenDetails : sheet.onReconnect;
      action();
      action();
      await tester.pumpAndSettle();
      expect(find.byType(DeviceStatusSheet), findsNothing);
      expect(observer.count(target == 'details' ? BirdRoutes.settingsDeviceDetails : BirdRoutes.connection), 1);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      expect(find.byType(GalleryPage), findsOneWidget);
      await tester.tap(status);
      await tester.pumpAndSettle();
      expect(find.byType(DeviceStatusSheet), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('重新连接先核实期间及连接页存活期间不重复打开', (tester) async {
    final deps = B4Dependencies();
    addTearDown(deps.close);
    final observer = B4RouteObserver();
    deps.deviceSessionCubit.verification = Completer<bool>();
    await pumpB4(
      tester,
      DeviceDetailsPage(controller: BirdSettingsController()),
      deps,
      observers: [observer],
      routes: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const Scaffold(body: Text('connection')),
      ),
    );
    final reconnect = tester.widget<TextButton>(find.byKey(const Key('device-reconnect'))).onPressed!;
    reconnect();
    reconnect();
    await tester.pump(const Duration(seconds: 3));
    expect(deps.deviceSessionCubit.verificationCalls, 1);
    deps.deviceSessionCubit.verification!.complete(false);
    await tester.pumpAndSettle();
    reconnect();
    expect(observer.count(BirdRoutes.connection), 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
