import 'dart:io';

import 'package:aves/bird_companion/features/jobs/domain/job_failure.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_report.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/production_task_result_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('R0 production task navigation baseline', () {
    test('all four task entries stay on production-backed routes', () {
      final root = File(
        'lib/bird_companion/features/tasks/presentation/'
        'task_experience_root.dart',
      ).readAsStringSync();

      expect(root, contains('RepositoryTaskExperienceController'));
      expect(root, isNot(contains('DemoTaskExperienceDataSource')));
      expect(root, contains('onStartTask: _startTask'));
      expect(root, contains('case TaskType.importIndex:'));
      expect(root, contains('_openSdCard();'));
      expect(root, contains('case TaskType.aiAnalysis:'));
      expect(root, contains('startAnalysisForActiveProject()'));
      expect(root, contains('_openTask(jobId)'));
      expect(root, contains('case TaskType.copy:'));
      expect(root, contains('BirdRoutes.copyConfirmation'));
      expect(root, contains('case TaskType.sync:'));
      expect(root, contains('refreshFromBox(includeScan: true)'));
    });

    test('copy completion keeps the real job and source project for report flow', () {
      final root = File(
        'lib/bird_companion/features/tasks/presentation/'
        'task_experience_root.dart',
      ).readAsStringSync();

      expect(root, contains('controller.copyCompletedJobs.listen((jobId)'));
      expect(root, contains('_openReport('));
      expect(root, contains('report(jobId)'));
      expect(root, contains('jobRepository.failurePage(jobId)'));
      expect(root, contains('ProductionTaskResultPage('));
      expect(root, contains('GalleryArgs(sourceProjectId)'));
    });

    test('disconnect notices and authoritative reconnect refresh remain wired', () {
      final detailPage = File(
        'lib/bird_companion/features/tasks/presentation/pages/'
        'task_detail_page.dart',
      ).readAsStringSync();
      final controller = File(
        'lib/bird_companion/features/tasks/presentation/'
        'repository_task_experience_controller.dart',
      ).readAsStringSync();

      expect(detailPage, contains('TaskConnectionState.disconnected'));
      expect(detailPage, contains('TaskDisconnectedNotice'));
      expect(detailPage, contains('TaskConnectionState.reconnecting'));
      expect(detailPage, contains('_reconnectingNotice()'));
      expect(controller, contains('state.isConnected && previous !='));
      expect(controller, contains('refreshFromBox(includeScan: true)'));
    });
  });

  group('R0 production report widget baseline', () {
    testWidgets('partial report renders authoritative counts and failures', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 1100);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: ProductionTaskResultPage(
            report: JobReport(
              jobId: 'job-copy-42',
              result: JobReportResult.partialSuccess,
              totalCount: 12,
              successCount: 10,
              failedCount: 1,
              skippedCount: 1,
            ),
            failures: [
              JobFailure(
                fileId: 'DSC_0042.ARW',
                reason: '目标存储空间不足',
                code: 'target_full',
              ),
            ],
          ),
        ),
      );

      expect(find.text('照片部分复制完成'), findsOneWidget);
      await tester.tap(find.text('查看复制报告'));
      await tester.pumpAndSettle();

      expect(find.text('总计'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('成功'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('DSC_0042.ARW'), findsOneWidget);
      expect(find.text('目标存储空间不足'), findsOneWidget);
    });

    testWidgets('successful copy report forwards the album action', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var openAlbumCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ProductionTaskResultPage(
            report: const JobReport(
              jobId: 'job-copy-43',
              result: JobReportResult.success,
              totalCount: 24,
              successCount: 24,
              failedCount: 0,
              skippedCount: 0,
            ),
            onOpenAlbum: () => openAlbumCount += 1,
          ),
        ),
      );

      expect(find.text('照片复制完成'), findsOneWidget);
      expect(find.text('进入相册'), findsOneWidget);

      await tester.tap(find.text('进入相册'));

      expect(openAlbumCount, 1);
    });
  });
}
