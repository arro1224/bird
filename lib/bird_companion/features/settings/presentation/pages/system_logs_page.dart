import 'package:aves/bird_companion/core/widgets/navigation_guard.dart';
import 'dart:async';
import 'package:aves/bird_companion/core/diagnostics/phone_diagnostic_widgets.dart';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_controls.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_row.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/device_information_pages.dart';
import 'package:flutter/material.dart';

class SystemLogsPage extends StatefulWidget {
  const SystemLogsPage({super.key});

  @override
  State<SystemLogsPage> createState() => _SystemLogsPageState();
}

class _SystemLogsPageState extends State<SystemLogsPage> {
  BirdCompanionDependencies? _dependencies;
  String? _downloadedPath;
  var _initialized = false;
  var _exporting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _dependencies = context.dependOnInheritedWidgetOfExactType<BirdCompanionScope>()?.dependencies;
  }

  Future<void> _exportLogs({String scope = 'device_and_jobs'}) async {
    final dependencies = _dependencies;
    if (dependencies == null) {
      _showMessage('请先连接拍鸟盒子后再导出诊断信息');
      return;
    }
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _downloadedPath = null;
    });
    try {
      final downloaded = await dependencies.logDownloadService.downloadWithRefresh(
        () => dependencies.jobRepository.exportLogs(scope: scope),
      );
      if (await downloaded.file.length() <= 0) {
        throw StateError('The downloaded diagnostic file is empty.');
      }
      if (!mounted) return;
      setState(() => _downloadedPath = downloaded.file.path);
      _showMessage('日志已保存到 ${downloaded.file.path}');
    } catch (error) {
      if (!mounted) return;
      final message = UserMessageMapper.fromError(error);
      _showMessage('${message.title}：${message.message}');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BirdSettingsScaffold(
      title: '系统与日志',
      titleFontSize: 25,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.settingsPageHorizontal,
          0,
          AppSpacing.settingsPageHorizontal,
          AppSpacing.xl,
        ),
        children: [
          _SectionCard(
            label: '日志与诊断',
            icon: Icons.receipt_long_outlined,
            rows: [
              _LogRow(
                Icons.description_outlined,
                '导出盒子运行日志',
                subtitle: '从拍鸟盒子下载设备运行记录',
                onTap: _exporting ? null : () => _exportLogs(scope: 'device'),
              ),
              _LogRow(
                Icons.phone_android_rounded,
                '导出手机诊断包',
                key: const Key('logs-export-package'),
                subtitle: '扫描与连接过程；断联时也可导出',
                onTap: () => showPhoneDiagnostics(context),
              ),
              _LogRow(
                Icons.warning_amber_rounded,
                '异常说明',
                subtitle: '了解操作失败与应用崩溃的区别',
                onTap: () => _openPage(const DiagnosticRecordsPage()),
                showDivider: false,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const BirdSettingsCard(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: AppColors.forestPrimary, size: 22),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '盒子运行日志记录设备侧运行情况；手机连接诊断记录手机端蓝牙和网络过程。两类文件来源不同，按问题分别导出。',
                    style: TextStyle(color: AppColors.mutedInk, fontSize: 13, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _SectionCard(
            label: '应用信息',
            icon: Icons.shield_outlined,
            rows: [
              _LogRow(
                Icons.info_outline_rounded,
                '关于应用',
                key: const Key('logs-about'),
                onTap: () => _openPage(const AboutBirdAppPage()),
              ),
              _LogRow(
                Icons.code_rounded,
                '开源许可',
                key: const Key('logs-licenses'),
                onTap: () => _openPage(const OpenSourceLicensesPage()),
              ),
              _LogRow(
                Icons.shield_outlined,
                '隐私说明',
                key: const Key('logs-privacy'),
                onTap: () => _openPage(const PrivacyNoticePage()),
                showDivider: false,
              ),
            ],
          ),
          if (_downloadedPath != null) ...[
            const SizedBox(height: AppSpacing.sm),
            BirdSettingsCard(
              child: SelectableText(
                '本地文件位置：$_downloadedPath',
                key: const Key('logs-local-file-path'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _openPage(Widget page) {
    guardBirdNavigation(
      context,
      () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => page),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.label, required this.icon, required this.rows});

  final String label;
  final IconData icon;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => BirdSettingsCard(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
          child: Row(
            children: [
              Icon(icon, color: AppColors.forestPrimary, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.forestDeep,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        ...rows,
      ],
    ),
  );
}

class _LogRow extends StatelessWidget {
  const _LogRow(
    this.icon,
    this.title, {
    super.key,
    this.subtitle,
    this.onTap,
    this.showDivider = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) => BirdSettingsRow(
    title: title,
    subtitle: subtitle,
    minHeight: 64,
    titleFontSize: 16,
    titleColor: AppColors.ink,
    titleFontWeight: FontWeight.w600,
    leadingSize: 44,
    leadingGap: AppSpacing.md,
    leading: Icon(icon, color: AppColors.forestPrimary, size: 23),
    trailing: const BirdChevron(color: AppColors.forestPrimary),
    onTap: onTap,
    showDivider: showDivider,
  );
}
