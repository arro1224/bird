import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/features/settings/presentation/settings_cubit.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/cache_management_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/privacy_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/version_info_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => SettingsCubit(BirdCompanionScope.of(context))..load(),
    child: Scaffold(
      backgroundColor: AppColors.paper,
      body: BlocConsumer<SettingsCubit, SettingsState>(
        listenWhen: (before, after) =>
            after.message.isNotEmpty && before.message != after.message,
        listener: (context, state) => ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(state.message))),
        builder: (context, state) => Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 28),
              children: [
                Text(
                  '设备设置',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                BlocBuilder<DeviceSessionCubit, DeviceSessionState>(
                  bloc: BirdCompanionScope.of(context).deviceSessionCubit,
                  builder: (context, session) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DeviceHero(session: session),
                      const SizedBox(height: 18),
                      const _SectionTitle('连接'),
                      _SettingsGroup(
                        children: [
                          _SettingsTile(
                            icon: Icons.wifi_rounded,
                            title: '连接方式',
                            value: session.device?.networkMode.label ?? '未连接',
                            enabled: session.device != null,
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed(BirdRoutes.settingsNetwork),
                          ),
                          _SettingsTile(
                            icon: Icons.memory_rounded,
                            title: '设备详情',
                            subtitle: '电量、温度、存储卡和当前任务',
                            enabled: session.device != null,
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed(BirdRoutes.settingsDeviceDetails),
                          ),
                          _SettingsTile(
                            icon: Icons.link_rounded,
                            title: '重新连接设备',
                            subtitle: '重新连接，并更新手机上尚未传回盒子的修改',
                            enabled: !state.loading,
                            onTap: () => openReconnectConnection(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const _SectionTitle('手机存储'),
                      CacheManagementCard(
                        imageBytes: state.imageCacheBytes,
                        albumBytes: state.albumCacheBytes,
                        onClearImages: state.loading
                            ? null
                            : () => context
                                  .read<SettingsCubit>()
                                  .clearImageCache(),
                        onClearAlbumData: state.loading
                            ? null
                            : () => context
                                  .read<SettingsCubit>()
                                  .clearAlbumCache(),
                      ),
                      const SizedBox(height: 18),
                      const _SectionTitle('遇到问题'),
                      _SettingsGroup(
                        children: [
                          _SettingsTile(
                            icon: Icons.monitor_heart_outlined,
                            title: '检查连接问题',
                            subtitle: '检查盒子连接和尚未更新的修改',
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed(BirdRoutes.diagnostics),
                          ),
                          _SettingsTile(
                            icon: Icons.link_off_rounded,
                            iconColor: AppColors.danger,
                            title: '忘记当前盒子',
                            subtitle: '清除本机保存的连接信息',
                            enabled: session.device != null && !state.loading,
                            onTap: () => _confirmForget(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const _SectionTitle('关于'),
                      VersionInfoCard(
                        session: session,
                        appVersion: state.appVersion,
                      ),
                      const PrivacyCard(),
                    ],
                  ),
                ),
              ],
            ),
            if (state.loading)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    ),
  );

  Future<void> _confirmForget(BuildContext context) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.link_off_rounded, color: AppColors.danger),
        title: const Text('忘记当前盒子？'),
        content: const Text('将断开连接并删除手机上保存的盒子地址。照片和尚未传回盒子的修改不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('忘记'),
          ),
        ],
      ),
    );
    if (approved != true || !context.mounted) return;
    await context.read<SettingsCubit>().forgetDevice();
    if (context.mounted) {
      await Navigator.of(context).pushNamedAndRemoveUntil(
        BirdRoutes.connection,
        (route) => false,
      );
    }
  }
}

class _DeviceHero extends StatelessWidget {
  const _DeviceHero({required this.session});

  final DeviceSessionState session;

  @override
  Widget build(BuildContext context) {
    final device = session.device;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 112,
                  height: 82,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.mist,
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                    ),
                    child: Icon(
                      Icons.memory_rounded,
                      size: 54,
                      color: AppColors.brand,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device?.name ?? '未连接拍鸟盒子',
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 10,
                            color: session.isConnected
                                ? AppColors.success
                                : AppColors.inkMuted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            session.isConnected ? '在线' : '等待连接',
                            style: TextStyle(
                              color: session.isConnected
                                  ? AppColors.success
                                  : AppColors.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 26),
            _DeviceRow(label: '软件兼容信息', value: device?.apiVersion ?? '盒子未提供'),
            _DeviceRow(
              label: '连接方式',
              value: device?.networkMode.label ?? '未连接',
            ),
            _DeviceRow(
              label: '连接地址',
              value: device?.baseUri.host.isNotEmpty == true
                  ? device!.baseUri.host
                  : '未连接',
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: AppColors.inkMuted)),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 5, bottom: 7),
    child: Text(
      '• $text',
      style: const TextStyle(
        color: AppColors.brand,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index < children.length - 1) const Divider(height: 1, indent: 54),
        ],
      ],
    ),
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.enabled = true,
    this.iconColor = AppColors.brand,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final bool enabled;
  final Color iconColor;

  @override
  Widget build(BuildContext context) => ListTile(
    enabled: enabled,
    minVerticalPadding: 10,
    leading: Icon(icon, color: enabled ? iconColor : AppColors.inkMuted),
    title: Text(title, style: const TextStyle(fontSize: 17, height: 1.3)),
    subtitle: subtitle == null
        ? null
        : Text(subtitle!, style: const TextStyle(fontSize: 15, height: 1.3)),
    trailing: value == null
        ? const Icon(Icons.chevron_right)
        : Text(
            value!,
            style: const TextStyle(color: AppColors.inkMuted, fontSize: 15),
          ),
    onTap: onTap,
  );
}
