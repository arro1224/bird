import 'dart:io';

import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/files/log_download_service.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/batches/data/batch_api.dart';
import 'package:aves/bird_companion/features/copy/data/copy_api.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_api.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/review/data/review_api.dart';
import 'package:aves/bird_companion/features/jobs/data/job_api.dart';
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
    expect(batches.items, hasLength(4));
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

  test('项目列表按拍摄阶段筛选并保留全部记录', () async {
    final api = BatchApi(client);

    final all = await api.page(sort: 'created_at_desc');
    final inProgress = await api.page(
      state: 'in_progress',
      sort: 'created_at_desc',
    );
    final review = await api.page(
      state: 'review',
      sort: 'created_at_desc',
    );
    final failed = await api.page(
      state: 'failed',
      sort: 'created_at_desc',
    );

    expect(all.items, hasLength(4));
    expect(
      inProgress.items.map((batch) => batch.id),
      ['mock-batch-history-03'],
    );
    expect(inProgress.items.single.state, 'analyzing');
    expect(review.items.map((batch) => batch.id), ['mock-batch-current']);
    expect(review.items.single.state, 'ready_to_review');
    expect(failed.items.map((batch) => batch.id), [
      'mock-batch-history-02',
    ]);
    expect(failed.items.single.state, 'failed');
    expect(
      all.items.singleWhere((batch) => batch.id == 'mock-batch-history-01').state,
      'completed',
    );
  });

  test('批量保留照片后当前项目汇总立即返回新数量', () async {
    final batchApi = BatchApi(client);
    final photoApi = PhotoApi(client);
    final before = await batchApi.current();

    final outcome = await photoApi.batchOperation(
      'mock-batch-current',
      const ['photo-0005', 'photo-0006'],
      'keep',
      version: 1,
    );
    final after = await batchApi.current();
    final reviewPage = await batchApi.page(state: 'review');

    expect(outcome.succeededIds, ['photo-0005', 'photo-0006']);
    expect(after?.pendingReviewCount, before!.pendingReviewCount - 2);
    expect(after?.keepCount, before.keepCount + 2);
    expect(reviewPage.items.single.pendingReviewCount, after?.pendingReviewCount);
    expect(reviewPage.items.single.keepCount, after?.keepCount);
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
      version: 1,
    );
    final updated = await reviewApi.detail('photo-0002');

    expect(outcome.succeededIds, ['photo-0002']);
    expect(outcome.failed, contains('missing-photo'));
    expect(updated.photo.summary.keepState, 'featured');
  });

  test('copy-v1 设备、预检与明细形成闭环（RC3 任务闭环在下方独立测试）', () async {
    final copyApi = CopyApi(client);
    final devices = (await copyApi.devices()).devices;

    expect(devices, isNotEmpty);
    final source = devices.firstWhere((device) => device.canBeSource);
    final target = devices.firstWhere((device) => device.canBeTarget);
    expect(target.mediaId, isNotEmpty);
    expect(target.presentationName, 'U 盘 Ee');

    final draft = CopyRequestDraft(
      batchId: 'mock-batch-current',
      scope: CopyScope.keptAssets,
      sourceMediaId: source.mediaId,
      targetMediaId: target.mediaId,
      conflictStrategy: ConflictStrategy.skip,
      reviewExport: const ReviewExportConfig(
        enabled: true,
        writeXmp: true,
        writeCsv: true,
        embedIntoSupportedCopy: true,
      ),
    );
    final preview = await copyApi.preview(draft);
    expect(preview.logicalPhotoCount, 34);
    expect(preview.previewToken, isNotEmpty);
    expect(preview.hasEnoughSpace, isTrue);

    // 预检明细可分页（§10.2），冲突项带 skip 决策。
    final itemPage = await copyApi.previewItems(preview.previewToken);
    expect(itemPage.items, hasLength(20));
    expect(itemPage.hasMore, isTrue);
    expect(itemPage.items.map((item) => item.conflictDecision), contains('skip'));
  });

  test('RC3 复制任务闭环：capabilities/预检拒绝全量备份/创建→轮询部分完成/动作版本冲突/安全移除', () async {
    // 用可变 clock 驱动 mock 服务器状态机（真实后端语义：读时按相对时间推进）。
    var now = DateTime(2026, 9, 17, 10);
    final clocked = MockBoxServer(
      photoCount: 1200,
      assetDirectory: Directory('tool/mock_box_server/assets'),
      logRequests: false,
      clock: () => now,
    );
    final clockedUri = await clocked.start();
    addTearDown(clocked.close);
    final copyApi = CopyApi(ApiClient()..configure(clockedUri));

    // capabilities（rc3 契约）。
    final capabilities = await copyApi.capabilities();
    expect(capabilities.revision, '1.0-rc3');
    expect(capabilities.copyReady, isTrue);
    expect(capabilities.supportedScopes, contains(CopyScope.mediaFullBackup));

    const draft = CopyRequestDraft(
      batchId: 'mock-batch-current',
      scope: CopyScope.keptAssets,
      sourceMediaId: 'media_2d6dee77bb5ecc73e3d34787',
      targetMediaId: 'media_7f9a76e6c97690b61aedf6fd',
      conflictStrategy: ConflictStrategy.skip,
      reviewExport: ReviewExportConfig.disabled(),
    );

    // 预检拒绝全量备份（镜像真实后端 P0-2）。
    await expectLater(
      copyApi.preview(
        CopyRequestDraft(
          batchId: 'mock-batch-current',
          scope: CopyScope.mediaFullBackup,
          sourceMediaId: draft.sourceMediaId,
          targetMediaId: draft.targetMediaId,
          conflictStrategy: ConflictStrategy.skip,
          reviewExport: const ReviewExportConfig.disabled(),
        ),
      ),
      throwsA(
        isA<ApiException>()
            .having((error) => error.code, 'code', 'COPY_SCOPE_UNSUPPORTED')
            .having((error) => error.statusCode, 'status', 422),
      ),
    );

    // 创建任务并轮询到部分完成。
    final summary = await copyApi.createJob(draft, 'unused_token_for_mock');
    expect(summary.copyJobId, startsWith('copy_job_'));

    final queued = await copyApi.getJob(summary.copyJobId);
    expect(queued.state.wire, 'queued');
    expect(queued.stats!.totalFiles, 2);

    now = now.add(const Duration(seconds: 3));
    final running = await copyApi.getJob(summary.copyJobId);
    expect(running.state.wire, 'running');
    expect(running.allowedActions.map((action) => action.wire), containsAll(['pause', 'cancel']));

    // 进行中的任务占用源设备：安全移除被拒（§4.5）。
    final busySource = await copyApi.safeRemoveDevice(draft.sourceMediaId, role: 'source');
    expect(busySource.safeToRemove, isFalse);

    // 版本不符的动作 → 409 COPY_STATE_VERSION_CONFLICT。
    await expectLater(
      copyApi.jobAction(summary.copyJobId, 'pause', expectedStateVersion: running.stateVersion + 7),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'COPY_STATE_VERSION_CONFLICT',
        ),
      ),
    );

    now = now.add(const Duration(seconds: 10));
    final done = await copyApi.getJob(summary.copyJobId);
    expect(done.state.wire, 'completed_with_errors');
    expect(done.stats!.copiedFiles, 1);
    expect(done.stats!.failedFiles, 1);

    // 失败项过滤 + 事件增量 + 终态报告。
    final failedItems = await copyApi.jobItems(summary.copyJobId, state: 'failed');
    expect(failedItems.items, hasLength(1));
    final events = await copyApi.jobEvents(summary.copyJobId);
    expect(events.events.map((event) => event.type), contains('item_failed'));
    final incremental = await copyApi.jobEvents(summary.copyJobId, afterSeq: 1);
    expect(incremental.events.map((event) => event.seq), everyElement(greaterThan(1)));
    final report = await copyApi.jobReport(summary.copyJobId);
    expect(report.isPartialSuccess, isTrue);
    expect(report.failedFiles, 1);

    // 终态后目标设备空闲：安全移除放行（保持期 60s）。
    final freeTarget = await copyApi.safeRemoveDevice(
      draft.targetMediaId,
      role: 'target',
      expectedCopyJobId: summary.copyJobId,
    );
    expect(freeTarget.safeToRemove, isTrue);
    expect(freeTarget.keepUntil, isNotNull);
  });

  test('copy-v1 缺失同名策略时拒绝预检', () async {
    final copyApi = CopyApi(client);
    final devices = (await copyApi.devices()).devices;

    final draft = CopyRequestDraft(
      batchId: 'mock-batch-current',
      scope: CopyScope.keptAssets,
      sourceMediaId: devices.firstWhere((device) => device.canBeSource).mediaId,
      targetMediaId: devices.firstWhere((device) => device.canBeTarget).mediaId,
      reviewExport: const ReviewExportConfig.disabled(),
    );
    await expectLater(
      copyApi.preview(draft),
      throwsA(isA<ApiException>()),
    );
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
