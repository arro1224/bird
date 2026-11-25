import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:flutter/material.dart';

class JobCard extends StatelessWidget {
  const JobCard({super.key, required this.job, required this.onTap, this.onControl, this.onDelete, this.busy = false, this.stale = false, this.pendingCancellation = false});

  final BirdJobStatus job;
  final VoidCallback onTap;
  final ValueChanged<String>? onControl;
  final VoidCallback? onDelete;
  final bool busy;
  final bool stale;
  final bool pendingCancellation;

  @override
  Widget build(BuildContext context) {
    final progress = job.totalCount <= 0 ? job.progress.clamp(0.0, 1.0) : (job.finishedCount / job.totalCount).clamp(0.0, 1.0);
    final waitingImport = job.type == BirdJobType.analysis && job.state == BirdJobState.queued && job.workflowStage == 'waiting_import';
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: job.state == BirdJobState.failed ? AppColors.danger.withValues(alpha: .45) : AppColors.outline),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _accent(job).withValues(alpha: .14),
                    child: Icon(_icon(job.type), color: _accent(job)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_title(job), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  _StatePill(job: job, pendingCancellation: pendingCancellation, waitingImport: waitingImport),
                  const Icon(Icons.chevron_right, color: AppColors.inkMuted),
                ],
              ),
              const SizedBox(height: 16),
              if (waitingImport)
                const Text('导入完成后由盒子自动开始识别')
              else ...[
                Row(
                  children: [
                    _Metric(value: '${job.finishedCount} / ${job.totalCount}', label: '已处理 / 总数'),
                    _Metric(value: '${(progress * 100).round()}%', label: '进度'),
                    _Metric(value: _speed(job.speedBytesPerSecond), label: '当前速度'),
                    _Metric(value: '${job.failedCount}', label: '未完成'),
                  ],
                ),
                const SizedBox(height: 14),
                LinearProgressIndicator(value: progress, minHeight: 8, borderRadius: BorderRadius.circular(8), backgroundColor: AppColors.mist),
              ],
              if (pendingCancellation) const Text('取消待确认，请核对原任务状态', style: TextStyle(color: AppColors.amber)),
              Text('${stale ? '上次进度快照 · ' : ''}${job.updatedAt == null ? '盒子未提供更新时间' : '更新于 ${job.updatedAt!.toLocal().toIso8601String().split('.').first.replaceFirst('T', ' ')}'}', style: const TextStyle(color: AppColors.inkMuted)),
              if (job.currentFile?.isNotEmpty == true) ...[
                const SizedBox(height: 11),
                Text(
                  '正在处理：${job.currentFile}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.inkMuted),
                ),
              ],
              if (job.state == BirdJobState.failed) ...[
                const SizedBox(height: 12),
                Text(job.errorMessage ?? '照片处理没有完成，请重试', style: const TextStyle(color: AppColors.danger)),
              ],
              if (busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
              if (!busy && !stale && (pendingCancellation || job.canPause || job.canResume || job.canRestore || job.canRetry || job.canCancel || job.canDelete)) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (job.canPause) OutlinedButton(onPressed: () => onControl?.call('pause'), child: const Text('暂停')),
                    if (job.canResume) FilledButton(onPressed: () => onControl?.call('resume'), child: const Text('继续')),
                    if (job.canRetry) FilledButton(onPressed: () => onControl?.call('retry'), child: const Text('重试')),
                    if (job.canRestore) OutlinedButton(onPressed: () => onControl?.call('resume'), child: const Text('继续处理')),
                    if (job.canCancel || pendingCancellation) TextButton(onPressed: () => onControl?.call('cancel'), child: Text(pendingCancellation ? '核对取消结果' : '取消')),
                    if (job.canDelete) TextButton.icon(onPressed: onDelete, icon: const Icon(Icons.delete_outline, size: 18), label: const Text('删除')),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, maxLines: 1, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
        ),
      ],
    ),
  );
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.job, required this.pendingCancellation, required this.waitingImport});

  final BirdJobStatus job;
  final bool pendingCancellation, waitingImport;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: _accent(job).withValues(alpha: .14), borderRadius: BorderRadius.circular(12)),
    child: Text(
      pendingCancellation
          ? '取消待确认'
          : waitingImport
          ? '等待导入完成'
          : job.isFinishing
          ? '正在收尾'
          : job.state.label,
      style: TextStyle(color: _accent(job), fontWeight: FontWeight.w800, fontSize: 12),
    ),
  );
}

String _title(BirdJobStatus job) => switch (job.type) {
  BirdJobType.copy => '复制原始照片',
  BirdJobType.analysis => '识别照片',
  BirdJobType.import => '导入照片',
  BirdJobType.sync => '准备浏览图片',
  BirdJobType.unknown => '其他照片处理',
};

IconData _icon(BirdJobType type) => switch (type) {
  BirdJobType.copy => Icons.storage_outlined,
  BirdJobType.analysis => Icons.psychology_outlined,
  BirdJobType.import => Icons.download_outlined,
  BirdJobType.sync => Icons.sync_rounded,
  BirdJobType.unknown => Icons.assignment_outlined,
};

Color _accent(BirdJobStatus job) => switch (job.state) {
  BirdJobState.failed => AppColors.danger,
  BirdJobState.completed => AppColors.success,
  BirdJobState.paused => AppColors.amber,
  _ => AppColors.brand,
};

String _speed(double? bytes) => bytes == null || bytes <= 0 ? '—' : '${(bytes / 1024 / 1024).toStringAsFixed(0)} MB/s';
