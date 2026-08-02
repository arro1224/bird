import 'dart:io';

import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/files/log_download_service.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/features/batches/data/batch_api.dart';
import 'package:aves/bird_companion/features/copy/data/copy_api.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_api.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/review/data/review_api.dart';
import 'package:aves/bird_companion/features/jobs/data/job_api.dart';
import 'package:aves/bird_companion/features/jobs/data/job_repository_impl.dart';
import 'package:aves/bird_companion/features/jobs/presentation/job_detail_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/mock_box_server/mock_box_server.dart';

void main() {
  late MockBoxServer server;
  late Uri baseUri;
  late ApiClient client;

  setUp(() async {
    server = MockBoxServer(
      photoCount: 1200,
      assetDirectory: Directory('tool/mock_box_server/assets'),
      logRequests: false,
    );
    baseUri = await server.start();
    client = ApiClient()..configure(baseUri);
  });

  tearDown(() => server.close());

  test('模拟盒子返回可分页照片，并将媒体地址解析为当前盒子地址', () async {
    final batchApi = BatchApi(client);
    final api = PhotoApi(client);
    final currentBatch = await batchApi.current();
    final batches = await batchApi.page();
    final page = await api.page(
      'mock-batch-current',
      const PhotoQuery(pageSize: 10),
    );

    expect(currentBatch?.id, 'mock-batch-current');
    expect(currentBatch?.totalFiles, 1200);
    expect(batches.items, hasLength(3));
    expect(page.items, hasLength(10));
    expect(page.hasMore, isTrue);
    expect(page.nextCursor, '10');
    expect(
      page.items.first.preview.thumbnailUri.toString(),
      startsWith('$baseUri/mock/media/'),
    );
    expect(
      page.items.first.preview.previewUri.toString(),
      startsWith('$baseUri/mock/media/'),
    );

    final httpClient = HttpClient();
    addTearDown(() => httpClient.close(force: true));
    final request = await httpClient.getUrl(
      page.items.first.preview.previewUri!,
    );
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.contentType?.mimeType, 'image/png');
    expect(bytes.length, greaterThan(1000));
  });

  test('1200 张性能集使用游标分页时无重复、无丢项', () async {
    final api = PhotoApi(client);
    final reviewApi = ReviewApi(client);
    final ids = <String>[];
    String? cursor;
    var requestCount = 0;

    do {
      final page = await api.page(
        'mock-batch-current',
        PhotoQuery(pageSize: 200, cursor: cursor),
      );
      ids.addAll(page.items.map((photo) => photo.id));
      cursor = page.nextCursor;
      requestCount += 1;
      if (!page.hasMore) break;
    } while (requestCount < 10);

    expect(requestCount, 6);
    expect(ids, hasLength(1200));
    expect(ids.toSet(), hasLength(1200));

    final groups = await reviewApi.groups('mock-batch-current');
    final groupedIds = groups.expand((group) => group.memberFileIds).toSet();
    expect(groups, hasLength(86));
    expect(groupedIds, ids.toSet());
  });

  test('本地模拟盒子首屏数据和首张缩略图在两秒内可用', () async {
    final watch = Stopwatch()..start();
    final page = await PhotoApi(client).page(
      'mock-batch-current',
      const PhotoQuery(pageSize: 60),
    );
    final httpClient = HttpClient();
    addTearDown(() => httpClient.close(force: true));
    final request = await httpClient.getUrl(
      page.items.first.preview.thumbnailUri!,
    );
    final response = await request.close();
    await response.drain<void>();
    watch.stop();

    expect(response.statusCode, HttpStatus.ok);
    expect(page.items, hasLength(60));
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('不存在的缩略图返回 404，客户端可使用占位图降级', () async {
    final httpClient = HttpClient();
    addTearDown(() => httpClient.close(force: true));
    final request = await httpClient.getUrl(
      baseUri.resolve('/mock/media/not-found.png'),
    );
    final response = await request.close();
    await response.drain<void>();

    expect(response.statusCode, HttpStatus.notFound);
  });

  test('场景、连拍组、详情、保存决定和批量操作形成完整往返', () async {
    final photoApi = PhotoApi(client);
    final reviewApi = ReviewApi(client);

    final scenes = await photoApi.scenes('mock-batch-current');
    final groups = await reviewApi.groups(
      'mock-batch-current',
      sceneId: scenes.first.id,
    );
    final before = await reviewApi.detail('photo-0001');

    expect(scenes, hasLength(4));
    expect(groups, isNotEmpty);
    expect(groups.first.members, isNotEmpty);
    expect(before.history, isNotEmpty);
    expect(before.decision?.version, 1);

    await reviewApi.save(
      UserDecisionPatch.fromDecision(
        UserDecision(
          fileId: 'photo-0001',
          keepState: KeepState.discard,
          userScore: 4.5,
          userSpeciesId: 'common-kingfisher',
          userSpecies: '普通翠鸟',
          userTags: const ['复核完成'],
          version: before.decision?.version,
        ),
      ),
    );
    final after = await reviewApi.detail('photo-0001');

    expect(after.decision?.keepState, KeepState.discard);
    expect(after.decision?.version, 2);
    expect(after.decision?.userTags, contains('复核完成'));
    expect(after.history.last.source, 'app');

    await expectLater(
      reviewApi.save(
        UserDecisionPatch.fromDecision(
          UserDecision(
            fileId: 'photo-0001',
            keepState: KeepState.featured,
            version: before.decision?.version,
          ),
        ),
      ),
      throwsA(
        isA<ApiException>()
            .having(
              (error) => error.statusCode,
              'statusCode',
              HttpStatus.conflict,
            )
            .having(
              (error) => UserMessageMapper.fromError(error).title,
              'message title',
              '照片审阅结果已更新',
            ),
      ),
    );

    final outcome = await photoApi.batchOperation(
      'mock-batch-current',
      const ['photo-0002', 'missing-photo'],
      'featured',
    );
    final updated = await reviewApi.detail('photo-0002');

    expect(outcome.succeededIds, ['photo-0002']);
    expect(outcome.failed, contains('missing-photo'));
    expect(updated.photo.summary.keepState, 'featured');
  });

  test('复制估算、完整创建请求、任务进度和权威报告形成闭环', () async {
    final copyApi = CopyApi(client);
    final jobApi = JobApi(client);
    final estimate = await copyApi.estimate('mock-batch-current', 'keep');

    expect(estimate.targets, isNotEmpty);
    expect(estimate.targets.first.online, isTrue);
    expect(estimate.version, 0);

    final job = await copyApi.create(
      'mock-batch-current',
      'keep',
      estimate.targets.first.id,
      xmpEnabled: true,
      verifyAfterCopy: true,
      version: estimate.version,
    );
    expect(job.sourceProjectId, 'mock-batch-current');
    expect(job.type.name, 'copy');

    await server.completeJob(job.id);
    final completed = await jobApi.detail(job.id);
    final report = await jobApi.report(job.id);
    final events = EventClient();
    final detailCubit = JobDetailCubit(
      JobRepositoryImpl(jobApi),
      events,
      job.id,
    );
    addTearDown(detailCubit.close);
    addTearDown(events.dispose);
    await detailCubit.load();

    expect(completed.state.name, 'completed');
    expect(report.jobId, job.id);
    expect(report.successCount, report.totalCount);
    expect(report.failedCount, 0);
    expect(detailCubit.state.report?.jobId, job.id);

    await server.failJob(job.id, failedCount: 1);
    await detailCubit.load();
    expect(detailCubit.state.failures, hasLength(1));
    expect(
      detailCubit.state.job?.availableActions,
      contains('skip_failed'),
    );

    await detailCubit.control('skip_failed');
    expect(detailCubit.state.job?.state.name, 'completed');
    expect(detailCubit.state.report?.skippedCount, 1);
    expect(detailCubit.state.failures, isEmpty);
  });

  test('日志导出会下载非空文件并保留本地路径', () async {
    final directory = await Directory.systemTemp.createTemp('bird-b6-logs-');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final jobApi = JobApi(client);
    final service = LogDownloadService(
      client,
      directoryProvider: () async => directory,
    );

    final downloaded = await service.downloadWithRefresh(
      () => jobApi.exportLogs(scope: 'device_and_jobs'),
    );

    expect(await downloaded.file.exists(), isTrue);
    expect(await downloaded.file.length(), greaterThan(0));
    expect(downloaded.file.parent.path, directory.path);
  });

  test(
    '同一幂等键的并发请求只创建一次，重启后仍可重放并恢复项目',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bird-b7-mock-state-',
      );
      final stateFile = File('${directory.path}/state.json');
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

      await server.close();
      await client.dispose();
      server = MockBoxServer(
        photoCount: 60,
        assetDirectory: Directory('tool/mock_box_server/assets'),
        logRequests: false,
        stateFile: stateFile,
      );
      baseUri = await server.start();
      client = ApiClient()..configure(baseUri);

      const idempotencyKey = 'b7-project-replay-0001';
      const request = {
        'name': 'B7 persistent project',
        'card_id': 'card-mock-001',
      };
      final concurrent = await Future.wait([
        client.post(
          ApiEndpoints.batches,
          data: request,
          idempotencyKey: idempotencyKey,
        ),
        client.post(
          ApiEndpoints.batches,
          data: request,
          idempotencyKey: idempotencyKey,
        ),
      ]);
      final projectId = concurrent.first['project_id'];

      expect(projectId, 'project-0001');
      expect(concurrent.last['project_id'], projectId);
      expect(
        (await BatchApi(client).page()).items.where((project) => project.id == projectId),
        hasLength(1),
      );

      await server.close();
      await client.dispose();
      server = MockBoxServer(
        photoCount: 60,
        assetDirectory: Directory('tool/mock_box_server/assets'),
        logRequests: false,
        stateFile: stateFile,
      );
      baseUri = await server.start();
      client = ApiClient()..configure(baseUri);

      final replayed = await client.post(
        ApiEndpoints.batches,
        data: request,
        idempotencyKey: idempotencyKey,
      );
      final restoredCurrent = await BatchApi(client).current();

      expect(replayed['project_id'], projectId);
      expect(restoredCurrent?.id, projectId);
      expect(
        (await BatchApi(client).page()).items.where((project) => project.id == projectId),
        hasLength(1),
      );
    },
  );
}
