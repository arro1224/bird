import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_controls.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_row.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:flutter/material.dart';

class SystemLogsPage extends StatefulWidget {
  const SystemLogsPage({super.key});

  @override
  State<SystemLogsPage> createState() => _SystemLogsPageState();
}

class _SystemLogsPageState extends State<SystemLogsPage> {
  BirdCompanionDependencies? _dependencies;
  DeviceStatus? _status;
  Object? _error;
  String? _downloadedPath;
  var _loading = false;
  var _exporting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependencies != null) return;
    final scope = context.dependOnInheritedWidgetOfExactType<BirdCompanionScope>();
    _dependencies = scope?.dependencies;
    if (_dependencies != null) _loadStatus();
  }

  Future<void> _loadStatus() async {
    final dependencies = _dependencies;
    if (dependencies == null || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await dependencies.deviceRepository.fetchStatus();
      if (!mounted) return;
      setState(() => _status = status);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportLogs({String scope = 'device_and_jobs'}) async {
    final dependencies = _dependencies;
    if (dependencies == null || _exporting) return;
    setState(() {
      _exporting = true;
      _error = null;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('日志已保存到 ${downloaded.file.path}')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
      final message = UserMessageMapper.fromError(error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${message.title}：${message.message}')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final errorMessage = _error == null ? null : UserMessageMapper.fromError(_error!);
    return BirdSettingsScaffold(
      title: '系统与日志',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.settingsPageHorizontal,
          0,
          AppSpacing.settingsPageHorizontal,
          AppSpacing.xs,
        ),
        children: [
          _SectionCard(
            label: '盒子版本信息',
            rows: [
              _LogRow(
                Icons.api_outlined,
                '设备 API 版本',
                '当前连接设备报告的协议版本',
                value: status?.connection.apiVersion ?? '未连接',
                onTap: _loadStatus,
              ),
              _LogRow(
                Icons.memory_rounded,
                '固件版本',
                '设备状态接口报告的软件/固件版本',
                value: status?.softwareVersion ?? '未提供',
                onTap: _loadStatus,
              ),
              _LogRow(
                Icons.psychology_outlined,
                '模型版本',
                '设备状态接口报告的 AI 模型版本',
                value: status?.modelVersion ?? '未提供',
                onTap: _loadStatus,
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
                '生成并下载设备运行日志',
                onTap: _exporting ? null : () => _exportLogs(scope: 'device'),
              ),
              _LogRow(
                Icons.archive_outlined,
                '导出诊断包',
                '生成包含设备与任务日志的诊断文件',
                onTap: _exporting ? null : _exportLogs,
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
          if (errorMessage != null) ...[
            const SizedBox(height: AppSpacing.xs),
            BirdSettingsCard(
              child: Text(
                '${errorMessage.title}：${errorMessage.message}',
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          const BirdSettingsCard(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.forestPrimary,
                ),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '导出的日志与诊断信息仅用于问题排查；下载地址为短时签名地址，过期后会自动重新申请。',
                    style: TextStyle(fontSize: 12.5, height: 1.25),
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
            onPressed: _dependencies == null || _exporting ? null : _exportLogs,
          ),
        ],
      ),
    );
  }
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
            style: const TextStyle(
              color: AppColors.mutedInk,
              fontWeight: FontWeight.w600,
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
