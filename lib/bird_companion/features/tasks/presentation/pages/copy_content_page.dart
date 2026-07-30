import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_design_components.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_page_frame.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_scene_art.dart';
import 'package:flutter/material.dart';

class CopyContentPage extends StatelessWidget {
  const CopyContentPage({super.key, required this.controller, this.onNext});

  final TaskExperienceController controller;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (_, _) => TaskPageFrame(
      title: '复制照片',
      subtitle: '步骤 2 / 3 · 选择复制内容',
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
      bottomNavigationBar: TaskBottomActions(
        primaryLabel: '下一步',
        onPrimary: onNext ?? () {},
        secondaryLabel: '保存为默认策略',
        onSecondary: () {},
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TaskSurface(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            radius: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _BlockTitle('复制范围'),
                const SizedBox(height: 12),
                _CopyModeCard(
                  mode: CopyMode.keep,
                  title: '仅复制保留照片',
                  subtitle: '${_count(controller.copyEstimate.keptCount)} 张',
                  selected: controller.copyMode == CopyMode.keep,
                  recommended: true,
                  onTap: () => controller.selectCopyMode(CopyMode.keep),
                ),
                const SizedBox(height: 10),
                _CopyModeCard(
                  mode: CopyMode.all,
                  title: '复制全部照片',
                  subtitle: '${_count(controller.copyEstimate.totalPhotoCount)} 张',
                  selected: controller.copyMode == CopyMode.all,
                  onTap: () => controller.selectCopyMode(CopyMode.all),
                ),
                const SizedBox(height: 10),
                _CopyModeCard(
                  mode: CopyMode.dual,
                  title: '双轨复制',
                  subtitle: '保留照片 + 完整备份',
                  selected: controller.copyMode == CopyMode.dual,
                  onTap: () => controller.selectCopyMode(CopyMode.dual),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TaskSurface(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            radius: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _BlockTitle('目标存储'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const TaskExternalDriveArt(size: 60),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            controller.copyEstimate.targetName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${controller.copyEstimate.availableSpaceTb.toStringAsFixed(1)} TB 可用',
                            style: const TextStyle(
                              color: AppColors.mutedInk,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: LinearProgressIndicator(
                              minHeight: 6,
                              value: (controller.copyEstimate.spaceGb / (controller.copyEstimate.availableSpaceTb * 1024)).clamp(0, 1),
                              color: AppColors.forestPrimary,
                              backgroundColor: AppColors.divider,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '预计使用：${controller.copyEstimate.spaceGb.toStringAsFixed(1)} GB',
                            style: const TextStyle(
                              color: AppColors.mutedInk,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TaskSurface(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            radius: 18,
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _BlockTitle('生成同名 XMP'),
                      SizedBox(height: 8),
                      Text(
                        '写入评分、标签、鸟种和保留状态',
                        style: TextStyle(
                          color: AppColors.mutedInk,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Switch(
                  value: controller.generateXmp,
                  onChanged: controller.setGenerateXmp,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    ),
  );

  static String _count(int value) => value.toString().replaceAllMapped(
    RegExp(r'(\\d)(?=(\\d{3})+$)'),
    (match) => '${match[1]},',
  );
}

class _BlockTitle extends StatelessWidget {
  const _BlockTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: AppColors.forestDeep,
      fontSize: 20,
      fontWeight: FontWeight.w800,
      height: 1.15,
    ),
  );
}

class _CopyModeCard extends StatelessWidget {
  const _CopyModeCard({
    required this.mode,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.recommended = false,
  });

  final CopyMode mode;
  final String title;
  final String subtitle;
  final bool selected;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('copy-mode-card'),
    color: selected ? AppColors.forestSoft.withValues(alpha: .18) : Colors.transparent,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.forestPrimary : AppColors.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppColors.forestPrimary : AppColors.mutedInk,
              size: 30,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.forestDeep,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.mutedInk,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            if (recommended)
              Container(
                key: const Key('copy-recommended-badge'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.forestSoft.withValues(alpha: .64),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Text(
                  '推荐',
                  style: TextStyle(
                    color: AppColors.forestPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
