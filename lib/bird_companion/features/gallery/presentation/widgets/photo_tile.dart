import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/analysis_placeholder.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';

class PhotoTile extends StatelessWidget {
  const PhotoTile({super.key, required this.photo, required this.selected, required this.onTap, required this.onLongPress});
  final PhotoSummary photo;
  final bool selected;
  final VoidCallback onTap, onLongPress;
  @override
  Widget build(BuildContext c) {
    final image = photo.preview.thumbnailUri;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (image != null && image.toString().isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: image.toString(),
                      fit: BoxFit.cover,
                      cacheKey: 'bird-photo-${photo.id}',
                      placeholder: (_, __) => AnalysisPlaceholder(state: photo.analysisState),
                      errorWidget: (_, __, ___) => AnalysisPlaceholder(state: photo.analysisState),
                    )
                  else
                    AnalysisPlaceholder(state: photo.analysisState),
                  if (photo.keepState != null && photo.keepState != 'pending')
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          photo.keepState == 'keep'
                              ? '保留'
                              : photo.keepState == 'discard'
                              ? '丢弃'
                              : '精选',
                        ),
                      ),
                    ),
                  if (selected) const Positioned(right: 4, top: 4, child: CircleAvatar(radius: 12, child: Icon(Icons.check, size: 16))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (photo.keepState != null) _ReviewPill(state: photo.keepState!),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          (photo.recognition?.candidates.isNotEmpty ?? false) ? photo.recognition!.candidates.first.name : photo.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        '${photo.rating?.totalScore.toStringAsFixed(0) ?? '-'} 分',
                        style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewPill extends StatelessWidget {
  const _ReviewPill({required this.state});
  final String state;
  @override
  Widget build(BuildContext context) {
    final pending = state == 'pending';
    return DecoratedBox(
      decoration: ShapeDecoration(color: pending ? AppColors.amberLight : AppColors.brandLight, shape: const StadiumBorder()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Text(
          state == 'featured'
              ? '精选'
              : state == 'discard'
              ? '弃用'
              : state == 'keep'
              ? '保留'
              : '待复核',
          style: TextStyle(color: pending ? AppColors.warning : AppColors.brand, fontWeight: FontWeight.w800, fontSize: 12),
        ),
      ),
    );
  }
}
