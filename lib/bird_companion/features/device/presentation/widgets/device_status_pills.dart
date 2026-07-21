import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:flutter/material.dart';

class DeviceStatusPills extends StatelessWidget {
  const DeviceStatusPills({
    super.key,
    required this.status,
    required this.session,
    required this.onTap,
  });

  final DeviceStatus status;
  final DeviceSessionState session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: _semanticLabel,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 390;
          final pills = <Widget>[
            _StatusPill(
              icon: session.isConnected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              label: session.isConnected ? '已连接' : '连接中断',
              warning: !session.isConnected,
              compact: compact,
            ),
            _StatusPill(
              icon: Icons.battery_5_bar_rounded,
              label: status.batteryPercent == null ? '电量 —' : '电量 ${status.batteryPercent}%',
              compact: compact,
            ),
            _StatusPill(
              icon: Icons.storage_rounded,
              label: _storageLabel(status),
              warning: status.card.inserted && !status.card.readable,
              compact: compact,
            ),
          ];
          if (compact) {
            return Row(
              children: [
                for (var index = 0; index < pills.length; index++) ...[
                  if (index > 0) const SizedBox(width: 6),
                  Expanded(child: pills[index]),
                ],
              ],
            );
          }
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: pills,
          );
        },
      ),
    ),
  );

  String get _semanticLabel => [
    session.isConnected ? '设备已连接' : '设备连接中断',
    status.batteryPercent == null ? '电量未知' : '电量百分之${status.batteryPercent}',
    _storageLabel(status),
    '点按查看设备状态',
  ].join('，');

  static String _storageLabel(DeviceStatus status) {
    if (status.card.inserted && !status.card.readable) return '存储异常';
    final bytes = status.storageFreeBytes;
    if (bytes == null) return '存储状态';
    final gib = bytes / 1024 / 1024 / 1024;
    final value = gib >= 1024 ? '${(gib / 1024).toStringAsFixed(1)}TB' : '${gib.toStringAsFixed(0)}GB';
    return '$value 可用';
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    this.warning = false,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final bool warning;
  final bool compact;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: warning ? AppColors.dangerSoft : AppColors.paperStrong,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      border: Border.all(
        color: warning ? AppColors.danger.withValues(alpha: .38) : AppColors.outline,
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: compact ? 17 : 20,
            color: warning ? AppColors.danger : AppColors.brand,
          ),
          SizedBox(width: compact ? 4 : AppSpacing.xs),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontSize: compact ? 13.5 : null,
                  color: warning ? AppColors.danger : AppColors.brandDark,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
