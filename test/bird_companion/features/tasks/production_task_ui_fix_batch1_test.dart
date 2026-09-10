import 'dart:io';

import 'package:aves/bird_companion/core/sync/pending_operation.dart';
import 'package:aves/bird_companion/core/sync/sync_coordinator.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_config_cubit.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_confirmation_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_sync_result_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('batch 1 copy title bar', () {
    testWidgets('content title stays centered at narrow width and 1.5x text', (
      tester,
    ) async {
      await _setViewport(tester, const Size(320, 680));
      var backCount = 0;

      await tester.pumpWidget(
        _scaledApp(
          home: CopyContentStep(
            state: _copyState,
            onBack: () => backCount++,
            onScopeSelected: (_) {},
            onSourceSelected: (_) {},
            onTargetSelected: (_) {},
            onPairPolicySelected: (_) {},
            onConflictSelected: (_) {},
            onReviewExportChanged: (_) {},
            onEmbedChanged: (_) {},
            onSaveDefaults: () {},
            onNext: () {},
          ),
        ),
      );

      expect(find.byKey(const Key('copy-flow-titlebar')), findsOneWidget);
      expect(find.text('复制照片'), findsOneWidget);
      expect(find.text('步骤 1 / 2 · 配置复制'), findsOneWidget);
      expect(
        tester.getCenter(find.byKey(const Key('copy-flow-title'))).dx,
        closeTo(160, 1),
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('copy-flow-back')));
      expect(backCount, 1);
    });

    testWidgets('confirmation title uses the same stable title bar', (
      tester,
    ) async {
      await _setViewport(tester, const Size(320, 680));

      await tester.pumpWidget(
        _scaledApp(
          home: CopyFinalConfirmationStep(
            state: _copyState,
            onBack: () {},
            onRefreshPreview: () {},
            onSubmit: () {},
          ),
        ),
      );

      expect(find.text('确认复制'), findsOneWidget);
      expect(find.text('步骤 2 / 2 · 最后确认'), findsOneWidget);
      expect(
        tester.getCenter(find.byKey(const Key('copy-flow-title'))).dx,
        closeTo(160, 1),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('batch 1 sync result sheet', () {
    testWidgets('outstanding result scrolls and actions stack on a short phone', (
      tester,
    ) async {
      await _setViewport(tester, const Size(320, 480));
      var openCount = 0;
      final conflict = _operation(
        'conflict',
        PendingOperationStatus.conflict,
      );
      final failed = _operation('failed', PendingOperationStatus.failed);

      await tester.pumpWidget(
        _scaledApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: TaskSyncResultSheet(
                result: SyncResult(
                  syncedCount: 20,
                  failedOperations: [conflict, failed],
                  remainingOperations: [conflict, failed],
                ),
                onOpenConflicts: () => openCount++,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('task-sync-result-scroll')), findsOneWidget);
      expect(find.byKey(const Key('task-sync-outstanding-notice')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('task-sync-open-conflicts')),
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('task-sync-open-conflicts')));
      await tester.pump();
      expect(openCount, 1);
    });

    testWidgets('successful result exposes one clear completion action', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TaskSyncResultSheet(
              result: SyncResult(
                syncedCount: 8,
                failedOperations: [],
                remainingOperations: [],
              ),
            ),
          ),
        ),
      );

      expect(find.text('同步完成'), findsOneWidget);
      expect(find.text('8 项修改已安全同步到盒子'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '完成'), findsOneWidget);
      expect(find.text('稍后处理'), findsNothing);
    });

    test('task root opens the sync result as a scroll-controlled sheet', () {
      final source = File(
        'lib/bird_companion/features/tasks/presentation/'
        'task_experience_root.dart',
      ).readAsStringSync();

      expect(source, contains('isScrollControlled: true'));
      expect(source, contains('TaskSyncResultSheet('));
    });
  });
}

const _copyState = CopyConfigState(
  scope: CopyScope.keptAssets,
  batchId: 'batch-1',
  sourceMediaId: 'media_source_1',
  loadingDevices: false,
  devices: [
    StorageDeviceSummary(
      mediaId: 'media_source_1',
      displayName: '相机卡（读卡器）',
      kind: 'card_reader',
      kindConfidence: 'high',
      detail: '双逻辑槽位读卡器 · 119.2 GB · EXFAT',
      capacityBytes: 128000000000,
      freeBytes: 96400000000,
      filesystem: 'exfat',
      label: '',
      roleState: 'available',
      canBeSource: true,
      canBeTarget: false,
      targetBlockReasons: ['当前任务源设备'],
      identityConfidence: 'stable_uuid',
    ),
    StorageDeviceSummary(
      mediaId: 'media_target_1',
      displayName: 'Samsung T7 Shield with a long storage name',
      kind: 'external_ssd',
      kindConfidence: 'high',
      detail: 'Samsung T7 · 2 TB · EXFAT',
      capacityBytes: 2000000000000,
      freeBytes: 1200000000000,
      filesystem: 'exfat',
      label: 'T7',
      roleState: 'available',
      canBeSource: false,
      canBeTarget: true,
      targetBlockReasons: [],
      identityConfidence: 'stable_uuid',
    ),
  ],
);

PendingOperation _operation(String id, PendingOperationStatus status) => PendingOperation(
  id: id,
  type: PendingOperationType.updateReview,
  payload: const {'file_id': 'file-1', 'version': 1},
  createdAt: DateTime.utc(2026, 8, 10),
  deviceId: 'device-1',
  projectId: 'project-1',
  fileId: 'file-1',
  status: status,
);

Widget _scaledApp({required Widget home}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: const TextScaler.linear(1.5)),
    child: child!,
  ),
  home: home,
);

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
