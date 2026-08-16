import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/media/media_asset_event.dart';
import 'package:aves/bird_companion/core/media/media_asset_http_client.dart';
import 'package:aves/bird_companion/core/media/media_asset_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/network/reconnect_policy.dart';
import 'package:aves/bird_companion/features/device/data/device_status_api.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_api.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';

Future<void> main(List<String> arguments) async {
  final baseUri = _baseUri(arguments);
  try {
    final report = await runProgressiveMediaP4Acceptance(baseUri);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
  } catch (error, stackTrace) {
    stderr.writeln('P4 progressive media acceptance failed: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  }
}

/// Runs the controllable P4 media gate against an already-running K7 box.
///
/// Two non-ready resources are temporarily changed and restored. The gate
/// also restores asset event delivery even when an assertion fails midway.
Future<ProgressiveMediaP4Report> runProgressiveMediaP4Acceptance(
  Uri baseUri,
) async {
  final apiClient = ApiClient()..configure(baseUri);
  final mediaClient = MediaAssetHttpClient();
  final events = EventClient(
    reconnectPolicy: const ReconnectPolicy(
      maxAttempts: 5,
      initialDelay: Duration(milliseconds: 20),
      maxDelay: Duration(milliseconds: 100),
    ),
  );
  final watch = Stopwatch()..start();
  _AssetBaseline? firstBaseline;
  _AssetBaseline? secondBaseline;
  try {
    final health = await apiClient.getUri(baseUri.resolve('/healthz'));
    _require(health['status'] == 'ok', 'K7 health status is not ok');
    _require(
      health['progressive_media'] == true,
      'K7 is not running with --progressive-media',
    );
    final device = await DeviceStatusApi(apiClient).fetchStatus();
    final page = await PhotoApi(apiClient).page(
      'mock-batch-current',
      const PhotoQuery(pageSize: 64),
    );
    final candidates = page.items
        .where(
          (photo) => photo.preview.thumbnailUri != null && photo.preview.previewUri != null && photo.preview.thumbnailStatus == MediaAssetStatus.pending && photo.preview.previewStatus == MediaAssetStatus.notRequested,
        )
        .take(2)
        .toList(growable: false);
    _require(
      candidates.length == 2,
      'K7 must expose two pending/not_requested photos for the P4 gate',
    );
    final first = candidates[0];
    final second = candidates[1];
    firstBaseline = _AssetBaseline(
      fileId: first.id,
      thumbnailStatus: first.preview.thumbnailStatus,
      previewStatus: first.preview.previewStatus,
    );
    secondBaseline = _AssetBaseline(
      fileId: second.id,
      thumbnailStatus: second.preview.thumbnailStatus,
      previewStatus: second.preview.previewStatus,
    );

    final initialEvent = events.events.first;
    await events.connect(
      baseUri.replace(scheme: 'ws', path: '/api/v1/events'),
      accessToken: 'p4-acceptance',
    );
    await initialEvent.timeout(const Duration(seconds: 2));

    await _setAsset(
      apiClient,
      baseUri,
      first.id,
      MediaAssetKind.thumbnail,
      MediaAssetStatus.pending,
      emitEvent: false,
    );
    final notReady = await _captureFailure(
      () => mediaClient.fetch(first.preview.thumbnailUri!),
    );
    _require(
      notReady.kind == MediaAssetFailureKind.notReady && notReady.retryAfter == const Duration(seconds: 1),
      'pending thumbnail did not return retryable asset_not_ready',
    );

    final readyEventFuture = _nextAssetEvent(
      events,
      fileId: first.id,
      kind: MediaAssetKind.thumbnail,
    );
    await _setAsset(
      apiClient,
      baseUri,
      first.id,
      MediaAssetKind.thumbnail,
      MediaAssetStatus.ready,
    );
    final readyEvent = await readyEventFuture;
    final ready = await mediaClient.fetch(first.preview.thumbnailUri!);
    _require(ready.bytes?.isNotEmpty == true, 'ready thumbnail is empty');
    _require(
      ready.etag == readyEvent.etag,
      'asset_ready ETag differs from the HTTP ETag',
    );
    final notModified = await mediaClient.fetch(
      first.preview.thumbnailUri!,
      ifNoneMatch: ready.etag,
    );
    _require(notModified.notModified, 'If-None-Match did not return 304');

    await _setAsset(
      apiClient,
      baseUri,
      first.id,
      MediaAssetKind.preview,
      MediaAssetStatus.pending,
      emitEvent: false,
    );
    await _setAsset(
      apiClient,
      baseUri,
      second.id,
      MediaAssetKind.thumbnail,
      MediaAssetStatus.pending,
      emitEvent: false,
    );
    final orderedEvents = events.events
        .map(AssetReadyEvent.tryFromDeviceEvent)
        .where((event) => event != null)
        .cast<AssetReadyEvent>()
        .where(
          (event) => (event.fileId == second.id && event.kind == MediaAssetKind.thumbnail) || (event.fileId == first.id && event.kind == MediaAssetKind.preview),
        )
        .take(2)
        .toList();
    await _setAsset(
      apiClient,
      baseUri,
      second.id,
      MediaAssetKind.thumbnail,
      MediaAssetStatus.ready,
    );
    await _setAsset(
      apiClient,
      baseUri,
      first.id,
      MediaAssetKind.preview,
      MediaAssetStatus.ready,
    );
    final order = await orderedEvents.timeout(const Duration(seconds: 2));
    _require(
      order[0].fileId == second.id && order[0].kind == MediaAssetKind.thumbnail && order[1].fileId == first.id && order[1].kind == MediaAssetKind.preview,
      'out-of-order asset completion was not delivered in wire order',
    );

    final reconnectObserved = events.connectionStates.firstWhere(
      (state) => state == EventConnectionState.reconnecting || state == EventConnectionState.disconnected,
    );
    await _setEvents(apiClient, baseUri, false);
    await reconnectObserved.timeout(const Duration(seconds: 2));
    await _setAsset(
      apiClient,
      baseUri,
      second.id,
      MediaAssetKind.preview,
      MediaAssetStatus.pending,
      emitEvent: false,
    );
    var missingEventObserved = false;
    final missingEventSubscription = events.events
        .map(AssetReadyEvent.tryFromDeviceEvent)
        .where((event) => event != null)
        .cast<AssetReadyEvent>()
        .where(
          (event) => event.fileId == second.id && event.kind == MediaAssetKind.preview,
        )
        .listen((_) => missingEventObserved = true);
    await _setAsset(
      apiClient,
      baseUri,
      second.id,
      MediaAssetKind.preview,
      MediaAssetStatus.ready,
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await missingEventSubscription.cancel();
    _require(
      !missingEventObserved,
      'asset event was emitted while event delivery was disabled',
    );
    final fallback = await mediaClient.fetch(second.preview.previewUri!);
    _require(
      fallback.bytes?.isNotEmpty == true,
      'HTTP fallback could not recover a ready preview',
    );
    await _setEvents(apiClient, baseUri, true);

    watch.stop();
    return ProgressiveMediaP4Report(
      baseUri: baseUri,
      deviceId: device.connection.id,
      apiVersion: device.connection.apiVersion ?? 'unknown',
      firstFileId: first.id,
      secondFileId: second.id,
      readyEtag: ready.etag!,
      readyBytes: ready.bytes!.length,
      fallbackBytes: fallback.bytes!.length,
      retryAfterSeconds: notReady.retryAfter!.inSeconds,
      outOfOrderEvents: [
        for (final event in order) '${event.fileId}:${event.kind.wireValue}',
      ],
      websocketDisconnectObserved: true,
      missingEventFallbackVerified: true,
      totalMilliseconds: watch.elapsedMilliseconds,
    );
  } finally {
    Object? restorationError;
    try {
      await _setEvents(apiClient, baseUri, true);
      if (firstBaseline != null) {
        await _restoreBaseline(apiClient, baseUri, firstBaseline);
      }
      if (secondBaseline != null) {
        await _restoreBaseline(apiClient, baseUri, secondBaseline);
      }
    } catch (error) {
      restorationError = error;
    }
    mediaClient.dispose();
    await events.dispose();
    await apiClient.dispose();
    if (restorationError != null) {
      throw StateError(
        'P4 could not restore K7 media state: $restorationError',
      );
    }
  }
}

class ProgressiveMediaP4Report {
  const ProgressiveMediaP4Report({
    required this.baseUri,
    required this.deviceId,
    required this.apiVersion,
    required this.firstFileId,
    required this.secondFileId,
    required this.readyEtag,
    required this.readyBytes,
    required this.fallbackBytes,
    required this.retryAfterSeconds,
    required this.outOfOrderEvents,
    required this.websocketDisconnectObserved,
    required this.missingEventFallbackVerified,
    required this.totalMilliseconds,
  });

  final Uri baseUri;
  final String deviceId;
  final String apiVersion;
  final String firstFileId;
  final String secondFileId;
  final String readyEtag;
  final int readyBytes;
  final int fallbackBytes;
  final int retryAfterSeconds;
  final List<String> outOfOrderEvents;
  final bool websocketDisconnectObserved;
  final bool missingEventFallbackVerified;
  final int totalMilliseconds;

  Map<String, dynamic> toJson() => {
    'base_uri': baseUri.toString(),
    'device_id': deviceId,
    'api_version': apiVersion,
    'first_file_id': firstFileId,
    'second_file_id': secondFileId,
    'ready_etag': readyEtag,
    'ready_bytes': readyBytes,
    'fallback_bytes': fallbackBytes,
    'retry_after_seconds': retryAfterSeconds,
    'out_of_order_events': outOfOrderEvents,
    'websocket_disconnect_observed': websocketDisconnectObserved,
    'missing_event_fallback_verified': missingEventFallbackVerified,
    'total_milliseconds': totalMilliseconds,
  };
}

class _AssetBaseline {
  const _AssetBaseline({
    required this.fileId,
    required this.thumbnailStatus,
    required this.previewStatus,
  });

  final String fileId;
  final MediaAssetStatus thumbnailStatus;
  final MediaAssetStatus previewStatus;
}

Future<void> _restoreBaseline(
  ApiClient client,
  Uri baseUri,
  _AssetBaseline baseline,
) async {
  await _setAsset(
    client,
    baseUri,
    baseline.fileId,
    MediaAssetKind.thumbnail,
    baseline.thumbnailStatus,
    emitEvent: false,
  );
  await _setAsset(
    client,
    baseUri,
    baseline.fileId,
    MediaAssetKind.preview,
    baseline.previewStatus,
    emitEvent: false,
  );
}

Future<void> _setAsset(
  ApiClient client,
  Uri baseUri,
  String fileId,
  MediaAssetKind kind,
  MediaAssetStatus status, {
  bool emitEvent = true,
}) async {
  final wireStatus = status.wireValue;
  _require(wireStatus != null, 'Cannot control an App-only media status');
  await client.postUri(
    baseUri.resolve('/mock/control/assets'),
    data: {
      'file_id': fileId,
      'kind': kind.wireValue,
      'status': wireStatus,
      'emit_event': emitEvent,
    },
  );
}

Future<void> _setEvents(
  ApiClient client,
  Uri baseUri,
  bool enabled,
) => client.postUri(
  baseUri.resolve('/mock/control/events'),
  data: {'enabled': enabled},
);

Future<AssetReadyEvent> _nextAssetEvent(
  EventClient events, {
  required String fileId,
  required MediaAssetKind kind,
}) => events.events.map(AssetReadyEvent.tryFromDeviceEvent).where((event) => event != null).cast<AssetReadyEvent>().firstWhere((event) => event.fileId == fileId && event.kind == kind).timeout(const Duration(seconds: 2));

Future<MediaAssetFailure> _captureFailure(
  Future<void> Function() request,
) async {
  try {
    await request();
  } on MediaAssetFailure catch (failure) {
    return failure;
  }
  throw StateError('Expected the media request to fail.');
}

Uri _baseUri(List<String> arguments) {
  final value = arguments.isEmpty ? 'http://127.0.0.1:8787' : arguments.first;
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw ArgumentError.value(value, 'baseUri', 'Expected a complete K7 URL.');
  }
  return uri;
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
