import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_controls.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_row.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_sheet.dart';
import 'package:flutter/material.dart';

/// 复制与备份设置（迁移对照文档 §3.7）。
///
/// v1 正式模式固定强校验，不提供「完整性校验」开关；不再有跨批次全局默认
/// 目标盘；XMP 策略合并为「随副本保存审阅信息」总开关 + 「支持时写入副本」。
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
                Text('默认复制范围', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: AppSpacing.xxs),
                const Text('仅作为新任务的初始选项，最终确认页不可跳过', style: TextStyle(color: AppColors.mutedInk)),
                const SizedBox(height: AppSpacing.md),
                SegmentedButton<BirdCopyMode>(
                  showSelectedIcon: false,
                  style: BirdSettingsControlStyles.segmented,
                  segments: BirdCopyMode.values.map((mode) => ButtonSegment(value: mode, label: Text(mode.label))).toList(),
                  selected: {controller.copyMode},
                  onSelectionChanged: (value) => controller.setCopyMode(value.first),
                ),
                const SizedBox(height: AppSpacing.md),
                const Divider(height: 1),
                BirdSettingsRow(
                  title: '随副本保存审阅信息',
                  subtitle: '向目标盘输出 XMP 与审阅 CSV',
                  titleFontSize: 16,
                  trailing: Switch(value: controller.reviewExportEnabled, onChanged: controller.setReviewExportEnabled),
                  minHeight: 60,
                ),
                BirdSettingsRow(
                  title: '支持时写入副本',
                  subtitle: '向 JPEG/HEIF/TIFF 副本嵌入标准字段；RAW 只写 sidecar，永不修改相机卡',
                  titleFontSize: 16,
                  trailing: Switch(
                    value: controller.embedReviewMetadata,
                    onChanged: controller.reviewExportEnabled
                        ? controller.setEmbedReviewMetadata
                        : null,
                  ),
                  minHeight: 60,
                ),
                BirdSettingsRow(
                  title: '电量不足时提醒',
                  subtitle: '复制或备份时电量过低提醒',
                  titleFontSize: 16,
                  trailing: Switch(value: controller.lowBatteryReminder, onChanged: controller.setLowBatteryReminder),
                  minHeight: 60,
                ),
                BirdSettingsRow(
                  title: '复制完成自动打开任务报告',
                  subtitle: '查看此次复制任务的详细报告',
                  titleFontSize: 16,
                  trailing: Switch(value: controller.autoOpenReport, onChanged: controller.setAutoOpenReport),
                  minHeight: 60,
                ),
                BirdSettingsRow(
                  key: const Key('copy-naming-policy'),
                  title: '命名与目录规则',
                  subtitle: '目标盘按 BirdBox/年/月/日 保存原文件名',
                  titleFontSize: 16,
                  showDivider: false,
                  trailing: const Icon(
                    Icons.lock_outline_rounded,
                    color: AppColors.mutedInk,
                  ),
                  minHeight: 60,
                  onTap: () => _showNamingPolicy(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const BirdSettingsCard(
            child: Row(
              children: [
                Icon(Icons.verified_outlined, color: AppColors.forestPrimary),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'v1 复制正式模式固定开启文件校验，不提供关闭选项。目标设备选择在每次任务中单独确认。',
                    style: TextStyle(color: AppColors.mutedInk, fontSize: 12.5, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _showNamingPolicy(BuildContext context) => showBirdSettingsSheet<void>(
    context: context,
    title: '命名与目录规则',
    child: const BirdSettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '保留原始文件名',
            style: TextStyle(color: AppColors.forestDeep, fontSize: 17, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: AppSpacing.xs),
          Text('复制时不修改相机生成的文件名，避免与原始素材失去对应关系。', style: TextStyle(color: AppColors.mutedInk, height: 1.5)),
          SizedBox(height: AppSpacing.md),
          Text(
            '固定目录规则',
            style: TextStyle(color: AppColors.forestDeep, fontSize: 17, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: AppSpacing.xs),
          Text('目标盘写入 BirdBox/年/月/日/原始文件名，日期取自拍摄时间。', style: TextStyle(color: AppColors.mutedInk, height: 1.5)),
          SizedBox(height: AppSpacing.md),
          Text(
            '协议限制',
            style: TextStyle(color: AppColors.forestDeep, fontSize: 17, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: AppSpacing.xs),
          Text('BirdBox v1 不支持自定义重命名模板，不修改原扩展名大小写。', style: TextStyle(color: AppColors.mutedInk, height: 1.5)),
        ],
      ),
    ),
    footer: BirdSettingsPrimaryButton(
      label: '知道了',
      onPressed: () => Navigator.pop(context),
    ),
  );
}
