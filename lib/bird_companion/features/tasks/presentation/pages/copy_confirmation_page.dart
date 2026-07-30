import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_design_components.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_page_frame.dart';
import 'package:flutter/material.dart';

class CopyConfirmationPage extends StatelessWidget {
  const CopyConfirmationPage({
    super.key,
    required this.controller,
    this.onStart,
    this.onModify,
  });

  final TaskExperienceController controller;
  final VoidCallback? onStart;
  final VoidCallback? onModify;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (_, _) {
      final canStart = controller.copyEstimate.targetOnline && controller.copyEstimate.hasEnoughSpace;
      return TaskPageFrame(
        title: '确认复制',
        subtitle: '步骤 3 / 3 · 最后确认',
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
        bottomNavigationBar: TaskBottomActions(
          primaryLabel: '开始复制',
          onPrimary: canStart ? onStart ?? () {} : null,
          secondaryLabel: '返回修改',
          onSecondary: onModify ?? () => Navigator.maybePop(context),
        ),
        child: Column(
          children: [
            TaskSurface(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
              radius: 20,
              child: Column(
                children: [
                  _SummaryRow(
                    icon: Icons.photo_outlined,
                    label: '复制范围',
                    value: _modeLabel(controller.copyMode),
                  ),
                  _SummaryRow(
                    icon: Icons.image_outlined,
                    label: '照片数量',
                    value: _count(controller.copyEstimate.photoCount),
                    unit: '张',
                  ),
                  _SummaryRow(
                    icon: Icons.save_alt_outlined,
                    label: '预计使用空间',
                    value: controller.copyEstimate.spaceGb.toStringAsFixed(1),
                    unit: 'GB',
                  ),
                  _SummaryRow(
                    icon: Icons.storage_outlined,
                    label: '目标存储',
                    value: controller.copyEstimate.targetName,
                    valueSize: 16,
                  ),
                  _SummaryRow(
                    icon: Icons.description_outlined,
                    label: 'XMP',
                    value: controller.generateXmp ? '已开启' : '已关闭',
                    divider: false,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              key: const Key('copy-safety-notice'),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: AppColors.forestSoft.withValues(alpha: .48),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    color: AppColors.forestPrimary,
                    size: 30,
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      '不会修改或删除相机存储卡中的原始照片。\n复制期间请勿拔出目标存储设备。',
                      style: TextStyle(
                        color: AppColors.forestPrimary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TaskSurface(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
              radius: 18,
              child: Column(
                children: [
                  _SummaryRow(
                    icon: Icons.schedule_outlined,
                    label: '预计耗时',
                    value: '约 ${controller.copyEstimate.estimatedMinutes}',
                    unit: '分钟',
                  ),
                  InkWell(
                    onTap: () => controller.setVerifyAfterCopy(
                      !controller.verifyAfterCopy,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 62,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.shield_outlined,
                            color: AppColors.forestPrimary,
                            size: 28,
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Text(
                              '复制完成后校验',
                              style: TextStyle(
                                color: AppColors.ink,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            controller.verifyAfterCopy ? '开启' : '关闭',
                            key: const Key('copy-verification-status'),
                            style: const TextStyle(
                              color: AppColors.forestPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!canStart) ...[
              const SizedBox(height: 16),
              Text(
                controller.copyEstimate.targetOnline ? '目标存储空间不足，请更换目标位置' : '目标存储已断开，请重新连接后再开始复制',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );

  String _modeLabel(CopyMode mode) => switch (mode) {
    CopyMode.keep => '仅保留照片',
    CopyMode.all => '全部照片',
    CopyMode.dual => '双轨复制',
  };

  String _count(int value) => value.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]},',
  );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    this.unit,
    this.divider = true,
    this.valueSize = 24,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? unit;
  final bool divider;
  final double valueSize;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 62),
        child: Row(
          children: [
            Icon(icon, color: AppColors.forestPrimary, size: 28),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: value,
                      style: TextStyle(
                        color: AppColors.forestPrimary,
                        fontSize: valueSize > 20 ? valueSize - 2 : valueSize,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (unit != null)
                      TextSpan(
                        text: ' $unit',
                        style: const TextStyle(
                          color: AppColors.mutedInk,
                          fontSize: 14,
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
