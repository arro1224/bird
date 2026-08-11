import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/features/jobs/data/job_api.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_create_requests.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_failure.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_page.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_report.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_repository.dart';
import 'package:aves/bird_companion/features/jobs/presentation/job_center_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('B3 complete job snapshot', () {
    test('preserves task timestamps and distinguishes a missing version', () {
      final job = BirdJobStatus.fromJson(
        _jobJson(version: null)
          ..['started_at'] = '2026-08-10T01:00:00Z'
          ..['finished_at'] = '2026-08-10T01:03:00Z',
      );

      expect(job.version, isNull);
      expect(job.startedAt, DateTime.utc(2026, 8, 10, 1));
      expect(job.finishedAt, DateTime.utc(2026, 8, 10, 1, 3));
      expect(job.toJson(), isNot(contains('version')));
    });

    test('rejects missing and non-v1 available actions', () {
      final missing = _jobJson(version: 1)..remove('available_actions');
      final legacyRetry = _jobJson(version: 1)..['available_actions'] = <String>['retry'];

      expect(
        () => BirdJobStatus.fromJson(missing),
        throwsA(
          isA<ProtocolCompatibilityException>().having(
            (error) => error.field,
            'field',
            'available_actions',
          ),
        ),
      );
      expect(
        () => BirdJobStatus.fromJson(legacyRetry),
        throwsA(isA<ProtocolCompatibilityException>()),
      );
    });
  });

  group('B3 task controls', () {
    test('job API sends only action and version from the frozen request', () async {
      final client = _B3ApiClient();
      final api = JobApi(client);

      await api.control('job-b3', 'pause', version: 7);

      expect(client.lastPath, '/api/v1/jobs/job-b3/actions');
      expect(client.lastData, <String, dynamic>{
        'action': 'pause',
        'version': 7,
      });
      expect(
        () => api.control('job-b3', 'retry', version: 7),
        throwsArgumentError,
      );
      expect(
        () => api.control('job-b3', 'pause', version: -1),
        throwsArgumentError,
      );
    });

    test('job center blocks writes when the snapshot has no version', () async {
      final repository = _B3Repository(
        BirdJobStatus.fromJson(_jobJson(version: null)),
      );
      final cubit = JobCenterCubit(repository);
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.control('job-b3', 'pause');

      expect(repository.controlCalls, 0);
      expect(cubit.state.error, isA<StateError>());
    });

    test('job center blocks actions omitted from available_actions', () async {
      final repository = _B3Repository(
        BirdJobStatus.fromJson(
          _jobJson(version: 3)..['available_actions'] = <String>[],
        ),
      );
      final cubit = JobCenterCubit(repository);
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.control('job-b3', 'pause');

      expect(repository.controlCalls, 0);
      expect(cubit.state.error, isA<StateError>());
    });
  });

  group('B3 failures and logs', () {
    test('parses failure pagination and the signed log response', () async {
      final client = _B3ApiClient();
      final api = JobApi(client);

      final page = await api.failurePage('job-b3');
      final downloadUrl = await api.exportLogs(
        scope: 'jobs',
        jobId: 'job-b3',
      );

      expect(page.items.single.fileId, 'file-1');
      expect(page.items.single.filename, 'DSC_0001.ARW');
      expect(page.items.single.retryable, isTrue);
      expect(page.hasMore, isFalse);
      expect(downloadUrl, '/signed/log-b3.zip');
      expect(client.lastData, <String, dynamic>{
        'scope': 'jobs',
        'job_id': 'job-b3',
      });
    });

    test('does not invent a cursor or ready log state', () async {
      final client = _B3ApiClient()
        ..failureHasMore = true
        ..logState = 'building';
      final api = JobApi(client);

      await expectLater(
        api.failurePage('job-b3'),
        throwsA(isA<ProtocolCompatibilityException>()),
      );
      await expectLater(
        api.exportLogs(scope: 'device_and_jobs'),
        throwsA(isA<ProtocolCompatibilityException>()),
      );
    });
  });
}

Map<String, dynamic> _jobJson({required int? version}) => <String, dynamic>{
  'job_id': 'job-b3',
  'job_type': 'copy',
  'job_state': 'running',
  'workflow_stage': 'copying',
  'progress': .25,
  'total_count': 20,
  'finished_count': 5,
  'failed_count': 1,
  'skipped_count': 0,
  'available_actions': <String>['pause', 'cancel'],
  'version': ?version,
};

class _B3ApiClient extends ApiClient {
  String? lastPath;
  Object? lastData;
  bool failureHasMore = false;
  String logState = 'ready';

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    lastPath = path;
    if (path.endsWith('/failures')) {
      return <String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'file_id': 'file-1',
            'filename': 'DSC_0001.ARW',
            'error_code': 'COPY_IO_ERROR',
            'reason': 'write failed',
            'retryable': true,
          },
        ],
        'has_more': failureHasMore,
        'next_cursor': null,
      };
    }
    return _jobJson(version: 7);
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Object? data,
    String? idempotencyKey,
  }) async {
    lastPath = path;
    lastData = data;
    if (path.endsWith('/logs/export')) {
      return <String, dynamic>{
        'export_id': 'export-b3',
        'state': logState,
        'download_url': '/signed/log-b3.zip',
        'expires_at': '2026-08-10T02:00:00Z',
      };
    }
    return _jobJson(version: 8);
  }
}

class _B3Repository implements JobRepository {
  _B3Repository(this.job);

  BirdJobStatus job;
  int controlCalls = 0;

  @override
  Future<JobPage> page({
    String? cursor,
    int pageSize = 50,
    String? state,
    String? type,
  }) async => JobPage(items: <BirdJobStatus>[job], hasMore: false);

  @override
  Future<BirdJobStatus> control(
    String id,
    String action, {
    required int version,
  }) async {
    controlCalls++;
    return job;
  }

  @override
  Future<BirdJobStatus> detail(String id) async => job;

  @override
  Future<List<BirdJobStatus>> list() async => <BirdJobStatus>[job];

  @override
  Future<List<JobFailure>> failures(String jobId) async => const <JobFailure>[];

  @override
  Future<JobFailurePage> failurePage(
    String jobId, {
    String? cursor,
    int pageSize = 50,
  }) async => const JobFailurePage.empty();

  @override
  Future<String?> exportLogs({
    String scope = 'device_and_jobs',
    String? jobId,
  }) async => '/signed/log.zip';

  @override
  Future<void> delete(String id) async {}

  @override
  Future<JobReport> report(String id) => throw UnsupportedError('not used');

  @override
  Future<BirdJobStatus> createAnalysis(
    String projectId,
    AnalysisJobRequest request,
  ) => throw UnsupportedError('not used');

  @override
  Future<BirdJobStatus> createImport(
    String projectId,
    ImportJobRequest request,
  ) => throw UnsupportedError('not used');
}
