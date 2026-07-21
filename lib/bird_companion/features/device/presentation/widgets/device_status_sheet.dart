import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:flutter/material.dart';

Future<void> showDeviceStatusSheet(
  BuildContext context, {
  required DeviceStatus status,
  DeviceSessionState? session,
  required VoidCallback onReconnect,
  required VoidCallback onOpenDetails,
  VoidCallback? onOpenTask,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => DeviceStatusSheet(
    status: status,
    session: session,
    onReconnect: onReconnect,
    onOpenDetails: onOpenDetails,
    onOpenTask: onOpenTask,
  ),
);

class DeviceStatusSheet extends StatelessWidget {
  const DeviceStatusSheet({
    super.key,
    required this.status,
    this.session,
    required this.onReconnect,
    required this.onOpenDetails,
    this.onOpenTask,
  });

  final DeviceStatus status;
  final DeviceSessionState? session;
  final VoidCallback onReconnect;
  final VoidCallback onOpenDetails;
  final VoidCallback? onOpenTask;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .62,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageHorizontal,
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              const SizedBox(width: 48),
              Expanded(
                child: Text(status.connection.name, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageHorizontal,
              0,
              AppSpacing.pageHorizontal,
              AppSpacing.lg,
            ),
            children: [
              _StatusSummary(status: status, session: session),
              const SizedBox(height: AppSpacing.md),
              BirdCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _StatusRow(
                      icon: Icons.thermostat_rounded,
                      label: '盒子温度',
                      value: status.temperatureCelsius == null ? '—' : '${status.temperatureCelsius!.toStringAsFixed(0)}°C${status.temperatureCelsius! >= 70 ? ' 偏高' : ''}',
                      warning: (status.temperatureCelsius ?? 0) >= 70,
                    ),
                    const Divider(),
                    _StatusRow(
                      icon: Icons.sd_card_outlined,
                      label: 'SD 卡状态',
                      value: _cardStatus(status.card),
                      warning: status.card.inserted && !status.card.readable,
                    ),
                    const Divider(),
                    _StatusRow(
                      icon: Icons.pie_chart_outline_rounded,
                      label: '剩余容量',
                      value: _capacity(status),
                    ),
                    const Divider(),
                    _StatusRow(
                      icon: Icons.format_list_bulleted_rounded,
                      label: '当前任务',
                      value: status.currentJob == null ? '暂无运行中的任务' : _jobStatus(status),
                      onTap: status.currentJob == null ? null : onOpenTask,
                    ),
                    const Divider(),
                    _StatusRow(
                      icon: Icons.shield_outlined,
                      label: '异常信息',
                      value: status.hasError ? status.errorMessage ?? status.errorCode ?? '设备报告异常' : '设备运行正常 · 暂无异常',
                      warning: status.hasError,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: BirdButton(
                      label: '查看设备详情',
                      onPressed: onOpenDetails,
                      expanded: false,
                      variant: BirdButtonVariant.outlined,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: BirdButton(
                      label: '重新连接',
                      onPressed: onReconnect,
                      expanded: false,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  static String _cardStatus(CardStatus card) {
    if (!card.inserted) return '未插入';
    if (!card.readable) return '${card.name ?? '存储卡'} · 不可读';
    return '${card.name ?? '存储卡'} · 已插入 · 可读';
  }

  static String _capacity(DeviceStatus status) {
    final free = status.storageFreeBytes;
    final total = status.storageTotalBytes;
    if (free == null && total == null) return '—';
    return '${free == null ? '—' : _storage(free)} 可用${total == null ? '' : ' · 总容量 ${_storage(total)}'}';
  }

  static String _jobStatus(DeviceStatus status) {
    final job = status.currentJob!;
    final total = job.totalCount;
    final finished = job.finishedCount;
    if (total <= 0) return job.state.label;
    final percent = (finished / total * 100).clamp(0, 100).round();
    return '${job.state.label} · $percent%';
  }

  static String _storage(int bytes) {
    final gib = bytes / 1024 / 1024 / 1024;
    return gib >= 1024 ? '${(gib / 1024).toStringAsFixed(1)}TB' : '${gib.toStringAsFixed(0)}GB';
  }
}

class _StatusSummary extends StatelessWidget {
  const _StatusSummary({required this.status, required this.session});

  final DeviceStatus status;
  final DeviceSessionState? session;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _SummaryItem(
          icon: Icons.wifi_rounded,
          label: _connectionLabel(session),
          note: _connectionNote(session),
          warning: session != null && !session!.isConnected,
        ),
      ),
      const SizedBox(width: AppSpacing.xs),
      Expanded(
        child: _SummaryItem(
          icon: Icons.battery_5_bar_rounded,
          label: status.batteryPercent == null ? '电量 —' : '电量 ${status.batteryPercent}%',
          note: status.isExternalPower ? '外接电源' : '使用电池',
        ),
      ),
      const SizedBox(width: AppSpacing.xs),
      Expanded(
        child: _SummaryItem(
          icon: Icons.storage_rounded,
          label: status.storageFreeBytes == null ? '存储 —' : '可用 ${DeviceStatusSheet._storage(status.storageFreeBytes!)}',
          note: _storageWarning(status) ? '需要检查' : '存储正常',
          warning: _storageWarning(status),
        ),
      ),
    ],
  );

  static bool _storageWarning(DeviceStatus status) => (status.card.inserted && !status.card.readable) || status.card.errorCode != null || status.card.errorMessage != null;

  static String _connectionLabel(DeviceSessionState? session) => switch (session?.phase) {
    DeviceSessionPhase.reconnecting => '重连中',
    DeviceSessionPhase.connecting => '连接中',
    DeviceSessionPhase.disconnected => '未连接',
    DeviceSessionPhase.incompatible => '版本不兼容',
    _ => '已连接',
  };

  static String _connectionNote(DeviceSessionState? session) => switch (session?.phase) {
    DeviceSessionPhase.reconnecting => '正在恢复连接',
    DeviceSessionPhase.connecting => '正在验证设备',
    DeviceSessionPhase.disconnected => '可尝试重新连接',
    DeviceSessionPhase.incompatible => '请检查设备版本',
    _ => '本地传输可用',
  };
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.icon,
    required this.label,
    required this.note,
    this.warning = false,
  });

  final IconData icon;
  final String label;
  final String note;
  final bool warning;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: warning ? AppColors.dangerSoft : AppColors.mist,
      borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
      border: Border.all(color: warning ? AppColors.danger.withValues(alpha: .35) : AppColors.outline),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
      child: Column(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: warning ? AppColors.danger : AppColors.brandMid,
            foregroundColor: AppColors.cream,
            child: Icon(icon, size: 20),
          ),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    this.warning = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool warning;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: warning ? AppColors.danger : AppColors.brand),
    title: Text(label),
    subtitle: Text(
      value,
      style: TextStyle(color: warning ? AppColors.danger : null),
    ),
    trailing: onTap == null ? null : const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}
