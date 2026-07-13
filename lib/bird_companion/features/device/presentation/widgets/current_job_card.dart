import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/widgets/progress_summary.dart';
import 'package:aves/bird_companion/core/widgets/status_badge.dart';
import 'package:flutter/material.dart';

class CurrentJobCard extends StatelessWidget {
  const CurrentJobCard({super.key, required this.job, required this.isControlling, required this.onControl, required this.onOpenTaskCenter});

  final BirdJobStatus? job;
  final bool isControlling;
  final ValueChanged<String> onControl;
  final VoidCallback onOpenTaskCenter;

  @override
  Widget build(BuildContext context) {
    if (job == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text('当前没有运行中的任务。', style: Theme.of(context).textTheme.bodyMedium)),
              TextButton(onPressed: onOpenTaskCenter, child: const Text('任务中心')),
            ],
          ),
        ),
      );
    }
    final value = job!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('当前任务 · ${value.type.label}', style: Theme.of(context).textTheme.titleMedium)),
                StatusBadge(label: value.state.label, type: value.state == BirdJobState.failed ? StatusBadgeType.error : StatusBadgeType.info),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ProgressSummary(completed: value.finishedCount, total: value.totalCount),
            if (value.currentFile != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text('正在处理：${value.currentFile}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                if (value.canPause) OutlinedButton.icon(onPressed: isControlling ? null : () => onControl('pause'), icon: const Icon(Icons.pause_outlined), label: const Text('暂停')),
                if (value.canResume) FilledButton.icon(onPressed: isControlling ? null : () => onControl('resume'), icon: const Icon(Icons.play_arrow_rounded), label: const Text('继续')),
                if (value.canRetry) FilledButton.tonalIcon(onPressed: isControlling ? null : () => onControl('retry'), icon: const Icon(Icons.refresh_rounded), label: const Text('重试')),
                TextButton(onPressed: onOpenTaskCenter, child: const Text('查看详情')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
