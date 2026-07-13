import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/widgets/progress_summary.dart';
import 'package:flutter/material.dart';

class JobCard extends StatelessWidget {
  const JobCard({super.key, required this.job, required this.onTap, this.onControl, this.onDelete, this.busy = false});
  final BirdJobStatus job;
  final VoidCallback onTap;
  final ValueChanged<String>? onControl;
  final VoidCallback? onDelete;
  final bool busy;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('${job.type.label}任务', style: Theme.of(context).textTheme.titleLarge)),
                _StatePill(label: job.state.label),
              ],
            ),
            const SizedBox(height: 8),
            Text(job.currentFile?.isNotEmpty == true ? job.currentFile! : '正在等待盒子处理', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            ProgressSummary(completed: job.finishedCount, total: job.totalCount),
            if (busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
            if (!busy && (job.canPause || job.canResume || job.canRestore || job.canDelete))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (job.canPause) TextButton(onPressed: () => onControl?.call('pause'), child: const Text('暂停')),
                    if (job.canResume) TextButton(onPressed: () => onControl?.call('resume'), child: const Text('继续')),
                    if (job.canRestore) TextButton(onPressed: () => onControl?.call('restore'), child: const Text('恢复任务')),
                    if (job.canPause || job.canResume) TextButton(onPressed: () => onControl?.call('cancel'), child: const Text('取消')),
                    if (job.canDelete) TextButton.icon(onPressed: onDelete, icon: const Icon(Icons.delete_outline, size: 18), label: const Text('删除')),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const ShapeDecoration(color: AppColors.brandLight, shape: StadiumBorder()),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Text(
        label,
        style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w800),
      ),
    ),
  );
}
