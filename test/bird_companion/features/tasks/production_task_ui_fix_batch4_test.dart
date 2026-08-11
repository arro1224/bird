import 'package:aves/bird_companion/features/jobs/domain/job_failure.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_report.dart';
import 'package:aves/bird_companion/features/tasks/demo/demo_task_experience_data_source.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/production_task_result_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_result_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('batch 4 responsive task results', () {
    testWidgets('demo report scrolls, closes, and keeps album action reachable', (
      tester,
    ) async {
      await _setViewport(tester, const Size(320, 420));
      final controller = TaskExperienceController(
        const DemoTaskExperienceDataSource(),
      );
      addTearDown(controller.dispose);
      var albumOpenCount = 0;

      await tester.pumpWidget(
        _scaledApp(
          home: TaskResultPage(
            controller: controller,
            onOpenAlbum: () => albumOpenCount++,
          ),
        ),
      );

      final reportButton = find.byKey(
        const Key('task-result-open-report'),
      );
      await tester.ensureVisible(reportButton);
      expect(tester.takeException(), isNull);
      await tester.tap(reportButton);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('task-result-report-scroll')),
        findsOneWidget,
      );
      final closeButton = find.byKey(
        const Key('task-result-close-report'),
      );
      await tester.ensureVisible(closeButton);
      await tester.tap(closeButton);
      await tester.pumpAndSettle();

      final albumButton = find.byKey(
        const Key('task-result-open-album'),
      );
      await tester.ensureVisible(albumButton);
      await tester.tap(albumButton);
      expect(albumOpenCount, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('production metrics stack and long report values scroll', (
      tester,
    ) async {
      await _setViewport(tester, const Size(320, 480));
      const manifest = 'manifest-with-an-extremely-long-authoritative-server-identifier-20260810';

      await tester.pumpWidget(
        _scaledApp(
          home: ProductionTaskResultPage(
            report: JobReport(
              jobId: 'job-batch-4',
              result: JobReportResult.partialSuccess,
              totalCount: 12345,
              successCount: 12343,
              failedCount: 1,
              skippedCount: 1,
              copiedBytes: 9876543210,
              manifestId: manifest,
              startedAt: DateTime.utc(2026, 8, 10, 1),
              finishedAt: DateTime.utc(2026, 8, 10, 1, 8, 9),
            ),
            failures: const [
              JobFailure(
                fileId: 'DCIM/100BIRD/EXTREMELY-LONG-FILE-NAME-0001.ARW',
                reason: '目标存储暂时不可用，需要重新连接后重试该文件',
              ),
            ],
          ),
        ),
      );

      final openReport = find.byKey(
        const Key('production-task-open-report'),
      );
      await tester.ensureVisible(openReport);
      expect(tester.takeException(), isNull);
      await tester.tap(openReport);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('production-task-report-scroll')),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text(manifest));
      final labelRect = tester.getRect(find.text('清单 ID'));
      final valueRect = tester.getRect(find.text(manifest));
      expect(valueRect.top, greaterThan(labelRect.bottom));
      expect(tester.takeException(), isNull);
    });
  });
}

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
