import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_history_filter.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class BatchListTile extends StatelessWidget {
  const BatchListTile({super.key, required this.batch, required this.onOpen, required this.onResume, this.actionLabel = '查看图库'});
  final BatchSummary batch;
  final VoidCallback onOpen;
  final VoidCallback onResume;
  final String actionLabel;

  (String, Color, Color, IconData) get _status => switch (classifyBatchHistory(batch)) {
    BatchHistoryCategory.inProgress => ('进行中', AppColors.brandLight, AppColors.brandMid, Icons.sync_rounded),
    BatchHistoryCategory.review => ('待挑选', AppColors.amberLight, AppColors.pending, Icons.fact_check_outlined),
    BatchHistoryCategory.failed => ('异常', AppColors.dangerSoft, AppColors.danger, Icons.error_outline_rounded),
    BatchHistoryCategory.completed => ('已完成', AppColors.brandLight, AppColors.success, Icons.check_circle_outline_rounded),
    BatchHistoryCategory.unknown => ('状态待确认', AppColors.mist, AppColors.inkMuted, Icons.help_outline_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HistoryCover(batch: batch),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          batch.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.brandDark, fontSize: 21, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text('${batch.totalFiles} 张', style: const TextStyle(color: AppColors.inkMuted)),
                        const SizedBox(height: 7),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: status.$2,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(status.$4, size: 16, color: status.$3),
                                const SizedBox(width: 5),
                                Text(
                                  status.$1,
                                  style: TextStyle(color: status.$3, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryCover extends StatelessWidget {
  const _HistoryCover({required this.batch});

  final BatchSummary batch;

  @override
  Widget build(BuildContext context) {
    final url = batch.cover?.thumbnailUri?.toString();
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 132,
        height: 92,
        child: url?.isNotEmpty == true ? CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover, errorWidget: (_, _, _) => const _HistoryPlaceholder()) : const _HistoryPlaceholder(),
      ),
    );
  }
}

class _HistoryPlaceholder extends StatelessWidget {
  const _HistoryPlaceholder();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppColors.brandLight,
    child: Icon(Icons.landscape_outlined, color: AppColors.brand, size: 36),
  );
}
