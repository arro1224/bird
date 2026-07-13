import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/widgets/page_back_button.dart';
import 'package:aves/bird_companion/core/widgets/progress_summary.dart';
import 'package:aves/bird_companion/features/jobs/presentation/job_detail_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class JobDetailPage extends StatelessWidget {
  const JobDetailPage({super.key, this.jobId, this.sourceBatchId});
  final String? jobId;
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
    appBar: AppBar(
      leading: const BirdPageBackButton(),
      title: const Text('任务详情'),
      actions: [IconButton(onPressed: () => context.read<JobDetailCubit>().load(), icon: const Icon(Icons.refresh), tooltip: '刷新任务状态')],
    ),
    body: BlocConsumer<JobDetailCubit, JobDetailState>(
      listenWhen: (before, after) => before.message != after.message && after.message != null,
      listener: (context, state) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message!))),
      builder: (context, state) {
        if (state.loading && state.job == null) return const Center(child: CircularProgressIndicator());
        final job = state.job;
        if (job == null) return Center(child: Text('无法读取任务详情：${state.error ?? '请返回任务中心重试'}'));
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ProgressSummary(completed: job.finishedCount, total: job.totalCount, label: job.type.label),
            const SizedBox(height: 16),
            _InfoRow(label: '当前文件', value: job.currentFile?.isNotEmpty == true ? job.currentFile! : '等待盒子返回'),
            _InfoRow(label: '状态', value: job.state.label),
            if (job.speedBytesPerSecond != null) _InfoRow(label: '速度', value: '${(job.speedBytesPerSecond! / 1024 / 1024).toStringAsFixed(1)} MB/s'),
            if (state.failures.isNotEmpty)
              ExpansionTile(
                title: Text('失败项 ${state.failures.length}'),
                children: state.failures.map((item) => ListTile(title: Text(item.fileId), subtitle: Text(item.reason))).toList(),
              ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('$state.error', style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
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
      if (job.state == BirdJobState.running || job.state == BirdJobState.paused) TextButton(onPressed: () => context.read<JobDetailCubit>().control('cancel'), child: const Text('取消任务')),
      if (job.canDelete)
        TextButton.icon(
          icon: const Icon(Icons.delete_outline),
          label: const Text('删除任务'),
          onPressed: () async {
            final approved = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('删除此任务？'),
                content: const Text('只移除任务记录，不会删除已经复制的照片。'),
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
          label: const Text('返回当前批次'),
        ),
    ],
  );
}
