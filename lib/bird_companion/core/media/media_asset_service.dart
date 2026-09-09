import 'dart:async';
import 'dart:io';

import 'package:aves/bird_companion/core/media/media_asset_cache.dart';
import 'package:aves/bird_companion/core/media/media_asset_coordinator.dart';
import 'package:aves/bird_companion/core/media/media_asset_http_client.dart';
import 'package:aves/bird_companion/core/media/media_asset_models.dart';
import 'package:dio/dio.dart';

class MediaAssetLoadResult {
  const MediaAssetLoadResult({
    required this.file,
    required this.fromCache,
    this.etag,
  });

  final File file;
  final bool fromCache;
  final String? etag;
}

abstract interface class MediaAssetLoader {
  Future<MediaAssetLoadResult> load(
    MediaAssetDescriptor descriptor, {
    bool forceRefresh = false,
    CancelToken? cancelToken,
  });
}

class MediaAssetService implements MediaAssetLoader {
  MediaAssetService({
    required MediaAssetHttpClient httpClient,
    required MediaAssetCache cache,
    required MediaAssetCoordinator coordinator,
  }) : this._(httpClient, cache, coordinator);

  MediaAssetService._(
    this._httpClient,
    this._cache,
    this._coordinator,
  );

  final MediaAssetHttpClient _httpClient;
  final MediaAssetCache _cache;
  final MediaAssetCoordinator _coordinator;
  final Map<String, Future<MediaAssetLoadResult>> _inFlight = {};
  final Map<MediaAssetKey, String> _latestIdentity = {};

  @override
  Future<MediaAssetLoadResult> load(
    MediaAssetDescriptor descriptor, {
    bool forceRefresh = false,
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled ?? false) {
      throw _cancelledFailure(cancelToken!.cancelError);
    }
    final tracked = _coordinator.track(descriptor);
    final status = tracked.descriptor.status;
    if (status == MediaAssetStatus.failed || (!status.canRequest && !forceRefresh)) {
      throw MediaAssetStateException(status);
    }
    final uri = tracked.descriptor.uri;
    if (uri == null) {
      throw ArgumentError.value(
        descriptor,
        'descriptor',
        'Media URI is required before loading.',
      );
    }
    final identity = _cache.keyFor(tracked.descriptor);
    _latestIdentity[descriptor.key] = identity;
    final existing = _inFlight[identity];
    if (existing != null) {
      return _waitForSubscriber(existing, cancelToken);
    }
    final shared = _startTransfer(
      tracked.descriptor,
      identity: identity,
      forceRefresh: forceRefresh,
    );
    return _waitForSubscriber(shared, cancelToken);
  }

  Future<MediaAssetLoadResult> _startTransfer(
    MediaAssetDescriptor descriptor, {
    required String identity,
    required bool forceRefresh,
  }) {
    late final Future<MediaAssetLoadResult> shared;
    shared =
        _loadShared(
          descriptor,
          identity: identity,
          forceRefresh: forceRefresh,
        ).whenComplete(() {
          if (identical(_inFlight[identity], shared)) {
            _inFlight.remove(identity);
          }
        });
    _inFlight[identity] = shared;
    return shared;
  }

  Future<MediaAssetLoadResult> _loadShared(
    MediaAssetDescriptor descriptor, {
    required String identity,
    required bool forceRefresh,
  }) async {
    final cached = await _cache.read(descriptor);
    if (cached != null && !cached.isStale && !forceRefresh) {
      _recordLoadedIfCurrent(descriptor.key, identity, cached.etag);
      return MediaAssetLoadResult(
        file: cached.file,
        fromCache: true,
        etag: cached.etag,
      );
    }
    try {
      var response = await _httpClient.fetch(
        descriptor.uri!,
        ifNoneMatch: cached?.etag,
      );
      if (response.notModified && cached == null) {
        response = await _httpClient.fetch(descriptor.uri!);
      }
      if (response.notModified) {
        final refreshed = await _cache.write(
          descriptor,
          await cached!.file.readAsBytes(),
          etag: response.etag ?? cached.etag,
          maxAge: response.maxAge,
        );
        _recordLoadedIfCurrent(
          descriptor.key,
          identity,
          response.etag ?? cached.etag,
        );
        return MediaAssetLoadResult(
          file: refreshed,
          fromCache: true,
          etag: response.etag ?? cached.etag,
        );
      }
      final file = await _cache.write(
        descriptor,
        response.bytes!,
        etag: response.etag,
        contentType: response.contentType,
        maxAge: response.maxAge,
      );
      _recordLoadedIfCurrent(descriptor.key, identity, response.etag);
      return MediaAssetLoadResult(
        file: file,
        fromCache: false,
        etag: response.etag,
      );
    } on MediaAssetFailure catch (failure) {
      if (failure.kind == MediaAssetFailureKind.cancelled) rethrow;
      if (_latestIdentity[descriptor.key] == identity) {
        _coordinator.recordFailure(descriptor.key, failure);
      }
      rethrow;
    }
  }

  void _recordLoadedIfCurrent(
    MediaAssetKey key,
    String identity,
    String? etag,
  ) {
    if (_latestIdentity[key] == identity) {
      _coordinator.recordLoaded(key, etag: etag);
    }
  }

  Future<MediaAssetLoadResult> _waitForSubscriber(
    Future<MediaAssetLoadResult> shared,
    CancelToken? cancelToken,
  ) {
    if (cancelToken == null) return shared;
    if (cancelToken.isCancelled) {
      return Future.error(_cancelledFailure(cancelToken.cancelError));
    }
    return Future.any([
      shared,
      cancelToken.whenCancel.then<MediaAssetLoadResult>(
        (error) => throw _cancelledFailure(error),
      ),
    ]);
  }

  MediaAssetFailure _cancelledFailure(Object? cause) => MediaAssetFailure(
    kind: MediaAssetFailureKind.cancelled,
    message: 'Media request subscription was cancelled.',
    cause: cause,
  );

  Future<void> evict(MediaAssetDescriptor descriptor) => _cache.remove(descriptor);

  void dispose() => _httpClient.dispose();
}
