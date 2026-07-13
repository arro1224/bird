import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class ComparisonPhotoPane extends StatelessWidget {
  const ComparisonPhotoPane({super.key, required this.detail, required this.rank, required this.saving, required this.onMark, this.transformationController});
  final ReviewDetail detail;
  final int rank;
  final bool saving;
  final ValueChanged<KeepState> onMark;
  final TransformationController? transformationController;
  @override
  Widget build(BuildContext context) {
    final photo = detail.photo.summary;
    final url = photo.preview.previewUri?.toString();
    final species = photo.recognition?.candidates.isNotEmpty == true ? photo.recognition!.candidates.first.name : '待识别';
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: InteractiveViewer(
              transformationController: transformationController,
              minScale: 1,
              maxScale: 5,
              child: url?.isNotEmpty == true
                  ? CachedNetworkImage(
                      imageUrl: url!,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined)),
                    )
                  : const Center(child: Icon(Icons.photo_outlined, size: 48)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: const ShapeDecoration(color: Color(0xFFD9F0D8), shape: StadiumBorder()),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Text(
                      '${String.fromCharCode(65 + rank)} · ${rank == 0
                          ? '精选'
                          : rank == 1
                          ? '保留'
                          : rank == 2
                          ? '待确认'
                          : '弃用'}',
                      style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF175642)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text('${photo.rating?.totalScore.toStringAsFixed(0) ?? '-'} 分 · $species', style: const TextStyle(fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          if (saving) const LinearProgressIndicator(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(tooltip: '保留', onPressed: saving ? null : () => onMark(KeepState.keep), icon: const Icon(Icons.check_circle_outline)),
              IconButton(tooltip: '弃用', onPressed: saving ? null : () => onMark(KeepState.discard), icon: const Icon(Icons.cancel_outlined)),
              IconButton(tooltip: '精选', onPressed: saving ? null : () => onMark(KeepState.featured), icon: const Icon(Icons.star_outline)),
            ],
          ),
        ],
      ),
    );
  }
}
