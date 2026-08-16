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

  @override
  Future<MediaAssetLoadResult> load(
    MediaAssetDescriptor descriptor, {
    bool forceRefresh = false,
    CancelToken? cancelToken,
  }) async {
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
    final cached = await _cache.read(tracked.descriptor);
    if (cached != null && !cached.isStale && !forceRefresh) {
      _coordinator.recordLoaded(descriptor.key, etag: cached.etag);
      return MediaAssetLoadResult(
        file: cached.file,
        fromCache: true,
        etag: cached.etag,
      );
    }
    try {
      var response = await _httpClient.fetch(
        uri,
        ifNoneMatch: cached?.etag,
        cancelToken: cancelToken,
      );
      if (response.notModified && cached == null) {
        response = await _httpClient.fetch(uri, cancelToken: cancelToken);
      }
      if (response.notModified) {
        final refreshed = await _cache.write(
          tracked.descriptor,
          await cached!.file.readAsBytes(),
          etag: response.etag ?? cached.etag,
          maxAge: response.maxAge,
        );
        _coordinator.recordLoaded(
          descriptor.key,
          etag: response.etag ?? cached.etag,
        );
        return MediaAssetLoadResult(
          file: refreshed,
          fromCache: true,
          etag: response.etag ?? cached.etag,
        );
      }
      final file = await _cache.write(
        tracked.descriptor,
        response.bytes!,
        etag: response.etag,
        contentType: response.contentType,
        maxAge: response.maxAge,
      );
      _coordinator.recordLoaded(descriptor.key, etag: response.etag);
      return MediaAssetLoadResult(
        file: file,
        fromCache: false,
        etag: response.etag,
      );
    } on MediaAssetFailure catch (failure) {
      if (failure.kind == MediaAssetFailureKind.cancelled) rethrow;
      _coordinator.recordFailure(descriptor.key, failure);
      rethrow;
    }
  }

  Future<void> evict(MediaAssetDescriptor descriptor) => _cache.remove(descriptor);

  void dispose() => _httpClient.dispose();
}
