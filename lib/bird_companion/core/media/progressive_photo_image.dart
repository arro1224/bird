import 'package:aves/bird_companion/core/files/media_cache_identity.dart';
import 'package:aves/bird_companion/core/media/media_asset_coordinator.dart';
import 'package:aves/bird_companion/core/media/media_asset_models.dart';
import 'package:aves/bird_companion/core/media/media_asset_service.dart';
import 'package:aves/bird_companion/core/media/progressive_media_image.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Adapts a photo DTO to the shared progressive media state machine.
///
/// A preview can keep its thumbnail visible until the first decoded preview
/// frame is available. Optional dependencies preserve isolated widget tests
/// and old callers while production pages use the progressive path.
class ProgressivePhotoImage extends StatelessWidget {
  const ProgressivePhotoImage({
    super.key,
    required this.photo,
    required this.kind,
    required this.placeholderBuilder,
    this.missingBuilder,
    this.loader,
    this.coordinator,
    this.deviceNamespace,
    this.allowNetworkFallback = true,
    this.fallbackToThumbnail = false,
    this.failureBuilder,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.cacheHeight,
    this.legacyCacheVariant,
  }) : assert(
         (loader == null) == (coordinator == null),
         'loader and coordinator must either both be provided or both be null.',
       );

  final PhotoSummary photo;
  final MediaAssetKind kind;
  final MediaAssetLoader? loader;
  final MediaAssetCoordinator? coordinator;
  final String? deviceNamespace;
  final bool allowNetworkFallback;
  final bool fallbackToThumbnail;
  final MediaPlaceholderBuilder placeholderBuilder;
  final MediaPlaceholderBuilder? missingBuilder;
  final MediaFailureBuilder? failureBuilder;
  final BoxFit fit;
  final int? cacheWidth;
  final int? cacheHeight;
  final String? legacyCacheVariant;

  @override
  Widget build(BuildContext context) {
    final uri = _uriFor(kind);
    final placeholder = _placeholder(context);
    if (uri == null || uri.toString().isEmpty) {
      final hasThumbnailFallback = kind == MediaAssetKind.preview && fallbackToThumbnail && photo.preview.thumbnailUri != null;
      return hasThumbnailFallback ? placeholder : (missingBuilder ?? placeholderBuilder)(context);
    }

    final assetLoader = loader;
    final assetCoordinator = coordinator;
    if (assetLoader == null || assetCoordinator == null) {
      return CachedNetworkImage(
        imageUrl: uri.toString(),
        cacheKey: mediaCacheIdentity(
          uri: uri,
          mediaId: photo.id,
          variant: legacyCacheVariant ?? kind.wireValue,
        ),
        fit: fit,
        memCacheWidth: cacheWidth,
        memCacheHeight: cacheHeight,
        placeholder: (_, _) => _placeholder(context),
        errorWidget: (_, _, _) => const ColoredBox(
          color: Color(0xffe6ece2),
          child: Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: Color(0xff42604c),
            ),
          ),
        ),
      );
    }

    final namespace = deviceNamespace?.trim();
    final descriptor = MediaAssetDescriptor(
      key: MediaAssetKey(
        deviceId: namespace?.isNotEmpty == true
            ? namespace!
            : uri.authority.isNotEmpty
            ? uri.authority
            : 'unbound',
        fileId: photo.id,
        kind: kind,
      ),
      uri: uri,
      status: _statusFor(kind),
    );
    return ProgressiveMediaImage(
      key: ValueKey(
        'progressive-photo-${descriptor.key.deviceId}-${photo.id}-${kind.wireValue}',
      ),
      descriptor: descriptor,
      loader: assetLoader,
      coordinator: assetCoordinator,
      allowNetworkFallback: allowNetworkFallback,
      fit: fit,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      placeholderBuilder: (_) => _placeholder(context),
      failureBuilder: failureBuilder ?? _defaultFailure,
    );
  }

  Widget _placeholder(BuildContext context) {
    final base = placeholderBuilder(context);
    if (kind != MediaAssetKind.preview || !fallbackToThumbnail || photo.preview.thumbnailUri == null) {
      return KeyedSubtree(
        key: ValueKey(
          'media-asset-pending-${photo.id}-${kind.wireValue}',
        ),
        child: base,
      );
    }
    return KeyedSubtree(
      key: ValueKey('media-asset-pending-${photo.id}-preview'),
      child: ProgressivePhotoImage(
        photo: photo,
        kind: MediaAssetKind.thumbnail,
        loader: loader,
        coordinator: coordinator,
        deviceNamespace: deviceNamespace,
        allowNetworkFallback: allowNetworkFallback,
        placeholderBuilder: placeholderBuilder,
        missingBuilder: missingBuilder,
        failureBuilder: (_, _, _) => base,
        fit: fit,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        legacyCacheVariant: '${legacyCacheVariant ?? 'preview'}-fallback',
      ),
    );
  }

  Widget _defaultFailure(
    BuildContext context,
    Object error,
    VoidCallback retry,
  ) => ColoredBox(
    key: ValueKey('media-asset-failed-${photo.id}-${kind.wireValue}'),
    color: const Color(0xffe6ece2),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 140 || constraints.maxHeight < 110;
        if (compact) {
          return Center(
            child: IconButton(
              key: ValueKey(
                'media-asset-retry-${photo.id}-${kind.wireValue}',
              ),
              tooltip: kind == MediaAssetKind.preview ? '重新检查预览图' : '重新检查缩略图',
              onPressed: retry,
              icon: const Icon(
                Icons.refresh_rounded,
                color: Color(0xff42604c),
              ),
            ),
          );
        }
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.broken_image_outlined,
                color: Color(0xff42604c),
              ),
              const SizedBox(height: 4),
              Text(
                kind == MediaAssetKind.preview ? '预览图暂不可用' : '缩略图暂不可用',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              TextButton.icon(
                key: ValueKey(
                  'media-asset-retry-${photo.id}-${kind.wireValue}',
                ),
                onPressed: retry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重新检查'),
              ),
            ],
          ),
        );
      },
    ),
  );

  Uri? _uriFor(MediaAssetKind value) => switch (value) {
    MediaAssetKind.thumbnail => photo.preview.thumbnailUri,
    MediaAssetKind.preview => photo.preview.previewUri,
  };

  MediaAssetStatus _statusFor(MediaAssetKind value) => switch (value) {
    MediaAssetKind.thumbnail => photo.preview.thumbnailStatus,
    MediaAssetKind.preview => photo.preview.previewStatus,
  };
}
