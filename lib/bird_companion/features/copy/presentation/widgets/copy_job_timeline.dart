import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_timeline.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_design_components.dart';
import 'package:flutter/material.dart';

/// 复制任务七阶段时间线（迁移对照 §3.5）。
///
/// 只渲染 [CopyTimeline.compute] 的结果；阶段 5/6 无后端信号时恒 pending，
/// OpenAPI 冻结后在 compute 单点接入。
class CopyJobTimeline extends StatelessWidget {
  const CopyJobTimeline({super.key, required this.timeline});

  final CopyTimeline timeline;

  @override
  Widget build(BuildContext context) => TaskSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TaskSectionTitle('复制阶段'),
        for (final (index, stage) in timeline.stages.indexed)
          _StageRow(
            stage: stage,
            isLast: index == timeline.stages.length - 1,
          ),
      ],
    ),
  );
}

class _StageRow extends StatelessWidget {
  const _StageRow({required this.stage, required this.isLast});

  final CopyTimelineStage stage;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (stage.status) {
      CopyStageStatus.pending => (Icons.radio_button_unchecked, AppColors.inkMuted),
      CopyStageStatus.active => (Icons.adjust, AppColors.forestPrimary),
      CopyStageStatus.done => (Icons.check_circle, AppColors.success),
      CopyStageStatus.failed => (Icons.cancel, AppColors.danger),
      CopyStageStatus.skipped => (Icons.remove_circle_outline, AppColors.inkMuted),
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Icon(icon, size: 22, color: color),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: stage.status == CopyStageStatus.done
                        ? AppColors.success.withValues(alpha: .45)
                        : AppColors.outline,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      stage.label,
                      style: TextStyle(
                        fontWeight: stage.status == CopyStageStatus.active
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: switch (stage.status) {
                          CopyStageStatus.pending ||
                          CopyStageStatus.skipped => AppColors.inkMuted,
                          CopyStageStatus.failed => AppColors.danger,
                          _ => AppColors.forestDeep,
                        },
                      ),
                    ),
                  ),
                  if (stage.status == CopyStageStatus.active)
                    const Text('进行中', style: TextStyle(fontSize: 12, color: AppColors.forestPrimary))
                  else if (stage.status == CopyStageStatus.failed)
                    const Text('失败', style: TextStyle(fontSize: 12, color: AppColors.danger))
                  else if (stage.status == CopyStageStatus.skipped)
                    const Text('已跳过', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
