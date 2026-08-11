import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_controls.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/device_information_pages.dart';
import 'package:flutter/material.dart';

class StorageTargetPage extends StatelessWidget {
  const StorageTargetPage({super.key, required this.controller});

  final BirdSettingsController controller;

  static const _targets = <_StorageTarget>[
    _StorageTarget('removable-e', '移动硬盘（E:）', '剩余 1.82 TB / 共 2.00 TB', .52, Icons.storage_rounded, true),
    _StorageTarget('t7', 'Samsung T7 Shield', '剩余 1.20 TB / 共 2.00 TB', .55, Icons.save_outlined, false),
    _StorageTarget('local', '本机存储', '剩余 118 GB / 共 256 GB', .57, Icons.phone_android_rounded, false),
  ];

  @override
  Widget build(BuildContext context) => BirdSettingsScaffold(
    title: '选择目标位置',
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.settingsPageHorizontal,
          AppSpacing.md,
          AppSpacing.settingsPageHorizontal,
          AppSpacing.xl,
        ),
        children: [
          Text('请选择复制或导出的目标存储位置', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.mutedInk)),
          const SizedBox(height: AppSpacing.lg),
          for (final target in _targets) ...[
            _StorageTargetCard(
              key: Key('storage-${target.id}'),
              target: target,
              selected: controller.selectedStorageId == target.id,
              onTap: () => controller.setStorageTarget(target.id),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          BirdSettingsCard(
            padding: EdgeInsets.zero,
            child: InkWell(
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const AddStorageTargetPage(),
                ),
              ),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
              child: const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 56,
                      child: Center(child: Icon(Icons.add_box_outlined, size: 38, color: AppColors.forestPrimary)),
                    ),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('新增目标设备', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                          SizedBox(height: AppSpacing.xxs),
                          Text('连接新的存储设备', style: TextStyle(color: AppColors.mutedInk)),
                        ],
                      ),
                    ),
                    BirdChevron(),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const BirdSettingsCard(
            borderColor: Color(0xFFE8C78B),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 34),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('复制前请确认目标存储空间充足', style: TextStyle(fontWeight: FontWeight.w700)),
                      SizedBox(height: AppSpacing.xxs),
                      Text('空间不足可能导致复制失败或数据不完整', style: TextStyle(color: AppColors.mutedInk)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          BirdSettingsPrimaryButton(
            key: const Key('storage-confirm'),
            label: '设为默认目标位置',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    ),
  );
}

class _StorageTargetCard extends StatelessWidget {
  const _StorageTargetCard({super.key, required this.target, required this.selected, required this.onTap});
  final _StorageTarget target;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => BirdSettingsCard(
    borderColor: selected ? AppColors.forestSoft : null,
    padding: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox.square(
              dimension: 56,
              child: Center(
                child: Icon(target.icon, size: 38, color: AppColors.forestPrimary),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(target.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      if (target.recommended)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                          decoration: BoxDecoration(color: AppColors.forestSoft, borderRadius: BorderRadius.circular(AppSpacing.radiusSmall)),
                          child: const Text(
                            '推荐',
                            style: TextStyle(color: AppColors.forestPrimary, fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(target.capacity, style: const TextStyle(color: AppColors.mutedInk)),
                  const SizedBox(height: AppSpacing.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: target.used,
                      minHeight: 7,
                      color: AppColors.forestPrimary,
                      backgroundColor: AppColors.forestSoft,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            selected
                ? const CircleAvatar(
                    radius: 21,
                    backgroundColor: AppColors.success,
                    child: Icon(Icons.check_rounded, color: Colors.white),
                  )
                : Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.mutedInk.withValues(alpha: .45), width: 2),
                    ),
                  ),
          ],
        ),
      ),
    ),
  );
}

class _StorageTarget {
  const _StorageTarget(this.id, this.name, this.capacity, this.used, this.icon, this.recommended);
  final String id;
  final String name;
  final String capacity;
  final double used;
  final IconData icon;
  final bool recommended;
}
