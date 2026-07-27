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
            style: TextStyle(color: AppColors.forestDeep, fontSize: 31, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text('所有文件已校验通过', style: TextStyle(color: AppColors.mutedInk, fontSize: 17)),
          const SizedBox(height: 16),
          TaskSurface(
            child: Column(
              children: [
                _row(Icons.photo_library_outlined, '复制照片', '${result.photoCount.toString().replaceAll('2012', '2,012')} 张'),
                _row(Icons.storage_outlined, '数据大小', '${result.dataSizeGb} GB'),
                _row(Icons.description_outlined, 'XMP 文件', '${result.xmpCount.toString().replaceAll('2012', '2,012')} 个'),
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
            filled: false,
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => const SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Text('演示复制报告\n2,012 个文件校验通过，0 个失败。', style: TextStyle(fontSize: 18, height: 1.7)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TaskActionButton('进入相册', onPressed: onOpenAlbum ?? () {}),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value, {bool divider = true}) => Column(
    children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: AppColors.forestPrimary),
        title: Text(label),
        trailing: Text(
          value,
          style: const TextStyle(color: AppColors.forestPrimary, fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      if (divider) const Divider(height: 1),
    ],
  );
}
