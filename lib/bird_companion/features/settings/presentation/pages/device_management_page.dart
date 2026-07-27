import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_asset_catalog.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_controls.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:flutter/material.dart';

class DeviceManagementPage extends StatelessWidget {
  const DeviceManagementPage({super.key, required this.controller, this.onOpenDetails});

  final BirdSettingsController controller;
  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context) => BirdSettingsScaffold(
    title: '更换设备',
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
          const BirdSettingsSectionLabel('当前连接设备'),
          _DeviceCard(
            key: const Key('device-current'),
            name: '拍鸟伴侣 K7',
            serial: 'SN：PB2406A0086',
            selected: controller.selectedDeviceId == 'k7-current',
            onTap: onOpenDetails,
          ),
          const SizedBox(height: AppSpacing.xl),
          const BirdSettingsSectionLabel('可用设备'),
          _DeviceCard(
            key: const Key('device-available-1'),
            name: '拍鸟伴侣 K7',
            serial: 'SN：PB2406A0087',
            selected: controller.selectedDeviceId == 'k7-nearby-1',
            onTap: () => _select(context, 'k7-nearby-1'),
          ),
          const SizedBox(height: AppSpacing.md),
          _DeviceCard(
            key: const Key('device-available-2'),
            name: '拍鸟伴侣 K7',
            serial: 'SN：PB2406A0088',
            selected: controller.selectedDeviceId == 'k7-nearby-2',
            onTap: () => _select(context, 'k7-nearby-2'),
          ),
          const SizedBox(height: AppSpacing.xl),
          BirdSettingsOutlineButton(
            key: const Key('device-rescan'),
            label: controller.searchingDevices ? '正在搜索' : '重新搜索',
            icon: Icons.refresh_rounded,
            onPressed: controller.beginDeviceSearch,
          ),
          const SizedBox(height: AppSpacing.lg),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline_rounded, color: AppColors.forestPrimary, size: 22),
              SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  '请确保设备已开机并处于配对模式',
                  style: TextStyle(color: AppColors.forestPrimary),
                ),
              ),
            ],
          ),
          if (controller.searchingDevices) ...[
            const SizedBox(height: AppSpacing.sm),
            const Center(
              child: Text('正在重新搜索附近设备…', style: TextStyle(color: AppColors.mutedInk)),
            ),
          ],
        ],
      ),
    ),
  );

  void _select(BuildContext context, String id) {
    controller.setDevice(id);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已选择设备，等待真实连接服务接入')),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    super.key,
    required this.name,
    required this.serial,
    required this.selected,
    this.onTap,
  });

  final String name;
  final String serial;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => BirdSettingsCard(
    borderColor: selected ? AppColors.forestSoft : null,
    padding: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 142),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const SizedBox(
                width: 112,
                height: 104,
                child: Center(child: BirdSettingsDeviceIcon(size: 82)),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(serial, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.mutedInk)),
                  ],
                ),
              ),
              if (selected)
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.success,
                  child: Icon(Icons.check_rounded, color: Colors.white),
                )
              else
                const BirdSettingsAssetIcon(
                  BirdSettingsAssetCatalog.wifi,
                  label: '可通过 Wi-Fi 连接',
                  size: 34,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
