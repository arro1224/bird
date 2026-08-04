import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_asset_catalog.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_controls.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_row.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/system_logs_page.dart';
import 'package:flutter/material.dart';

class DeviceDetailsPage extends StatefulWidget {
  const DeviceDetailsPage({super.key, required this.controller});

  final BirdSettingsController controller;

  @override
  State<DeviceDetailsPage> createState() => _DeviceDetailsPageState();
}

class _DeviceDetailsPageState extends State<DeviceDetailsPage> {
  BirdCompanionDependencies? _dependencies;
  Future<DeviceStatus>? _statusFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = context.dependOnInheritedWidgetOfExactType<BirdCompanionScope>()?.dependencies;
    if (identical(_dependencies, dependencies)) return;
    _dependencies = dependencies;
    _statusFuture = dependencies?.deviceRepository.fetchStatus();
  }

  @override
  Widget build(BuildContext context) {
    if (_dependencies == null) return _buildPage(context, null, legacy: true);
    return FutureBuilder<DeviceStatus>(
      future: _statusFuture,
      builder: (context, snapshot) => _buildPage(
        context,
        snapshot.data,
        loading: snapshot.connectionState == ConnectionState.waiting,
        error: snapshot.error,
      ),
    );
  }

  Widget _buildPage(
    BuildContext context,
    DeviceStatus? status, {
    bool legacy = false,
    bool loading = false,
    Object? error,
  }) => BirdSettingsScaffold(
    title: '设备详情',
    body: ListenableBuilder(
      listenable: widget.controller,
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
                      Text(
                        status?.connection.name ?? (legacy ? '拍鸟伴侣 K7' : '拍鸟盒子'),
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _DeviceHealthBadge(
                        loading: loading,
                        available: status != null || legacy,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.xs,
                        children: [
                          TextButton.icon(
                            key: const Key('device-reconnect'),
                            onPressed: () => openReconnectConnection(context),
                            icon: const BirdSettingsAssetIcon(
                              BirdSettingsAssetCatalog.reconnect,
                              label: '重新连接',
                              size: 24,
                            ),
                            label: const Text('重新连接'),
                          ),
                          TextButton.icon(
                            onPressed: () => Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => const SystemLogsPage(),
                              ),
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
          if (error != null) ...[
            const SizedBox(height: AppSpacing.md),
            BirdSettingsCard(
              child: _StatusError(
                error: error,
                onRetry: _reload,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          BirdSettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CardTitle('设备参数'),
                _InfoRow(
                  Icons.info_outline_rounded,
                  '设备编号',
                  status?.connection.id ?? (legacy ? 'K7-7B2A-9C31' : '未连接'),
                ),
                _InfoRow(
                  Icons.inventory_2_outlined,
                  '固件版本',
                  status?.softwareVersion ?? (legacy ? '1.2.4' : '盒子未提供'),
                ),
                _InfoRow(
                  Icons.code_rounded,
                  '设备版本',
                  status?.connection.apiVersion ?? (legacy ? '2.1.0' : '盒子未提供'),
                ),
                _InfoRow(
                  Icons.memory_rounded,
                  '模型版本',
                  status?.modelVersion ?? (legacy ? 'BirdAI 3.0.2' : '盒子未提供'),
                ),
                _AssetInfoRow(
                  BirdSettingsAssetCatalog.wifi,
                  '连接方式',
                  status?.connection.networkMode.label ?? '未连接',
                ),
                _InfoRow(
                  Icons.wifi_rounded,
                  '盒子地址',
                  status?.connection.baseUri.toString() ?? '未连接',
                ),
                _AssetInfoRow(
                  BirdSettingsAssetCatalog.runtime,
                  '状态更新时间',
                  _formatTime(status?.updatedAt),
                ),
                _InfoRow(
                  Icons.storage_outlined,
                  '存储容量',
                  _formatStorage(
                    status?.storageFreeBytes,
                    status?.storageTotalBytes,
                  ),
                ),
                _AssetInfoRow(
                  BirdSettingsAssetCatalog.sdCard,
                  'SD 卡',
                  status?.card.inserted == true ? status?.card.name ?? '已插入' : '未插入',
                  showDivider: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          BirdSettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CardTitle('设备状态'),
                _InfoRow(
                  Icons.battery_full_rounded,
                  '电量',
                  status?.batteryPercent == null ? '盒子未提供' : '${status!.batteryPercent}%',
                ),
                _AssetInfoRow(
                  BirdSettingsAssetCatalog.temperature,
                  '温度',
                  status?.temperatureCelsius == null ? '盒子未提供' : '${status!.temperatureCelsius!.toStringAsFixed(1)}°C',
                ),
                _TaskProgressRow(job: status?.currentJob),
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
                  showDivider: widget.controller.technicalDetailsExpanded,
                  onTap: widget.controller.toggleTechnicalDetails,
                  trailing: Icon(
                    widget.controller.technicalDetailsExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  ),
                ),
                if (widget.controller.technicalDetailsExpanded) ...[
                  _InfoRow(
                    Icons.api_rounded,
                    'API 版本',
                    status?.connection.apiVersion ?? (legacy ? 'v1' : '盒子未提供'),
                  ),
                  _InfoRow(
                    Icons.router_outlined,
                    '设备地址',
                    status?.connection.baseUri.authority ?? (legacy ? '192.168.4.1' : '未连接'),
                  ),
                  _InfoRow(
                    Icons.security_outlined,
                    '连接安全',
                    status != null || legacy ? '已认证本地会话' : '尚未验证',
                    showDivider: false,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );

  String _formatTime(DateTime? value) {
    if (value == null) return '盒子未提供';
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _formatStorage(int? free, int? total) {
    if (free == null || total == null) return '盒子未提供';
    final freeGb = free / 1024 / 1024 / 1024;
    final totalGb = total / 1024 / 1024 / 1024;
    return '${freeGb.toStringAsFixed(0)} GB 可用 / '
        '${totalGb.toStringAsFixed(0)} GB';
  }

  void _reload() {
    final dependencies = _dependencies;
    if (dependencies == null) return;
    setState(() {
      _statusFuture = dependencies.deviceRepository.fetchStatus();
    });
  }
}

class _DeviceHealthBadge extends StatelessWidget {
  const _DeviceHealthBadge({
    required this.loading,
    required this.available,
  });

  final bool loading;
  final bool available;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
    decoration: BoxDecoration(
      color: available ? AppColors.forestSoft : AppColors.amberLight,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          loading
              ? Icons.sync_rounded
              : available
              ? Icons.check_circle_rounded
              : Icons.warning_amber_rounded,
          size: 18,
          color: available ? AppColors.success : AppColors.warning,
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          loading
              ? '正在读取'
              : available
              ? '运行正常'
              : '状态不可用',
          style: const TextStyle(
            color: AppColors.forestPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _StatusError extends StatelessWidget {
  const _StatusError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = UserMessageMapper.fromError(error);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.danger),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(message.message),
            ],
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    );
  }
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
  const _TaskProgressRow({this.job});

  final BirdJobStatus? job;
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
              Row(
                children: [
                  const Expanded(
                    child: Text('当前任务', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Text(
                    job == null ? '无' : '${(job!.progress * 100).round()}%',
                    style: const TextStyle(color: AppColors.mutedInk),
                  ),
                ],
              ),
              Text(
                job?.type.label ?? '暂无进行中的任务',
                style: const TextStyle(color: AppColors.mutedInk),
              ),
              const SizedBox(height: AppSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: job?.progress ?? 0,
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
