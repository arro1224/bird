import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_design_components.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_page_frame.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_scene_art.dart';
import 'package:flutter/material.dart';

class TaskResultPage extends StatelessWidget {
  const TaskResultPage({super.key, required this.controller, this.onOpenAlbum});

  final TaskExperienceController controller;
  final VoidCallback? onOpenAlbum;

  @override
  Widget build(BuildContext context) {
    final result = controller.completion;
    return TaskPageFrame(
      title: '任务完成',
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
      bottomNavigationBar: TaskBottomActions(
        primaryLabel: '进入相册',
        onPrimary: onOpenAlbum ?? () {},
        secondaryLabel: '查看复制报告',
        onSecondary: () => _showReport(context),
        secondaryFirst: true,
      ),
      child: Column(
        children: [
          const SizedBox(height: 2),
          const TaskSuccessBadge(
            key: Key('task-result-success-badge'),
            size: 94,
          ),
          const SizedBox(height: 18),
          const Text(
            '照片复制完成',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.forestDeep,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '所有文件已校验通过',
            style: TextStyle(color: AppColors.mutedInk, fontSize: 17),
          ),
          const SizedBox(height: 16),
          TaskSurface(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
            radius: 20,
            child: Column(
              children: [
                _MetricRow(
                  icon: Icons.photo_library_outlined,
                  label: '复制照片',
                  value: _count(result.photoCount),
                  unit: '张',
                ),
                _MetricRow(
                  icon: Icons.storage_outlined,
                  label: '数据大小',
                  value: result.dataSizeGb.toStringAsFixed(1),
                  unit: 'GB',
                ),
                _MetricRow(
                  icon: Icons.description_outlined,
                  label: 'XMP 文件',
                  value: _count(result.xmpCount),
                  unit: '个',
                ),
                _MetricRow(
                  icon: Icons.schedule_outlined,
                  label: '耗时',
                  value: '${result.elapsedMinutes}',
                  unit: '分 ${result.elapsedSeconds} 秒',
                  divider: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: AppColors.forestSoft.withValues(alpha: .56),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.eco_outlined,
                  key: Key('task-result-review-icon'),
                  color: AppColors.forestPrimary,
                  size: 32,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '待人工确认 ${result.pendingReviewCount} 张照片，\n可以继续进入相册进行复核。',
                    style: const TextStyle(
                      color: AppColors.forestPrimary,
                      fontSize: 15,
                      height: 1.55,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showReport(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    builder: (_) => const SafeArea(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Text(
          '演示复制报告\n2,012 个文件校验通过，0 个失败。',
          style: TextStyle(fontSize: 18, height: 1.7),
        ),
      ),
    ),
  );

  String _count(int value) => value.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]},',
  );
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    this.divider = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final bool divider;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 68),
        child: Row(
          children: [
            Icon(icon, color: AppColors.forestPrimary, size: 29),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              flex: 2,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: value,
                      style: const TextStyle(
                        color: AppColors.forestPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    TextSpan(
                      text: ' $unit',
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
      if (divider) const Divider(height: 1),
    ],
  );
}
