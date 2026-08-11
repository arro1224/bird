import 'dart:io';

import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/features/jobs/data/job_api.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_failure.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_page.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_report.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_repository.dart';
import 'package:aves/bird_companion/features/jobs/presentation/job_center_cubit.dart';
import 'package:aves/bird_companion/features/tasks/demo/demo_task_experience_data_source.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/adapters/job_status_view_adapter.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/production_task_result_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_detail_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('R4 workflow stage', () {
    test('adapter preserves workflow_stage and reports future values', () {
      String? unknown;
      JobStatusViewAdapter.unknownWorkflowStageReporter = (value) {
        unknown = value;
      };
      addTearDown(() {
        JobStatusViewAdapter.unknownWorkflowStageReporter = null;
      });

      final known = JobStatusViewAdapter.toTaskSummary(
        const BirdJobStatus(
          id: 'job-copy-known',
          type: BirdJobType.copy,
          state: BirdJobState.running,
          workflowStage: 'verifying',
        ),
      );
      final future = JobStatusViewAdapter.toTaskSummary(
        const BirdJobStatus(
          id: 'job-copy-future',
          type: BirdJobType.copy,
          state: BirdJobState.running,
          workflowStage: 'future_copy_stage',
        ),
      );

      expect(known?.workflowStage, 'verifying');
      expect(future?.workflowStage, 'future_copy_stage');
      expect(unknown, 'future_copy_stage');
    });

    testWidgets('unknown stage is generic and progress does not select step', (
      tester,
    ) async {
      final controller =
          TaskExperienceController(
            const DemoTaskExperienceDataSource(),
          )..replaceRepositoryTasks(const [
            TaskSummary(
              id: 'job-copy-r4',
              type: TaskType.copy,
              title: '复制',
              processed: 99,
              total: 100,
              progressPercent: 99,
              remainingMinutes: 1,
              state: TaskRunState.running,
              workflowStage: 'future_copy_stage',
            ),
          ]);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: TaskDetailPage(controller: controller)),
      );

      expect(find.text('处理中'), findsOneWidget);
      final source = File(
        'lib/bird_companion/features/tasks/presentation/pages/task_detail_page.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('progressPercent * 4')));
    });
  });

  group('R4 result and report', () {
    testWidgets('result uses result enum and report failures paginate', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? requestedCursor;

      await tester.pumpWidget(
        MaterialApp(
          home: ProductionTaskResultPage(
            report: JobReport(
              jobId: 'job-copy-report',
              result: JobReportResult.partialSuccess,
              totalCount: 12,
              successCount: 10,
              failedCount: 2,
              skippedCount: 0,
              copiedBytes: 1536,
              manifestId: 'manifest-42',
              startedAt: DateTime.utc(2026, 8, 9, 1),
              finishedAt: DateTime.utc(2026, 8, 9, 1, 2, 3),
            ),
            initialFailurePage: const JobFailurePage(
              items: [JobFailure(fileId: 'A.ARW', reason: '读取失败')],
              hasMore: true,
              nextCursor: 'cursor-2',
            ),
            loadFailurePage: (cursor) async {
              requestedCursor = cursor;
              return const JobFailurePage(
                items: [JobFailure(fileId: 'B.ARW', reason: '写入失败')],
                hasMore: false,
              );
            },
          ),
        ),
      );

      expect(find.text('照片部分复制完成'), findsOneWidget);
      expect(find.text('盒子未提供权威数量'), findsOneWidget);
      await tester.tap(find.text('查看复制报告'));
      await tester.pumpAndSettle();

      expect(find.text('复制报告'), findsOneWidget);
      expect(find.text('manifest-42'), findsOneWidget);
      expect(find.text('2 分 3 秒'), findsWidgets);
      expect(find.text('A.ARW'), findsOneWidget);

      await tester.tap(find.byKey(const Key('report-load-more-failures')));
      await tester.pumpAndSettle();

      expect(requestedCursor, 'cursor-2');
      expect(find.text('B.ARW'), findsOneWidget);
      expect(find.byKey(const Key('report-load-more-failures')), findsNothing);
    });

    testWidgets('failed result is not inferred from failed count', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ProductionTaskResultPage(
            report: JobReport(
              jobId: 'job-failed',
              result: JobReportResult.failed,
              totalCount: 2,
              successCount: 2,
              failedCount: 0,
              skippedCount: 0,
            ),
          ),
        ),
      );

      expect(find.text('照片复制失败'), findsOneWidget);
      expect(find.byIcon(Icons.error_rounded), findsOneWidget);
    });
  });

  test('job API sends and parses job/failure cursors', () async {
    final client = _PagingApiClient();
    final api = JobApi(client);

    final jobs = await api.page(cursor: 'job-cursor', pageSize: 20);
    final failures = await api.failurePage(
      'job-1',
      cursor: 'failure-cursor',
      pageSize: 10,
    );

    expect(jobs.hasMore, isTrue);
    expect(jobs.nextCursor, 'next-job');
    expect(failures.hasMore, isTrue);
    expect(failures.nextCursor, 'next-failure');
    expect(client.queries[0], {'page_size': 20, 'cursor': 'job-cursor'});
    expect(client.queries[1], {
      'page_size': 10,
      'cursor': 'failure-cursor',
    });
  });

  test('job center appends unique pages in server order', () async {
    final repository = _PagingRepository();
    final cubit = JobCenterCubit(repository);
    addTearDown(cubit.close);

    await cubit.load();
    expect(cubit.state.jobs.map((job) => job.id), ['job-b', 'job-a']);
    expect(cubit.state.hasMore, isTrue);

    await cubit.loadMore();
    expect(cubit.state.jobs.map((job) => job.id), [
      'job-b',
      'job-a',
      'job-c',
    ]);
    expect(repository.requestedCursors, [null, 'page-2']);
    expect(cubit.state.hasMore, isFalse);
  });
}

class _PagingApiClient extends ApiClient {
  final List<Map<String, dynamic>> queries = [];

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    queries.add(queryParameters ?? const {});
    if (path.endsWith('/failures')) {
      return {
        'items': [
          {'file_id': 'A.ARW', 'reason': 'failed'},
        ],
        'has_more': true,
        'next_cursor': 'next-failure',
      };
    }
    return {
      'items': [
        {
          'job_id': 'job-1',
          'job_type': 'copy',
          'job_state': 'running',
          'progress': 0.5,
          'total_count': 2,
          'finished_count': 1,
          'failed_count': 0,
          'skipped_count': 0,
          'available_actions': <String>[],
          'version': 1,
        },
      ],
      'has_more': true,
      'next_cursor': 'next-job',
    };
  }
}

class _PagingRepository implements JobRepository {
  final List<String?> requestedCursors = [];

  @override
  Future<JobPage> page({
    String? cursor,
    int pageSize = 50,
    String? state,
    String? type,
  }) async {
    requestedCursors.add(cursor);
    return cursor == null
        ? JobPage(
            items: [_job('job-b'), _job('job-a')],
            hasMore: true,
            nextCursor: 'page-2',
          )
        : JobPage(
            items: [_job('job-a'), _job('job-c')],
            hasMore: false,
          );
  }

  BirdJobStatus _job(String id) => BirdJobStatus(
    id: id,
    type: BirdJobType.copy,
    state: BirdJobState.running,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
