import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_asset_catalog.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/system_logs_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/help_center_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_controls.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_row.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_sheet.dart';
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
    final connected = !production || (_dependencies!.deviceSessionCubit.state.isConnected && _status != null && _error == null);
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
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              _StatusPill(
                connected ? Icons.link_rounded : Icons.link_off_rounded,
                connected ? '已连接' : '未连接',
                passed: connected,
              ),
              _StatusPill(
                Icons.wifi_rounded,
                _status?.connection.networkMode.label ?? (production ? '网络未知' : 'Wi-Fi 5GHz'),
                passed: connected,
              ),
              _StatusPill(
                Icons.shield_outlined,
                connected ? '状态接口可用' : '状态接口不可用',
                passed: connected,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const BirdSettingsCard(
            key: Key('network-transfer-note'),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: AppColors.forestPrimary),
                SizedBox(width: AppSpacing.sm),
                Expanded(child: Text('照片仍通过 Wi-Fi 传输，蓝牙仅用于发现与配网')),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
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
                                : connected
                                ? '网络连接正常'
                                : '网络连接需要处理',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            errorMessage?.message ?? (connected ? '盒子状态接口响应正常，可继续传输照片' : '请重新连接盒子后再次检测'),
                            style: const TextStyle(color: AppColors.mutedInk),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _MetricRow(
                  Icons.public_rounded,
                  '当前 IP',
                  _status?.connection.baseUri.host ?? (production ? '未连接' : '192.168.4.1'),
                ),
                _MetricRow(
                  Icons.wifi_rounded,
                  '设备名称',
                  _status?.connection.name ?? (production ? '未连接' : 'K7_7B2A'),
                ),
                _MetricRow(
                  Icons.signal_cellular_alt_rounded,
                  '状态接口',
                  connected ? '正常' : '不可用',
                ),
                _MetricRow(
                  Icons.schedule_rounded,
                  '响应时间',
                  _latencyMilliseconds == null ? (production ? '未检测' : '18 ms') : '$_latencyMilliseconds ms',
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
                  title: '切换网络',
                  subtitle: '切换至其他可用网络',
                  leading: const BirdSettingsAssetIcon(
                    BirdSettingsAssetCatalog.wifi,
                    label: '切换网络',
                    size: 28,
                  ),
                  trailing: const BirdChevron(),
                  onTap: _openDeviceManagement,
                ),
                BirdSettingsRow(
                  key: const Key('network-hotspot-details'),
                  title: '查看热点信息',
                  subtitle: '查看当前热点详细信息',
                  leading: const Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.forestPrimary,
                  ),
                  trailing: const BirdChevron(),
                  onTap: _showHotspotDetails,
                ),
                BirdSettingsRow(
                  title: '导出诊断结果',
                  subtitle: '保存或分享网络诊断结果',
                  showDivider: false,
                  leading: const Icon(
                    Icons.download_outlined,
                    color: AppColors.forestPrimary,
                  ),
                  trailing: const BirdChevron(),
                  onTap: _openSystemLogs,
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
                  connected ? '当前设备会话已建立' : '尚未建立可用设备会话',
                  passed: connected,
                ),
                _CheckRow(
                  Icons.api_rounded,
                  '状态接口',
                  _status != null ? '已成功读取盒子状态' : '未能读取盒子状态',
                  passed: _status != null,
                ),
                _CheckRow(
                  Icons.sync_rounded,
                  '实时状态更新',
                  _dependencies?.eventClient.currentState.name ?? (production ? '未连接' : 'connected'),
                  passed: !production || _dependencies!.eventClient.currentState.name == 'connected',
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

  void _openDeviceManagement() {
    Navigator.of(context).pushNamed(
      _dependencies == null ? BirdRoutes.settingsDeviceManagement : BirdRoutes.settingsNetwork,
    );
  }

  void _openSystemLogs() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SystemLogsPage()),
    );
  }

  void _openHelpCenter() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const HelpCenterPage()),
    );
  }

  Future<void> _showHotspotDetails() => showBirdSettingsSheet<void>(
    context: context,
    title: '热点信息',
    child: BirdSettingsCard(
      child: Column(
        children: [
          BirdSettingsValueRow(
            label: '热点名称',
            value: _status?.connection.name ?? 'K7_7B2A',
          ),
          BirdSettingsValueRow(
            label: '频段',
            value: _status?.connection.networkMode.label ?? '5 GHz',
          ),
          BirdSettingsValueRow(
            label: '设备地址',
            value: _status?.connection.baseUri.host ?? '192.168.4.1',
          ),
          const BirdSettingsValueRow(label: '信号强度', value: '良好'),
          const BirdSettingsValueRow(
            label: '安全类型',
            value: 'WPA2',
            showDivider: false,
          ),
        ],
      ),
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.icon, this.label, {this.passed = true});
  final IconData icon;
  final String label;
  final bool passed;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: AppColors.settingsSurface,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: passed ? AppColors.forestPrimary : AppColors.warning,
          size: 18,
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 15)),
      ],
    ),
  );
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
