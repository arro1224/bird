import 'dart:async';

import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/help_center_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_controls.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_row.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:flutter/material.dart';

class DiagnosticRecordsPage extends StatefulWidget {
  const DiagnosticRecordsPage({super.key, this.initialCrashTab = false});

  final bool initialCrashTab;

  @override
  State<DiagnosticRecordsPage> createState() => _DiagnosticRecordsPageState();
}

class _DiagnosticRecordsPageState extends State<DiagnosticRecordsPage> {
  late bool _crashTab = widget.initialCrashTab;

  @override
  Widget build(BuildContext context) => BirdSettingsScaffold(
    title: '诊断记录',
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.settingsPageHorizontal,
        AppSpacing.md,
        AppSpacing.settingsPageHorizontal,
        AppSpacing.xl,
      ),
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('错误记录')),
            ButtonSegment(value: true, label: Text('崩溃记录')),
          ],
          selected: {_crashTab},
          onSelectionChanged: (value) => setState(() => _crashTab = value.first),
          style: BirdSettingsControlStyles.segmented,
        ),
        const SizedBox(height: AppSpacing.md),
        BirdSettingsCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.forestSoft,
                  child: Icon(Icons.check_rounded, color: AppColors.forestPrimary, size: 34),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  _crashTab ? '暂无崩溃记录' : '暂无错误记录',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.forestDeep,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                const Text(
                  '设备和应用运行正常\n新的异常会自动记录在这里',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.mutedInk),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        BirdSettingsCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: BirdSettingsRow(
            title: '导出全部记录',
            subtitle: '生成可供技术支持查看的诊断文件',
            showDivider: false,
            leading: const Icon(Icons.ios_share_rounded, color: AppColors.forestPrimary),
            trailing: const BirdChevron(),
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('诊断记录已准备导出')),
            ),
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
        const BirdSettingsCard(
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
              _ArticleSection('我们使用的数据', '连接状态、设备版本和诊断日志仅用于完成设备管理、故障排查与体验优化。'),
              _ArticleSection('您的控制权', '您可以随时清理应用缓存、导出诊断信息，或断开当前设备。', last: true),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.md),
        BirdSettingsCard(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            children: [
              BirdSettingsRow(
                title: '诊断信息说明',
                subtitle: '查看导出文件包含的内容',
                leading: Icon(Icons.description_outlined, color: AppColors.forestPrimary),
              ),
              BirdSettingsRow(
                title: '本地存储说明',
                subtitle: '查看照片与缓存的保存位置',
                leading: Icon(Icons.storage_outlined, color: AppColors.forestPrimary),
                showDivider: false,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class OpenSourceLicensesPage extends StatelessWidget {
  const OpenSourceLicensesPage({super.key});

  static const packages = [
    ('Flutter', 'BSD 3-Clause License · Google LLC'),
    ('go_router', 'BSD 3-Clause License · Flutter Authors'),
    ('flutter_bloc', 'MIT License · Felix Angelov'),
    ('mobile_scanner', 'BSD 3-Clause License · Community'),
    ('package_info_plus', 'BSD 3-Clause License · Flutter Community'),
  ];

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
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.md),
                child: Text(
                  '第三方组件',
                  style: TextStyle(color: AppColors.forestDeep, fontWeight: FontWeight.w800),
                ),
              ),
              for (var i = 0; i < packages.length; i++)
                BirdSettingsRow(
                  title: packages[i].$1,
                  subtitle: packages[i].$2,
                  showDivider: i != packages.length - 1,
                ),
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
              Expanded(child: Text('完整许可文本随应用发布，并保留各项目的版权与许可声明。')),
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
      children: [
        const BirdSettingsCard(
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
              Text('版本 2.1.0 · 设备协议 BirdBox v1', style: TextStyle(color: AppColors.mutedInk)),
              SizedBox(height: AppSpacing.md),
              BirdSettingsRow(title: '产品定位', trailing: Text('拍鸟盒子移动控制端')),
              BirdSettingsRow(title: '设备支持', trailing: Text('拍鸟伴侣 K7')),
              BirdSettingsRow(title: 'AI 模型', trailing: Text('BirdAI 3.0.2'), showDivider: false),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        BirdSettingsCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            children: [
              BirdSettingsRow(
                title: '隐私说明',
                leading: const Icon(Icons.shield_outlined, color: AppColors.forestPrimary),
                trailing: const BirdChevron(),
                onTap: () => _open(context, const PrivacyNoticePage()),
              ),
              BirdSettingsRow(
                title: '开源许可',
                leading: const Icon(Icons.code_rounded, color: AppColors.forestPrimary),
                trailing: const BirdChevron(),
                onTap: () => _open(context, const OpenSourceLicensesPage()),
              ),
              BirdSettingsRow(
                title: '帮助中心',
                leading: const Icon(Icons.help_outline_rounded, color: AppColors.forestPrimary),
                trailing: const BirdChevron(),
                showDivider: false,
                onTap: () => _open(context, const HelpCenterPage()),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Center(
          child: Text('© 2026 拍鸟伴侣', style: TextStyle(color: AppColors.mutedInk)),
        ),
      ],
    ),
  );

  static void _open(BuildContext context, Widget page) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => page),
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
