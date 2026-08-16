import 'dart:async';
import 'dart:io';

import 'package:aves/bird_companion/core/media/media_asset_cache.dart';
import 'package:aves/bird_companion/core/media/media_asset_coordinator.dart';
import 'package:aves/bird_companion/core/media/media_asset_models.dart';
import 'package:aves/bird_companion/core/media/media_asset_service.dart';
import 'package:aves/bird_companion/core/media/progressive_photo_image.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/features/review/presentation/review_edit_page.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/comparison_photo_pane.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/subject_overlay_view.dart';
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

  testWidgets('详情页等待 preview 时保留 thumbnail，解码完成后定向替换', (
    tester,
  ) async {
    final previewResult = Completer<MediaAssetLoadResult>();
    final loader = _FakeLoader((descriptor, forceRefresh) async {
      if (descriptor.key.kind == MediaAssetKind.preview) {
        final result = await previewResult.future;
        coordinator.recordLoaded(descriptor.key, etag: result.etag);
        return result;
      }
      coordinator.recordLoaded(descriptor.key, etag: '"thumbnail"');
      return _imageResult('"thumbnail"');
    });
    final photo = _summary(
      previewStatus: MediaAssetStatus.pending,
      thumbnailStatus: MediaAssetStatus.ready,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: SubjectOverlayView(
              photo: PhotoDetail(summary: photo),
              subjects: const [],
              mediaAssetLoader: loader,
              mediaAssetCoordinator: coordinator,
              deviceNamespace: 'box-1',
              allowNetworkFallback: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(loader.kinds, [MediaAssetKind.thumbnail]);
    expect(_displayedKinds(tester), contains('thumbnail'));
    expect(
      find.byKey(const ValueKey('media-asset-pending-photo-1-preview')),
      findsOneWidget,
    );

    await coordinator.handleDeviceEvent(
      DeviceEvent(
        eventId: 'evt-preview-ready',
        type: 'asset_ready',
        timestamp: DateTime.utc(2026, 8, 16),
        payload: const {
          'project_id': 'project-1',
          'file_id': 'photo-1',
          'kind': 'preview',
          'status': 'ready',
          'etag': '"preview"',
          'width': 1440,
          'height': 1080,
        },
      ),
    );
    await tester.pump();

    expect(loader.kinds, [MediaAssetKind.thumbnail, MediaAssetKind.preview]);
    expect(_displayedKinds(tester), contains('thumbnail'));

    previewResult.complete(_imageResult('"preview"'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_displayedKinds(tester), contains('preview'));
  });

  testWidgets('对比页 preview 409 后只允许手动重新检查', (tester) async {
    var backendReady = false;
    late _FakeLoader loader;
    loader = _FakeLoader((descriptor, forceRefresh) async {
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
      return _imageResult('"recovered"');
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 520,
            child: ComparisonPhotoPane(
              detail: ReviewDetail(
                photo: PhotoDetail(
                  summary: _summary(
                    previewStatus: MediaAssetStatus.ready,
                    thumbnailStatus: MediaAssetStatus.ready,
                  ),
                ),
              ),
              rank: 0,
              saving: false,
              mediaAssetLoader: loader,
              mediaAssetCoordinator: coordinator,
              deviceNamespace: 'box-1',
              allowNetworkFallback: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(loader.count(MediaAssetKind.preview), 1);
    expect(
      find.byKey(const ValueKey('media-asset-failed-photo-1-preview')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 10));
    expect(loader.count(MediaAssetKind.preview), 1);

    backendReady = true;
    await tester.tap(
      find.byKey(const ValueKey('media-asset-retry-photo-1-preview')),
    );
    await tester.pumpAndSettle();

    expect(loader.count(MediaAssetKind.preview), 2);
    expect(_displayedKinds(tester), contains('preview'));
  });

  testWidgets('审核编辑卡片使用同一 preview 到 thumbnail 渐进路径', (
    tester,
  ) async {
    final loader = _FakeLoader((descriptor, forceRefresh) async {
      coordinator.recordLoaded(descriptor.key, etag: '"thumbnail"');
      return _imageResult('"thumbnail"');
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewEditPage(
          keepState: KeepState.pending,
          species: '',
          score: '',
          tags: '',
          photo: _summary(
            previewStatus: MediaAssetStatus.pending,
            thumbnailStatus: MediaAssetStatus.ready,
          ),
          mediaAssetLoader: loader,
          mediaAssetCoordinator: coordinator,
          deviceNamespace: 'box-1',
          allowNetworkFallback: false,
        ),
      ),
    );
    await tester.pump();

    expect(loader.kinds, [MediaAssetKind.thumbnail]);
    expect(_displayedKinds(tester), contains('thumbnail'));
  });

  testWidgets('分组页紧凑缩略图失败入口不会溢出', (tester) async {
    final loader = _FakeLoader((descriptor, forceRefresh) async {
      const failure = MediaAssetFailure(
        kind: MediaAssetFailureKind.assetFailed,
        statusCode: 409,
        errorCode: 'asset_failed',
      );
      coordinator.recordFailure(descriptor.key, failure);
      throw failure;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.square(
            dimension: 76,
            child: ProgressivePhotoImage(
              photo: _summary(
                previewStatus: MediaAssetStatus.pending,
                thumbnailStatus: MediaAssetStatus.ready,
              ),
              kind: MediaAssetKind.thumbnail,
              loader: loader,
              coordinator: coordinator,
              deviceNamespace: 'box-1',
              allowNetworkFallback: false,
              placeholderBuilder: (_) => const ColoredBox(
                color: Colors.green,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('media-asset-retry-photo-1-thumbnail')),
      findsOneWidget,
    );
  });
}

PhotoSummary _summary({
  required MediaAssetStatus previewStatus,
  required MediaAssetStatus thumbnailStatus,
}) => PhotoSummary(
  id: 'photo-1',
  filename: 'photo-1.jpg',
  format: 'JPEG',
  preview: PreviewRef(
    thumbnailUri: Uri.parse('http://box.local/photo-1/thumbnail'),
    previewUri: Uri.parse('http://box.local/photo-1/preview'),
    thumbnailStatus: thumbnailStatus,
    previewStatus: previewStatus,
  ),
  analysisState: AnalysisState.completed,
);

MediaAssetLoadResult _imageResult(String etag) => MediaAssetLoadResult(
  file: File('tool/mock_box_server/assets/kingfisher.png'),
  fromCache: false,
  etag: etag,
);

List<String> _displayedKinds(WidgetTester tester) => tester
    .widgetList<Image>(find.byType(Image))
    .where((image) => image.key is ValueKey<String>)
    .map((image) => (image.key! as ValueKey<String>).value)
    .where((key) => key.startsWith('media-image-'))
    .map((key) => key.contains('-preview-') ? 'preview' : 'thumbnail')
    .toList();

typedef _LoadHandler =
    Future<MediaAssetLoadResult> Function(
      MediaAssetDescriptor descriptor,
      bool forceRefresh,
    );

class _FakeLoader implements MediaAssetLoader {
  _FakeLoader(this._handler);

  final _LoadHandler _handler;
  int calls = 0;
  final List<MediaAssetKind> kinds = [];

  int count(MediaAssetKind kind) => kinds.where((value) => value == kind).length;

  @override
  Future<MediaAssetLoadResult> load(
    MediaAssetDescriptor descriptor, {
    bool forceRefresh = false,
    CancelToken? cancelToken,
  }) {
    calls++;
    kinds.add(descriptor.key.kind);
    return _handler(descriptor, forceRefresh);
  }
}

class _NoopInvalidator implements MediaAssetCacheInvalidator {
  @override
  Future<void> remove(MediaAssetDescriptor descriptor) async {}
}
