import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_asset_catalog.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_controls.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_row.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:flutter/material.dart';

class NetworkDiagnosticsPage extends StatefulWidget {
  const NetworkDiagnosticsPage({super.key});

  @override
  State<NetworkDiagnosticsPage> createState() => _NetworkDiagnosticsPageState();
}

class _NetworkDiagnosticsPageState extends State<NetworkDiagnosticsPage> {
  bool _checking = false;

  @override
  Widget build(BuildContext context) => BirdSettingsScaffold(
    title: '网络诊断',
    actions: [
      IconButton(
        tooltip: '帮助',
        onPressed: () => _message('网络帮助将在帮助中心中打开'),
        icon: const Icon(Icons.help_outline_rounded, color: AppColors.forestPrimary),
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
        const Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xxs,
          children: [
            _StatusPill(Icons.link_rounded, '已连接'),
            _StatusPill(Icons.wifi_rounded, 'Wi-Fi 5GHz'),
            _StatusPill(Icons.shield_outlined, '本地网络正常'),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        BirdSettingsCard(
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 27,
                    backgroundColor: AppColors.success,
                    child: Icon(Icons.check_rounded, color: Colors.white, size: 34),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _checking ? '正在重新检测网络…' : '网络连接正常',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        const Text('网络状态良好，设备可正常传输照片', style: TextStyle(color: AppColors.mutedInk)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              const _MetricRow(Icons.public_rounded, '当前 IP', '192.168.4.1'),
              const _MetricRow(Icons.wifi_rounded, '热点名称', 'K7_7B2A'),
              const _MetricRow(Icons.signal_cellular_alt_rounded, '信号强度', '良好'),
              const _MetricRow(Icons.schedule_rounded, '延迟', '18 ms', showDivider: false),
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
                leading: const BirdSettingsAssetIcon(BirdSettingsAssetCatalog.reconnect, label: '重新检测网络', size: 28),
                trailing: _checking ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5)) : const BirdChevron(),
                onTap: _checking ? null : _recheck,
              ),
              BirdSettingsRow(
                title: '切换网络',
                subtitle: '切换至其他可用网络',
                leading: const BirdSettingsAssetIcon(BirdSettingsAssetCatalog.wifi, label: '切换网络', size: 28),
                trailing: const BirdChevron(),
                onTap: () => _message('演示模式未扫描真实 Wi-Fi'),
              ),
              BirdSettingsRow(
                title: '查看热点信息',
                subtitle: '查看当前热点详细信息',
                leading: const Icon(Icons.info_outline_rounded, color: AppColors.forestPrimary),
                trailing: const BirdChevron(),
                onTap: () => _message('热点 K7_7B2A · 192.168.4.1'),
              ),
              BirdSettingsRow(
                title: '导出诊断结果',
                subtitle: '保存或分享网络诊断结果',
                showDivider: false,
                leading: const Icon(Icons.download_outlined, color: AppColors.forestPrimary),
                trailing: const BirdChevron(),
                onTap: () => _message('演示模式不会生成真实诊断文件'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        const BirdSettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('常见问题排查', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              SizedBox(height: AppSpacing.xs),
              _CheckRow(Icons.bluetooth_rounded, '蓝牙与本地网络权限', '权限已开启，允许正常访问本地网络'),
              _CheckRow(Icons.wifi_rounded, '热点连接状态', '已连接至设备热点，信号稳定'),
              _CheckRow(Icons.phonelink_lock_rounded, '局域网访问', '设备可被局域网内其他设备访问', showDivider: false),
            ],
          ),
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
      ],
    ),
  );

  Future<void> _recheck() async {
    setState(() => _checking = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (mounted) setState(() => _checking = false);
  }

  void _message(String value) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(color: AppColors.settingsSurface, borderRadius: BorderRadius.circular(99)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.forestPrimary, size: 18),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    ),
  );
}

class _MetricRow extends StatelessWidget {
  const _MetricRow(this.icon, this.label, this.value, {this.showDivider = true});
  final IconData icon;
  final String label;
  final String value;
  final bool showDivider;
  @override
  Widget build(BuildContext context) => BirdSettingsRow(
    title: label,
    leading: Icon(icon, color: AppColors.forestPrimary),
    trailing: Text(value, style: TextStyle(color: value == '良好' ? AppColors.success : AppColors.mutedInk)),
    showDivider: showDivider,
  );
}

class _CheckRow extends StatelessWidget {
  const _CheckRow(this.icon, this.title, this.subtitle, {this.showDivider = true});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool showDivider;
  @override
  Widget build(BuildContext context) => BirdSettingsRow(
    title: title,
    subtitle: subtitle,
    leading: CircleAvatar(
      backgroundColor: AppColors.forestSoft,
      child: Icon(icon, color: AppColors.forestPrimary),
    ),
    trailing: const Icon(Icons.check_circle_rounded, color: AppColors.success),
    showDivider: showDivider,
  );
}
