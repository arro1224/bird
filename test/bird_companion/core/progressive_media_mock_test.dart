import 'dart:io';

import 'package:aves/bird_companion/core/media/media_asset_event.dart';
import 'package:aves/bird_companion/core/media/media_asset_http_client.dart';
import 'package:aves/bird_companion/core/media/media_asset_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_api.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/mock_box_server/mock_box_server.dart';

void main() {
  late MockBoxServer server;
  late Uri baseUri;
  late ApiClient apiClient;
  late MediaAssetHttpClient mediaClient;

  setUp(() async {
    server = MockBoxServer(
      photoCount: 8,
      assetDirectory: Directory('tool/mock_box_server/assets'),
      logRequests: false,
      progressiveMedia: true,
    );
    baseUri = await server.start();
    apiClient = ApiClient()..configure(baseUri);
    mediaClient = MediaAssetHttpClient();
  });

  tearDown(() async {
    mediaClient.dispose();
    await apiClient.dispose();
    await server.close();
  });

  test('渐进模式返回状态，旧模式默认仍不返回状态', () async {
    final page = await PhotoApi(apiClient).page(
      'mock-batch-current',
      const PhotoQuery(pageSize: 8),
    );
    final byId = {for (final photo in page.items) photo.id: photo};

    expect(
      byId['photo-0001']?.preview.thumbnailStatus,
      MediaAssetStatus.ready,
    );
    expect(
      byId['photo-0002']?.preview.thumbnailStatus,
      MediaAssetStatus.failed,
    );
    expect(
      byId['photo-0003']?.preview.thumbnailStatus,
      MediaAssetStatus.pending,
    );

    final legacy = MockBoxServer(
      photoCount: 4,
      assetDirectory: Directory('tool/mock_box_server/assets'),
      logRequests: false,
    );
    final legacyUri = await legacy.start();
    final legacyClient = ApiClient()..configure(legacyUri);
    addTearDown(() async {
      await legacyClient.dispose();
      await legacy.close();
    });
    final legacyPage = await PhotoApi(legacyClient).page(
      'mock-batch-current',
      const PhotoQuery(pageSize: 1),
    );
    expect(
      legacyPage.items.single.preview.thumbnailStatus,
      MediaAssetStatus.legacy,
    );
  });

  test('404/409/file_not_found 被精确分类且 Retry-After 可读取', () async {
    final page = await PhotoApi(apiClient).page(
      'mock-batch-current',
      const PhotoQuery(pageSize: 8),
    );
    final byId = {for (final photo in page.items) photo.id: photo};

    await expectLater(
      mediaClient.fetch(byId['photo-0003']!.preview.thumbnailUri!),
      throwsA(
        isA<MediaAssetFailure>()
            .having(
              (failure) => failure.kind,
              'kind',
              MediaAssetFailureKind.notReady,
            )
            .having(
              (failure) => failure.retryAfter,
              'retryAfter',
              const Duration(seconds: 1),
            ),
      ),
    );
    await expectLater(
      mediaClient.fetch(byId['photo-0002']!.preview.thumbnailUri!),
      throwsA(
        isA<MediaAssetFailure>().having(
          (failure) => failure.kind,
          'kind',
          MediaAssetFailureKind.assetFailed,
        ),
      ),
    );
    await expectLater(
      mediaClient.fetch(
        baseUri.resolve('/api/v1/files/missing-file/thumbnail'),
      ),
      throwsA(
        isA<MediaAssetFailure>().having(
          (failure) => failure.kind,
          'kind',
          MediaAssetFailureKind.fileNotFound,
        ),
      ),
    );
  });

  test('ready 返回 ETag，If-None-Match 命中 304', () async {
    final page = await PhotoApi(apiClient).page(
      'mock-batch-current',
      const PhotoQuery(pageSize: 8),
    );
    final ready = page.items.singleWhere(
      (photo) => photo.id == 'photo-0001',
    );
    final first = await mediaClient.fetch(
      ready.preview.thumbnailUri!,
    );
    final second = await mediaClient.fetch(
      ready.preview.thumbnailUri!,
      ifNoneMatch: first.etag,
    );

    expect(first.bytes, isNotEmpty);
    expect(first.etag, isNotNull);
    expect(second.notModified, isTrue);
    expect(second.etag, first.etag);
    expect(server.lastSignedAssetAuthorizationHeader, isNull);
  });

  test('资源变为 ready 后通过 WebSocket 发送完整定向事件', () async {
    final events = EventClient();
    addTearDown(events.dispose);
    final initialEvent = events.events.first;
    await events.connect(
      baseUri.replace(scheme: 'ws', path: '/api/v1/events'),
      accessToken: 'mock-token',
    );
    await initialEvent.timeout(const Duration(seconds: 2));
    final eventFuture = events.events.where((event) => event.type == 'asset_ready').map(AssetReadyEvent.tryFromDeviceEvent).where((event) => event != null).cast<AssetReadyEvent>().first.timeout(const Duration(seconds: 2));

    await server.setMediaAssetStatus(
      'photo-0003',
      'thumbnail',
      'ready',
    );
    final event = await eventFuture;

    expect(event.eventId, startsWith('evt-asset-'));
    expect(event.projectId, 'mock-batch-current');
    expect(event.fileId, 'photo-0003');
    expect(event.kind, MediaAssetKind.thumbnail);
    expect(event.etag, contains('photo-0003-thumbnail'));
  });
}
