import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/features/jobs/data/job_api.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_failure.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_page.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_report.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/production_task_result_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('B4 authoritative job report', () {
    test('preserves every frozen report field', () {
      final report = JobReport.fromJson(_reportJson());

      expect(report.jobId, 'job-b4');
      expect(report.result, JobReportResult.partialSuccess);
      expect(report.totalCount, 12);
      expect(report.successCount, 9);
      expect(report.failedCount, 2);
      expect(report.skippedCount, 1);
      expect(report.copiedBytes, 1536);
      expect(report.manifestId, 'manifest-b4');
      expect(report.startedAt, DateTime.utc(2026, 8, 10, 1));
      expect(report.finishedAt, DateTime.utc(2026, 8, 10, 1, 2, 3));
    });

    test('does not invent required counts or an unknown result', () {
      final missingCount = _reportJson()..remove('failed_count');
      final unknownResult = _reportJson()..['result'] = 'future_result';

      expect(
        () => JobReport.fromJson(missingCount),
        throwsA(
          isA<ProtocolCompatibilityException>().having(
            (error) => error.field,
            'field',
            'failed_count',
          ),
        ),
      );
      expect(
        () => JobReport.fromJson(unknownResult),
        throwsA(
          isA<ProtocolCompatibilityException>().having(
            (error) => error.field,
            'field',
            'result',
          ),
        ),
      );
    });

    test('rejects invalid optional field types from the frozen schema', () {
      final nullCopiedBytes = _reportJson()..['copied_bytes'] = null;
      final numericManifest = _reportJson()..['manifest_id'] = 42;
      final numericTimestamp = _reportJson()..['started_at'] = 42;

      expect(
        () => JobReport.fromJson(nullCopiedBytes),
        throwsA(isA<ProtocolCompatibilityException>()),
      );
      expect(
        () => JobReport.fromJson(numericManifest),
        throwsA(isA<ProtocolCompatibilityException>()),
      );
      expect(
        () => JobReport.fromJson(numericTimestamp),
        throwsA(isA<ProtocolCompatibilityException>()),
      );
    });

    test('report API rejects a response for another job', () async {
      final client = _B4ApiClient()..responseJobId = 'job-other';
      final api = JobApi(client);

      await expectLater(
        api.report('job-b4'),
        throwsA(
          isA<ProtocolCompatibilityException>().having(
            (error) => error.field,
            'field',
            'job_id',
          ),
        ),
      );
      expect(client.lastPath, '/api/v1/jobs/job-b4/report');
      await expectLater(api.report('  '), throwsArgumentError);
    });
  });

  testWidgets('failure details retry without replacing the report', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    String? requestedCursor = 'not-requested';

    await tester.pumpWidget(
      MaterialApp(
        home: ProductionTaskResultPage(
          report: JobReport.fromJson(_reportJson()),
          initialFailureError: StateError('first page unavailable'),
          loadFailurePage: (cursor) async {
            calls++;
            requestedCursor = cursor;
            return const JobFailurePage(
              items: <JobFailure>[
                JobFailure(
                  fileId: 'file-b4-1',
                  filename: 'DSC_0001.ARW',
                  reason: '目标盘写入失败',
                ),
              ],
              hasMore: false,
            );
          },
        ),
      ),
    );

    expect(find.text('照片部分复制完成'), findsOneWidget);
    await tester.tap(find.byKey(const Key('production-task-open-report')));
    await tester.pumpAndSettle();

    expect(find.text('manifest-b4'), findsOneWidget);
    expect(find.text('失败明细加载失败，请重试。'), findsOneWidget);
    expect(find.byKey(const Key('report-load-more-failures')), findsOneWidget);

    await tester.tap(find.byKey(const Key('report-load-more-failures')));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(requestedCursor, isNull);
    expect(find.text('DSC_0001.ARW'), findsOneWidget);
    expect(find.textContaining('file-b4-1'), findsOneWidget);
    expect(find.textContaining('目标盘写入失败'), findsOneWidget);
    expect(find.text('失败明细加载失败，请重试。'), findsNothing);
  });
}

Map<String, dynamic> _reportJson() => <String, dynamic>{
  'job_id': 'job-b4',
  'result': 'partial_success',
  'total_count': 12,
  'success_count': 9,
  'failed_count': 2,
  'skipped_count': 1,
  'copied_bytes': 1536,
  'manifest_id': 'manifest-b4',
  'started_at': '2026-08-10T01:00:00Z',
  'finished_at': '2026-08-10T01:02:03Z',
};

class _B4ApiClient extends ApiClient {
  String responseJobId = 'job-b4';
  String? lastPath;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    lastPath = path;
    return _reportJson()..['job_id'] = responseJobId;
  }
}
