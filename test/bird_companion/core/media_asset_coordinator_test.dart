import 'package:aves/bird_companion/core/media/media_asset_cache.dart';
import 'package:aves/bird_companion/core/media/media_asset_coordinator.dart';
import 'package:aves/bird_companion/core/media/media_asset_models.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EventClient eventClient;
  late _RecordingInvalidator invalidator;
  late MediaAssetCoordinator coordinator;
  const key = MediaAssetKey(
    deviceId: 'device-1',
    fileId: 'file-1',
    kind: MediaAssetKind.thumbnail,
  );
  final descriptor = MediaAssetDescriptor(
    key: key,
    uri: Uri.parse('http://box/media/file-1/thumb?signature=secret'),
    status: MediaAssetStatus.pending,
  );

  setUp(() {
    eventClient = EventClient();
    invalidator = _RecordingInvalidator();
    coordinator = MediaAssetCoordinator(
      eventClient: eventClient,
      activeDeviceId: () => 'device-1',
      cacheInvalidator: invalidator,
      retryPolicy: const MediaAssetRetryPolicy(
        delays: [Duration.zero],
        maxDelay: Duration.zero,
        maxAttempts: 2,
      ),
    );
    coordinator.track(descriptor);
  });

  tearDown(() async {
    await coordinator.dispose();
    await eventClient.dispose();
  });

  test('asset_not_ready 使用有限次数并按资源发送 retryDue', () async {
    const failure = MediaAssetFailure(
      kind: MediaAssetFailureKind.notReady,
      statusCode: 404,
      errorCode: 'asset_not_ready',
      retryable: true,
      retryAfter: Duration.zero,
    );
    final firstRetry = coordinator.watch(key).firstWhere((update) => update.reason == MediaAssetUpdateReason.retryDue);

    expect(coordinator.recordFailure(key, failure), isTrue);
    await firstRetry.timeout(const Duration(seconds: 1));
    expect(coordinator.snapshot(key)?.retryAttempt, 1);

    final secondRetry = coordinator.watch(key).firstWhere((update) => update.reason == MediaAssetUpdateReason.retryDue);
    expect(coordinator.recordFailure(key, failure), isTrue);
    await secondRetry.timeout(const Duration(seconds: 1));
    expect(coordinator.recordFailure(key, failure), isFalse);
    expect(coordinator.snapshot(key)?.retryAttempt, 2);
  });

  test('asset_failed 进入终态且不安排重试', () async {
    const failure = MediaAssetFailure(
      kind: MediaAssetFailureKind.assetFailed,
      statusCode: 409,
      errorCode: 'asset_failed',
    );

    expect(coordinator.recordFailure(key, failure), isFalse);
    expect(
      coordinator.snapshot(key)?.descriptor.status,
      MediaAssetStatus.failed,
    );
    expect(
      coordinator.snapshot(key)?.lastFailure?.kind,
      MediaAssetFailureKind.assetFailed,
    );
  });

  test('asset_ready 只更新目标资源并在新 ETag 时清缓存', () async {
    const otherKey = MediaAssetKey(
      deviceId: 'device-1',
      fileId: 'file-2',
      kind: MediaAssetKind.thumbnail,
    );
    coordinator.track(
      MediaAssetDescriptor(
        key: otherKey,
        uri: Uri.parse('http://box/media/file-2/thumb'),
        status: MediaAssetStatus.pending,
      ),
    );
    final targetUpdate = coordinator
        .watch(key)
        .firstWhere(
          (update) => update.reason == MediaAssetUpdateReason.assetReadyEvent,
        );

    await coordinator.handleDeviceEvent(
      DeviceEvent(
        eventId: 'evt-1',
        type: 'asset_ready',
        timestamp: DateTime.utc(2026, 8, 16),
        payload: const {
          'project_id': 'project-1',
          'file_id': 'file-1',
          'kind': 'thumbnail',
          'status': 'ready',
          'etag': '"etag-v2"',
          'width': 512,
          'height': 341,
        },
      ),
    );
    await targetUpdate;

    expect(invalidator.removed, [
      descriptor.copyWith(status: MediaAssetStatus.ready),
    ]);
    expect(coordinator.snapshot(key)?.etag, '"etag-v2"');
    expect(
      coordinator.snapshot(key)?.descriptor.status,
      MediaAssetStatus.ready,
    );
    expect(
      coordinator.snapshot(otherKey)?.descriptor.status,
      MediaAssetStatus.pending,
    );

    expect(coordinator.track(descriptor).descriptor.status, MediaAssetStatus.ready);
  });

  test('组件复用不会覆盖运行时失败态，手动重试可以显式解除', () {
    const failure = MediaAssetFailure(
      kind: MediaAssetFailureKind.assetFailed,
      statusCode: 409,
      errorCode: 'asset_failed',
    );
    coordinator.recordFailure(key, failure);

    final staleReady = descriptor.copyWith(status: MediaAssetStatus.ready);
    expect(
      coordinator.track(staleReady).descriptor.status,
      MediaAssetStatus.failed,
    );

    final retryDescriptor = descriptor.copyWith(
      status: MediaAssetStatus.legacy,
    );
    expect(
      coordinator.resetForManualRetry(retryDescriptor).descriptor.status,
      MediaAssetStatus.legacy,
    );
    expect(coordinator.snapshot(key)?.lastFailure, isNull);
  });
}

class _RecordingInvalidator implements MediaAssetCacheInvalidator {
  final List<MediaAssetDescriptor> removed = [];

  @override
  Future<void> remove(MediaAssetDescriptor descriptor) async {
    removed.add(descriptor);
  }
}
