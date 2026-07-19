import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class BatchListTile extends StatelessWidget {
  const BatchListTile({super.key, required this.batch, required this.onOpen, required this.onResume, this.actionLabel = '查看图库'});
  final BatchSummary batch;
  final VoidCallback onOpen;
  final VoidCallback onResume;
  final String actionLabel;

  (String, Color, Color) get _status {
    final state = batch.copyState.toLowerCase();
    if (state == 'pending' || state == 'incomplete' || state == 'idle') {
      return ('待审阅', AppColors.amberLight, AppColors.pending);
    }
    if (state == 'completed' || state == 'copied' || state == 'success') {
      return ('复制完成', AppColors.brandLight, AppColors.brand);
    }
    return ('已完成', AppColors.brandLight, AppColors.brand);
  }

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.all(20),
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
                      const SizedBox(height: 8),
                      DecoratedBox(
                        decoration: ShapeDecoration(
                          color: _status.$2,
                          shape: const StadiumBorder(),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          child: Text(
                            _status.$1,
                            style: TextStyle(
                              color: _status.$3,
                              fontWeight: FontWeight.w700,
                            ),
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

class _HistoryCover extends StatelessWidget {
  const _HistoryCover({required this.batch});

  final BatchSummary batch;

  @override
  Widget build(BuildContext context) {
    final url = batch.cover?.thumbnailUri?.toString();
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 112,
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
