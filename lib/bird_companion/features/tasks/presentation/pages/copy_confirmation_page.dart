import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_design_components.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_page_frame.dart';
import 'package:flutter/material.dart';

class CopyConfirmationPage extends StatelessWidget {
  const CopyConfirmationPage({super.key, required this.controller, this.onStart, this.onModify});
  final TaskExperienceController controller;
  final VoidCallback? onStart;
  final VoidCallback? onModify;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (_, _) => TaskPageFrame(
      title: '确认复制',
      subtitle: '步骤 3 / 3 · 最后确认',
      child: Column(
        children: [
          TaskSurface(
            child: Column(
              children: [
                _row(
                  Icons.image_outlined,
                  '复制范围',
                  controller.copyMode.name == 'keep'
                      ? '仅保留照片'
                      : controller.copyMode.name == 'all'
                      ? '全部照片'
                      : '双轨复制',
                ),
                _row(Icons.collections_outlined, '总照片数', _count(controller.copyEstimate.totalPhotoCount)),
                _row(Icons.favorite_border_rounded, '已确认保留', _count(controller.copyEstimate.keptCount)),
                _row(Icons.rate_review_outlined, '待审阅', _count(controller.copyEstimate.pendingReviewCount)),
                _row(Icons.delete_outline_rounded, '已丢弃', _count(controller.copyEstimate.discardedCount)),
                _row(Icons.photo_outlined, '本次复制', _count(controller.copyEstimate.photoCount)),
                _row(Icons.storage_outlined, '预计使用空间', '${controller.copyEstimate.spaceGb} GB'),
                _row(Icons.storage_rounded, '目标存储', controller.copyEstimate.targetName),
                _row(Icons.description_outlined, 'XMP', controller.generateXmp ? '已开启' : '已关闭', divider: false),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            key: const Key('copy-safety-notice'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.forestSoft.withValues(alpha: .42),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(Icons.verified_user_outlined, color: AppColors.forestPrimary, size: 30),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '不会修改或删除相机存储卡中的原始照片。\n复制期间请勿拔出目标存储设备。',
                    style: TextStyle(color: AppColors.forestPrimary, height: 1.55, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TaskSurface(
            child: Column(
              children: [
                _row(Icons.schedule_outlined, '预计耗时', '约 ${controller.copyEstimate.estimatedMinutes} 分钟'),
                InkWell(
                  onTap: () => controller.setVerifyAfterCopy(!controller.verifyAfterCopy),
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 58,
                    child: Row(
                      children: [
                        const Icon(Icons.verified_user_outlined, color: AppColors.forestPrimary),
                        const SizedBox(width: 16),
                        const Expanded(child: Text('复制完成后校验')),
                        Text(
                          controller.verifyAfterCopy ? '开启' : '关闭',
                          key: const Key('copy-verification-status'),
                          style: const TextStyle(color: AppColors.forestPrimary, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (!controller.copyEstimate.targetOnline || !controller.copyEstimate.hasEnoughSpace) ...[
            Text(
              controller.copyEstimate.targetOnline ? '目标存储空间不足，请更换目标位置' : '目标存储已断开，请重新连接后再开始复制',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: controller.copyEstimate.targetOnline && controller.copyEstimate.hasEnoughSpace ? onStart ?? () {} : null,
              child: const Text('开始复制'),
            ),
          ),
          const SizedBox(height: 10),
          TaskActionButton('返回修改', filled: false, onPressed: onModify ?? () => Navigator.maybePop(context)),
        ],
      ),
    ),
  );
  Widget _row(IconData icon, String label, String value, {bool divider = true}) => Column(
    children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: AppColors.forestPrimary),
        title: Text(label),
        trailing: SizedBox(
          width: 176,
          child: Text(
            value,
            maxLines: 2,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.forestPrimary, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      if (divider) const Divider(height: 1),
    ],
  );

  String _count(int value) => '${value.toString().replaceAllMapped(RegExp(r"(\d)(?=(\d{3})+$)"), (match) => '${match[1]},')} 张';
}
