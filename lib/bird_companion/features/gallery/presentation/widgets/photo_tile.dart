import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
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
  });

  final PhotoSummary photo;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool compact;
  final bool operationFailed;

  @override
  Widget build(BuildContext context) {
    final image = photo.preview.thumbnailUri;
    final score = photo.rating?.totalScore;
    final state = photo.keepState ?? 'pending';
    final isFeatured = state == 'featured' || photo.isRecommended;
    final needsReview = state == 'pending' || photo.analysisState == AnalysisState.lowConfidence || photo.recognition?.isLowConfidence == true;

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
                    CachedNetworkImage(
                      imageUrl: image.toString(),
                      fit: BoxFit.cover,
                      cacheKey: 'bird-photo-${photo.id}-${image.pathSegments.last}',
                      memCacheWidth: cacheWidth,
                      memCacheHeight: cacheHeight,
                      maxWidthDiskCache: cacheWidth * 2,
                      maxHeightDiskCache: cacheHeight * 2,
                      placeholder: (_, _) => AnalysisPlaceholder(state: photo.analysisState),
                      errorWidget: (_, _, _) => AnalysisPlaceholder(state: photo.analysisState),
                    )
                  else
                    AnalysisPlaceholder(state: photo.analysisState),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.transparent, Color(0xAA182016)],
                      ),
                    ),
                  ),
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
                            isFeatured ? Icons.star_rounded : Icons.circle,
                            size: isFeatured ? 23 : 15,
                            color: isFeatured
                                ? AppColors.amber
                                : needsReview
                                ? AppColors.amber
                                : const Color(0xFFA9D56C),
                            shadows: const [Shadow(color: Colors.black38, blurRadius: 4)],
                          ),
                  ),
                  if (operationFailed)
                    const Positioned(
                      left: 7,
                      top: 7,
                      child: _StatusBadge(
                        label: '操作失败',
                        color: AppColors.danger,
                      ),
                    ),
                  if (!operationFailed && !compact && photo.analysisState == AnalysisState.failed)
                    const Positioned(
                      left: 8,
                      top: 8,
                      child: _StatusBadge(label: '识别未完成', color: AppColors.danger),
                    )
                  else if (!compact && photo.clarityState == ClarityState.blurred)
                    const Positioned(
                      right: 7,
                      bottom: 7,
                      child: _StatusBadge(label: '模糊', color: AppColors.inkMuted),
                    )
                  else if (!compact && needsReview)
                    const Positioned(
                      right: 7,
                      bottom: 7,
                      child: _StatusBadge(label: '需要确认', color: AppColors.amber),
                    )
                  else if (!compact && photo.isRecommended)
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
