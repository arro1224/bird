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
                  minHeight: 86,
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
                BirdSettingsRow(
                  key: const Key('photo-default-filter'),
                  title: '筛选默认条件',
                  minHeight: 86,
                  onTap: () => _showDefaultFilterSheet(context),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        controller.defaultPhotoFilter.label,
                        style: const TextStyle(color: AppColors.mutedInk),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      const BirdChevron(),
                    ],
                  ),
                ),
                BirdSettingsRow(
                  title: '仅显示鸟类照片',
                  minHeight: 86,
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

  Future<void> _showDefaultFilterSheet(BuildContext context) async {
    final selected = await showModalBottomSheet<BirdDefaultPhotoFilter>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.settingsSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusSheet),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.settingsPageHorizontal,
              AppSpacing.sm,
              AppSpacing.settingsPageHorizontal,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '新打开相册的默认筛选',
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                const Text(
                  '已保存的相册视图仍优先恢复，不会被默认条件覆盖。',
                  style: TextStyle(color: AppColors.mutedInk),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final option in BirdDefaultPhotoFilter.values)
                  ListTile(
                    key: ValueKey('default-filter-${option.name}'),
                    title: Text(option.label),
                    trailing: option == controller.defaultPhotoFilter
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.success,
                          )
                        : null,
                    onTap: () => Navigator.pop(sheetContext, option),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected != null) controller.setDefaultPhotoFilter(selected);
  }
}
