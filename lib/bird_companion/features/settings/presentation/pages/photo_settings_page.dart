import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_controls.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_row.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:flutter/material.dart';

class PhotoSettingsPage extends StatelessWidget {
  const PhotoSettingsPage({super.key, required this.controller});

  final BirdSettingsController controller;

  @override
  Widget build(BuildContext context) => BirdSettingsScaffold(
    title: '照片设置',
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
          const BirdSettingsSectionLabel('照片设置'),
          BirdSettingsCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Column(
              children: [
                BirdSettingsRow(
                  key: const Key('photo-sort'),
                  title: '默认照片排序',
                  onTap: () => _showSortSheet(context),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(controller.sortOrder.label, style: const TextStyle(color: AppColors.mutedInk)),
                      const SizedBox(width: AppSpacing.xs),
                      const BirdChevron(),
                    ],
                  ),
                ),
                const BirdSettingsRow(
                  title: '筛选默认条件',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('未设置', style: TextStyle(color: AppColors.mutedInk)),
                      SizedBox(width: AppSpacing.xs),
                      BirdChevron(),
                    ],
                  ),
                ),
                BirdSettingsRow(
                  title: '仅显示鸟类照片',
                  showDivider: false,
                  trailing: Switch(value: controller.birdPhotosOnly, onChanged: controller.setBirdPhotosOnly),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _showSortSheet(BuildContext context) async {
    final selected = await showModalBottomSheet<BirdPhotoSortOrder>(
      context: context,
      showDragHandle: false,
      isScrollControlled: true,
      backgroundColor: AppColors.settingsSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusSheet)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.settingsPageHorizontal,
            AppSpacing.lg,
            AppSpacing.settingsPageHorizontal,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const SizedBox(width: AppSpacing.minimumControl),
                  Expanded(
                    child: Text(
                      '默认照片排序',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final item in BirdPhotoSortOrder.values)
                InkWell(
                  onTap: () => Navigator.pop(context, item),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 62),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: item == controller.sortOrder ? AppColors.forestSoft.withValues(alpha: .55) : null,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: Text(item.label, style: Theme.of(context).textTheme.titleMedium)),
                        if (item == controller.sortOrder)
                          const CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.success,
                            child: Icon(Icons.check_rounded, color: Colors.white, size: 22),
                          )
                        else
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.mutedInk.withValues(alpha: .45), width: 2),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) controller.setSortOrder(selected);
  }
}
