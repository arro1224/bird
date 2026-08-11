import 'dart:io';

import 'package:aves/bird_companion/core/sync/pending_operation.dart';
import 'package:aves/bird_companion/core/sync/sync_coordinator.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_confirmation_cubit.dart';
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
            onModeSelected: (_) {},
            onTargetSelected: (_) {},
            onXmpChanged: (_) {},
            onNext: () {},
            onSaveDefaults: () {},
          ),
        ),
      );

      expect(find.byKey(const Key('copy-flow-titlebar')), findsOneWidget);
      expect(find.text('复制照片'), findsOneWidget);
      expect(find.text('步骤 2 / 3 · 选择复制内容'), findsOneWidget);
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
            onSubmit: () {},
          ),
        ),
      );

      expect(find.text('确认复制'), findsOneWidget);
      expect(find.text('步骤 3 / 3 · 最后确认'), findsOneWidget);
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

const _copyState = CopyConfirmationState(
  mode: 'keep',
  targetId: 'target-1',
  estimate: CopyEstimate(
    mode: 'keep',
    fileCount: 2012,
    requiredBytes: 238700000000,
    pendingCount: 12,
    version: 7,
    targets: [
      StorageTarget(
        id: 'target-1',
        name: 'Samsung T7 Shield with a long storage name',
        freeBytes: 1200000000000,
        totalBytes: 2000000000000,
        online: true,
      ),
    ],
  ),
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
