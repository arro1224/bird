import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_controls.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_row.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_sheet.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/device_information_pages.dart';
import 'package:flutter/material.dart';

class SystemLogsPage extends StatefulWidget {
  const SystemLogsPage({super.key});

  @override
  State<SystemLogsPage> createState() => _SystemLogsPageState();
}

class _SystemLogsPageState extends State<SystemLogsPage> {
  BirdCompanionDependencies? _dependencies;
  DeviceStatus? _status;
  final String _appVersion = '2.1.0';
  String? _downloadedPath;
  var _initialized = false;
  var _loading = false;
  var _exporting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _dependencies = context.dependOnInheritedWidgetOfExactType<BirdCompanionScope>()?.dependencies;
    if (_dependencies != null) unawaited(_loadStatus());
  }

  Future<void> _loadStatus() async {
    final dependencies = _dependencies;
    if (dependencies == null || _loading) return;
    setState(() => _loading = true);
    try {
      final status = await dependencies.deviceRepository.fetchStatus();
      if (mounted) setState(() => _status = status);
    } catch (_) {
      // A disconnected box keeps the approved placeholders instead of
      // replacing the page with an error panel.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    final status = _status;
    return BirdSettingsScaffold(
      title: '系统与日志',
      titleFontSize: 20,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.settingsPageHorizontal,
          0,
          AppSpacing.settingsPageHorizontal,
          AppSpacing.lg,
        ),
        children: [
          _SectionCard(
            label: '版本信息',
            rows: [
              _LogRow(
                Icons.view_in_ar_outlined,
                '软件版本',
                '当前应用软件版本',
                value: _appVersion,
                onTap: _showVersionDetails,
              ),
              _LogRow(
                Icons.memory_rounded,
                '固件版本',
                '设备固件版本',
                value: status?.softwareVersion ?? '1.2.4',
                onTap: _showVersionDetails,
              ),
              _LogRow(
                Icons.psychology_outlined,
                '模型版本',
                'AI 模型版本',
                value: status?.modelVersion ?? 'BirdAI 3.0.2',
                onTap: _showVersionDetails,
                showDivider: false,
              ),
            ],
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: AppSpacing.xs),
          _SectionCard(
            label: '日志与诊断',
            rows: [
              _LogRow(
                Icons.description_outlined,
                '导出设备日志',
                '导出设备运行日志',
                onTap: _exporting ? null : () => _exportLogs(scope: 'device'),
              ),
              _LogRow(
                Icons.archive_outlined,
                '导出诊断包',
                '导出包含日志与诊断信息的压缩包',
                onTap: _exporting ? null : _exportLogs,
              ),
              _LogRow(
                Icons.warning_amber_rounded,
                '错误记录',
                '查看历史错误记录',
                onTap: () => _openPage(const DiagnosticRecordsPage()),
              ),
              _LogRow(
                Icons.file_present_outlined,
                '最近崩溃记录',
                '查看最近崩溃的详细信息',
                onTap: () => _openPage(const DiagnosticRecordsPage(initialCrashTab: true)),
                showDivider: false,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          _SectionCard(
            label: '存储与缓存',
            rows: [
              _LogRow(
                Icons.cleaning_services_outlined,
                '清理缓存',
                '清理应用缓存数据，释放存储空间',
                onTap: () => _openPage(const StorageCachePage()),
              ),
              _LogRow(
                Icons.image_outlined,
                '查看离线缩略图占用',
                '查看离线缩略图占用的存储空间',
                onTap: () => _openPage(const StorageCachePage()),
                showDivider: false,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          _SectionCard(
            label: '隐私与说明',
            rows: [
              _LogRow(
                Icons.shield_outlined,
                '隐私说明',
                '查看隐私政策与数据使用说明',
                onTap: () => _openPage(const PrivacyNoticePage()),
              ),
              _LogRow(
                Icons.code_rounded,
                '开源许可',
                '查看第三方开源组件许可信息',
                onTap: () => _openPage(const OpenSourceLicensesPage()),
              ),
              _LogRow(
                Icons.info_outline_rounded,
                '关于应用',
                '应用介绍与开发者信息',
                onTap: () => _openPage(const AboutBirdAppPage()),
                showDivider: false,
              ),
            ],
          ),
          if (_downloadedPath != null) ...[
            const SizedBox(height: AppSpacing.xs),
            BirdSettingsCard(
              child: SelectableText(
                '本地文件位置：$_downloadedPath',
                key: const Key('logs-local-file-path'),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          const BirdSettingsCard(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xxs,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.forestPrimary,
                  size: 20,
                ),
                SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    '导出的日志与诊断信息仅用于问题排查与优化，不会用于其他用途。',
                    style: TextStyle(
                      color: AppColors.mutedInk,
                      fontSize: 9.5,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          BirdSettingsPrimaryButton(
            key: const Key('logs-export-package'),
            label: _exporting ? '正在生成诊断包' : '导出诊断包',
            icon: Icons.archive_outlined,
            height: 44,
            onPressed: _exporting ? null : _exportLogs,
          ),
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
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  Future<void> _showVersionDetails() => showBirdSettingsSheet<void>(
    context: context,
    title: '版本详情',
    child: BirdSettingsCard(
      child: Column(
        children: [
          BirdSettingsValueRow(label: '应用版本', value: _appVersion),
          BirdSettingsValueRow(
            label: '固件版本',
            value: _status?.softwareVersion ?? '1.2.4',
          ),
          BirdSettingsValueRow(
            label: 'AI 模型',
            value: _status?.modelVersion ?? 'BirdAI 3.0.2',
          ),
          const BirdSettingsValueRow(label: '设备协议', value: 'BirdBox v1'),
          const BirdSettingsValueRow(
            label: '更新时间',
            value: '2025-07-16',
            showDivider: false,
          ),
        ],
      ),
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.label, required this.rows});

  final String label;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => BirdSettingsCard(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.xxs,
            left: AppSpacing.xxs,
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.forestDeep,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
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
    this.title,
    this.subtitle, {
    this.value,
    this.onTap,
    this.showDivider = true,
  });

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
    minHeight: 42,
    titleFontSize: 12,
    subtitleFontSize: 10,
    titleColor: AppColors.ink,
    titleFontWeight: FontWeight.w600,
    leadingSize: 40,
    leadingGap: AppSpacing.xs,
    leading: CircleAvatar(
      radius: 14,
      backgroundColor: AppColors.forestSoft,
      child: Icon(icon, color: AppColors.forestPrimary, size: 17),
    ),
    trailing: value == null
        ? const BirdChevron(color: AppColors.forestPrimary)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 92),
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.mutedInk,
                    fontSize: 13,
                  ),
                ),
              ),
              const BirdChevron(color: AppColors.forestPrimary),
            ],
          ),
    onTap: onTap,
    showDivider: showDivider,
  );
}
