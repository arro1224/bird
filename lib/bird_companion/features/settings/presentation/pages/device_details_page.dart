import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_asset_catalog.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_controls.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_row.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:flutter/material.dart';

class DeviceDetailsPage extends StatelessWidget {
  const DeviceDetailsPage({super.key, required this.controller});

  final BirdSettingsController controller;

  @override
  Widget build(BuildContext context) => BirdSettingsScaffold(
    title: '设备详情',
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
          BirdSettingsCard(
            child: Row(
              children: [
                const SizedBox(
                  width: 126,
                  height: 124,
                  child: Center(child: BirdSettingsDeviceIcon(size: 94)),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('拍鸟伴侣 K7', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: AppSpacing.xs),
                      const _HealthyBadge(),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.xs,
                        children: [
                          TextButton.icon(
                            key: const Key('device-reconnect'),
                            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已开始重新连接拍鸟伴侣 K7')),
                            ),
                            icon: const BirdSettingsAssetIcon(
                              BirdSettingsAssetCatalog.reconnect,
                              label: '重新连接',
                              size: 24,
                            ),
                            label: const Text('重新连接'),
                          ),
                          TextButton.icon(
                            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('演示模式未生成真实日志文件')),
                            ),
                            icon: const Icon(Icons.description_outlined),
                            label: const Text('导出日志'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const BirdSettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardTitle('设备参数'),
                _InfoRow(Icons.info_outline_rounded, '设备编号', 'K7-7B2A-9C31'),
                _InfoRow(Icons.inventory_2_outlined, '固件版本', '1.2.4'),
                _InfoRow(Icons.code_rounded, '软件版本', '2.1.0'),
                _InfoRow(Icons.memory_rounded, '模型版本', 'BirdAI 3.0.2'),
                _AssetInfoRow(BirdSettingsAssetCatalog.wifi, '连接方式', '盒子 Wi-Fi 5GHz'),
                _InfoRow(Icons.wifi_rounded, 'IP / 热点信息', '192.168.4.1\nK7_7B2A'),
                _AssetInfoRow(BirdSettingsAssetCatalog.runtime, '最后同步时间', '2025-07-16 10:18'),
                _InfoRow(Icons.info_outline_rounded, '设备序列号', 'K7-7B2A-9C31'),
                _InfoRow(Icons.storage_outlined, '存储容量', '894 GB（剩余 685 GB）'),
                _AssetInfoRow(BirdSettingsAssetCatalog.sdCard, 'SD 卡容量', 'SanDisk 128GB · U3 · V30', showDivider: false),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const BirdSettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardTitle('设备状态'),
                _InfoRow(Icons.battery_full_rounded, '电量', '78%'),
                _AssetInfoRow(BirdSettingsAssetCatalog.temperature, '温度', '36°C'),
                _TaskProgressRow(),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          BirdSettingsCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Column(
              children: [
                BirdSettingsRow(
                  key: const Key('device-technical-details'),
                  title: '技术详情',
                  showDivider: controller.technicalDetailsExpanded,
                  onTap: controller.toggleTechnicalDetails,
                  trailing: Icon(
                    controller.technicalDetailsExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  ),
                ),
                if (controller.technicalDetailsExpanded) ...const [
                  _InfoRow(Icons.api_rounded, 'API 版本', 'v1'),
                  _InfoRow(Icons.router_outlined, 'MAC 地址', '7B:2A:9C:31:44:08'),
                  _InfoRow(Icons.security_outlined, '连接安全', '本地加密会话', showDivider: false),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _HealthyBadge extends StatelessWidget {
  const _HealthyBadge();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
    decoration: BoxDecoration(color: AppColors.forestSoft, borderRadius: BorderRadius.circular(AppSpacing.radiusSmall)),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
        SizedBox(width: AppSpacing.xxs),
        Text(
          '运行正常',
          style: TextStyle(color: AppColors.forestPrimary, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Text(label, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.label, this.value, {this.showDivider = true});
  final IconData icon;
  final String label;
  final String value;
  final bool showDivider;
  @override
  Widget build(BuildContext context) => BirdSettingsRow(
    title: label,
    showDivider: showDivider,
    leading: Icon(icon, color: AppColors.forestPrimary),
    trailing: Flexible(
      child: Text(
        value,
        textAlign: TextAlign.end,
        style: const TextStyle(color: AppColors.mutedInk),
      ),
    ),
  );
}

class _AssetInfoRow extends StatelessWidget {
  const _AssetInfoRow(this.asset, this.label, this.value, {this.showDivider = true});
  final String asset;
  final String label;
  final String value;
  final bool showDivider;
  @override
  Widget build(BuildContext context) => BirdSettingsRow(
    title: label,
    showDivider: showDivider,
    leading: BirdSettingsAssetIcon(asset, label: label, size: 24),
    trailing: Flexible(
      child: Text(
        value,
        textAlign: TextAlign.end,
        style: const TextStyle(color: AppColors.mutedInk),
      ),
    ),
  );
}

class _TaskProgressRow extends StatelessWidget {
  const _TaskProgressRow();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Row(
      children: [
        const SizedBox.square(
          dimension: 44,
          child: Center(child: Icon(Icons.task_outlined, color: AppColors.forestPrimary)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Expanded(
                    child: Text('当前任务', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Text('78%', style: TextStyle(color: AppColors.mutedInk)),
                ],
              ),
              const Text('分析本次拍摄', style: TextStyle(color: AppColors.mutedInk)),
              const SizedBox(height: AppSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: const LinearProgressIndicator(
                  value: .78,
                  minHeight: 7,
                  color: AppColors.forestPrimary,
                  backgroundColor: AppColors.forestSoft,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
