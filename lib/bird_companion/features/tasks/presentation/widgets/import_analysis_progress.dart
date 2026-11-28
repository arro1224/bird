import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:flutter/material.dart';

/// Keeps the real import summary visible even when it finishes between polls.
class ImportAnalysisProgress extends StatelessWidget {
  const ImportAnalysisProgress({super.key, required this.progress, required this.connection});
  final ImportAnalysisTaskProgress progress;
  final TaskConnectionState connection;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('import-analysis-stages'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _stage('导入与索引', progress.importTask),
      const SizedBox(height: 6),
      _stage('AI 识别', progress.analysisTask),
      const SizedBox(height: 6),
      const Text('浏览图片由盒子另行准备，不计入识别进度。', style: TextStyle(color: AppColors.mutedInk, fontSize: 12)),
    ],
  );

  Widget _stage(String label, TaskSummary task) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$label · ${_status(task)}', key: ValueKey('workflow-stage-${task.id}')),
      if (!task.waitingForImport) Text('${task.processed} / ${task.total} 张 · ${task.progressPercent}%'),
      Text(task.freshnessFor(connection), style: const TextStyle(color: AppColors.mutedInk, fontSize: 12)),
    ],
  );

  String _status(TaskSummary task) => task.pendingCancellation
      ? '取消待确认'
      : task.waitingForImport
      ? '等待导入完成'
      : task.isFinishing
      ? '等待盒子确认完成'
      : switch (task.state) {
          TaskRunState.queued => '等待开始',
          TaskRunState.running => '进行中',
          TaskRunState.paused => '已暂停',
          TaskRunState.completed => '已完成',
          TaskRunState.cancelled => '已取消',
          TaskRunState.failed => '失败',
        };
}
