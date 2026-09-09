import 'dart:io';
import 'dart:typed_data';

import 'package:aves/bird_companion/core/files/media_cache_identity.dart';
import 'package:aves/bird_companion/core/media/media_asset_models.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class CachedMediaAsset {
  const CachedMediaAsset({
    required this.file,
    required this.validTill,
    this.etag,
  });

  final File file;
  final DateTime validTill;
  final String? etag;

  bool get isStale => !validTill.isAfter(DateTime.now());
}

abstract interface class MediaAssetCacheInvalidator {
  Future<void> remove(MediaAssetDescriptor descriptor);
}

/// Persists validators separately because flutter_cache_manager 3.4 does not
/// expose its stored ETag through FileInfo.
abstract interface class MediaAssetEtagStore {
  String? read(String cacheKey);

  Future<void> write(String cacheKey, String etag);

  Future<void> remove(String cacheKey);
}

class LocalCacheMediaAssetEtagStore implements MediaAssetEtagStore {
  const LocalCacheMediaAssetEtagStore(this._cache);

  static const _prefix = 'image:media_etag:';

  final LocalCache _cache;

  String _key(String cacheKey) => '$_prefix$cacheKey';

  @override
  String? read(String cacheKey) => _cache.read<String>(_key(cacheKey));

  @override
  Future<void> write(String cacheKey, String etag) => _cache.write(_key(cacheKey), etag);

  @override
  Future<void> remove(String cacheKey) => _cache.remove(_key(cacheKey));
}

class MediaAssetCache implements MediaAssetCacheInvalidator {
  MediaAssetCache({
    BaseCacheManager? manager,
    MediaAssetEtagStore? etagStore,
  }) : this._(manager ?? DefaultCacheManager(), etagStore);

  MediaAssetCache._(this._manager, this._etagStore);

  final BaseCacheManager _manager;
  final MediaAssetEtagStore? _etagStore;
  final Map<String, String> _etags = {};

  String keyFor(MediaAssetDescriptor descriptor) {
    final uri = descriptor.uri;
    if (uri == null) {
      throw ArgumentError.value(
        descriptor,
        'descriptor',
        'Media URI is required for a cache identity.',
      );
    }
    return mediaCacheIdentity(
      uri: uri,
      mediaId: descriptor.key.fileId,
      variant: descriptor.key.kind.wireValue,
      deviceNamespace: descriptor.key.deviceId,
    );
  }

  Future<CachedMediaAsset?> read(MediaAssetDescriptor descriptor) async {
    if (descriptor.uri == null) return null;
    final key = keyFor(descriptor);
    final info = await _manager.getFileFromCache(key);
    if (info == null || !await info.file.exists()) return null;
    var etag = _etags[key];
    if (etag == null) {
      try {
        etag = _etagStore?.read(key);
      } catch (_) {
        // Cached bytes remain usable if optional validator metadata is corrupt.
      }
    }
    if (etag != null && etag.isNotEmpty) {
      _etags[key] = etag;
    }
    return CachedMediaAsset(
      file: info.file,
      validTill: info.validTill,
      etag: etag,
    );
  }

  Future<File> write(
    MediaAssetDescriptor descriptor,
    Uint8List bytes, {
    String? etag,
    String? contentType,
    Duration maxAge = const Duration(hours: 1),
  }) async {
    final uri = descriptor.uri;
    if (uri == null) {
      throw ArgumentError.value(
        descriptor,
        'descriptor',
        'Media URI is required before writing the cache.',
      );
    }
    final key = keyFor(descriptor);
    final file = await _manager.putFile(
      uri.toString(),
      bytes,
      key: key,
      eTag: etag,
      maxAge: maxAge,
      fileExtension: _extension(contentType),
    );
    await _rememberEtag(key, etag);
    return file;
  }

  @override
  Future<void> remove(MediaAssetDescriptor descriptor) async {
    if (descriptor.uri == null) return;
    final key = keyFor(descriptor);
    _etags.remove(key);
    try {
      await _manager.removeFile(key);
    } finally {
      await _removePersistedEtag(key);
    }
  }

  Future<void> _rememberEtag(String key, String? etag) async {
    if (etag == null || etag.isEmpty) {
      _etags.remove(key);
      await _removePersistedEtag(key);
      return;
    }
    _etags[key] = etag;
    try {
      await _etagStore?.write(key, etag);
    } catch (_) {
      // A metadata write failure must not discard successfully cached bytes.
    }
  }

  Future<void> _removePersistedEtag(String key) async {
    try {
      await _etagStore?.remove(key);
    } catch (_) {
      // Cache eviction remains best effort when local metadata is unavailable.
    }
  }

  static String _extension(String? contentType) => switch (contentType?.split(';').first.trim().toLowerCase()) {
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/webp' => 'webp',
    'image/heic' || 'image/heif' => 'heic',
    _ => 'image',
  };
}
