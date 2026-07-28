import 'dart:io';

import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/features/batches/data/batch_api.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_api.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/review/data/review_api.dart';
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
      UserDecision(
        fileId: 'photo-0001',
        keepState: KeepState.discard,
        userScore: 4.5,
        userSpeciesId: 'common-kingfisher',
        userSpecies: '普通翠鸟',
        userTags: const ['复核完成'],
        version: before.decision?.version,
      ),
    );
    final after = await reviewApi.detail('photo-0001');

    expect(after.decision?.keepState, KeepState.discard);
    expect(after.decision?.version, 2);
    expect(after.decision?.userTags, contains('复核完成'));
    expect(after.history.last.source, 'app');

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
}
