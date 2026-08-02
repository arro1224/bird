import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/widgets/page_back_button.dart';
import 'package:aves/bird_companion/core/widgets/progress_summary.dart';
import 'package:aves/bird_companion/features/jobs/presentation/job_detail_cubit.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class JobDetailPage extends StatelessWidget {
  const JobDetailPage({super.key, required this.jobId, this.sourceBatchId});
  final String jobId;
  final String? sourceBatchId;

  @override
  Widget build(BuildContext context) {
    final deps = BirdCompanionScope.of(context);
    return BlocProvider(
      create: (_) => JobDetailCubit(deps.jobRepository, deps.eventClient, jobId, deps.refreshCoordinator, deps.dataChangeBus)..load(),
      child: _JobDetailView(sourceBatchId: sourceBatchId),
    );
  }
}

class _JobDetailView extends StatelessWidget {
  const _JobDetailView({this.sourceBatchId});
  final String? sourceBatchId;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.paper,
    appBar: AppBar(
      leading: const BirdPageBackButton(),
      title: const Text('处理详情'),
      actions: [IconButton(onPressed: () => context.read<JobDetailCubit>().load(), icon: const Icon(Icons.refresh), tooltip: '刷新处理进度')],
    ),
    body: BlocConsumer<JobDetailCubit, JobDetailState>(
      listenWhen: (before, after) => before.message != after.message && after.message != null,
      listener: (context, state) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message!))),
      builder: (context, state) {
        if (state.loading && state.job == null) return const Center(child: CircularProgressIndicator());
        final job = state.job;
        if (job == null) {
          final message = state.error == null ? null : UserMessageMapper.fromError(state.error!);
          return Center(
            child: Text(
              message == null ? '请返回处理进度页重试' : '${message.title}：${message.message}',
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.brandLight,
                          child: Icon(_jobIcon(job.type), color: AppColors.brand),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(job.type.label, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        ),
                        Text(
                          job.state.label,
                          style: TextStyle(color: _jobColor(job), fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    ProgressSummary(completed: job.finishedCount, total: job.totalCount, label: job.type.label),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    _InfoRow(label: '正在处理', value: job.currentFile?.isNotEmpty == true ? job.currentFile! : '等待盒子更新'),
                    _InfoRow(label: '记录编号', value: job.id),
                    if (job.speedBytesPerSecond != null) _InfoRow(label: '处理速度', value: '${(job.speedBytesPerSecond! / 1024 / 1024).toStringAsFixed(1)} MB/s'),
                  ],
                ),
              ),
            ),
            if (state.report != null) ...[
              const SizedBox(height: 16),
              _JobReportCard(report: state.report!),
            ],
            if (state.failures.isNotEmpty)
              Card(
                color: AppColors.amberLight.withValues(alpha: .45),
                child: ExpansionTile(
                  leading: const Icon(Icons.error_outline, color: AppColors.danger),
                  title: Text(
                    '失败项 ${state.failures.length}',
                    style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text('展开查看失败原因，可使用下方重试操作'),
                  children: state.failures.map((item) => ListTile(title: Text(item.fileId), subtitle: Text(item.reason))).toList(),
                ),
              ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Builder(
                  builder: (_) {
                    final message = UserMessageMapper.fromError(state.error!);
                    return Text(
                      '${message.title}：${message.message}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 24),
            if (state.controlling) const Center(child: CircularProgressIndicator()),
            if (!state.controlling) _JobActions(job: job, sourceBatchId: sourceBatchId),
          ],
        );
      },
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        SizedBox(
          width: 88,
          child: Text(label, style: const TextStyle(color: AppColors.inkMuted)),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _JobReportCard extends StatelessWidget {
  const _JobReportCard({required this.report});

  final JobReport report;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('job-authoritative-report'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _resultLabel(report.result),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: report.failedCount > 0 ? AppColors.danger : AppColors.success,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              Text('成功 ${report.successCount}'),
              Text('失败 ${report.failedCount}'),
              Text('跳过 ${report.skippedCount}'),
              Text('总计 ${report.totalCount}'),
            ],
          ),
        ],
      ),
    ),
  );

  String _resultLabel(JobReportResult result) => switch (result) {
    JobReportResult.success => '任务报告：全部完成',
    JobReportResult.partialSuccess => '任务报告：部分完成',
    JobReportResult.failed => '任务报告：处理失败',
    JobReportResult.cancelled => '任务报告：已取消',
    JobReportResult.unknown => '任务报告',
  };
}

class _JobActions extends StatelessWidget {
  const _JobActions({required this.job, this.sourceBatchId});
  final BirdJobStatus job;
  final String? sourceBatchId;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      if (job.canPause) OutlinedButton(onPressed: () => context.read<JobDetailCubit>().control('pause'), child: const Text('暂停')),
      if (job.canResume) FilledButton(onPressed: () => context.read<JobDetailCubit>().control('resume'), child: const Text('继续')),
      if (job.canRetry) FilledButton(onPressed: () => context.read<JobDetailCubit>().control('retry'), child: const Text('重试')),
      if (job.availableActions.contains('skip_failed'))
        OutlinedButton(
          onPressed: () => context.read<JobDetailCubit>().control('skip_failed'),
          child: const Text('跳过失败项'),
        ),
      if (job.state == BirdJobState.running || job.state == BirdJobState.paused) TextButton(onPressed: () => context.read<JobDetailCubit>().control('cancel'), child: const Text('停止处理')),
      if (job.canDelete)
        TextButton.icon(
          icon: const Icon(Icons.delete_outline),
          label: const Text('删除记录'),
          onPressed: () async {
            final approved = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('删除这条处理记录？'),
                content: const Text('只移除进度记录，不会删除已经保存的照片。'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
                  FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('删除')),
                ],
              ),
            );
            if (approved == true && context.mounted && await context.read<JobDetailCubit>().delete() && context.mounted) Navigator.of(context).pop();
          },
        ),
      if (sourceBatchId != null && job.canDelete)
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pushReplacementNamed(BirdRoutes.gallery, arguments: GalleryArgs(sourceBatchId!)),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('返回本次拍摄'),
        ),
    ],
  );
}

IconData _jobIcon(BirdJobType type) => switch (type) {
  BirdJobType.copy => Icons.storage_outlined,
  BirdJobType.analysis => Icons.psychology_outlined,
  BirdJobType.import => Icons.download_outlined,
  BirdJobType.sync => Icons.sync_rounded,
  BirdJobType.unknown => Icons.assignment_outlined,
};

Color _jobColor(BirdJobStatus job) => switch (job.state) {
  BirdJobState.failed => AppColors.danger,
  BirdJobState.completed => AppColors.success,
  BirdJobState.paused => AppColors.amber,
  _ => AppColors.brand,
};
