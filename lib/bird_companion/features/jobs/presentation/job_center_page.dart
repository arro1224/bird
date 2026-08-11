import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/widgets/empty_state.dart';
import 'package:aves/bird_companion/features/jobs/presentation/job_center_cubit.dart';
import 'package:aves/bird_companion/features/jobs/presentation/widgets/job_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Secondary task detail/recovery surface. The production task-tab entrypoint
/// remains [TaskExperienceRoot]; this page is reached from job deep links and
/// diagnostics only.
class JobCenterPage extends StatelessWidget {
  const JobCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final dependencies = BirdCompanionScope.of(context);
    return BlocProvider(
      create: (_) => JobCenterCubit(
        dependencies.jobRepository,
        dependencies.refreshCoordinator,
        dependencies.eventClient,
        dependencies.dataChangeBus,
      )..load(),
      child: const _JobCenterView(),
    );
  }
}

class _JobCenterView extends StatefulWidget {
  const _JobCenterView();

  @override
  State<_JobCenterView> createState() => _JobCenterViewState();
}

class _JobCenterViewState extends State<_JobCenterView> {
  bool _showCompleted = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.paper,
    body: BlocConsumer<JobCenterCubit, JobCenterState>(
      listenWhen: (before, after) => before.error != after.error && after.error != null,
      listener: (context, state) {
        final message = UserMessageMapper.fromError(state.error!);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${message.title}：${message.message}')),
        );
      },
      builder: (context, state) {
        if (state.loading && state.jobs.isEmpty) return const Center(child: CircularProgressIndicator());
        final jobs = state.jobs.where((job) => _showCompleted ? _ended(job) : !_ended(job)).toList();
        final errorMessage = state.error == null ? null : UserMessageMapper.fromError(state.error!);
        return RefreshIndicator(
          onRefresh: () => context.read<JobCenterCubit>().load(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('下午好', style: TextStyle(color: AppColors.inkMuted, fontSize: 16)),
                        Text('处理进度', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(onPressed: () => context.read<JobCenterCubit>().load(), icon: const Icon(Icons.refresh_rounded), tooltip: '刷新进度'),
                ],
              ),
              const SizedBox(height: 18),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('进行中')),
                  ButtonSegment(value: true, label: Text('已完成')),
                ],
                selected: {_showCompleted},
                showSelectedIcon: false,
                onSelectionChanged: (value) => setState(() => _showCompleted = value.first),
              ),
              const SizedBox(height: 18),
              if (jobs.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: EmptyState(
                    icon: _showCompleted ? Icons.task_alt_rounded : Icons.assignment_outlined,
                    title: errorMessage?.title ?? (_showCompleted ? '暂无已完成的处理' : '现在没有正在处理的照片'),
                    message: errorMessage?.message ?? '照片识别、读取和保存进度会显示在这里。',
                    actionLabel: errorMessage?.actionLabel ?? '刷新',
                    onAction: () => context.read<JobCenterCubit>().load(),
                  ),
                )
              else
                ...jobs.map(
                  (job) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: JobCard(
                      job: job,
                      busy: state.actingJobId == job.id,
                      onTap: () => Navigator.of(context).pushNamed(BirdRoutes.jobDetail, arguments: JobDetailArgs(job.id)),
                      onControl: (action) => context.read<JobCenterCubit>().control(job.id, action),
                      onDelete: job.canDelete ? () => _confirmDelete(context, job.id) : null,
                    ),
                  ),
                ),
              if (state.hasMore) ...[
                const SizedBox(height: 4),
                Center(
                  child: state.loadingMore
                      ? const CircularProgressIndicator()
                      : OutlinedButton.icon(
                          onPressed: () => context.read<JobCenterCubit>().loadMore(),
                          icon: const Icon(Icons.expand_more_rounded),
                          label: const Text('加载更多任务'),
                        ),
                ),
                const SizedBox(height: 12),
              ],
              if (!_showCompleted && jobs.isNotEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: AppColors.brand),
                        SizedBox(width: 10),
                        Expanded(child: Text('可以退出软件，盒子仍会继续处理照片')),
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
        title: const Text('删除这条处理记录？'),
        content: const Text('只清理进度记录，不会删除已经保存的照片。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('删除')),
        ],
      ),
    );
    if (approved == true && context.mounted) await context.read<JobCenterCubit>().delete(id);
  }
}

bool _ended(BirdJobStatus job) => job.state == BirdJobState.completed || job.state == BirdJobState.cancelled;
