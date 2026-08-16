import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/files/media_cache_identity.dart';
import 'package:aves/bird_companion/core/media/media_asset_coordinator.dart';
import 'package:aves/bird_companion/core/media/media_asset_models.dart';
import 'package:aves/bird_companion/core/media/media_asset_service.dart';
import 'package:aves/bird_companion/core/media/progressive_media_image.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/analysis_placeholder.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class PhotoTile extends StatelessWidget {
  const PhotoTile({
    super.key,
    required this.photo,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    this.compact = false,
    this.operationFailed = false,
    this.deviceNamespace,
    this.showRatingOverlay = true,
    this.mediaAssetLoader,
    this.mediaAssetCoordinator,
    this.allowNetworkFallback = true,
  });

  final PhotoSummary photo;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool compact;
  final bool operationFailed;
  final String? deviceNamespace;
  final bool showRatingOverlay;
  final MediaAssetLoader? mediaAssetLoader;
  final MediaAssetCoordinator? mediaAssetCoordinator;
  final bool allowNetworkFallback;

  @override
  Widget build(BuildContext context) {
    final image = photo.preview.thumbnailUri;
    final score = photo.rating?.totalScore;
    final keepState = KeepStateWireValue.fromWire(photo.keepState);
    final state = keepState.wireValue;
    final statusIcon = switch (keepState) {
      KeepState.featured => Icons.star_rounded,
      _ => Icons.circle,
    };
    final statusColor = switch (keepState) {
      KeepState.pending => AppColors.pending,
      KeepState.keep => AppColors.keep,
      KeepState.discard => AppColors.danger,
      KeepState.featured => AppColors.featured,
    };
    final needsReview = keepState == KeepState.pending || photo.analysisState == AnalysisState.lowConfidence || photo.recognition?.isLowConfidence == true;

    return LayoutBuilder(
      builder: (context, constraints) {
        final pixelRatio = MediaQuery.devicePixelRatioOf(context);
        final cacheWidth = (constraints.maxWidth * pixelRatio).ceil().clamp(64, 1024);
        final cacheHeight = (constraints.maxHeight * pixelRatio).ceil().clamp(64, 1024);
        return RepaintBoundary(
          child: Material(
            color: AppColors.mist,
            borderRadius: BorderRadius.circular(compact ? 9 : 14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (image != null && image.toString().isNotEmpty)
                    if (mediaAssetLoader != null && mediaAssetCoordinator != null)
                      ProgressiveMediaImage(
                        descriptor: MediaAssetDescriptor(
                          key: MediaAssetKey(
                            deviceId: _deviceIdFor(image),
                            fileId: photo.id,
                            kind: MediaAssetKind.thumbnail,
                          ),
                          uri: image,
                          status: photo.preview.thumbnailStatus,
                        ),
                        loader: mediaAssetLoader!,
                        coordinator: mediaAssetCoordinator!,
                        fit: BoxFit.cover,
                        cacheWidth: cacheWidth,
                        cacheHeight: cacheHeight,
                        allowNetworkFallback: allowNetworkFallback,
                        placeholderBuilder: (_) => KeyedSubtree(
                          key: ValueKey('media-asset-pending-${photo.id}'),
                          child: AnalysisPlaceholder(
                            state: photo.analysisState,
                          ),
                        ),
                        failureBuilder: (_, error, retry) => _ThumbnailFailure(
                          key: ValueKey(
                            'media-asset-failed-${photo.id}',
                          ),
                          error: error,
                          compact: compact,
                          onRetry: retry,
                          photoId: photo.id,
                        ),
                      )
                    else
                      CachedNetworkImage(
                        imageUrl: image.toString(),
                        fit: BoxFit.cover,
                        cacheKey: mediaCacheIdentity(
                          uri: image,
                          mediaId: photo.id,
                          variant: 'thumbnail',
                          deviceNamespace: deviceNamespace,
                        ),
                        memCacheWidth: cacheWidth,
                        memCacheHeight: cacheHeight,
                        maxWidthDiskCache: cacheWidth * 2,
                        maxHeightDiskCache: cacheHeight * 2,
                        placeholder: (_, _) => AnalysisPlaceholder(
                          state: photo.analysisState,
                        ),
                        errorWidget: (_, _, _) => AnalysisPlaceholder(
                          state: photo.analysisState,
                        ),
                      )
                  else
                    AnalysisPlaceholder(state: photo.analysisState),
                  const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            Color(0xAA182016),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (showRatingOverlay)
                    Positioned(
                      left: 8,
                      bottom: 7,
                      child: Text(
                        score?.toStringAsFixed(1) ?? '—',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 16 : 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  if (selected || showRatingOverlay)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: selected
                          ? const CircleAvatar(
                              radius: 12,
                              backgroundColor: AppColors.brand,
                              child: Icon(Icons.check_rounded, size: 16, color: Colors.white),
                            )
                          : Icon(
                              key: ValueKey('photo-status-$state'),
                              statusIcon,
                              size: keepState == KeepState.featured ? 23 : 15,
                              color: statusColor,
                              shadows: const [Shadow(color: Colors.black38, blurRadius: 4)],
                            ),
                    ),
                  if (showRatingOverlay && operationFailed)
                    const Positioned(
                      left: 7,
                      top: 7,
                      child: _StatusBadge(
                        label: '操作失败',
                        color: AppColors.danger,
                      ),
                    ),
                  if (showRatingOverlay && !operationFailed && !compact && photo.analysisState == AnalysisState.failed)
                    const Positioned(
                      left: 8,
                      top: 8,
                      child: _StatusBadge(label: '识别未完成', color: AppColors.danger),
                    )
                  else if (showRatingOverlay && !compact && photo.clarityState == ClarityState.blurred)
                    const Positioned(
                      right: 7,
                      bottom: 7,
                      child: _StatusBadge(label: '模糊', color: AppColors.inkMuted),
                    )
                  else if (showRatingOverlay && !compact && needsReview)
                    const Positioned(
                      right: 7,
                      bottom: 7,
                      child: _StatusBadge(label: '需要确认', color: AppColors.amber),
                    )
                  else if (showRatingOverlay && !compact && photo.isRecommended)
                    const Positioned(
                      right: 7,
                      bottom: 7,
                      child: _StatusBadge(label: '系统推荐', color: AppColors.brandDark),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _deviceIdFor(Uri image) {
    final explicit = deviceNamespace?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return image.authority.isEmpty ? 'unbound' : image.authority;
  }
}

class _ThumbnailFailure extends StatelessWidget {
  const _ThumbnailFailure({
    super.key,
    required this.error,
    required this.compact,
    required this.onRetry,
    required this.photoId,
  });

  final Object error;
  final bool compact;
  final VoidCallback onRetry;
  final String photoId;

  @override
  Widget build(BuildContext context) {
    final failure = error is MediaAssetFailure ? error as MediaAssetFailure : null;
    final generatedFailed = failure?.kind == MediaAssetFailureKind.assetFailed;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(compact ? 4 : 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.broken_image_outlined,
                size: compact ? 20 : 26,
                color: AppColors.inkMuted,
              ),
              SizedBox(height: compact ? 1 : 4),
              Text(
                generatedFailed ? '缩略图生成失败' : '缩略图暂不可用',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.inkMuted,
                  fontSize: compact ? 9 : 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(
                height: compact ? 24 : 30,
                child: TextButton(
                  key: ValueKey('media-asset-retry-$photoId'),
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    '重试',
                    style: TextStyle(fontSize: compact ? 10 : 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: color.withValues(alpha: .9), borderRadius: BorderRadius.circular(6)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    ),
  );
}
