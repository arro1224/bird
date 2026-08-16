import 'dart:io';

import 'package:aves/bird_companion/core/media/media_asset_cache.dart';
import 'package:aves/bird_companion/core/media/media_asset_coordinator.dart';
import 'package:aves/bird_companion/core/media/media_asset_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_api.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/acceptance/progressive_media_p4_acceptance.dart';
import '../../../tool/mock_box_server/mock_box_server.dart';

void main() {
  test('P4 可控 K7 门禁覆盖乱序事件、WS 丢失和 HTTP 恢复', () async {
    final server = MockBoxServer(
      photoCount: 1200,
      assetDirectory: Directory('tool/mock_box_server/assets'),
      logRequests: false,
      progressiveMedia: true,
    );
    final baseUri = await server.start();
    addTearDown(server.close);

    final report = await runProgressiveMediaP4Acceptance(baseUri);

    expect(report.apiVersion, 'v1');
    expect(report.readyBytes, greaterThan(1000));
    expect(report.fallbackBytes, greaterThan(1000));
    expect(report.retryAfterSeconds, 1);
    expect(report.outOfOrderEvents, [
      '${report.secondFileId}:thumbnail',
      '${report.firstFileId}:preview',
    ]);
    expect(report.websocketDisconnectObserved, isTrue);
    expect(report.missingEventFallbackVerified, isTrue);

    final client = ApiClient()..configure(baseUri);
    addTearDown(client.dispose);
    final restored = await PhotoApi(client).page(
      'mock-batch-current',
      const PhotoQuery(pageSize: 16),
    );
    final byId = {for (final photo in restored.items) photo.id: photo};
    for (final fileId in [report.firstFileId, report.secondFileId]) {
      expect(
        byId[fileId]?.preview.thumbnailStatus,
        MediaAssetStatus.pending,
      );
      expect(
        byId[fileId]?.preview.previewStatus,
        MediaAssetStatus.notRequested,
      );
    }
  });

  test('P4 跨版本门禁保持旧 K7 的 legacy URL 读取', () async {
    final server = MockBoxServer(
      photoCount: 16,
      assetDirectory: Directory('tool/mock_box_server/assets'),
      logRequests: false,
    );
    final baseUri = await server.start();
    final client = ApiClient()..configure(baseUri);
    addTearDown(() async {
      await client.dispose();
      await server.close();
    });

    final page = await PhotoApi(client).page(
      'mock-batch-current',
      const PhotoQuery(pageSize: 4),
    );

    expect(page.items, isNotEmpty);
    expect(
      page.items.map((photo) => photo.preview.thumbnailStatus),
      everyElement(MediaAssetStatus.legacy),
    );
    expect(
      page.items.map((photo) => photo.preview.previewStatus),
      everyElement(MediaAssetStatus.legacy),
    );
    final bytes = await client.downloadSignedBytes(
      page.items.first.preview.thumbnailUri!,
    );
    expect(bytes.bytes, isNotEmpty);
  });

  test('P4 默认重试严格止于 5 次', () async {
    final events = EventClient();
    final coordinator = MediaAssetCoordinator(
      eventClient: events,
      activeDeviceId: () => 'device-a',
      cacheInvalidator: _NoopInvalidator(),
      retryPolicy: const MediaAssetRetryPolicy(
        delays: [Duration.zero],
        maxDelay: Duration.zero,
        maxAttempts: 5,
      ),
    );
    addTearDown(() async {
      await coordinator.dispose();
      await events.dispose();
    });
    const key = MediaAssetKey(
      deviceId: 'device-a',
      fileId: 'retry-file',
      kind: MediaAssetKind.preview,
    );
    coordinator.track(
      const MediaAssetDescriptor(
        key: key,
        status: MediaAssetStatus.pending,
      ),
    );
    const failure = MediaAssetFailure(
      kind: MediaAssetFailureKind.notReady,
      retryable: true,
      retryAfter: Duration.zero,
    );

    for (var attempt = 1; attempt <= 5; attempt++) {
      final due = coordinator
          .watch(key)
          .firstWhere(
            (update) => update.reason == MediaAssetUpdateReason.retryDue,
          );
      expect(coordinator.recordFailure(key, failure), isTrue);
      await due.timeout(const Duration(seconds: 1));
      expect(coordinator.snapshot(key)?.retryAttempt, attempt);
    }
    expect(coordinator.recordFailure(key, failure), isFalse);
    expect(coordinator.snapshot(key)?.retryAttempt, 5);
  });

  test('P4 千资源乱序压力保持目标订阅和设备缓存隔离', () async {
    var activeDevice = 'device-a';
    final events = EventClient();
    final coordinator = MediaAssetCoordinator(
      eventClient: events,
      activeDeviceId: () => activeDevice,
      cacheInvalidator: _NoopInvalidator(),
    );
    addTearDown(() async {
      await coordinator.dispose();
      await events.dispose();
    });
    for (var index = 0; index < 1000; index++) {
      coordinator.track(
        MediaAssetDescriptor(
          key: MediaAssetKey(
            deviceId: 'device-a',
            fileId: 'pressure-$index',
            kind: MediaAssetKind.thumbnail,
          ),
          status: MediaAssetStatus.pending,
        ),
      );
    }
    const isolatedKey = MediaAssetKey(
      deviceId: 'device-b',
      fileId: 'pressure-500',
      kind: MediaAssetKind.thumbnail,
    );
    coordinator.track(
      const MediaAssetDescriptor(
        key: isolatedKey,
        status: MediaAssetStatus.pending,
      ),
    );
    const targetKey = MediaAssetKey(
      deviceId: 'device-a',
      fileId: 'pressure-500',
      kind: MediaAssetKind.thumbnail,
    );
    var targetUpdates = 0;
    final targetSubscription = coordinator
        .watch(targetKey)
        .where(
          (update) => update.reason == MediaAssetUpdateReason.assetReadyEvent,
        )
        .listen((_) => targetUpdates++);
    addTearDown(targetSubscription.cancel);

    final watch = Stopwatch()..start();
    for (var index = 999; index >= 0; index--) {
      await coordinator.handleDeviceEvent(
        DeviceEvent(
          eventId: 'evt-pressure-$index',
          type: 'asset_ready',
          timestamp: DateTime.utc(2026, 8, 16),
          payload: {
            'project_id': 'project-pressure',
            'file_id': 'pressure-$index',
            'kind': 'thumbnail',
            'status': 'ready',
            'etag': '"pressure-$index"',
            'width': 512,
            'height': 341,
          },
        ),
      );
    }
    await Future<void>.delayed(Duration.zero);
    watch.stop();

    expect(targetUpdates, 1);
    expect(
      coordinator.snapshot(targetKey)?.descriptor.status,
      MediaAssetStatus.ready,
    );
    expect(
      coordinator.snapshot(isolatedKey)?.descriptor.status,
      MediaAssetStatus.pending,
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));

    activeDevice = 'device-b';
    expect(
      coordinator.snapshot(isolatedKey)?.descriptor.status,
      MediaAssetStatus.pending,
    );
  });
}

class _NoopInvalidator implements MediaAssetCacheInvalidator {
  @override
  Future<void> remove(MediaAssetDescriptor descriptor) async {}
}
