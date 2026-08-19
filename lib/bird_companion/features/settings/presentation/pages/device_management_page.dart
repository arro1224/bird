import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_asset_catalog.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:aves/bird_companion/features/settings/presentation/device_management_cubit.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_controls.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DeviceManagementPage extends StatelessWidget {
  const DeviceManagementPage({
    super.key,
    required this.controller,
    this.onOpenDetails,
  });

  final BirdSettingsController controller;
  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<BirdCompanionScope>();
    ConnectionRepository? connectionRepository;
    try {
      connectionRepository = scope?.dependencies.connectionRepository;
    } catch (_) {
      // Lightweight widget-test scopes may intentionally omit repositories.
    }
    if (scope != null && connectionRepository != null) {
      return BlocProvider(
        create: (_) => DeviceManagementCubit(
          connectionRepository!,
          scope.dependencies.deviceSessionCubit,
        )..initialize(),
        child: _ProductionDeviceManagementView(onOpenDetails: onOpenDetails),
      );
    }
    return _legacyView(context);
  }

  Widget _legacyView(BuildContext context) => BirdSettingsScaffold(
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
              Icon(
                Icons.info_outline_rounded,
                color: AppColors.forestPrimary,
                size: 22,
              ),
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
              child: Text(
                '正在重新搜索附近设备…',
                style: TextStyle(color: AppColors.mutedInk),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  void _select(BuildContext context, String id) {
    controller.setDevice(id);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已选择设备，等待真实连接服务接入')));
  }
}

class _ProductionDeviceManagementView extends StatelessWidget {
  const _ProductionDeviceManagementView({this.onOpenDetails});

  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<DeviceManagementCubit, DeviceManagementState>(
        builder: (context, state) {
          final dependencies = BirdCompanionScope.of(context);
          final current = dependencies.deviceSessionCubit.state.device;
          final seen = <String>{};
          final candidates = [
            ...state.available,
            ...state.recent,
          ].where((device) => seen.add(device.id)).toList(growable: false);
          final errorMessage = state.error == null
              ? null
              : UserMessageMapper.fromError(state.error!);
          return BirdSettingsScaffold(
            title: '更换设备',
            body: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.settingsPageHorizontal,
                AppSpacing.md,
                AppSpacing.settingsPageHorizontal,
                AppSpacing.xl,
              ),
              children: [
                const BirdSettingsSectionLabel('当前连接设备'),
                if (current == null)
                  const BirdSettingsCard(child: Text('当前没有已连接的拍鸟盒子'))
                else
                  _DeviceCard(
                    key: const Key('device-current'),
                    name: current.name,
                    serial: '${current.id}\n${current.baseUri.authority}',
                    selected: true,
                    onTap: onOpenDetails,
                  ),
                const SizedBox(height: AppSpacing.xl),
                const BirdSettingsSectionLabel('发现与历史设备'),
                if (candidates.isEmpty && !state.searching)
                  const BirdSettingsCard(
                    child: Text('没有发现可连接设备，可确认盒子已开机后重新搜索。'),
                  ),
                for (final device in candidates) ...[
                  _DeviceCard(
                    key: ValueKey('device-${device.id}'),
                    name: device.name,
                    serial: '${device.id}\n${device.baseUri.authority}',
                    selected: current?.id == device.id,
                    busy: state.connectingDeviceId == device.id,
                    onTap: state.connectingDeviceId == null
                        ? () => _connect(context, device)
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                BirdSettingsOutlineButton(
                  key: const Key('device-rescan'),
                  label: state.searching ? '取消搜索' : '重新搜索',
                  icon: state.searching
                      ? Icons.close_rounded
                      : Icons.refresh_rounded,
                  onPressed: state.searching
                      ? context.read<DeviceManagementCubit>().cancelSearch
                      : context.read<DeviceManagementCubit>().search,
                ),
                if (state.searching) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                if (errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    '${errorMessage.title}：${errorMessage.message}',
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ],
              ],
            ),
          );
        },
      );

  Future<void> _connect(BuildContext context, DeviceConnection device) async {
    final connected = await context.read<DeviceManagementCubit>().connect(
      device,
    );
    if (!context.mounted || !connected) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已连接 ${device.name}')));
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    super.key,
    required this.name,
    required this.serial,
    required this.selected,
    this.busy = false,
    this.onTap,
  });

  final String name;
  final String serial;
  final bool selected;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => BirdSettingsCard(
    borderColor: selected ? AppColors.forestSoft : null,
    padding: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 160),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const SizedBox(
                width: 112,
                height: 112,
                child: Center(child: BirdSettingsDeviceIcon(size: 82)),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      serial,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.mutedInk,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox.square(
                  dimension: 36,
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              else if (selected)
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
