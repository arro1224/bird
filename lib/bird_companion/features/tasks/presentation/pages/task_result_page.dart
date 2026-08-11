import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_design_components.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_page_frame.dart';
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
      child: Column(
        children: [
          Container(
            key: const Key('task-result-success-badge'),
            width: 94,
            height: 94,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success,
              border: Border.all(color: Colors.white.withValues(alpha: .92), width: 8),
              boxShadow: const [BoxShadow(color: Color(0x220E351D), blurRadius: 18, offset: Offset(0, 7))],
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 58),
          ),
          const SizedBox(height: 18),
          const Text(
            '照片复制完成',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.forestDeep, fontSize: 31, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text('所有文件已校验通过', style: TextStyle(color: AppColors.mutedInk, fontSize: 17)),
          const SizedBox(height: 16),
          TaskSurface(
            child: Column(
              children: [
                _row(
                  Icons.photo_library_outlined,
                  '复制照片',
                  '${_count(result.photoCount)} 张',
                ),
                _row(Icons.storage_outlined, '数据大小', '${result.dataSizeGb} GB'),
                _row(
                  Icons.description_outlined,
                  'XMP 文件',
                  '${_count(result.xmpCount)} 个',
                ),
                _row(Icons.schedule_outlined, '耗时', '${result.elapsedMinutes} 分 ${result.elapsedSeconds} 秒', divider: false),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: AppColors.forestSoft.withValues(alpha: .58), borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                const Icon(Icons.eco_outlined, key: Key('task-result-review-icon'), color: AppColors.forestPrimary, size: 34),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '待人工确认 ${result.pendingReviewCount} 张照片，\n可以继续进入相册进行复核。',
                    style: const TextStyle(color: AppColors.forestPrimary, height: 1.55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TaskActionButton(
            '查看复制报告',
            key: const Key('task-result-open-report'),
            filled: false,
            onPressed: () => _showReport(
              context,
              photoCount: result.photoCount,
              pendingReviewCount: result.pendingReviewCount,
            ),
          ),
          const SizedBox(height: 10),
          TaskActionButton(
            '进入相册',
            key: const Key('task-result-open-album'),
            onPressed: onOpenAlbum ?? () {},
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _count(int value) {
    final digits = value.toString();
    return digits.replaceAllMapped(
      RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }

  Future<void> _showReport(
    BuildContext context, {
    required int photoCount,
    required int pendingReviewCount,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.paper,
    builder: (sheetContext) => SafeArea(
      child: FractionallySizedBox(
        heightFactor: .72,
        child: ListView(
          key: const Key('task-result-report-scroll'),
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            const Text(
              '复制报告',
              style: TextStyle(
                color: AppColors.forestDeep,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${_count(photoCount)} 个文件已完成，待复核 ${_count(pendingReviewCount)} 个。',
              style: const TextStyle(fontSize: 18, height: 1.7),
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('task-result-close-report'),
              onPressed: () => Navigator.pop(sheetContext),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _row(IconData icon, String label, String value, {bool divider = true}) => TaskMetricRow(
    icon: icon,
    label: label,
    value: value,
    divider: divider,
    valueStyle: const TextStyle(color: AppColors.forestPrimary, fontSize: 20, fontWeight: FontWeight.w700),
  );
}
