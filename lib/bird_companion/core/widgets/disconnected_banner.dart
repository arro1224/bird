import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class DisconnectedBanner extends StatelessWidget {
  const DisconnectedBanner({
    super.key,
    required this.isConnected,
    this.lastUpdatedAt,
    this.onReconnect,
    this.isVerifying = false,
    this.message,
  });

  final bool isConnected;
  final DateTime? lastUpdatedAt;
  final VoidCallback? onReconnect;
  final bool isVerifying;
  final String? message;

  @override
  Widget build(BuildContext context) {
    if (isConnected) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final lastUpdated = lastUpdatedAt == null ? '' : ' 最后更新：${TimeOfDay.fromDateTime(lastUpdatedAt!).format(context)}。';
    return Material(
      color: isVerifying ? scheme.secondaryContainer : scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        child: Row(
          children: [
            Icon(isVerifying ? Icons.sync_rounded : Icons.wifi_off_rounded, color: isVerifying ? scheme.onSecondaryContainer : scheme.onErrorContainer),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(message ?? (isVerifying ? '正在恢复盒子连接，当前内容为手机缓存。' : '与盒子的连接已断开，盒子仍会继续处理照片。$lastUpdated'), style: TextStyle(color: isVerifying ? scheme.onSecondaryContainer : scheme.onErrorContainer)),
            ),
            if (onReconnect != null && !isVerifying) TextButton(onPressed: onReconnect, child: const Text('重连')),
          ],
        ),
      ),
    );
  }
}
