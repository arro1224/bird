import 'dart:async';

import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/bird_asset_catalog.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_design_components.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_page_frame.dart';
import 'package:flutter/material.dart';

class TaskDetailPage extends StatelessWidget {
  const TaskDetailPage({
    super.key,
    required this.controller,
    this.taskId,
    this.onShowResult,
    this.onTaskCompleted,
    this.onControl,
    this.onExportLog,
    this.allowDemoCompletion = true,
  });

  final TaskExperienceController controller;
  final String? taskId;
  final VoidCallback? onShowResult;
  final ValueChanged<TaskType>? onTaskCompleted;
  final Future<void> Function(String taskId, TaskAction action)? onControl;
  final Future<String> Function(String taskId)? onExportLog;
  final bool allowDemoCompletion;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (_, _) {
      final task = taskId == null ? controller.currentTask : controller.taskById(taskId!);
      return TaskPageFrame(
        title: '任务详情',
        actions: [
          if (task.type == TaskType.copy && task.state == TaskRunState.completed && onShowResult != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (value) {
                if (value == 'result') onShowResult?.call();
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'result', child: Text('查看复制结果'))],
            ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (controller.connectionState == TaskConnectionState.disconnected) ...[
              const TaskDisconnectedNotice(),
              const SizedBox(height: 12),
            ] else if (controller.connectionState == TaskConnectionState.reconnecting) ...[
              _reconnectingNotice(),
              const SizedBox(height: 12),
            ],
            _summaryCard(task),
            const SizedBox(height: 12),
            const Text(
              '任务进度',
              style: TextStyle(color: AppColors.forestDeep, fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _timeline(task),
            const SizedBox(height: 10),
            _details(task),
            if (task.failureReason != null) ...[
              const SizedBox(height: 10),
              _failureNotice(task),
            ],
            const SizedBox(height: 12),
            _actions(context, task),
          ],
        ),
      );
    },
  );

  Widget _summaryCard(TaskSummary task) => TaskSurface(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    child: Stack(
      children: [
        Positioned(
          right: -28,
          bottom: -42,
          width: 150,
          height: 210,
          child: Opacity(opacity: .18, child: Image.asset(BirdAssetCatalog.reedsRight)),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.type.label,
                    style: const TextStyle(color: AppColors.forestDeep, fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ),
                TaskStatusChip(label: _stateLabel(task), icon: _stateIcon(task.state)),
              ],
            ),
            const SizedBox(height: 13),
            RichText(
              key: const Key('task-progress-emphasis'),
              text: TextSpan(
                style: const TextStyle(fontSize: 20, color: AppColors.mutedInk),
                children: [
                  TextSpan(
                    text: _count(task.processed),
                    style: const TextStyle(color: AppColors.forestPrimary, fontSize: 31, fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: ' / ${_count(task.total)} 张'),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${task.progressPercent}%',
              style: const TextStyle(color: AppColors.forestPrimary, fontSize: 42, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            LinearProgressIndicator(value: task.progressPercent / 100, minHeight: 7),
            const SizedBox(height: 11),
            Text('预计剩余 ${task.remainingMinutes} 分钟', style: const TextStyle(color: AppColors.mutedInk)),
          ],
        ),
      ],
    ),
  );

  Widget _timeline(TaskSummary task) {
    final labels = switch (task.type) {
      TaskType.importIndex => const ['读取照片', '建立索引', '生成缩略图', '准备分析'],
      TaskType.aiAnalysis => const ['读取批次', 'AI 识别分析', '质量评分', '生成结果'],
      TaskType.copy => const ['确认复制范围', '复制照片', '校验文件', '生成报告'],
      TaskType.sync => const ['准备同步', '同步结果', '校验差异', '完成同步'],
    };
    final currentIndex = task.progressPercent >= 100 ? 4 : (task.progressPercent * 4 ~/ 100).clamp(0, 3);
    return TaskSurface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Column(
        children: [
          for (var index = 0; index < labels.length; index++)
            _step(
              index < currentIndex
                  ? Icons.check_circle
                  : index == currentIndex
                  ? Icons.adjust_rounded
                  : Icons.circle_outlined,
              labels[index],
              index < currentIndex
                  ? '已完成'
                  : index == currentIndex
                  ? _stateLabel(task)
                  : '等待中',
              last: index == labels.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _details(TaskSummary task) => TaskSurface(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
    child: Column(
      children: [
        _line(Icons.folder_outlined, '来源批次', task.sourceBatch ?? '等待盒子返回'),
        _line(Icons.insert_drive_file_outlined, '当前文件', task.currentFile ?? '等待处理'),
        _line(Icons.speed_rounded, '处理速度', task.speed ?? '--'),
        _line(Icons.gpp_maybe_outlined, '失败数量', '${task.failedCount ?? 0}', divider: false),
      ],
    ),
  );

  Widget _failureNotice(TaskSummary task) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.amberLight, borderRadius: BorderRadius.circular(10)),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
        const SizedBox(width: 10),
        Expanded(
          child: Text(task.failureReason!, style: const TextStyle(color: AppColors.ink, height: 1.4)),
        ),
      ],
    ),
  );

  Widget _reconnectingNotice() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.forestSoft.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.forestPrimary.withValues(alpha: .28)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.sync_rounded, size: 22, color: AppColors.forestPrimary),
        SizedBox(width: 9),
        Expanded(
          child: Text(
            '正在重新连接盒子，任务进度保持不变；连接恢复后将刷新状态。',
            style: TextStyle(color: AppColors.ink, fontSize: 13, height: 1.35),
          ),
        ),
      ],
    ),
  );

  Widget _actions(BuildContext context, TaskSummary task) {
    final actions = task.availableActions;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (task.type == TaskType.aiAnalysis && task.state == TaskRunState.queued && actions.contains(TaskAction.resume))
          _actionButton(
            '开始 AI 分析',
            () => _performAction(task, TaskAction.resume),
          ),
        if (allowDemoCompletion && task.state == TaskRunState.running && task.type != TaskType.sync)
          _actionButton(
            switch (task.type) {
              TaskType.importIndex => '演示完成导入',
              TaskType.aiAnalysis => '演示完成 AI 分析',
              TaskType.copy => '演示完成复制',
              TaskType.sync => '',
            },
            () {
              controller.completeTask(task.id);
              onTaskCompleted?.call(task.type);
            },
          ),
        if (actions.contains(TaskAction.pause))
          _actionButton(
            '暂停任务',
            () => _performAction(task, TaskAction.pause),
            filled: false,
          ),
        if (actions.contains(TaskAction.resume) && task.state != TaskRunState.queued)
          _actionButton(
            '继续任务',
            () => _performAction(task, TaskAction.resume),
          ),
        if (actions.contains(TaskAction.retry))
          _actionButton(
            '重试失败项',
            () => _performAction(task, TaskAction.retry),
          ),
        if (actions.contains(TaskAction.skipFailed))
          _actionButton(
            '跳过失败项',
            () => _performAction(task, TaskAction.skipFailed),
            filled: false,
          ),
        if (actions.contains(TaskAction.cancel)) _actionButton('取消任务', () => _confirmCancel(context, task), filled: false),
        if (actions.contains(TaskAction.exportLog))
          _actionButton(
            '导出日志',
            () => unawaited(_exportLog(context, task)),
            filled: false,
          ),
      ],
    );
  }

  Widget _actionButton(String label, VoidCallback onPressed, {bool filled = true}) => SizedBox(
    width: 164,
    height: 48,
    child: filled ? FilledButton(onPressed: onPressed, child: Text(label)) : OutlinedButton(onPressed: onPressed, child: Text(label)),
  );

  void _performAction(TaskSummary task, TaskAction action) {
    final productionControl = onControl;
    if (productionControl != null) {
      unawaited(productionControl(task.id, action));
      return;
    }
    controller.performAction(task.id, action);
  }

  Future<void> _exportLog(BuildContext context, TaskSummary task) async {
    final export = onExportLog;
    if (export == null) {
      _performAction(task, TaskAction.exportLog);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('演示模式：日志导出请求已记录')),
      );
      return;
    }
    try {
      final path = await export(task.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('任务日志已下载到：$path')),
      );
    } catch (error) {
      if (!context.mounted) return;
      final message = UserMessageMapper.fromError(error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${message.title}：${message.message}')),
      );
    }
  }

  Widget _step(IconData icon, String title, String state, {bool last = false}) => SizedBox(
    height: 55,
    child: Row(
      children: [
        SizedBox(
          width: 34,
          height: 55,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              if (!last)
                Positioned(
                  key: const Key('task-timeline-connector'),
                  top: 29,
                  bottom: -1,
                  child: Container(width: 1.5, color: state == '已完成' ? AppColors.forestPrimary : const Color(0xFFD5D5CF)),
                ),
              Positioned(top: 8, child: Icon(icon, color: state == '等待中' ? const Color(0xFF9A9D96) : AppColors.forestPrimary, size: 24)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Text(state, style: TextStyle(color: state == '等待中' ? AppColors.mutedInk : AppColors.forestPrimary)),
      ],
    ),
  );

  Widget _line(IconData icon, String label, String value, {bool divider = true}) => Column(
    children: [
      SizedBox(
        height: 38,
        child: Row(
          children: [
            Icon(icon, key: const Key('task-detail-info-icon'), size: 22, color: AppColors.forestPrimary),
            const SizedBox(width: 12),
            Text(label),
            const Spacer(),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(color: AppColors.mutedInk),
              ),
            ),
          ],
        ),
      ),
      if (divider) const Divider(height: 1),
    ],
  );

  Future<void> _confirmCancel(BuildContext context, TaskSummary task) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('取消任务？'),
        content: const Text('盒子会停止当前任务，已经完成的文件不会被删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('继续任务')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确认取消')),
        ],
      ),
    );
    if (approved == true) _performAction(task, TaskAction.cancel);
  }

  String _stateLabel(TaskSummary task) => switch (task.state) {
    TaskRunState.queued => '等待中',
    TaskRunState.running => '进行中',
    TaskRunState.paused => '已暂停',
    TaskRunState.failed => '失败 ${task.failedCount ?? 0} 项',
    TaskRunState.completed => '已完成',
    TaskRunState.cancelled => '已取消',
  };

  IconData _stateIcon(TaskRunState state) => switch (state) {
    TaskRunState.queued => Icons.schedule_outlined,
    TaskRunState.running => Icons.sync_rounded,
    TaskRunState.paused => Icons.pause_rounded,
    TaskRunState.failed => Icons.error_outline_rounded,
    TaskRunState.completed => Icons.check_circle_outline_rounded,
    TaskRunState.cancelled => Icons.block_outlined,
  };

  String _count(int value) => value.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (match) => '${match[1]},');
}
