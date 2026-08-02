import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_design_components.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_nature_background.dart';
import 'package:flutter/material.dart';

class TaskHomePage extends StatelessWidget {
  const TaskHomePage({
    super.key,
    required this.controller,
    this.onOpenCurrentTask,
    this.onOpenSdCard,
    this.onOpenTask,
    this.onStartTask,
  });

  final TaskExperienceController controller;
  final VoidCallback? onOpenCurrentTask;
  final VoidCallback? onOpenSdCard;
  final ValueChanged<String>? onOpenTask;
  final ValueChanged<TaskType>? onStartTask;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('task-home-page'),
    backgroundColor: AppColors.paper,
    body: Stack(
      children: [
        const Positioned.fill(child: TaskNatureBackground()),
        SafeArea(
          bottom: false,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                  sliver: SliverList.list(
                    children: [
                      _header(context),
                      if (controller.hasDisconnectedTask) ...[
                        const SizedBox(height: 12),
                        const TaskDisconnectedNotice(),
                      ],
                      const SizedBox(height: 14),
                      const TaskSectionTitle('当前任务'),
                      _currentTask(),
                      const SizedBox(height: 12),
                      const TaskSectionTitle('下一步'),
                      _actionGrid(context),
                      const SizedBox(height: 12),
                      const TaskSectionTitle('任务列表'),
                      TaskGroupFilter(
                        selected: controller.selectedGroup,
                        onSelected: controller.selectGroup,
                      ),
                      const SizedBox(height: 8),
                      _taskList(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _header(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      const Text(
        '任务',
        style: TextStyle(
          color: AppColors.forestDeep,
          fontSize: 42,
          fontWeight: FontWeight.w800,
        ),
      ),
      IconButton.filled(
        key: const Key('task-executable-actions-button'),
        tooltip: '查看可执行操作',
        onPressed: controller.executableTaskTypes.isEmpty ? null : () => _showExecutableActions(context),
        style: IconButton.styleFrom(
          backgroundColor: AppColors.forestPrimary,
          minimumSize: const Size(48, 48),
          maximumSize: const Size(48, 48),
        ),
        icon: const Icon(Icons.add_rounded, size: 30),
      ),
    ],
  );

  Widget _currentTask() {
    final task = controller.currentTaskOrNull;
    if (task == null) {
      return const TaskSurface(
        key: Key('task-empty-current'),
        padding: EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.hourglass_empty_rounded, color: AppColors.forestPrimary),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                '暂无盒子任务，连接设备后会自动同步。',
                style: TextStyle(color: AppColors.mutedInk, fontSize: 15),
              ),
            ),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: () {
        if (onOpenTask != null) {
          onOpenTask!(task.id);
        } else {
          onOpenCurrentTask?.call();
        }
      },
      child: TaskSurface(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: AppColors.forestDeep,
                    ),
                  ),
                ),
                TaskStatusChip(
                  label: _stateLabel(task),
                  icon: _stateIcon(task.state),
                ),
              ],
            ),
            if (task.sourceBatch case final sourceBatch?) ...[
              const SizedBox(height: 7),
              Text(
                '来源批次 · $sourceBatch',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.mutedInk, fontSize: 13),
              ),
            ],
            const SizedBox(height: 9),
            Text(
              '${_count(task.processed)} / ${_count(task.total)} 张',
              style: const TextStyle(
                fontSize: 22,
                color: AppColors.mutedInk,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${task.progressPercent}%',
              style: const TextStyle(
                fontSize: 40,
                color: AppColors.forestPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: task.progressPercent / 100,
                minHeight: 7,
                color: AppColors.forestPrimary,
                backgroundColor: AppColors.divider,
              ),
            ),
            if (task.currentFile != null || task.speed != null) ...[
              const SizedBox(height: 9),
              Row(
                children: [
                  if (task.currentFile case final currentFile?)
                    Expanded(
                      child: Text(
                        '当前 $currentFile',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.mutedInk,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  if (task.speed case final speed?)
                    Text(
                      speed,
                      style: const TextStyle(
                        color: AppColors.forestDeep,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '预计剩余 ${task.remainingMinutes} 分钟',
                    style: const TextStyle(
                      color: AppColors.mutedInk,
                      fontSize: 16,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.forestPrimary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionGrid(BuildContext context) {
    const descriptions = {
      TaskType.importIndex: '读取存储卡并建立批次',
      TaskType.aiAnalysis: '分析当前批次照片',
      TaskType.copy: '确认范围和目标硬盘',
      TaskType.sync: '同步批次和审片结果',
    };
    if (controller.executableTaskTypes.isEmpty) {
      return const TaskSurface(
        key: Key('task-actions-unavailable'),
        padding: EdgeInsets.all(16),
        child: Text(
          '任务创建将在盒子任务接口接入后开放；当前页面只展示真实任务。',
          style: TextStyle(color: AppColors.mutedInk, height: 1.4),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 78,
        crossAxisSpacing: 12,
        mainAxisSpacing: 10,
      ),
      itemCount: controller.executableTaskTypes.length,
      itemBuilder: (_, index) {
        final type = controller.executableTaskTypes[index];
        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _activateType(context, type),
          child: TaskSurface(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(
                  _typeIcon(type),
                  color: AppColors.forestPrimary,
                  size: 30,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.forestDeep,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        descriptions[type]!,
                        style: const TextStyle(
                          color: AppColors.mutedInk,
                          fontSize: 10.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _taskList() {
    final tasks = controller.visibleTasks;
    if (tasks.isEmpty) {
      return const TaskSurface(
        key: Key('task-list-empty'),
        padding: EdgeInsets.all(18),
        child: Center(
          child: Text(
            '当前分组没有任务',
            style: TextStyle(color: AppColors.mutedInk),
          ),
        ),
      );
    }
    return TaskSurface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < tasks.length; index++) ...[
            _taskRow(tasks[index]),
            if (index != tasks.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  Widget _taskRow(TaskSummary task) => ListTile(
    key: Key('task-record-${task.id}'),
    onTap: () {
      if (onOpenTask != null) {
        onOpenTask!(task.id);
      } else if (task.id == controller.currentTaskOrNull?.id) {
        onOpenCurrentTask?.call();
      }
    },
    minTileHeight: 72,
    leading: CircleAvatar(
      backgroundColor: AppColors.forestSoft.withValues(alpha: .5),
      child: Icon(_typeIcon(task.type), color: AppColors.forestPrimary),
    ),
    title: Text(
      task.type.label,
      style: const TextStyle(
        color: AppColors.forestDeep,
        fontWeight: FontWeight.w700,
      ),
    ),
    subtitle: Text(
      task.failureReason ?? _stateLabel(task),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          task.state == TaskRunState.failed ? '失败 ${task.failedCount ?? 0} 项' : '${task.progressPercent}%',
          style: TextStyle(
            color: task.state == TaskRunState.failed ? AppColors.danger : AppColors.forestDeep,
            fontSize: task.state == TaskRunState.failed ? 14 : 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.forestPrimary,
        ),
      ],
    ),
  );

  Future<void> _showExecutableActions(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.paper,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 16),
        children: [
          const Text(
            '当前可执行操作',
            style: TextStyle(
              color: AppColors.forestDeep,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (final type in controller.executableTaskTypes)
            ListTile(
              minTileHeight: 56,
              leading: Icon(
                _typeIcon(type),
                color: AppColors.forestPrimary,
              ),
              title: Text(type.label),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.pop(sheetContext);
                _activateType(context, type);
              },
            ),
        ],
      ),
    ),
  );

  void _activateType(BuildContext context, TaskType type) {
    if (type == TaskType.importIndex && onOpenSdCard != null) {
      onOpenSdCard!();
      return;
    }
    if (onStartTask != null) {
      onStartTask!(type);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${type.label}已进入当前可执行流程')),
    );
  }

  IconData _typeIcon(TaskType type) => switch (type) {
    TaskType.importIndex => Icons.sd_card_outlined,
    TaskType.aiAnalysis => Icons.image_search_outlined,
    TaskType.copy => Icons.copy_all_outlined,
    TaskType.sync => Icons.sync_rounded,
  };

  IconData _stateIcon(TaskRunState state) => switch (state) {
    TaskRunState.queued => Icons.schedule_outlined,
    TaskRunState.running => Icons.sync_rounded,
    TaskRunState.paused => Icons.pause_rounded,
    TaskRunState.failed => Icons.error_outline_rounded,
    TaskRunState.completed => Icons.check_rounded,
    TaskRunState.cancelled => Icons.block_outlined,
  };

  String _stateLabel(TaskSummary task) => switch (task.state) {
    TaskRunState.queued => '等待中',
    TaskRunState.running => '进行中',
    TaskRunState.paused => '已暂停',
    TaskRunState.failed => '失败 ${task.failedCount ?? 0} 项',
    TaskRunState.completed => '已完成',
    TaskRunState.cancelled => '已取消',
  };

  String _count(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }
}
