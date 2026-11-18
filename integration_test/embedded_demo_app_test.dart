import 'dart:async';
import 'dart:io';
import 'package:aves/main_bird_demo.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/simulation/embedded_demo/demo_runtime.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/photo_tile.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_api.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/run/smart_follow_run_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('embedded Android app opens offline album, tabs, settings and continuous-copy details', (tester) async {
    HttpOverrides.global = null;
    final runtime = await DemoRuntime.start();
    addTearDown(runtime.close);
    await tester.pumpWidget(BirdEmbeddedDemoApp(runtime: runtime));
    Future<void> settle([int rounds = 25]) async {
      for (var i = 0; i < rounds; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    expect(find.text('演示版 · 内置模拟盒子'), findsOneWidget);
    expect(runtime.dependencies.deviceSessionCubit.state.isConnected, isTrue);
    expect(((await runtime.dependencies.apiClient.get('/api/v1/projects/current'))['batch'] as Map)['total_files'], 60);
    expect(find.byType(PhotoTile), findsWidgets);
    expect(tester.takeException(), isNull);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    for (final label in ['任务', '设备', '相册']) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)).first);
      await settle(12);
      expect(tester.takeException(), isNull, reason: label);
    }
    for (final route in [
      BirdRoutes.settingsPhotos,
      BirdRoutes.settingsCopyBackup,
      BirdRoutes.settingsStorageTarget,
      BirdRoutes.settingsDeviceDetails,
      BirdRoutes.settingsNetwork,
      BirdRoutes.settingsNetworkDiagnostics,
      BirdRoutes.settingsSystemLogs,
      BirdRoutes.settingsHelp,
    ]) {
      unawaited(nav.pushNamed(route));
      await settle(15);
      expect(tester.takeException(), isNull, reason: route);
      nav.pop();
      await settle(5);
    }
    final job = await runtime.dependencies.apiClient.post(
      '/api/v1/projects/mock-batch-current/analysis-jobs',
      data: {
        'mode': 'standard',
        'smart_follow': {'target_media_id': 'media_7f9a76e6c97690b61aedf6fd'},
      },
    );
    final sid = job['smart_follow_session_id'] as String;
    unawaited(
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => SmartFollowRunPage(repository: runtime.dependencies.smartFollowRepository, sessionId: sid),
        ),
      ),
    );
    await settle(150);
    final snapshot = await SmartFollowApi(runtime.dependencies.apiClient).session(sid);
    expect(snapshot.isFinished, isTrue);
    expect(snapshot.copiedFileCount, 60);
    expect(find.text('查看复制文件明细'), findsOneWidget);
    await tester.ensureVisible(find.text('查看复制文件明细'));
    await tester.tap(find.text('查看复制文件明细'));
    await settle();
    expect(find.text('复制文件明细'), findsOneWidget);
    expect(find.textContaining('DSC_'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
