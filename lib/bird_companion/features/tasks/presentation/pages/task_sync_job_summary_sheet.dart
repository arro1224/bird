import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_design_components.dart';
import 'package:flutter/material.dart';

class TaskSyncJobSummarySheet extends StatelessWidget {
  const TaskSyncJobSummarySheet({super.key, required this.task});

  final TaskSummary task;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      key: const Key('task-sync-job-summary'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: AppColors.forestSoft,
                child: Icon(
                  Icons.cloud_done_outlined,
                  color: AppColors.forestPrimary,
                  size: 28,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  '同步任务摘要',
                  style: TextStyle(
                    color: AppColors.forestDeep,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TaskSurface(
            child: Column(
              children: [
                _row('已处理', '${task.processed} 项'),
                _row('任务总数', '${task.total} 项'),
                _row('失败', '${task.failedCount ?? 0} 项'),
                _row(
                  '完成时间',
                  _formatTime(task.finishedAt),
                  divider: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.amberLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '盒子当前没有提供可按任务恢复的逐项同步结果；这里仅显示任务详情中的权威汇总，不推断冲突或待处理项。',
              style: TextStyle(color: AppColors.ink, height: 1.4),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ),
        ],
      ),
    ),
  );

  static Widget _row(
    String label,
    String value, {
    bool divider = true,
  }) => Column(
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: AppColors.mutedInk),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.forestDeep,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      if (divider) const Divider(height: 1),
    ],
  );

  static String _formatTime(DateTime? value) {
    if (value == null) return '盒子未提供';
    final local = value.toLocal();
    String two(int part) => part.toString().padLeft(2, '0');
    return '${local.month}月${local.day}日 ${two(local.hour)}:${two(local.minute)}';
  }
}
