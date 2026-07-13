import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:flutter/material.dart';

class DeviceAlertBanner extends StatelessWidget {
  const DeviceAlertBanner({super.key, required this.status, this.onTap});

  final DeviceStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final alert = _alert;
    if (alert == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(AppSpacing.radiusMedium)),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(alert, style: TextStyle(color: scheme.onErrorContainer)),
            ),
          ],
        ),
      ),
    );
  }

  String? get _alert {
    if (status.hasError) return status.errorMessage ?? '盒子报告错误：${status.errorCode}';
    if (!status.card.inserted) return '未插入存储卡。你仍可查看历史批次和任务记录。';
    if ((status.temperatureCelsius ?? 0) >= 70) return '盒子温度较高，任务可能暂停或降载。';
    if ((status.batteryPercent ?? 100) <= 15 && !status.isExternalPower) return '电量不足，请连接电源后继续复制或深度分析。';
    return null;
  }
}
