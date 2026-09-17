import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/widgets/empty_state.dart';
import 'package:aves/bird_companion/core/widgets/error_notice.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:flutter/material.dart';

/// 复制任务列表页（RC3，审计 P0-3）。
///
/// 通用 `/api/v1/jobs` 任务中心不含 copy_jobs_v1 任务，不能复用，
/// 故独立成页（阶段 D 实施计划 §2.1）。
class CopyJobListPage extends StatefulWidget {
  const CopyJobListPage({super.key, this.repository});

  /// 测试注入；生产从 [BirdCompanionScope] 取 `copyJobRepository`。
  final CopyJobRepository? repository;

  @override
  State<CopyJobListPage> createState() => _CopyJobListPageState();
}

class _CopyJobListPageState extends State<CopyJobListPage> {
  final List<CopyJobListItem> _jobs = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _cursor;
  Object? _error;

  CopyJobRepository? get _repository =>
      widget.repository ?? BirdCompanionScope.maybeOf(context)?.copyJobRepository;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final repository = _repository;
    if (repository == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await repository.listJobs();
      if (!mounted) return;
      setState(() {
        _jobs
          ..clear()
          ..addAll(page.items);
        _hasMore = page.hasMore;
        _cursor = page.nextCursor;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final repository = _repository;
    if (repository == null || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await repository.listJobs(cursor: _cursor);
      if (!mounted) return;
      setState(() {
        _jobs.addAll(page.items);
        _hasMore = page.hasMore;
        _cursor = page.nextCursor;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(UserMessageMapper.fromError(error).message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = _repository;
    return Scaffold(
      appBar: AppBar(title: const Text('复制任务')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: _loading
            ? ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 64),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              )
            : _error != null
            ? ListView(
                children: [
                  ErrorNotice(
                    title: UserMessageMapper.fromError(_error!).title,
                    message: UserMessageMapper.fromError(_error!).message,
                    onRetry: _reload,
                  ),
                ],
              )
            : repository == null
            ? ListView(
                children: const [
                  EmptyState(
                    icon: Icons.usb_off_outlined,
                    title: '未连接盒子',
                    message: '连接盒子后即可查看复制任务进度与结果。',
                  ),
                ],
              )
            : _jobs.isEmpty
            ? ListView(
                children: const [
                  EmptyState(
                    key: Key('copy-job-list-empty'),
                    icon: Icons.task_alt_outlined,
                    title: '还没有复制任务',
                    message: '在相册多选「复制所选」或任务首页发起复制后，进度会显示在这里。',
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: _jobs.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= _jobs.length) {
                    unawaited(_loadMore());
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      ),
                    );
                  }
                  final job = _jobs[index];
                  return _JobListTile(
                    job: job,
                    onTap: () async {
                      await Navigator.of(context).pushNamed(
                        BirdRoutes.copyJobDetail,
                        arguments: CopyJobDetailArgs(job.copyJobId),
                      );
                      // 详情页可能已执行动作（取消/重试），返回后刷新列表。
                      await _reload();
                    },
                  );
                },
              ),
      ),
    );
  }
}

class _JobListTile extends StatelessWidget {
  const _JobListTile({required this.job, required this.onTap});

  final CopyJobListItem job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stats = job.stats;
    final progress = stats == null
        ? null
        : stats.totalFiles > 0
        ? '文件 ${stats.copiedFiles + stats.failedFiles}/${stats.totalFiles}'
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.outline.withValues(alpha: .6)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _StateIcon(state: job.state),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            job.isFullBackup ? '全量备份' : '照片复制',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            job.state.label,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: _stateColor(job.state),
                            ),
                          ),
                        ],
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          progress,
                          style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                if (job.createdAt != null)
                  Text(
                    _formatDate(job.createdAt!),
                    style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                  ),
                const Icon(Icons.chevron_right, color: AppColors.inkMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime time) =>
      '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

class _StateIcon extends StatelessWidget {
  const _StateIcon({required this.state});

  final CopyJobState state;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (state.wire) {
      'completed' => (Icons.check_circle, AppColors.success),
      'completed_with_errors' => (Icons.report, AppColors.warning),
      'failed' => (Icons.cancel, AppColors.danger),
      'cancelled' => (Icons.remove_circle_outline, AppColors.inkMuted),
      'waiting_for_source' || 'waiting_for_target' => (Icons.usb_off_outlined, AppColors.warning),
      _ => (Icons.autorenew, AppColors.forestPrimary),
    };
    return Icon(icon, color: color, size: 26);
  }
}

Color _stateColor(CopyJobState state) => switch (state.wire) {
  'completed' => AppColors.success,
  'completed_with_errors' => AppColors.warning,
  'failed' => AppColors.danger,
  'waiting_for_source' || 'waiting_for_target' => AppColors.warning,
  'cancelled' => AppColors.inkMuted,
  _ => AppColors.forestPrimary,
};
