import 'package:aves/bird_companion/core/widgets/navigation_guard.dart';
import 'dart:async';
import 'package:aves/bird_companion/app/app_dependencies.dart';

import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_asset_catalog.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/help_center_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_controls.dart';

import 'package:aves/bird_companion/features/connection/presentation/widgets/ble_diagnostic_export_dialog.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_row.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';

import 'package:flutter/material.dart';

class NetworkDiagnosticsPage extends StatefulWidget {
  const NetworkDiagnosticsPage({super.key});

  @override
  State<NetworkDiagnosticsPage> createState() => _NetworkDiagnosticsPageState();
}

class _NetworkDiagnosticsPageState extends State<NetworkDiagnosticsPage> {
  BirdCompanionDependencies? _dependencies;
  DeviceStatus? _status;
  Object? _error;
  int? _latencyMilliseconds;
  bool _checking = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = context.dependOnInheritedWidgetOfExactType<BirdCompanionScope>()?.dependencies;
    if (identical(_dependencies, dependencies)) return;
    _dependencies = dependencies;
    if (dependencies != null) unawaited(_recheck());
  }

  @override
  Widget build(BuildContext context) {
    final production = _dependencies != null;
    final demoMode = !production;
    final connected = !demoMode && (_dependencies!.deviceSessionCubit.state.isConnected && _status != null && _error == null);
    final errorMessage = _error == null ? null : UserMessageMapper.fromError(_error!);
    return BirdSettingsScaffold(
      title: '网络诊断',
      actions: [
        IconButton(
          tooltip: '帮助',
          onPressed: _openHelpCenter,
          icon: const Icon(
            Icons.help_outline_rounded,
            color: AppColors.forestPrimary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
      ],
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
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 27,
                      backgroundColor: connected ? AppColors.success : AppColors.warning,
                      child: Icon(
                        connected ? Icons.check_rounded : Icons.priority_high_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _checking
                                ? '正在重新检测网络…'
                            : demoMode
                                ? '页面演示模式'
                                : connected
                                ? '网络连接正常'
                                : '网络连接需要处理',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            errorMessage?.message ?? (demoMode ? '当前仅展示页面示例，连接真实盒子后才会读取实际状态' : (connected ? '盒子状态接口响应正常，可继续传输照片' : '请重新连接盒子后再次检测')),
                            style: const TextStyle(color: AppColors.mutedInk),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_latencyMilliseconds != null && _status != null) _MetricRow(
                  Icons.schedule_rounded,
                  '响应时间',
                  '$_latencyMilliseconds ms',
                  showDivider: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          BirdSettingsCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Column(
              children: [
                BirdSettingsRow(
                  key: const Key('network-recheck'),
                  title: '重新检测网络',
                  subtitle: '再次检测当前网络状态',
                  leading: const BirdSettingsAssetIcon(
                    BirdSettingsAssetCatalog.reconnect,
                    label: '重新检测网络',
                    size: 28,
                  ),
                  trailing: _checking
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const BirdChevron(),
                  onTap: _checking ? null : _recheck,
                ),
                BirdSettingsRow(
                  key: const Key('network-export-diagnostics'),
                  title: '导出诊断报告',
                  subtitle: '包含本次连接记录，便于反馈排查',
                  leading: const Icon(Icons.ios_share_rounded, color: AppColors.forestPrimary),
                  trailing: const BirdChevron(),
                  onTap: _exportDiagnostics,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          BirdSettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '连接链路检查',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.xs),
                _CheckRow(
                  Icons.devices_rounded,
                  '盒子会话',
                  demoMode ? '未连接真实盒子' : (connected ? '当前设备会话已建立' : '尚未建立可用设备会话'),
                  passed: connected,
                ),
                _CheckRow(
                  Icons.api_rounded,
                  '状态接口',
                  demoMode ? '未读取真实状态' : (_status != null ? '已成功读取盒子状态' : '未能读取盒子状态'),
                  passed: _status != null,
                ),
                _CheckRow(
                  Icons.sync_rounded,
                  '实时状态更新',
                  demoMode ? '未检测' : (_dependencies?.eventClient.currentState.name == 'connected' ? '已接收状态更新' : '未建立实时连接'),
                  passed: !demoMode && _dependencies!.eventClient.currentState.name == 'connected',
                  showDivider: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _recheck() async {
    setState(() => _checking = true);
    final dependencies = _dependencies;
    if (dependencies == null) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted) setState(() => _checking = false);
      return;
    }
    final stopwatch = Stopwatch()..start();
    try {
      final status = await dependencies.deviceRepository.fetchStatus().timeout(
        const Duration(seconds: 4),
      );
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _status = status;
        _error = null;
        _latencyMilliseconds = stopwatch.elapsedMilliseconds;
      });
    } catch (error) {
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _status = null;
        _error = error;
        _latencyMilliseconds = stopwatch.elapsedMilliseconds;
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _openHelpCenter() => guardBirdNavigation(
    context,
    () => Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => const HelpCenterPage())),
  );

  Future<void> _exportDiagnostics() async {
    final dependencies = _dependencies;
    if (dependencies == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('当前没有可导出的连接记录。')));
      return;
    }
    try {
      final export = await dependencies.bleDiagnosticSnapshotService.capture(
        dependencies.connectionAttempts.activeId,
        includeRetainedHistory: true,
      );
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      await showDialog<void>(
        context: context,
        builder: (_) => BleDiagnosticExportDialog(
          export: export,
          title: '回传网络诊断',
          files: dependencies.bleDiagnosticFilePlatform,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('诊断报告导出失败，请稍后重试。')));
      }
    }
  }
}


class _MetricRow extends StatelessWidget {
  const _MetricRow(
    this.icon,
    this.label,
    this.value, {
    this.showDivider = true,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool showDivider;
  @override
  Widget build(BuildContext context) => BirdSettingsRow(
    title: label,
    leading: Icon(icon, color: AppColors.forestPrimary),
    trailing: Text(
      value,
      style: TextStyle(
        color: value == '良好' ? AppColors.success : AppColors.mutedInk,
        fontSize: 15,
      ),
    ),
    showDivider: showDivider,
  );
}

class _CheckRow extends StatelessWidget {
  const _CheckRow(
    this.icon,
    this.title,
    this.subtitle, {
    required this.passed,
    this.showDivider = true,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool passed;
  final bool showDivider;
  @override
  Widget build(BuildContext context) => BirdSettingsRow(
    title: title,
    subtitle: subtitle,
    leading: CircleAvatar(
      backgroundColor: AppColors.forestSoft,
      child: Icon(icon, color: AppColors.forestPrimary),
    ),
    trailing: Icon(
      passed ? Icons.check_circle_rounded : Icons.error_outline_rounded,
      color: passed ? AppColors.success : AppColors.warning,
    ),
    showDivider: showDivider,
  );
}
