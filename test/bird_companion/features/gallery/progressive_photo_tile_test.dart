import 'dart:io';

import 'package:aves/bird_companion/core/media/media_asset_cache.dart';
import 'package:aves/bird_companion/core/media/media_asset_coordinator.dart';
import 'package:aves/bird_companion/core/media/media_asset_models.dart';
import 'package:aves/bird_companion/core/media/media_asset_service.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/photo_tile.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EventClient eventClient;
  late MediaAssetCoordinator coordinator;

  setUp(() {
    eventClient = EventClient();
    coordinator = MediaAssetCoordinator(
      eventClient: eventClient,
      activeDeviceId: () => 'box-1',
      cacheInvalidator: _NoopInvalidator(),
      retryPolicy: const MediaAssetRetryPolicy(
        delays: [Duration.zero],
        maxDelay: Duration.zero,
        maxAttempts: 2,
      ),
    );
  });

  tearDown(() async {
    await coordinator.dispose();
    await eventClient.dispose();
  });

  testWidgets('pending 缩略图等待 asset_ready 且只加载目标照片', (
    tester,
  ) async {
    final loader = _FakeLoader((descriptor, forceRefresh) async {
      coordinator.recordLoaded(descriptor.key, etag: '"ready"');
      return _imageResult(etag: '"ready"');
    });

    await tester.pumpWidget(
      _twoTileHarness(
        first: _photo('photo-1', MediaAssetStatus.pending),
        second: _photo('photo-2', MediaAssetStatus.pending),
        loader: loader,
        coordinator: coordinator,
        allowNetworkFallback: false,
      ),
    );

    expect(
      find.byKey(const ValueKey('media-asset-pending-photo-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('media-asset-pending-photo-2')),
      findsOneWidget,
    );
    expect(loader.fileIds, isEmpty);

    await coordinator.handleDeviceEvent(
      DeviceEvent(
        eventId: 'evt-ready-1',
        type: 'asset_ready',
        timestamp: DateTime.utc(2026, 8, 16),
        payload: const {
          'project_id': 'project-1',
          'file_id': 'photo-1',
          'kind': 'thumbnail',
          'status': 'ready',
          'etag': '"ready"',
          'width': 512,
          'height': 341,
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(loader.fileIds, ['photo-1']);
    expect(loader.statuses, [MediaAssetStatus.ready]);
    expect(
      find.byKey(const ValueKey('media-asset-pending-photo-2')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      _tileHarness(
        photo: _photo('photo-1', MediaAssetStatus.pending),
        loader: loader,
        coordinator: coordinator,
        allowNetworkFallback: false,
      ),
    );
    await tester.pump();

    expect(loader.fileIds, ['photo-1', 'photo-1']);
    expect(loader.statuses, everyElement(MediaAssetStatus.ready));
  });

  testWidgets('WS 不可用时 pending 通过 404 有限退避恢复', (
    tester,
  ) async {
    late _FakeLoader loader;
    loader = _FakeLoader((descriptor, forceRefresh) async {
      coordinator.track(descriptor);
      if (loader.calls == 1) {
        const failure = MediaAssetFailure(
          kind: MediaAssetFailureKind.notReady,
          statusCode: 404,
          errorCode: 'asset_not_ready',
          retryable: true,
          retryAfter: Duration.zero,
        );
        coordinator.recordFailure(descriptor.key, failure);
        throw failure;
      }
      coordinator.recordLoaded(descriptor.key, etag: '"etag-v2"');
      return _imageResult(etag: '"etag-v2"');
    });

    await tester.pumpWidget(
      _tileHarness(
        photo: _photo('photo-retry', MediaAssetStatus.pending),
        loader: loader,
        coordinator: coordinator,
        allowNetworkFallback: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(loader.calls, 2);
    expect(loader.forceRefreshValues, everyElement(isTrue));
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('409 进入失败态且只有手动点击才重新检查', (
    tester,
  ) async {
    var backendReady = false;
    late _FakeLoader loader;
    loader = _FakeLoader((descriptor, forceRefresh) async {
      coordinator.track(descriptor);
      if (!backendReady) {
        const failure = MediaAssetFailure(
          kind: MediaAssetFailureKind.assetFailed,
          statusCode: 409,
          errorCode: 'asset_failed',
        );
        coordinator.recordFailure(descriptor.key, failure);
        throw failure;
      }
      coordinator.recordLoaded(descriptor.key, etag: '"recovered"');
      return _imageResult(etag: '"recovered"');
    });

    await tester.pumpWidget(
      _tileHarness(
        photo: _photo('photo-failed', MediaAssetStatus.ready),
        loader: loader,
        coordinator: coordinator,
      ),
    );
    await tester.pump();

    expect(loader.calls, 1);
    expect(
      find.byKey(const ValueKey('media-asset-failed-photo-failed')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('media-asset-retry-photo-failed')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 10));
    expect(loader.calls, 1);

    backendReady = true;
    await tester.tap(
      find.byKey(const ValueKey('media-asset-retry-photo-failed')),
    );
    await tester.pump();
    await tester.pump();

    expect(loader.calls, 2);
    expect(find.byType(Image), findsOneWidget);
  });
}

PhotoSummary _photo(String id, MediaAssetStatus status) => PhotoSummary(
  id: id,
  filename: '$id.jpg',
  format: 'JPEG',
  preview: PreviewRef(
    thumbnailUri: Uri.parse('http://box.local/$id/thumbnail'),
    thumbnailStatus: status,
  ),
  analysisState: AnalysisState.processing,
);

Widget _tileHarness({
  required PhotoSummary photo,
  required MediaAssetLoader loader,
  required MediaAssetCoordinator coordinator,
  bool allowNetworkFallback = false,
}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 160,
      height: 200,
      child: PhotoTile(
        photo: photo,
        selected: false,
        onTap: () {},
        onLongPress: () {},
        deviceNamespace: 'box-1',
        mediaAssetLoader: loader,
        mediaAssetCoordinator: coordinator,
        allowNetworkFallback: allowNetworkFallback,
      ),
    ),
  ),
);

Widget _twoTileHarness({
  required PhotoSummary first,
  required PhotoSummary second,
  required MediaAssetLoader loader,
  required MediaAssetCoordinator coordinator,
  required bool allowNetworkFallback,
}) => MaterialApp(
  home: Scaffold(
    body: Row(
      children: [
        for (final photo in [first, second])
          Expanded(
            child: SizedBox(
              height: 200,
              child: PhotoTile(
                photo: photo,
                selected: false,
                onTap: () {},
                onLongPress: () {},
                deviceNamespace: 'box-1',
                mediaAssetLoader: loader,
                mediaAssetCoordinator: coordinator,
                allowNetworkFallback: allowNetworkFallback,
              ),
            ),
          ),
      ],
    ),
  ),
);

MediaAssetLoadResult _imageResult({required String etag}) => MediaAssetLoadResult(
  file: File('tool/mock_box_server/assets/kingfisher.png'),
  fromCache: false,
  etag: etag,
);

typedef _LoadHandler =
    Future<MediaAssetLoadResult> Function(
      MediaAssetDescriptor descriptor,
      bool forceRefresh,
    );

class _FakeLoader implements MediaAssetLoader {
  _FakeLoader(this._handler);

  final _LoadHandler _handler;
  int calls = 0;
  final List<String> fileIds = [];
  final List<bool> forceRefreshValues = [];
  final List<MediaAssetStatus> statuses = [];

  @override
  Future<MediaAssetLoadResult> load(
    MediaAssetDescriptor descriptor, {
    bool forceRefresh = false,
    CancelToken? cancelToken,
  }) {
    calls++;
    fileIds.add(descriptor.key.fileId);
    forceRefreshValues.add(forceRefresh);
    statuses.add(descriptor.status);
    return _handler(descriptor, forceRefresh);
  }
}

class _NoopInvalidator implements MediaAssetCacheInvalidator {
  @override
  Future<void> remove(MediaAssetDescriptor descriptor) async {}
}
