import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/core/diagnostics/phone_diagnostic_widgets.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_controls.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_row.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:flutter/material.dart';

class DiagnosticRecordsPage extends StatelessWidget {
  const DiagnosticRecordsPage({super.key});

  @override
  Widget build(BuildContext context) => BirdSettingsScaffold(
    title: '异常说明',
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.settingsPageHorizontal,
        AppSpacing.md,
        AppSpacing.settingsPageHorizontal,
        AppSpacing.xl,
      ),
      children: const [
        BirdSettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ArticleSection('操作失败', '某项功能未能完成，但应用仍可继续使用。连接或配网失败时，可导出手机诊断包，查看本机保留的扫描和连接过程。'),
              _ArticleSection('应用崩溃', '应用意外关闭或被系统终止。崩溃记录由手机系统管理，本应用不提供历史崩溃列表。', last: true),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.md),
        BirdSettingsCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: AppColors.forestPrimary),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '手机诊断包不是错误/崩溃历史记录，也不包含盒子运行日志。盒子日志需单独从设备导出。',
                  style: TextStyle(color: AppColors.mutedInk, height: 1.45),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class StorageCachePage extends StatefulWidget {
  const StorageCachePage({super.key});

  @override
  State<StorageCachePage> createState() => _StorageCachePageState();
}

class _StorageCachePageState extends State<StorageCachePage> {
  var _cacheMb = 286;
  var _clearing = false;

  Future<void> _clear() async {
    if (_clearing) return;
    setState(() => _clearing = true);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    setState(() {
      _cacheMb = 0;
      _clearing = false;
    });
  }

  @override
  Widget build(BuildContext context) => BirdSettingsScaffold(
    title: '存储与缓存',
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.settingsPageHorizontal,
        AppSpacing.md,
        AppSpacing.settingsPageHorizontal,
        AppSpacing.xl,
      ),
      children: [
        BirdSettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '应用缓存',
                style: TextStyle(color: AppColors.forestDeep, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '$_cacheMb MB',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.forestPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              LinearProgressIndicator(
                value: _cacheMb / 1200,
                minHeight: 8,
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text('包括临时预览图、诊断文件和界面缓存', style: TextStyle(color: AppColors.mutedInk)),
              const SizedBox(height: AppSpacing.md),
              BirdSettingsOutlineButton(
                label: _clearing ? '正在清理' : '清理应用缓存',
                icon: Icons.cleaning_services_outlined,
                onPressed: _clearing ? null : _clear,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        BirdSettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '缓存明细',
                style: TextStyle(color: AppColors.forestDeep, fontWeight: FontWeight.w800),
              ),
              BirdSettingsRow(title: '离线缩略图', trailing: Text('214 MB')),
              BirdSettingsRow(title: '诊断与日志', trailing: Text('48 MB')),
              BirdSettingsRow(title: '其他缓存', trailing: Text('24 MB'), showDivider: false),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const BirdSettingsCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: AppColors.forestPrimary),
              SizedBox(width: AppSpacing.sm),
              Expanded(child: Text('清理缓存不会删除盒子中的原始照片、审阅结果或任务记录。')),
            ],
          ),
        ),
      ],
    ),
  );
}

class PrivacyNoticePage extends StatelessWidget {
  const PrivacyNoticePage({super.key});

  @override
  Widget build(BuildContext context) => BirdSettingsScaffold(
    title: '隐私说明',
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.settingsPageHorizontal,
        AppSpacing.md,
        AppSpacing.settingsPageHorizontal,
        AppSpacing.xl,
      ),
      children: const [
        BirdSettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ArticleSection('本地优先', '拍鸟伴侣仅在当前局域网内与拍鸟盒子通信。原始照片默认保存在盒子或您选择的目标设备中。'),
              _ArticleSection('诊断信息', '手机诊断包包含本机保留的扫描、蓝牙连接和网络请求记录；只有您主动导出后才会生成文件。', last: true),
            ],
          ),
        ),
      ],
    ),
  );
}

class OpenSourceLicensesPage extends StatelessWidget {
  const OpenSourceLicensesPage({super.key});

  @override
  Widget build(BuildContext context) => BirdSettingsScaffold(
    title: '开源许可',
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.settingsPageHorizontal,
        AppSpacing.md,
        AppSpacing.settingsPageHorizontal,
        AppSpacing.xl,
      ),
      children: [
        BirdSettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '本应用使用的开源组件及其许可文本由 Flutter 根据实际依赖生成。',
                style: TextStyle(color: AppColors.mutedInk, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.md),
              BirdSettingsOutlineButton(
                label: '查看全部许可',
                icon: Icons.code_rounded,
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: '拍鸟伴侣',
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class AboutBirdAppPage extends StatelessWidget {
  const AboutBirdAppPage({super.key});

  @override
  Widget build(BuildContext context) => BirdSettingsScaffold(
    title: '关于应用',
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.settingsPageHorizontal,
        AppSpacing.md,
        AppSpacing.settingsPageHorizontal,
        AppSpacing.xl,
      ),
      children: const [
        BirdSettingsCard(
          child: Column(
            children: [
              CircleAvatar(
                radius: 38,
                backgroundColor: AppColors.forestPrimary,
                child: Text(
                  '鸟',
                  style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800),
                ),
              ),
              SizedBox(height: AppSpacing.sm),
              Text('拍鸟伴侣', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              AppBuildIdentityLabel(),
              SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.md),
        Center(
          child: Text('© 2026 拍鸟伴侣', style: TextStyle(color: AppColors.mutedInk)),
        ),
      ],
    ),
  );
}

class AddStorageTargetPage extends StatefulWidget {
  const AddStorageTargetPage({super.key});

  @override
  State<AddStorageTargetPage> createState() => _AddStorageTargetPageState();
}

class _AddStorageTargetPageState extends State<AddStorageTargetPage> {
  var _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    setState(() => _checking = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('暂未检测到新的存储设备')),
    );
  }

  @override
  Widget build(BuildContext context) => BirdSettingsScaffold(
    title: '新增目标设备',
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.settingsPageHorizontal,
        AppSpacing.md,
        AppSpacing.settingsPageHorizontal,
        AppSpacing.xl,
      ),
      children: [
        const BirdSettingsCard(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.forestSoft,
                  child: Icon(Icons.add_rounded, size: 34, color: AppColors.forestPrimary),
                ),
                SizedBox(height: AppSpacing.sm),
                Text('连接新的存储设备', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                Text(
                  '将移动硬盘或存储卡连接到拍鸟盒子\n系统会自动检测可用空间',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.mutedInk),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const BirdSettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '连接步骤',
                style: TextStyle(color: AppColors.forestDeep, fontWeight: FontWeight.w800),
              ),
              _StepRow(1, '连接存储设备', '使用盒子支持的 USB 或读卡器接口'),
              _StepRow(2, '等待设备识别', '通常需要 3-10 秒，请勿重复插拔'),
              _StepRow(3, '选择并设为默认', '检测成功后返回目标位置列表'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        BirdSettingsOutlineButton(
          label: _checking ? '正在检测' : '重新检测',
          icon: Icons.refresh_rounded,
          onPressed: _checking ? null : _check,
        ),
        const SizedBox(height: AppSpacing.md),
        const BirdSettingsCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: AppColors.forestPrimary),
              SizedBox(width: AppSpacing.sm),
              Expanded(child: Text('建议使用 exFAT 格式，并确保目标设备有足够可用空间。')),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ArticleSection extends StatelessWidget {
  const _ArticleSection(this.title, this.body, {this.last = false});
  final String title;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: last ? 0 : AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(color: AppColors.forestDeep, fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(body, style: const TextStyle(color: AppColors.mutedInk, height: 1.55)),
      ],
    ),
  );
}

class _StepRow extends StatelessWidget {
  const _StepRow(this.number, this.title, this.subtitle);
  final int number;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: AppColors.forestPrimary,
          child: Text(
            '$number',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(subtitle, style: const TextStyle(color: AppColors.mutedInk)),
            ],
          ),
        ),
      ],
    ),
  );
}
