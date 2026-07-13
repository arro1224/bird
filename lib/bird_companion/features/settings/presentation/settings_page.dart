import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/features/settings/presentation/settings_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => SettingsCubit(BirdCompanionScope.of(context)),
    child: Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: BlocConsumer<SettingsCubit, String>(
        listenWhen: (before, after) => after.isNotEmpty && before != after,
        listener: (context, message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message))),
        builder: (context, message) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            BlocBuilder<DeviceSessionCubit, DeviceSessionState>(
              bloc: BirdCompanionScope.of(context).deviceSessionCubit,
              builder: (context, session) => _DeviceHero(session: session),
            ),
            const SizedBox(height: 24),
            Text('连接与诊断', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.wifi_tethering_rounded, color: AppColors.brand),
                    title: const Text('重新连接 BIRD BOX'),
                    subtitle: const Text('刷新本地盒子连接与待同步操作'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.read<SettingsCubit>().reconnect(),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.monitor_heart_outlined, color: AppColors.brand),
                    title: const Text('设置诊断'),
                    subtitle: const Text('连接状态、日志导出与设备 API'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pushNamed(BirdRoutes.diagnostics),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('本地数据', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined, color: AppColors.brand),
                    title: const Text('缩略图缓存'),
                    subtitle: Text('约 ${(BirdCompanionScope.of(context).cache.estimateBytes() / 1024).toStringAsFixed(1)} KB · 不会清除待同步修改'),
                    trailing: TextButton(onPressed: () => context.read<SettingsCubit>().clearCache(), child: const Text('清理')),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.link_off_rounded, color: Theme.of(context).colorScheme.error),
                    title: const Text('忘记当前盒子'),
                    subtitle: const Text('清除本机保存的连接信息，并返回设备连接页'),
                    onTap: () => _confirmForget(context),
                  ),
                ],
              ),
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
        title: const Text('忘记当前盒子？'),
        content: const Text('将断开连接并删除本机保存的盒子地址。照片和待同步的人工审阅数据不会被删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('忘记')),
        ],
      ),
    );
    if (approved != true || !context.mounted) return;
    await context.read<SettingsCubit>().forgetDevice();
    if (context.mounted) await Navigator.of(context).pushNamedAndRemoveUntil(BirdRoutes.connection, (route) => false);
  }
}

class _DeviceHero extends StatelessWidget {
  const _DeviceHero({required this.session});
  final DeviceSessionState session;
  @override
  Widget build(BuildContext context) => Card(
    color: AppColors.brand,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.brandLight,
            child: Icon(Icons.memory_rounded, color: AppColors.brand),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.device?.name ?? '未连接拍鸟盒子', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
                const SizedBox(height: 4),
                Text(session.isConnected ? '● 本地连接稳定' : '● 等待连接', style: const TextStyle(color: Color(0xFFD9F0D8))),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
