import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_controls.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_row.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:flutter/material.dart';

class SystemLogsPage extends StatelessWidget {
  const SystemLogsPage({super.key});

  @override
  Widget build(BuildContext context) => BirdSettingsScaffold(
    title: '系统与日志',
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.settingsPageHorizontal,
        0,
        AppSpacing.settingsPageHorizontal,
        AppSpacing.xs,
      ),
      children: [
        const _SectionCard(
          label: '版本信息',
          rows: [
            _LogRow(Icons.inventory_2_outlined, '软件版本', '当前应用软件版本', value: '2.1.0'),
            _LogRow(Icons.memory_rounded, '固件版本', '设备固件版本', value: '1.2.4'),
            _LogRow(Icons.psychology_outlined, '模型版本', 'AI 模型版本', value: 'BirdAI 3.0.2', showDivider: false),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        _SectionCard(
          label: '日志与诊断',
          rows: [
            _LogRow(Icons.description_outlined, '导出设备日志', '导出设备运行日志', onTap: () => _message(context)),
            _LogRow(Icons.archive_outlined, '导出诊断包', '导出包含日志与诊断信息的压缩包', onTap: () => _message(context)),
            const _LogRow(Icons.warning_amber_rounded, '错误记录', '查看历史错误记录'),
            const _LogRow(Icons.report_gmailerrorred_rounded, '最近崩溃记录', '查看最近崩溃的详细信息', showDivider: false),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        const _SectionCard(
          label: '存储与缓存',
          rows: [
            _LogRow(Icons.cleaning_services_outlined, '清理缓存', '清理应用缓存数据，释放存储空间'),
            _LogRow(Icons.photo_library_outlined, '查看离线缩略图占用', '查看离线缩略图占用的存储空间', showDivider: false),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        const _SectionCard(
          label: '隐私与说明',
          rows: [
            _LogRow(Icons.shield_outlined, '隐私说明', '查看隐私政策与数据使用说明'),
            _LogRow(Icons.code_rounded, '开源许可', '查看第三方开源组件许可信息'),
            _LogRow(Icons.info_outline_rounded, '关于应用', '应用介绍与开发者信息', showDivider: false),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        const BirdSettingsCard(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: AppColors.forestPrimary),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '导出的日志与诊断信息仅用于问题排查与优化，不会用于其他用途。',
                  style: TextStyle(fontSize: 12.5, height: 1.25),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        BirdSettingsPrimaryButton(
          key: const Key('logs-export-package'),
          label: '导出诊断包',
          icon: Icons.archive_outlined,
          onPressed: () => _message(context),
        ),
      ],
    ),
  );

  void _message(BuildContext context) => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('演示模式不会生成真实诊断文件')),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.label, required this.rows});
  final String label;
  final List<Widget> rows;
  @override
  Widget build(BuildContext context) => BirdSettingsCard(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            label,
            style: const TextStyle(color: AppColors.mutedInk, fontWeight: FontWeight.w600),
          ),
        ),
        ...rows,
      ],
    ),
  );
}

class _LogRow extends StatelessWidget {
  const _LogRow(this.icon, this.title, this.subtitle, {this.value, this.onTap, this.showDivider = true});
  final IconData icon;
  final String title;
  final String subtitle;
  final String? value;
  final VoidCallback? onTap;
  final bool showDivider;
  @override
  Widget build(BuildContext context) => BirdSettingsRow(
    title: title,
    subtitle: subtitle,
    leading: CircleAvatar(
      backgroundColor: AppColors.forestSoft,
      child: Icon(icon, color: AppColors.forestPrimary),
    ),
    trailing: value == null
        ? const BirdChevron()
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value!, style: const TextStyle(color: AppColors.mutedInk)),
              const BirdChevron(),
            ],
          ),
    onTap: onTap,
    showDivider: showDivider,
  );
}
