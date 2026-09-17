import 'dart:async';

import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_config_cubit.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_confirmation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// 成功弹窗「查看任务进度」跳 RC3 任务详情（阶段 D 批次 4 验收）。
void main() {
  testWidgets('tap open-progress → push /copy-job-detail 携 CopyJobDetailArgs，返回后关闭复制页', (
    tester,
  ) async {
    final routeNames = <String?>[];
    final routeArgs = <Object?>[];
    final cubit = CopyConfigCubit(
      _WidgetFakeRepository(),
      batchId: 'batch-1',
      scope: CopyScope.batchAllAssets,
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: (settings) {
          routeNames.add(settings.name);
          routeArgs.add(settings.arguments);
          if (settings.name == '/test-copy-flow') {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => BlocProvider<CopyConfigCubit>.value(
                value: cubit,
                child: const CopyConfigFlow(batchId: 'batch-1'),
              ),
            );
          }
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: Text('复制任务详情占位')),
          );
        },
        home: const Scaffold(body: Text('home')),
      ),
    );
    unawaited(tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/test-copy-flow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await cubit.initialize();
    await tester.pump(const Duration(milliseconds: 100));
    cubit.selectTarget(_WidgetFakeRepository.targetId);
    cubit.setConflictStrategy(ConflictStrategy.skip);
    await cubit.fetchPreview();
    await tester.pump(const Duration(milliseconds: 100));
    await cubit.submit();
    await tester.pump(const Duration(milliseconds: 200));

    // 弹窗出现，主按钮可点。
    expect(find.byKey(const Key('copy-submit-result-open-progress')), findsOneWidget);
    await tester.tap(find.byKey(const Key('copy-submit-result-open-progress')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 300));

    expect(routeNames, contains('/copy-job-detail'));
    final detailIndex = routeNames.indexOf('/copy-job-detail');
    expect(routeArgs[detailIndex], isA<CopyJobDetailArgs>());
    expect((routeArgs[detailIndex] as CopyJobDetailArgs).copyJobId, _WidgetFakeRepository.jobId);
    // 复制页已关闭，停留在任务详情页。
    expect(find.text('复制任务详情占位'), findsOneWidget);
    expect(find.text('home'), findsNothing);
  });

  testWidgets('tap 返回 → 不跳详情，直接关闭复制页', (tester) async {
    final routeNames = <String?>[];
    final cubit = CopyConfigCubit(
      _WidgetFakeRepository(),
      batchId: 'batch-1',
      scope: CopyScope.batchAllAssets,
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: (settings) {
          routeNames.add(settings.name);
          if (settings.name == '/test-copy-flow') {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => BlocProvider<CopyConfigCubit>.value(
                value: cubit,
                child: const CopyConfigFlow(batchId: 'batch-1'),
              ),
            );
          }
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: Text('复制任务详情占位')),
          );
        },
        home: const Scaffold(body: Text('home')),
      ),
    );
    unawaited(tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/test-copy-flow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await cubit.initialize();
    await tester.pump(const Duration(milliseconds: 100));
    cubit.selectTarget(_WidgetFakeRepository.targetId);
    cubit.setConflictStrategy(ConflictStrategy.skip);
    await cubit.fetchPreview();
    await tester.pump(const Duration(milliseconds: 100));
    await cubit.submit();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byKey(const Key('copy-submit-result-close')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 300));

    expect(routeNames, isNot(contains('/copy-job-detail')));
    expect(find.text('home'), findsOneWidget);
  });
}

class _WidgetFakeRepository implements CopyRepository {
  static const targetId = 'media_target_1';
  static const jobId = 'copy_job_widget_1';

  @override
  Future<CopyCapabilities> capabilities() async => const CopyCapabilities(
    revision: '1.0-rc3',
    copyReady: true,
    supportedScopes: [CopyScope.batchAllAssets],
    recognitionPolicyVersion: 'recognized-assets-v1',
  );

  @override
  Future<SourceBinding> source({String? batchId}) async => SourceBinding(
    sourceMediaId: 'media_source_1',
    displayName: '相机卡（读卡器）',
    token: 'binding-token',
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    verifiedReadOnly: true,
    batchId: batchId,
  );

  @override
  Future<CopyPreferences> preferences() async =>
      const CopyPreferences(pairPolicy: PairPolicy.rawOnly, version: 1, origin: 'factory_default');

  @override
  Future<CopyPreferences> savePreferences(
    PairPolicy pairPolicy, {
    required int expectedVersion,
  }) async => CopyPreferences(
    pairPolicy: pairPolicy,
    version: expectedVersion + 1,
    origin: 'user_saved',
  );

  @override
  Future<List<CopyScopeOption>> scopeOptions({
    String? batchId,
    String? selectionId,
    Map<String, dynamic>? filter,
  }) async => [
    const CopyScopeOption(
      scope: CopyScope.batchAllAssets,
      available: true,
      logicalAssets: 120,
      countState: 'known',
      navigationAction: 'none',
    ),
  ];

  @override
  Future<CopyDeviceList> devices() async => const CopyDeviceList(devices: [
    StorageDeviceSummary(
      mediaId: 'media_source_1',
      displayName: '相机卡（读卡器）',
      kind: 'card_reader',
      kindConfidence: 'high',
      detail: '',
      capacityBytes: 128000000000,
      freeBytes: 96400000000,
      filesystem: 'exfat',
      label: '',
      roleState: 'available',
      canBeSource: true,
      canBeTarget: false,
      targetBlockReasons: [],
      identityConfidence: 'stable_uuid',
    ),
    StorageDeviceSummary(
      mediaId: targetId,
      displayName: 'U 盘 Ee',
      kind: 'usb_flash',
      kindConfidence: 'medium',
      detail: '',
      capacityBytes: 30765203456,
      freeBytes: 30500000000,
      filesystem: 'exfat',
      label: '',
      roleState: 'available',
      canBeSource: false,
      canBeTarget: true,
      targetBlockReasons: [],
      identityConfidence: 'stable_uuid',
    ),
  ]);

  @override
  Future<CopyPreview> preview(CopyRequestDraft draft) async => CopyPreview(
    previewToken: 'preview_token_widget',
    expiresAt: DateTime.now().add(const Duration(minutes: 15)),
    source: (await devices()).devices.first,
    target: (await devices()).devices.last,
    logicalPhotoCount: 120,
    actualFileCount: 239,
    totalBytes: 239 * 28 * 1024 * 1024,
    rawCount: 120,
    jpegCount: 119,
    videoCount: 0,
    companionCount: 2,
    estimatedDateDirectories: 3,
    conflictCount: 5,
    targetFreeBytes: 30500000000,
    safetyReserveBytes: 1538260172,
  );

  @override
  Future<CopyJobSummary> createJob(CopyRequestDraft draft, String previewToken) async =>
      CopyJobSummary(
        copyJobId: jobId,
        state: 'queued',
        eventSeq: 1,
        createdAt: DateTime.now(),
      );

  @override
  Future<CopySelectionSnapshot> createSelection(
    String batchId,
    List<String> assetIds, {
    required int clientRevision,
  }) async => CopySelectionSnapshot(
    selectionId: 'sel-1',
    assetCount: assetIds.length,
  );

  @override
  Future<BatchTargetPreference?> lastSuccessfulTarget(String batchId) async => null;

  @override
  Future<void> setDeviceAlias(String mediaId, String alias) async {}
}
