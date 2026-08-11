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
                      _currentTask(context),
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
          color: AppColors.brandDark,
          fontSize: 28,
          fontWeight: FontWeight.w800,
        ),
      ),
      _TaskExecutableActionsButton(
        key: const Key('task-executable-actions-button'),
        tooltip: '查看可执行操作',
        onPressed: () => _showExecutableActions(context),
      ),
    ],
  );

  Widget _currentTask(BuildContext context) {
    final task = controller.currentTaskOrNull;
    if (task == null) {
      return TaskSurface(
        key: const Key('task-empty-current'),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Icon(Icons.hourglass_empty_rounded, color: AppColors.forestPrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _emptyTaskMessage(),
                style: const TextStyle(color: AppColors.mutedInk, fontSize: 15),
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
        key: const Key('task-current-card'),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _currentTaskHeader(context, task),
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
              _currentTaskActivity(context, task),
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

  Widget _currentTaskHeader(BuildContext context, TaskSummary task) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked = constraints.maxWidth < 280 || MediaQuery.textScalerOf(context).scale(1) >= 1.3;
      final title = Text(
        task.title,
        key: const Key('task-current-title'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: AppColors.forestDeep,
        ),
      );
      final status = TaskStatusChip(
        key: const Key('task-current-status'),
        label: _stateLabel(task),
        icon: _stateIcon(task.state),
      );
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [title, const SizedBox(height: 8), status],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: title),
          const SizedBox(width: 10),
          status,
        ],
      );
    },
  );

  Widget _currentTaskActivity(BuildContext context, TaskSummary task) {
    final currentFile = task.currentFile;
    final speed = task.speed;
    final file = currentFile == null
        ? null
        : Text(
            '当前 $currentFile',
            key: const Key('task-current-file'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.mutedInk, fontSize: 13),
          );
    final speedLabel = speed == null
        ? null
        : Text(
            speed,
            key: const Key('task-current-speed'),
            style: const TextStyle(
              color: AppColors.forestDeep,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          );
    if (MediaQuery.textScalerOf(context).scale(1) >= 1.3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget?>[
          file,
          file != null && speedLabel != null ? const SizedBox(height: 4) : null,
          speedLabel,
        ].nonNulls.toList(),
      );
    }
    return Row(
      children: <Widget?>[
        file == null ? null : Expanded(child: file),
        file != null && speedLabel != null ? const SizedBox(width: 10) : null,
        speedLabel,
      ].nonNulls.toList(),
    );
  }

  Widget _actionGrid(BuildContext context) {
    final capabilities = controller.taskHomeCapabilities;
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final singleColumn = constraints.maxWidth < 320 || textScale >= 1.3;
        final itemHeight = singleColumn ? (78 + 32 * (textScale - 1)).clamp(78, 110).toDouble() : 78.0;
        return GridView.builder(
          key: const Key('task-action-grid'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: singleColumn ? 1 : 2,
            mainAxisExtent: itemHeight,
            crossAxisSpacing: 12,
            mainAxisSpacing: 10,
          ),
          itemCount: capabilities.length,
          itemBuilder: (_, index) {
            final capability = capabilities[index];
            final type = capability.type;
            return Opacity(
              opacity: capability.enabled ? 1 : .58,
              child: InkWell(
                key: Key('task-action-${type.name}'),
                borderRadius: BorderRadius.circular(18),
                onTap: capability.enabled ? () => _activateType(context, type) : null,
                child: TaskSurface(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(
                    children: [
                      Icon(
                        _typeIcon(type),
                        color: capability.enabled ? AppColors.forestPrimary : AppColors.mutedInk,
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
                              capability.enabled ? capability.description : capability.disabledReason ?? capability.description,
                              key: Key('task-action-reason-${type.name}'),
                              style: const TextStyle(
                                color: AppColors.mutedInk,
                                fontSize: 10.5,
                              ),
                              maxLines: singleColumn ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _taskList() {
    final tasks = controller.visibleTasks;
    if (tasks.isEmpty) {
      return TaskSurface(
        key: const Key('task-list-empty'),
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Text(
              '当前分组没有任务',
              style: TextStyle(color: AppColors.mutedInk),
            ),
            if (controller.hasMoreTasks) ...[
              const SizedBox(height: 10),
              controller.loadingMoreTasks
                  ? const CircularProgressIndicator()
                  : TextButton.icon(
                      onPressed: controller.loadMoreTasks,
                      icon: const Icon(Icons.expand_more_rounded),
                      label: const Text('继续加载任务'),
                    ),
            ],
          ],
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
          if (controller.hasMoreTasks) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: controller.loadingMoreTasks
                  ? const CircularProgressIndicator()
                  : TextButton.icon(
                      onPressed: controller.loadMoreTasks,
                      icon: const Icon(Icons.expand_more_rounded),
                      label: const Text('加载更多任务'),
                    ),
            ),
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
          for (final capability in controller.taskHomeCapabilities)
            ListTile(
              minTileHeight: 56,
              leading: Icon(
                _typeIcon(capability.type),
                color: capability.enabled ? AppColors.forestPrimary : AppColors.mutedInk,
              ),
              title: Text(capability.type.label),
              subtitle: Text(
                capability.enabled ? capability.description : capability.disabledReason ?? capability.description,
              ),
              trailing: Icon(capability.enabled ? Icons.chevron_right_rounded : Icons.lock_outline_rounded),
              enabled: capability.enabled,
              onTap: capability.enabled
                  ? () {
                      Navigator.pop(sheetContext);
                      _activateType(context, capability.type);
                    }
                  : null,
            ),
        ],
      ),
    ),
  );

  void _activateType(BuildContext context, TaskType type) {
    final capability = controller.taskHomeCapabilities.where((item) => item.type == type).firstOrNull;
    if (capability?.enabled != true) return;
    if (type == TaskType.importIndex && onOpenSdCard != null) {
      onOpenSdCard!();
      return;
    }
    if (onStartTask != null) {
      onStartTask!(type);
      return;
    }
  }

  String _emptyTaskMessage() => switch (controller.connectionState) {
    TaskConnectionState.disconnected => '连接已断开；盒子任务可能仍在运行，重新连接后将刷新进度。',
    TaskConnectionState.reconnecting => '正在重新连接盒子，连接恢复后将读取当前任务。',
    TaskConnectionState.connected when controller.loading => '正在读取盒子任务状态…',
    TaskConnectionState.connected when controller.error != null => '盒子任务状态读取失败，请刷新或重新连接。',
    TaskConnectionState.connected => '当前没有运行中的盒子任务。',
  };

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

class _TaskExecutableActionsButton extends StatelessWidget {
  const _TaskExecutableActionsButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
  });

  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: SizedBox.square(
          dimension: 48,
          child: InkResponse(
            onTap: onPressed,
            radius: 24,
            child: Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: enabled ? AppColors.brand : AppColors.outline,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.add_rounded,
                  size: 22,
                  color: enabled ? Colors.white : AppColors.inkFaint,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
