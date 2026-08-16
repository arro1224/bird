import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/core/media/media_asset_coordinator.dart';
import 'package:aves/bird_companion/core/media/media_asset_models.dart';
import 'package:aves/bird_companion/core/media/media_asset_service.dart';
import 'package:aves/bird_companion/core/media/progressive_photo_image.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:flutter/material.dart';

class ComparisonPhotoPane extends StatelessWidget {
  const ComparisonPhotoPane({
    super.key,
    required this.detail,
    required this.rank,
    this.selected = false,
    required this.saving,
    this.onTap,
    this.onMark,
    this.transformationController,
    this.mediaAssetLoader,
    this.mediaAssetCoordinator,
    this.deviceNamespace,
    this.allowNetworkFallback = true,
  });

  final ReviewDetail detail;
  final int rank;
  final bool selected;
  final bool saving;
  final VoidCallback? onTap;
  final ValueChanged<KeepState>? onMark;
  final TransformationController? transformationController;
  final MediaAssetLoader? mediaAssetLoader;
  final MediaAssetCoordinator? mediaAssetCoordinator;
  final String? deviceNamespace;
  final bool allowNetworkFallback;

  @override
  Widget build(BuildContext context) {
    final photo = detail.photo.summary;
    final reasons = photo.rating?.reasonTags ?? const <String>[];
    final currentScore = detail.decision?.userScore ?? photo.rating?.totalScore;
    return BirdPressable(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: selected ? AppColors.brandMid : AppColors.outline, width: selected ? 2.5 : 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  InteractiveViewer(
                    transformationController: transformationController,
                    minScale: 1,
                    maxScale: 5,
                    child: ProgressivePhotoImage(
                      photo: photo,
                      kind: MediaAssetKind.preview,
                      loader: mediaAssetLoader,
                      coordinator: mediaAssetCoordinator,
                      deviceNamespace: deviceNamespace,
                      allowNetworkFallback: allowNetworkFallback,
                      fallbackToThumbnail: true,
                      fit: BoxFit.cover,
                      legacyCacheVariant: 'comparison-preview',
                      missingBuilder: (_) => const ColoredBox(
                        color: AppColors.mist,
                        child: Center(
                          child: Icon(Icons.photo_outlined, size: 44),
                        ),
                      ),
                      placeholderBuilder: (_) => const ColoredBox(
                        color: AppColors.brandLight,
                        child: Center(
                          child: Icon(Icons.photo_outlined, size: 44),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: rank == 0 ? AppColors.brandDark.withValues(alpha: .9) : AppColors.paperStrong.withValues(alpha: .76),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        child: Text(
                          '推荐 ${rank + 1}',
                          style: TextStyle(color: rank == 0 ? Colors.white : AppColors.brandDark, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                  if (selected)
                    const Positioned(
                      right: 10,
                      top: 10,
                      child: CircleAvatar(
                        radius: 13,
                        backgroundColor: AppColors.brand,
                        child: Icon(Icons.check_rounded, color: Colors.white, size: 17),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: AppColors.paperStrong,
              border: Border.all(color: AppColors.outline),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final score = Text(
                      currentScore?.toStringAsFixed(1) ?? '—',
                      style: TextStyle(fontSize: constraints.maxWidth < 110 ? 26 : 32, fontWeight: FontWeight.w900, color: selected ? AppColors.brand : AppColors.inkMuted),
                    );
                    if (constraints.maxWidth < 110) return score;
                    return Row(
                      children: [
                        score,
                        const Spacer(),
                        Flexible(
                          child: Text(
                            _qualityLabel(photo.clarityState, reasons, compact: constraints.maxWidth < 140),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppColors.inkMuted, fontSize: constraints.maxWidth < 140 ? 12 : 14),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const Divider(height: 20),
                if (photo.rating?.eyeScore != null) _Metric(icon: Icons.remove_red_eye_outlined, label: '鸟眼', value: photo.rating!.eyeScore!),
                if (photo.rating?.compositionScore != null) _Metric(icon: Icons.crop_free_rounded, label: '画面安排', value: photo.rating!.compositionScore!),
                if (saving) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _qualityLabel(ClarityState clarity, List<String> reasons, {required bool compact}) {
  if (clarity == ClarityState.blurred || clarity == ClarityState.average) {
    return compact ? '轻微模糊' : '轻微运动模糊';
  }
  if (reasons.isEmpty) return '暂无照片质量说明';
  return reasons.first == '鸟眼清晰' ? '眼部清晰' : reasons.first;
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: AppColors.brandLight,
            child: Icon(icon, size: 17, color: AppColors.brand),
          ),
          const SizedBox(width: 6),
          if (constraints.maxWidth >= 110)
            Expanded(
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            )
          else
            const Spacer(),
          Text(
            value.toStringAsFixed(1),
            style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ),
  );
}
