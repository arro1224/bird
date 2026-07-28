import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CurrentBatchCard extends StatelessWidget {
  const CurrentBatchCard({
    super.key,
    required this.batch,
    required this.onOpen,
    this.onBrowseScenes,
    this.actionLabel = '进入本次拍摄',
    this.contextLabel = '本次拍摄',
    this.loading = false,
  });
  final BatchSummary batch;
  final VoidCallback onOpen;
  final VoidCallback? onBrowseScenes;
  final String actionLabel;
  final String contextLabel;
  final bool loading;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BatchCover(batch: batch),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Count(label: '张照片', value: batch.totalFiles),
              ),
              const SizedBox(height: 48, child: VerticalDivider()),
              Expanded(
                child: _Count(label: '待确认', value: batch.pendingReviewCount, emphasis: AppColors.pending),
              ),
              const SizedBox(height: 48, child: VerticalDivider()),
              Expanded(
                child: _Count(label: '已保留', value: batch.keepCount),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: loading ? null : onOpen,
              icon: loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.center_focus_strong_rounded),
              label: Text(loading ? '正在打开照片…' : actionLabel),
            ),
          ),
        ],
      ),
    ),
  );
}

class _BatchCover extends StatelessWidget {
  const _BatchCover({required this.batch});

  final BatchSummary batch;

  @override
  Widget build(BuildContext context) {
    final url = (batch.cover?.previewUri ?? batch.cover?.thumbnailUri)?.toString();
    return AspectRatio(
      aspectRatio: 1.72,
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.brandLight,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url?.isNotEmpty == true) CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover, errorWidget: (_, _, _) => const _CoverPlaceholder()) else const _CoverPlaceholder(),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xB014341E)]),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              top: 16,
              child: Text(
                _batchTitle(batch),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  shadows: [Shadow(color: Colors.black38, blurRadius: 8)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _batchTitle(BatchSummary batch) {
    final local = batch.createdAt.toLocal();
    final date = '${local.month}月${local.day}日';
    final name = batch.name.replaceFirst(RegExp(r'^\d{4}[.\-/年]\d{1,2}[.\-/月]\d{1,2}日?\s*'), '').trim();
    if (name.contains(date)) return name;
    return '${name.isEmpty ? batch.name : name} · $date';
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.brandLight, AppColors.mist],
      ),
    ),
    child: Icon(Icons.photo_camera_back_outlined, color: AppColors.brand, size: 44),
  );
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value, this.emphasis = AppColors.brand});
  final String label;
  final int value;
  final Color emphasis;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text(
        _formatCount(value),
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        textAlign: TextAlign.center,
        style: TextStyle(color: emphasis, fontSize: 24, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      Text(label, maxLines: 1, style: const TextStyle(color: AppColors.inkMuted, fontSize: 12)),
    ],
  );
}

String _formatCount(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
    buffer.write(digits[index]);
  }
  return buffer.toString();
}
