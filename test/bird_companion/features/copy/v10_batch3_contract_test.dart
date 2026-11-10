import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/copy/data/copy_api.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_config_cubit.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_job_detail_cubit.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fakes/fake_copy_environment.dart';

Future<CopyConfigCubit> ready(FakeCopyEnvironment repository) async {
  final cubit = CopyConfigCubit(repository, batchId: 'batch', scope: CopyScope.batchAllAssets, pollInterval: Duration.zero);
  await cubit.initialize();
  cubit.selectTarget('target');
  cubit.setConflictStrategy(ConflictStrategy.skip);
  expect(await cubit.fetchPreview(), true);
  return cubit;
}

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 150; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('State did not settle');
}

void main() {
  test('old 300-second responses are bounded to 120 seconds without changing the plan', () async {
    final repository = FakeCopyEnvironment()..previewLifetime = const Duration(seconds: 300);
    final started = DateTime.now();
    final cubit = await ready(repository);
    addTearDown(cubit.close);
    expect(cubit.state.preview!.expiresAt.isAfter(DateTime.now().add(const Duration(seconds: 120))), false);
    final original = repository.previewFor(cubit.state.draft);
    final bounded = original.boundedForRequest(started);
    expect(bounded.expiresAt, started.add(const Duration(seconds: 120)));
    expect(bounded.previewToken, original.previewToken);
    expect(bounded.targetFreeBytes, original.targetFreeBytes);
    expect(bounded.safetyReserveBytes, original.safetyReserveBytes);
    final expired = original.boundedForRequest(DateTime.now().subtract(const Duration(seconds: 130)));
    expect(expired.isExpired, true);
  });

  test('an earlier server expiry is never extended', () async {
    final repository = FakeCopyEnvironment()..previewLifetime = const Duration(seconds: 30);
    final cubit = await ready(repository);
    addTearDown(cubit.close);
    final original = repository.previewFor(cubit.state.draft);
    expect(identical(original.boundedForRequest(DateTime.now()), original), true);
  });

  for (final changeReserve in [false, true]) {
    test('same file counts but changed ${changeReserve ? 'reserve' : 'free space'} requires another confirmation', () async {
      final repository = _SpaceEnvironment();
      final cubit = await ready(repository);
      addTearDown(cubit.close);
      if (changeReserve) {
        repository.reserve = 200;
      } else {
        repository.free = 900000;
      }
      expect(await cubit.submit(), false);
      expect(repository.createCalls, 0);
      expect(cubit.state.planNotice, contains('变化'));
      expect(await cubit.submit(), true);
      expect(repository.createCalls, 1);
    });
  }

  test('server COPY_PREVIEW_EXPIRED rechecks once and never automatically repeats create', () async {
    final repository = _ExpireOnce();
    final cubit = await ready(repository);
    addTearDown(cubit.close);
    expect(await cubit.submit(), false);
    expect(repository.createCalls, 1);
    expect(repository.previewCalls, 3);
    expect(cubit.state.preflightStatus, CopyPreflightStatus.valid);
    expect(cubit.state.planNotice, contains('已重新检查'));
    expect(cubit.state.submitting, false);
    expect(await cubit.submit(), true);
    expect(repository.createCalls, 2);
  });

  test('app background expiry does not request HTTP until foreground and preserves reconfirmation', () async {
    final repository = _SpaceEnvironment()..previewLifetime = const Duration(milliseconds: 60);
    final cubit = await ready(repository);
    addTearDown(cubit.close);
    cubit.setAppLifecycleActive(false);
    repository.previewLifetime = const Duration(minutes: 1);
    repository.free = 900000;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(repository.previewCalls, 1);
    expect(cubit.state.preview, isNull);
    cubit.setAppLifecycleActive(true);
    await until(() => cubit.state.preview != null && !cubit.state.loadingPreview);
    await until(() => cubit.state.planNotice?.contains('变化') == true);
    expect(await cubit.submit(), false);
    expect(repository.createCalls, 0);
    expect(await cubit.submit(), true);
  });

  test('missing and fractional action versions are unknown, while explicit zero is valid', () {
    for (final version in [null, -1, 1.5, 'broken']) {
      final parsed = CopyJobDetail.fromJson({'copy_job_id': 'job', 'state': 'paused', 'state_version': ?version});
      expect(parsed.stateVersionKnown, false);
    }
    expect(CopyJobDetail.fromJson({'copy_job_id': 'job', 'state': 'paused', 'state_version': 0}).stateVersionKnown, true);
  });

  test('documented timing metrics supplement missing stats without overriding known zero', () {
    final detail = CopyJobDetail.fromJson({
      'copy_job_id': 'job',
      'state': 'completed',
      'stats': {'elapsed_seconds': 0, 'copied_bytes': 1000},
      'timing': {'elapsed_seconds': 10, 'bytes_per_second': 100},
    });
    expect(detail.stats!.elapsedSeconds, 0);
    expect(detail.stats!.bytesPerSecond, 100);
    expect(detail.stats!.copiedBytes, 1000);
    final report = CopyReport.fromJson({
      'elapsed_seconds': -1,
      'timing': {'elapsed_seconds': 10.25, 'bytes_per_second': 100.5},
    });
    expect(report.elapsedSeconds, 10.25);
    expect(report.bytesPerSecond, 100.5);
    final timingOnly = CopyJobDetail.fromJson({
      'copy_job_id': 'job',
      'state': 'completed',
      'timing': {'elapsed_seconds': 10},
    });
    expect(timingOnly.stats!.elapsedSeconds, 10);
    expect(timingOnly.stats!.knownFileCounts, isEmpty);
    expect(timingOnly.stats!.copiedBytesKnown, false);
  });

  test('missing version refreshes the task without writing an action or replaying it', () async {
    final repository = _Jobs();
    final cubit = CopyJobDetailCubit(repository, copyJobId: 'job');
    addTearDown(cubit.close);
    await cubit.load();
    repository.version = 12;
    await cubit.act(CopyAllowedAction.resume);
    expect(repository.actions, 0);
    expect(cubit.state.detail!.stateVersion, 12);
    await cubit.act(CopyAllowedAction.resume);
    expect(repository.actions, 1);
    expect(repository.sentVersion, 12);
  });

  test('empty successful action response is accepted; version, protocol and idempotency headers are sent', () async {
    final dio = Dio();
    final client = ApiClient(dio: dio)..configure(Uri.parse('http://192.0.2.1:8080'));
    addTearDown(client.dispose);
    late RequestOptions sent;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          sent = options;
          handler.resolve(Response(requestOptions: options, statusCode: 204, data: <String, dynamic>{}));
        },
      ),
    );
    expect(await CopyApi(client).jobAction('job', 'resume', expectedStateVersion: 12), isNull);
    expect(sent.data['expected_state_version'], 12);
    expect(sent.data['reason'], 'user_requested');
    expect(sent.headers['X-BirdBox-Protocol'], 'birdbox-copy-v1');
    expect(sent.headers['X-BirdBox-Copy-Revision'], '1.0-rc3');
    expect(sent.headers['Idempotency-Key'], isNotEmpty);
    expect(sent.headers['Idempotency-Key'], sent.headers['X-Idempotency-Key']);
  });

  test('nested HTTP errors preserve code and retryability without treating every status as occupied', () async {
    for (final status in [409, 422, 500, 503]) {
      final dio = Dio();
      final client = ApiClient(dio: dio)..configure(Uri.parse('http://192.0.2.1:8080'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response(
                requestOptions: options,
                statusCode: status,
                data: {
                  'error': {
                    'code': 'COPY_PREVIEW_EXPIRED',
                    'message': '预检已过期',
                    'details': {'retryable': true},
                  },
                },
              ),
            ),
          ),
        ),
      );
      await expectLater(
        client.get('/api/v1/copy-jobs/job'),
        throwsA(isA<ApiException>().having((error) => error.code, 'code', 'COPY_PREVIEW_EXPIRED').having((error) => error.retryable, 'retryable', true).having((error) => error.statusCode, 'status', status)),
      );
      await client.dispose();
    }
  });
}

class _SpaceEnvironment extends FakeCopyEnvironment {
  int free = 1000000, reserve = 100;
  @override
  CopyPreview previewFor(CopyRequestDraft draft) {
    final value = super.previewFor(draft);
    return CopyPreview(
      previewToken: value.previewToken,
      expiresAt: value.expiresAt,
      source: value.source,
      target: value.target,
      logicalPhotoCount: value.logicalPhotoCount,
      actualFileCount: value.plannedFileCount,
      totalBytes: value.totalBytes,
      rawCount: value.rawCount,
      jpegCount: value.jpegCount,
      videoCount: value.videoCount,
      companionCount: value.companionCount,
      estimatedDateDirectories: value.estimatedDateDirectories,
      conflictCount: value.conflictCount,
      targetFreeBytes: free,
      safetyReserveBytes: reserve,
    );
  }
}

class _ExpireOnce extends FakeCopyEnvironment {
  @override
  Future<CopyJobSummary> createJob(CopyRequestDraft draft, String previewToken) async {
    if (createCalls == 0) {
      createCalls++;
      throw const ApiException(message: '预检已过期', code: 'COPY_PREVIEW_EXPIRED', statusCode: 409, retryable: true);
    }
    return super.createJob(draft, previewToken);
  }
}

class _Jobs implements CopyJobRepository {
  int? version;
  int actions = 0;
  int? sentVersion;
  @override
  Future<CopyJobDetail> getJob(String id) async => CopyJobDetail.fromJson({
    'copy_job_id': 'job',
    'state': 'paused',
    'allowed_actions': ['resume'],
    if (version != null) 'state_version': version,
  });
  @override
  Future<CopyJobEventPage> jobEvents(String id, {int? afterSeq}) async => const CopyJobEventPage(events: [], hasMore: false);
  @override
  Future<CopyJobDetail?> jobAction(String id, String action, {required int expectedStateVersion}) async {
    actions++;
    sentVersion = expectedStateVersion;
    return getJob(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
