import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/widgets/error_notice.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_timeline.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_presentation.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_job_detail_cubit.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/copy_job_timeline.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_design_components.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_nature_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class CopyJobDetailPage extends StatefulWidget {
  const CopyJobDetailPage({super.key, required this.copyJobId, this.deviceId, this.createdJob, this.repository, this.deviceReader});

  final String copyJobId;
  final String? deviceId;
  final CopyJobSummary? createdJob;
  final CopyJobRepository? repository;
  final Future<CopyDeviceList> Function()? deviceReader;

  @override
  State<CopyJobDetailPage> createState() => _CopyJobDetailPageState();
}

class _CopyJobDetailPageState extends State<CopyJobDetailPage> {
  String? _deviceId;

  @override
  void didUpdateWidget(CopyJobDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.copyJobId != widget.copyJobId || oldWidget.deviceId != widget.deviceId) _deviceId = null;
  }

  @override
  Widget build(BuildContext context) {
    // Resolve inherited dependencies before provider.create, never inside it.
    final dependencies = widget.repository == null ? BirdCompanionScope.maybeOf(context) : null;
    final repository = widget.repository ?? dependencies!.copyJobRepository;
    _deviceId ??= widget.deviceId ?? dependencies?.deviceSessionCubit.state.device?.id;
    final deviceId = _deviceId;
    final jobId = widget.copyJobId;
    return BlocProvider<CopyJobDetailCubit>(
      key: ValueKey((jobId, deviceId, repository)),
      create: (_) => CopyJobDetailCubit(
        repository,
        copyJobId: jobId,
        deviceId: deviceId,
        deviceReader: widget.deviceReader ?? dependencies?.copyRepository.devices,
        activeJobs: dependencies?.activeCopyJobs,
        diagnostics: dependencies?.copyDiagnostics,
        detailReader: dependencies == null ? null : (trigger) => dependencies.copyJobRecovery.readJob(deviceId ?? '', jobId, trigger: trigger),
        canRead: dependencies == null ? null : () => deviceId != null && dependencies.copyJobRecovery.canRead(deviceId),
        sessionRefreshes: dependencies?.copyJobRecovery.sessionRefreshes,
      ),
      child: _CopyJobDetailView(createdJob: widget.createdJob),
    );
  }
}

class _CopyJobDetailView extends StatefulWidget {
  const _CopyJobDetailView({this.createdJob});
  final CopyJobSummary? createdJob;

  @override
  State<_CopyJobDetailView> createState() => _CopyJobDetailViewState();
}

class _CopyJobDetailViewState extends State<_CopyJobDetailView> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    context.read<CopyJobDetailCubit>().startPolling(foreground: lifecycle == null || lifecycle == AppLifecycleState.resumed);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    context.read<CopyJobDetailCubit>().setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CopyJobDetailCubit>();
    return Scaffold(
      appBar: AppBar(title: const Text('复制任务详情')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const TaskNatureBackground(),
          BlocConsumer<CopyJobDetailCubit, CopyJobDetailState>(
            listener: (context, state) {
              final notice = state.notice;
              if (notice != null) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text(notice)));
                cubit.consumeNotice();
              }
            },
            builder: (context, state) {
              if (state.detail == null) {
                if (state.loading && state.error == null) return const Center(child: CircularProgressIndicator());
                final error = state.error;
                return _FirstLoadErrorView(
                  jobId: cubit.copyJobId,
                  title: !cubit.deviceAvailable
                      ? '请连接原盒子'
                      : state.jobMissing
                      ? '任务已不存在或已被清理'
                      : error == null
                      ? '正在读取任务'
                      : UserMessageMapper.fromError(error).title,
                  message: !cubit.deviceAvailable
                      ? '连接创建此任务的盒子后，将自动继续读取进度。'
                      : error == null
                      ? '正在读取盒子上的任务状态。'
                      : UserMessageMapper.fromError(error).message,
                  automatic: !state.jobMissing && cubit.deviceAvailable,
                  onRetry: cubit.load,
                  createdJob: widget.createdJob,
                );
              }
              return _DetailView(
                state: state,
                deviceAvailable: cubit.deviceAvailable,
                onRefresh: cubit.load,
                onRetrySupplemental: cubit.retrySupplemental,
                onAction: cubit.act,
                onLoadMoreFailed: cubit.loadMoreFailedItems,
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Scheduling belongs to the Cubit, so loading/error rebuilds cannot reset it.
class _FirstLoadErrorView extends StatelessWidget {
  const _FirstLoadErrorView({required this.jobId, required this.title, required this.message, required this.automatic, required this.onRetry, this.createdJob});
  final String jobId, title, message;
  final bool automatic;
  final Future<void> Function() onRetry;
  final CopyJobSummary? createdJob;

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      ErrorNotice(title: title, message: message, onRetry: onRetry),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Text('任务编号 $jobId', style: const TextStyle(color: AppColors.inkMuted, fontSize: 12.5)),
      ),
      if (createdJob != null)
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text('任务已创建；创建时状态：${CopyJobState.fromWire(createdJob!.state).label}。当前进度正在读取。'),
        ),
      if (automatic)
        const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Text('盒子上的任务可能仍在继续，将自动重试读取进度；也可手动重试。', style: TextStyle(color: AppColors.inkMuted, fontSize: 12.5)),
        ),
      TextButton(onPressed: () => Navigator.of(context).pushReplacementNamed(BirdRoutes.copyJobs), child: const Text('查看复制任务列表')),
    ],
  );
}

class _DetailView extends StatelessWidget {
  const _DetailView({required this.state, required this.deviceAvailable, required this.onRefresh, required this.onRetrySupplemental, required this.onAction, required this.onLoadMoreFailed});
  final CopyJobDetailState state;
  final bool deviceAvailable;
  final Future<void> Function() onRefresh, onRetrySupplemental;
  final ValueChanged<CopyAllowedAction> onAction;
  final VoidCallback onLoadMoreFailed;

  @override
  Widget build(BuildContext context) {
    final detail = state.detail!;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _WaitingBanner(state: detail.state),
          _StateHeader(detail: detail, state: state),
          if (state.error != null)
            ErrorNotice(
              title: state.jobMissing
                  ? '任务已不存在或已被清理'
                  : deviceAvailable
                  ? '暂时无法读取最新进度'
                  : '请连接原盒子',
              message: '以上为最后一次读取的状态。连接创建此任务的盒子后可继续读取。',
              onRetry: onRefresh,
            ),
          _ProgressCard(detail: detail, report: state.report),
          const SizedBox(height: 12),
          CopyJobTimeline(
            timeline: CopyTimeline.compute(state: detail.state, stats: detail.stats, report: state.report, reviewExportEnabled: detail.reviewExportEnabled),
          ),
          const SizedBox(height: 12),
          _DeviceSnapshotCard(detail: detail, report: state.report, devices: state.devices, sourceSnapshot: state.sourceNameSnapshot, targetSnapshot: state.targetNameSnapshot),
          const SizedBox(height: 12),
          _ActionsSection(detail: detail, acting: state.acting || !deviceAvailable || state.jobMissing, onAction: onAction),
          if (state.eventsError != null || state.reportError != null || state.failedItemsError != null)
            ErrorNotice(
              title: '部分任务信息暂不可用',
              message: [if (state.eventsError != null) '任务动态读取失败', if (state.reportError != null) '结果报告读取失败', if (state.failedItemsError != null) '失败项读取失败'].join('；'),
              onRetry: onRetrySupplemental,
            ),
          if (state.failedItems.isNotEmpty || detail.state.isTerminal) ...[
            const SizedBox(height: 12),
            _FailedItemsSection(state: state, onLoadMore: onLoadMoreFailed),
          ],
          if (state.report != null) ...[
            const SizedBox(height: 12),
            _ReportCard(report: state.report!, taskState: detail.state),
          ],
          const SizedBox(height: 12),
          _EventsSection(state: state),
        ],
      ),
    );
  }
}

class _WaitingBanner extends StatelessWidget {
  const _WaitingBanner({required this.state});

  final CopyJobState state;

  @override
  Widget build(BuildContext context) {
    final (text, show) = switch (state.wire) {
      'waiting_for_source' => (
        '等待相机卡：请将源相机卡插回盒子，任务将自动继续。',
        true,
      ),
      'waiting_for_target' => (
        '等待原目标 U 盘：请重新插入同一目标设备，不会自动更换其他设备。',
        true,
      ),
      'pause_requested' => ('当前文件完成后暂停。', true),
      'cancel_requested' => ('正在取消：已完成的副本不会删除。', true),
      _ => ('', false),
    };
    if (!show) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.amberLight.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: .4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.usb_off_outlined, color: AppColors.warning, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.35, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _StateHeader extends StatelessWidget {
  const _StateHeader({required this.detail, required this.state});

  final CopyJobDetail detail;
  final CopyJobDetailState state;

  @override
  Widget build(BuildContext context) {
    final partial = state.report?.isPartialSuccess ?? false;
    final color = switch (detail.state.wire) {
      'completed' when !partial => AppColors.success,
      'completed' when partial => AppColors.warning,
      'completed_with_errors' => AppColors.warning,
      'failed' => AppColors.danger,
      'cancelled' => AppColors.inkMuted,
      _ => AppColors.forestPrimary,
    };
    return TaskSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  detail.isFullBackup ? '全量备份' : '照片复制',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.forestDeep),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  detail.state == CopyJobState.completed && partial ? '部分完成' : detail.state.label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '任务编号 ${detail.copyJobId}',
            style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// Outcomes, byte counts and box timing remain distinct from job completion.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.detail, this.report});
  final CopyJobDetail detail;
  final CopyReport? report;

  @override
  Widget build(BuildContext context) {
    final frozen = detail.state.isTerminal ? report : null;
    final progress = frozen == null ? CopyTaskProgress.fromStats(detail.stats, detail.state) : CopyTaskProgress.fromReport(frozen);
    final timing = CopyTaskTiming.forTask(detail, frozen);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TaskSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TaskSectionTitle('任务处理情况'),
            if (progress.percent != null) ...[
              LinearProgressIndicator(key: const Key('copy-job-progress-bar'), value: progress.percent, minHeight: 9, color: AppColors.forestPrimary, backgroundColor: AppColors.forestSoft),
              Text('${(progress.percent! * 100).toStringAsFixed(0)}%', key: const Key('copy-job-progress-percent')),
            ] else
              const Text('进度百分比暂不可用', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            const SizedBox(height: 6),
            Text(
              progress.summary(detail.state),
              key: const Key('copy-job-outcomes'),
              style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
            ),
            if (progress.total != null) Text('盒子文件总数：${progress.total}', style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            if (frozen == null && progress.copiedBytes != null) Text('已复制字节：${formatBytes(progress.copiedBytes!)}'),
            const SizedBox(height: 6),
            Text('耗时（盒子统计）：${timing.elapsedLabel}', key: const Key('copy-job-elapsed')),
            Text('速度（盒子统计）：${timing.speedLabel}', key: const Key('copy-job-speed')),
            Text('统计来源：${timing.source}', style: const TextStyle(fontSize: 11, color: AppColors.inkMuted)),
            if (!detail.state.isTerminal && detail.stats?.currentFile?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                '当前：${detail.stats!.currentFile}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeviceSnapshotCard extends StatelessWidget {
  const _DeviceSnapshotCard({required this.detail, this.report, this.devices = const [], this.sourceSnapshot, this.targetSnapshot});

  final CopyJobDetail detail;
  final CopyReport? report;
  final List<StorageDeviceSummary> devices;
  final CopyJobDeviceSnapshot? sourceSnapshot, targetSnapshot;

  @override
  Widget build(BuildContext context) => TaskSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TaskSectionTitle('存储设备'),
        _deviceRow('源设备', copyTaskDeviceName(source: true, snapshot: sourceSnapshot ?? detail.sourceDevice, reportSnapshot: report?.sourceDevice, devices: devices)),
        const Divider(height: 20),
        _deviceRow('目标设备', copyTaskDeviceName(source: false, snapshot: targetSnapshot ?? detail.targetDevice, reportSnapshot: report?.targetDevice, devices: devices)),
      ],
    ),
  );

  Widget _deviceRow(String label, String name) => Row(
    children: [
      SizedBox(
        width: 72,
        child: Text(label, style: const TextStyle(color: AppColors.inkMuted, fontSize: 13)),
      ),
      Expanded(
        child: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

/// 动作区：只渲染后端 `allowed_actions` 返回的按钮（迁移对照 §3.5）。
class _ActionsSection extends StatelessWidget {
  const _ActionsSection({
    required this.detail,
    required this.acting,
    required this.onAction,
  });

  final CopyJobDetail detail;
  final bool acting;
  final ValueChanged<CopyAllowedAction> onAction;

  @override
  Widget build(BuildContext context) {
    if (detail.allowedActions.isEmpty) return const SizedBox.shrink();
    return TaskSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TaskSectionTitle('任务操作'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final action in detail.allowedActions)
                _ActionButton(
                  action: action,
                  enabled: !acting,
                  onAction: onAction,
                ),
            ],
          ),
          if (acting) ...[
            const SizedBox(height: 10),
            const Text('正在发送指令…', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    required this.enabled,
    required this.onAction,
  });

  final CopyAllowedAction action;
  final bool enabled;
  final ValueChanged<CopyAllowedAction> onAction;

  @override
  Widget build(BuildContext context) {
    final destructive = action == CopyAllowedAction.cancel;
    return OutlinedButton.icon(
      key: Key('copy-job-action-${action.wire}'),
      onPressed: enabled ? () => _run(context) : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: destructive ? AppColors.danger : AppColors.forestPrimary,
        side: BorderSide(
          color: (destructive ? AppColors.danger : AppColors.forestPrimary).withValues(alpha: .5),
        ),
      ),
      icon: Icon(
        switch (action.wire) {
          'pause' => Icons.pause_circle_outline,
          'resume' => Icons.play_circle_outline,
          'cancel' => Icons.cancel_outlined,
          'retry_failed' => Icons.replay,
          'safe_remove_source' || 'safe_remove_target' => Icons.usb_outlined,
          _ => Icons.touch_app_outlined,
        },
        size: 18,
      ),
      label: Text(action.label),
    );
  }

  Future<void> _run(BuildContext context) async {
    switch (action.wire) {
      case 'pause':
        unawaited(
          _confirm(
            context,
            title: '暂停任务',
            message: '当前文件完成后暂停。已完成的副本保持不变，可随时继续。',
            onConfirm: () => onAction(action),
          ),
        );
      case 'cancel':
        unawaited(
          _confirm(
            context,
            title: '取消任务',
            message: '已完成的副本不会删除，未完成的文件项将停止复制。确定取消吗？',
            confirmLabel: '取消任务',
            onConfirm: () => onAction(action),
          ),
        );
      case 'safe_remove_source' || 'safe_remove_target':
        unawaited(
          _confirm(
            context,
            title: '安全移除设备',
            message: '盒子会先确认没有任务在写入该设备，确认后即可拔出。',
            onConfirm: () => onAction(action),
          ),
        );
      default:
        onAction(action);
    }
  }

  Future<void> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required VoidCallback onConfirm,
    String confirmLabel = '确定',
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('再想想'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (confirmed == true) onConfirm();
  }
}

/// 失败项列表（cursor 分页加载更多，不前端去重）。
class _FailedItemsSection extends StatelessWidget {
  const _FailedItemsSection({required this.state, required this.onLoadMore});

  final CopyJobDetailState state;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) => TaskSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TaskSectionTitle('失败项（${state.failedItems.length}）'),
        if (state.failedItems.isEmpty)
          Text(state.failedItemsError == null ? '没有失败项。' : '失败项尚未读取，请重试。', style: const TextStyle(fontSize: 13, color: AppColors.inkMuted))
        else
          for (final (index, item) in state.failedItems.indexed)
            Padding(
              padding: EdgeInsets.only(bottom: index == state.failedItems.length - 1 ? 0 : 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.sourceRelativePath ?? item.copyItemId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          item.failureText,
                          style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        if (state.failedHasMore)
          TextButton(
            key: const Key('copy-job-failed-load-more'),
            onPressed: onLoadMore,
            child: const Text('加载更多失败项'),
          ),
      ],
    ),
  );
}

/// 终态报告卡：部分成功不得显示成成功（迁移对照 §3.6）。
/// 审阅导出结果（XMP/CSV/嵌入）有数据时必须展示，CSV 失败计为部分完成。
class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, required this.taskState});

  final CopyReport report;
  final CopyJobState taskState;

  @override
  Widget build(BuildContext context) {
    final partial = report.isPartialSuccess || taskState == CopyJobState.completedWithErrors;
    final unsuccessful = taskState == CopyJobState.failed || taskState == CopyJobState.cancelled;
    final accent = unsuccessful
        ? AppColors.danger
        : partial
        ? AppColors.warning
        : AppColors.success;
    final title = taskState == CopyJobState.failed
        ? '任务失败报告'
        : taskState == CopyJobState.cancelled
        ? '任务取消报告'
        : partial
        ? '部分完成（有失败或降级）'
        : '复制完成';
    return TaskSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: TaskSectionTitle(title)),
              Icon(
                unsuccessful
                    ? Icons.cancel_outlined
                    : partial
                    ? Icons.report
                    : Icons.verified_outlined,
                color: accent,
              ),
            ],
          ),
          Text(CopyTaskProgress.fromReport(report).summary(taskState), key: const Key('copy-report-outcomes')),
          _metric('实际文件数', '${report.actualFileCount ?? '—'}'),
          _metric('已复制', '${report.copiedFiles ?? '—'}'),
          _metric('失败', '${report.failedFiles ?? '—'}', danger: (report.failedFiles ?? 0) > 0),
          _metric('同名跳过', '${report.skippedFiles ?? '—'}'),
          _metric('不适用', '${report.notApplicableFiles ?? '—'}'),
          if (report.totalBytes != null) _metric('总字节数', _bytes(report.totalBytes!)),
          _metric('耗时（盒子统计）', CopyTaskTiming.fromReport(report).elapsedLabel),
          _metric('速度（盒子统计）', CopyTaskTiming.fromReport(report).speedLabel),
          if (_hasReviewExportMetrics) ...[
            const Divider(height: 20),
            _metric('审阅 XMP', '${report.xmpCount ?? '—'}'),
            _metric(
              '审阅 CSV',
              switch (report.csvStatus) {
                'success' => '已导出',
                'failed' => '导出失败',
                'pending' => '等待导出',
                'not_requested' => '未开启',
                _ => '状态未确认',
              },
              danger: report.csvStatus == 'failed',
            ),
            if ((report.exportFailedCount ?? 0) > 0) _metric('审阅导出失败', '${report.exportFailedCount}', danger: true),
            if (report.embedSuccessCount != null || report.embedDegradedCount != null)
              _metric(
                '嵌入副本',
                '${report.embedSuccessCount ?? '—'} 成功${(report.embedDegradedCount ?? 0) > 0 ? ' · ${report.embedDegradedCount} 降级外置' : ''}',
                danger: (report.embedDegradedCount ?? 0) > 0,
              ),
          ],
        ],
      ),
    );
  }

  /// 后端返回了任一审阅导出字段才渲染导出区（字段缺失不占位）。
  bool get _hasReviewExportMetrics => report.xmpCount != null || report.csvStatus != null || report.embedSuccessCount != null || report.embedDegradedCount != null;

  Widget _metric(String label, String value, {bool danger = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: danger ? AppColors.danger : AppColors.forestDeep,
          ),
        ),
      ],
    ),
  );

  String _bytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}

/// 事件流（倒序，上限 50 条）。
class _EventsSection extends StatelessWidget {
  const _EventsSection({required this.state});

  final CopyJobDetailState state;

  @override
  Widget build(BuildContext context) {
    final events = state.events.reversed.take(50).toList(growable: false);
    return TaskSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TaskSectionTitle('任务动态'),
          if (events.isEmpty)
            const Text('暂无事件。', style: TextStyle(fontSize: 13, color: AppColors.inkMuted))
          else
            for (final (index, event) in events.indexed)
              Padding(
                padding: EdgeInsets.only(bottom: index == events.length - 1 ? 0 : 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _time(event.createdAt),
                      style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(event.message ?? event.type ?? '—', style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  String _time(DateTime? time) {
    if (time == null) return '—';
    // 后端时间为 ISO-8601 UTC（返修 P1-4）：展示层统一转手机本地时区。
    final local = time.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
  }
}
