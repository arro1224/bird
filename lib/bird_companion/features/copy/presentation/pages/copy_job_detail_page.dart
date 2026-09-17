import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/widgets/error_notice.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_timeline.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_job_detail_cubit.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/copy_job_timeline.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_design_components.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_nature_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// 复制任务详情页（RC3 任务闭环主页面，审计 P0-3 验收：
/// “创建任务后能进入任务详情，能看到真实状态、文件数和结果”）。
class CopyJobDetailPage extends StatefulWidget {
  const CopyJobDetailPage({super.key, required this.copyJobId, this.repository});

  final String copyJobId;

  /// 测试注入；生产从 [BirdCompanionScope] 取 `copyJobRepository`。
  final CopyJobRepository? repository;

  @override
  State<CopyJobDetailPage> createState() => _CopyJobDetailPageState();
}

class _CopyJobDetailPageState extends State<CopyJobDetailPage> {
  CopyJobDetailCubit? _cubit;

  @override
  Widget build(BuildContext context) {
    // repository 必须在页面自己的 build 里解析：create 回调内调用
    // BirdCompanionScope.maybeOf 会触发 dependOnInheritedWidget，
    // 属于 provider 禁止的 "listen during create" 生命周期（真机红屏）。
    final repository =
        widget.repository ?? BirdCompanionScope.maybeOf(context)!.copyJobRepository;
    return BlocProvider<CopyJobDetailCubit>(
      create: (_) => _cubit ??= CopyJobDetailCubit(repository, copyJobId: widget.copyJobId),
      child: const _CopyJobDetailView(),
    );
  }
}

class _CopyJobDetailView extends StatefulWidget {
  const _CopyJobDetailView();

  @override
  State<_CopyJobDetailView> createState() => _CopyJobDetailViewState();
}

class _CopyJobDetailViewState extends State<_CopyJobDetailView> {
  @override
  void initState() {
    super.initState();
    context.read<CopyJobDetailCubit>().load();
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
              final detail = state.detail;
              if (detail == null) {
                if (state.loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                final error = state.error;
                return ListView(
                  children: [
                    ErrorNotice(
                      title: error == null
                          ? '任务不存在'
                          : UserMessageMapper.fromError(error).title,
                      message: error == null
                          ? '未找到该复制任务，可能已被盒子清理。'
                          : UserMessageMapper.fromError(error).message,
                      onRetry: cubit.load,
                    ),
                  ],
                );
              }
              return _DetailView(
                state: state,
                onRefresh: cubit.load,
                onPoll: cubit.pollTick,
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

/// 按任务状态驱动轮询：运行态 2s / 等待设备 5s / 终态停止；后台不轮询，
/// 回前台立即 tick 一次（AppLifecycleListener）。
class _DetailView extends StatefulWidget {
  const _DetailView({
    required this.state,
    required this.onRefresh,
    required this.onPoll,
    required this.onAction,
    required this.onLoadMoreFailed,
  });

  final CopyJobDetailState state;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onPoll;
  final ValueChanged<CopyAllowedAction> onAction;
  final VoidCallback onLoadMoreFailed;

  @override
  State<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<_DetailView> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncTimer();
  }

  @override
  void didUpdateWidget(_DetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pollEnabled) {
      widget.onPoll();
    }
    _syncTimer();
  }

  bool get _lifecycleResumed =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  bool get _pollEnabled =>
      _lifecycleResumed && !(widget.state.detail?.state.isTerminal ?? true);

  void _syncTimer() {
    final waiting = widget.state.detail?.state.isWaitingDevice ?? false;
    final interval = waiting ? const Duration(seconds: 5) : const Duration(seconds: 2);
    if (!_pollEnabled) {
      _timer?.cancel();
      _timer = null;
      _currentInterval = null;
      return;
    }
    if (_timer != null && _timer!.isActive && _currentInterval == interval) return;
    _timer?.cancel();
    _currentInterval = interval;
    _timer = Timer.periodic(interval, (_) => widget.onPoll());
  }

  Duration? _currentInterval;

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.state.detail!;
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _WaitingBanner(state: detail.state),
          _StateHeader(detail: detail, state: widget.state),
          _ProgressCard(detail: detail),
          const SizedBox(height: 12),
          CopyJobTimeline(
            timeline: CopyTimeline.compute(state: detail.state, stats: detail.stats),
          ),
          const SizedBox(height: 12),
          _DeviceSnapshotCard(detail: detail),
          const SizedBox(height: 12),
          _ActionsSection(
            detail: detail,
            acting: widget.state.acting,
            onAction: widget.onAction,
          ),
          if (widget.state.failedItems.isNotEmpty || detail.state.isTerminal) ...[
            const SizedBox(height: 12),
            _FailedItemsSection(state: widget.state, onLoadMore: widget.onLoadMoreFailed),
          ],
          if (widget.state.report != null) ...[
            const SizedBox(height: 12),
            _ReportCard(report: widget.state.report!),
          ],
          const SizedBox(height: 12),
          _EventsSection(state: widget.state),
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
      'completed_with_errors' || 'failed' => AppColors.danger,
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
                  detail.state.label,
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

/// 进度卡：后端 P1-5 反馈当前进度为假值——0/null 一律不渲染。
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.detail});

  final CopyJobDetail detail;

  @override
  Widget build(BuildContext context) {
    final stats = detail.stats;
    final progress = stats?.effectiveProgressPercent;
    if (stats == null || progress == null || progress <= 0) {
      return const SizedBox.shrink();
    }
    final total = stats.totalFiles;
    final done = stats.copiedFiles + stats.failedFiles + stats.skippedFiles;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TaskSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TaskSectionTitle('复制进度'),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 9,
                      color: AppColors.forestPrimary,
                      backgroundColor: AppColors.forestSoft,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.forestPrimary),
                ),
              ],
            ),
            if (total > 0) ...[
              const SizedBox(height: 6),
              Text(
                '文件 $done/$total'
                '${stats.failedFiles > 0 ? '，失败 ${stats.failedFiles}' : ''}'
                '${stats.skippedFiles > 0 ? '，同名跳过 ${stats.skippedFiles}' : ''}',
                style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
              ),
            ],
            if (stats.currentFile?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                '当前：${stats.currentFile}',
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
  const _DeviceSnapshotCard({required this.detail});

  final CopyJobDetail detail;

  @override
  Widget build(BuildContext context) => TaskSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TaskSectionTitle('存储设备'),
        _deviceRow('源设备', detail.sourceDevice),
        const Divider(height: 20),
        _deviceRow('目标设备', detail.targetDevice),
      ],
    ),
  );

  Widget _deviceRow(String label, CopyJobDeviceSnapshot? device) => Row(
    children: [
      SizedBox(
        width: 72,
        child: Text(label, style: const TextStyle(color: AppColors.inkMuted, fontSize: 13)),
      ),
      Expanded(
        child: Text(
          device?.presentationLabel ?? '—',
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
          const Text('没有失败项。', style: TextStyle(fontSize: 13, color: AppColors.inkMuted))
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
                        const Text(
                          '副本校验不一致（COPY_HASH_MISMATCH），可重试失败项。',
                          style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
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
class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final CopyReport report;

  @override
  Widget build(BuildContext context) {
    final partial = report.isPartialSuccess;
    final accent = partial ? AppColors.warning : AppColors.success;
    final title = partial ? '部分完成（有失败项）' : '复制完成';
    return TaskSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: TaskSectionTitle(title)),
              Icon(
                partial ? Icons.report : Icons.verified_outlined,
                color: accent,
              ),
            ],
          ),
          _metric('实际文件数', '${report.actualFileCount ?? '—'}'),
          _metric('已复制', '${report.copiedFiles ?? '—'}'),
          _metric('失败', '${report.failedFiles ?? '—'}', danger: (report.failedFiles ?? 0) > 0),
          _metric('同名跳过', '${report.skippedFiles ?? '—'}'),
          _metric('不适用', '${report.notApplicableFiles ?? '—'}'),
          if (report.totalBytes != null)
            _metric('总字节数', _bytes(report.totalBytes!)),
          if (report.elapsedSeconds != null)
            _metric('耗时', _duration(report.elapsedSeconds!)),
          if (report.bytesPerSecond != null)
            _metric('有效吞吐', '${_bytes(report.bytesPerSecond!)}/s'),
        ],
      ),
    );
  }

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

  String _duration(int seconds) {
    if (seconds >= 60) {
      final minutes = seconds ~/ 60;
      return '$minutes 分 ${seconds % 60} 秒';
    }
    return '$seconds 秒';
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
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}
