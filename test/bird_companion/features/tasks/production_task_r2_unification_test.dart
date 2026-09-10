import 'dart:io';

import 'package:aves/bird_companion/core/sync/pending_operation.dart';
import 'package:aves/bird_companion/core/sync/sync_coordinator.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_sync_result_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('R2 production task detail unification', () {
    test('copy confirmation keeps one shared production task detail route', () {
      final confirmation = File(
        'lib/bird_companion/features/copy/presentation/'
        'copy_confirmation_page.dart',
      ).readAsStringSync();
      final router = File(
        'lib/bird_companion/app/app_router.dart',
      ).readAsStringSync();
      final compatibilityPage = File(
        'lib/bird_companion/features/jobs/presentation/'
        'job_detail_page.dart',
      ).readAsStringSync();

      // 任务进度联动（jobDetail 跳转）在后端交付后的阶段 D 接入；
      // 当前页面不再硬编码旧任务路由。
      expect(confirmation, isNot(contains('BirdRoutes.jobDetail')));
      expect(confirmation, contains('_CopySubmitResult'));
      expect(router, contains('JobDetailPage('));
      expect(
        compatibilityPage,
        contains('RepositoryTaskExperienceController('),
      );
      expect(compatibilityPage, contains('return TaskDetailPage('));
      expect(compatibilityPage, isNot(contains('JobDetailCubit')));
      expect(
        compatibilityPage,
        isNot(contains("title: const Text('处理详情')")),
      );
    });

    test('sync action uses the real service before refreshing box state', () {
      final root = File(
        'lib/bird_companion/features/tasks/presentation/'
        'task_experience_root.dart',
      ).readAsStringSync();

      final synchronize = root.indexOf('birdSyncService.synchronize()');
      final refresh = root.indexOf(
        'controller.refreshFromBox(includeScan: true)',
        synchronize,
      );
      expect(synchronize, greaterThanOrEqualTo(0));
      expect(refresh, greaterThan(synchronize));
      expect(root, contains('TaskSyncResultSheet('));
      expect(root, contains('PendingOperationStatus.conflict'));
    });
  });

  group('R2 sync result presentation', () {
    testWidgets('shows synced, failed, conflict and remaining counts', (
      tester,
    ) async {
      final failed = _operation(
        'failed',
        status: PendingOperationStatus.failed,
      );
      final conflict = _operation(
        'conflict',
        status: PendingOperationStatus.conflict,
      );
      final pending = _operation(
        'pending',
        status: PendingOperationStatus.pending,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskSyncResultSheet(
              result: SyncResult(
                syncedCount: 3,
                failedOperations: [failed, conflict],
                remainingOperations: [failed, conflict, pending],
              ),
            ),
          ),
        ),
      );

      expect(find.text('同步需要处理'), findsOneWidget);
      _expectCount('task-sync-synced-count', '3 项');
      _expectCount('task-sync-failed-count', '1 项');
      _expectCount('task-sync-conflict-count', '1 项');
      _expectCount('task-sync-remaining-count', '3 项');
      expect(find.text('处理冲突'), findsNothing);
    });

    testWidgets('forwards conflict handling when a project can be opened', (
      tester,
    ) async {
      var openCount = 0;
      final conflict = _operation(
        'conflict',
        status: PendingOperationStatus.conflict,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskSyncResultSheet(
              result: SyncResult(
                syncedCount: 0,
                failedOperations: [conflict],
                remainingOperations: [conflict],
              ),
              onOpenConflicts: () => openCount += 1,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('task-sync-open-conflicts')));
      await tester.pump();

      expect(openCount, 1);
    });
  });
}

PendingOperation _operation(
  String id, {
  required PendingOperationStatus status,
}) => PendingOperation(
  id: id,
  type: PendingOperationType.updateReview,
  payload: const {'file_id': 'file-1', 'version': 1},
  createdAt: DateTime.utc(2026, 8, 9),
  deviceId: 'device-1',
  projectId: 'project-1',
  fileId: 'file-1',
  status: status,
);

void _expectCount(String key, String value) {
  expect(
    find.descendant(
      of: find.byKey(Key(key)),
      matching: find.text(value),
    ),
    findsOneWidget,
  );
}
