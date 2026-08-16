import 'dart:io';
import 'dart:typed_data';

import 'package:aves/bird_companion/core/files/media_cache_identity.dart';
import 'package:aves/bird_companion/core/media/media_asset_models.dart';
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

class MediaAssetCache implements MediaAssetCacheInvalidator {
  MediaAssetCache({BaseCacheManager? manager}) : _manager = manager ?? DefaultCacheManager();

  final BaseCacheManager _manager;
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
    final info = await _manager.getFileFromCache(keyFor(descriptor));
    if (info == null || !await info.file.exists()) return null;
    return CachedMediaAsset(
      file: info.file,
      validTill: info.validTill,
      etag: _etags[keyFor(descriptor)],
    );
  }

  Future<File> write(
    MediaAssetDescriptor descriptor,
    Uint8List bytes, {
    String? etag,
    String? contentType,
    Duration maxAge = const Duration(hours: 1),
  }) {
    final uri = descriptor.uri;
    if (uri == null) {
      throw ArgumentError.value(
        descriptor,
        'descriptor',
        'Media URI is required before writing the cache.',
      );
    }
    final key = keyFor(descriptor);
    if (etag == null || etag.isEmpty) {
      _etags.remove(key);
    } else {
      _etags[key] = etag;
    }
    return _manager.putFile(
      uri.toString(),
      bytes,
      key: key,
      eTag: etag,
      maxAge: maxAge,
      fileExtension: _extension(contentType),
    );
  }

  @override
  Future<void> remove(MediaAssetDescriptor descriptor) async {
    if (descriptor.uri == null) return;
    final key = keyFor(descriptor);
    _etags.remove(key);
    await _manager.removeFile(key);
  }

  static String _extension(String? contentType) => switch (contentType?.split(';').first.trim().toLowerCase()) {
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/webp' => 'webp',
    'image/heic' || 'image/heif' => 'heic',
    _ => 'image',
  };
}
