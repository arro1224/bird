import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_asset_catalog.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/storage_target_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_controls.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_row.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:flutter/material.dart';

class CopyBackupSettingsPage extends StatelessWidget {
  const CopyBackupSettingsPage({super.key, required this.controller});

  final BirdSettingsController controller;

  @override
  Widget build(BuildContext context) => BirdSettingsScaffold(
    title: '复制与备份',
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
          const BirdSettingsSectionLabel('复制设置'),
          BirdSettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('默认复制方式', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: AppSpacing.xxs),
                const Text('复制任务的默认选项', style: TextStyle(color: AppColors.mutedInk)),
                const SizedBox(height: AppSpacing.md),
                SegmentedButton<BirdCopyMode>(
                  showSelectedIcon: true,
                  segments: BirdCopyMode.values.map((mode) => ButtonSegment(value: mode, label: Text(mode.label))).toList(),
                  selected: {controller.copyMode},
                  onSelectionChanged: (value) => controller.setCopyMode(value.first),
                ),
                const SizedBox(height: AppSpacing.md),
                const Divider(height: 1),
                BirdSettingsRow(
                  title: 'XMP / 后期标记策略',
                  subtitle: '保存审阅结果的 XMP 与标记',
                  titleFontSize: 15,
                  trailing: BirdSettingsDropdownFrame(
                    width: 174,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: controller.xmpStrategy,
                        items: const [
                          DropdownMenuItem(
                            value: '生成同名 XMP（推荐）',
                            child: Text('生成同名 XMP（推荐）', style: TextStyle(fontSize: 13)),
                          ),
                          DropdownMenuItem(
                            value: '写入照片元数据',
                            child: Text('写入照片元数据', style: TextStyle(fontSize: 13)),
                          ),
                          DropdownMenuItem(
                            value: '不导出标记',
                            child: Text('不导出标记', style: TextStyle(fontSize: 13)),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) controller.setXmpStrategy(value);
                        },
                      ),
                    ),
                  ),
                  minHeight: 60,
                ),
                BirdSettingsRow(
                  title: '复制完成后校验文件完整性',
                  subtitle: '校验复制的文件是否完整可读',
                  trailing: Switch(value: controller.verifyCopies, onChanged: controller.setVerifyCopies),
                  minHeight: 60,
                ),
                BirdSettingsRow(
                  title: '电量不足时提醒',
                  subtitle: '复制或备份时电量过低提醒',
                  trailing: Switch(value: controller.lowBatteryReminder, onChanged: controller.setLowBatteryReminder),
                  minHeight: 60,
                ),
                BirdSettingsRow(
                  title: '复制完成自动打开任务报告',
                  subtitle: '查看此次复制任务的详细报告',
                  trailing: Switch(value: controller.autoOpenReport, onChanged: controller.setAutoOpenReport),
                  minHeight: 60,
                ),
                const BirdSettingsRow(
                  title: '命名与目录规则',
                  subtitle: '设置复制时的文件命名与目录结构',
                  showDivider: false,
                  trailing: BirdChevron(),
                  minHeight: 60,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const BirdSettingsSectionLabel('默认目标位置'),
          BirdSettingsCard(
            padding: EdgeInsets.zero,
            child: InkWell(
              key: const Key('copy-target'),
              onTap: () => _openStorageTarget(context),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    const SizedBox.square(
                      dimension: 52,
                      child: Center(
                        child: BirdSettingsAssetIcon(
                          BirdSettingsAssetCatalog.storageHealthy,
                          label: '存储目标',
                          size: 36,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_targetName(controller.selectedStorageId), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(_targetCapacity(controller.selectedStorageId), style: const TextStyle(color: AppColors.mutedInk)),
                        ],
                      ),
                    ),
                    const BirdChevron(),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          BirdSettingsPrimaryButton(
            key: const Key('copy-save'),
            label: '保存备份设置',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('设置已保存在当前前端演示会话中')),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _openStorageTarget(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => StorageTargetPage(controller: controller),
      ),
    );
  }

  String _targetName(String id) => switch (id) {
    't7' => 'Samsung T7 Shield',
    'local' => '本机存储',
    _ => '移动硬盘（E:）',
  };

  String _targetCapacity(String id) => switch (id) {
    't7' => '剩余 1.20 TB / 共 2.00 TB',
    'local' => '剩余 118 GB / 共 256 GB',
    _ => '剩余 1.82 TB / 共 2.00 TB',
  };
}
