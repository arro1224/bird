import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/widgets/empty_state.dart';
import 'package:aves/bird_companion/features/jobs/presentation/job_center_cubit.dart';
import 'package:aves/bird_companion/features/jobs/presentation/widgets/job_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class JobCenterPage extends StatelessWidget {
  const JobCenterPage({super.key});
  @override
  Widget build(BuildContext context) {
    final deps = BirdCompanionScope.of(context);
    return BlocProvider(
      create: (_) => JobCenterCubit(deps.jobRepository, deps.refreshCoordinator, deps.eventClient, deps.dataChangeBus)..load(),
      child: const _JobCenterView(),
    );
  }
}

class _JobCenterView extends StatelessWidget {
  const _JobCenterView();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('任务中心'),
      actions: [
        IconButton(
          tooltip: '导出日志',
          icon: const Icon(Icons.file_download_outlined),
          onPressed: () async {
            final deps = BirdCompanionScope.of(context);
            try {
              final url = await deps.jobRepository.exportLogs();
              if (url == null) throw StateError('日志正在生成，请稍后重试');
              final log = await deps.logDownloadService.download(url);
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('日志已下载到：${log.file.path}')));
            } catch (error) {
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('日志导出失败：$error')));
            }
          },
        ),
      ],
    ),
    body: BlocConsumer<JobCenterCubit, JobCenterState>(
      listenWhen: (before, after) => before.error != after.error && after.error != null,
      listener: (context, state) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('任务操作失败：${state.error}'))),
      builder: (context, state) {
        if (state.loading && state.jobs.isEmpty) return const Center(child: CircularProgressIndicator());
        if (state.jobs.isEmpty) {
          return EmptyState(
            icon: Icons.assignment_outlined,
            title: state.error == null ? '暂无任务' : '暂时无法读取任务',
            message: state.error == null ? '分析、复制或同步任务会显示在这里。' : '请检查盒子连接后重试。',
            actionLabel: state.error == null ? '刷新' : '查看演示任务',
            onAction: state.error == null ? () => context.read<JobCenterCubit>().load() : context.read<JobCenterCubit>().showDemo,
          );
        }
        return RefreshIndicator(
          onRefresh: () => context.read<JobCenterCubit>().load(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _ConnectionHint(),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: Text('进行中的任务', style: Theme.of(context).textTheme.headlineSmall)),
                  Text('${state.jobs.length} 个任务', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 12),
              if (state.isDemo)
                MaterialBanner(
                  content: const Text('当前为演示任务，未连接盒子端。'),
                  actions: [TextButton(onPressed: () => context.read<JobCenterCubit>().load(), child: const Text('退出演示'))],
                ),
              ...state.jobs.map(
                (job) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: JobCard(
                    job: job,
                    busy: state.actingJobId == job.id,
                    onTap: () => Navigator.of(context).pushNamed(BirdRoutes.jobDetail, arguments: state.isDemo ? null : JobDetailArgs(job.id)),
                    onControl: (action) => context.read<JobCenterCubit>().control(job.id, action),
                    onDelete: state.isDemo ? null : () => _confirmDelete(context, job.id),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Card(
                color: AppColors.brand,
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Icon(Icons.sync_rounded, color: Colors.white),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '任务进度会在本地自动同步',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Future<void> _confirmDelete(BuildContext context, String id) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除已结束任务？'),
        content: const Text('运行中任务请先取消。删除只清理任务记录，不会清理已复制的文件。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('删除')),
        ],
      ),
    );
    if (approved == true && context.mounted) await context.read<JobCenterCubit>().delete(id);
  }
}

class _ConnectionHint extends StatelessWidget {
  const _ConnectionHint();
  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Icon(Icons.circle, size: 12, color: AppColors.success),
      SizedBox(width: 8),
      Text(
        '本地连接稳定',
        style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700),
      ),
    ],
  );
}
