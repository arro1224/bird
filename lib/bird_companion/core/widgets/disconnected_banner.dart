import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class DisconnectedBanner extends StatelessWidget {
  const DisconnectedBanner({
    super.key,
    required this.isConnected,
    this.lastUpdatedAt,
    this.onReconnect,
  });

  final bool isConnected;
  final DateTime? lastUpdatedAt;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    if (isConnected) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final lastUpdated = lastUpdatedAt == null ? '' : ' 最后更新：${TimeOfDay.fromDateTime(lastUpdatedAt!).format(context)}。';
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text('与盒子的连接已断开，盒子任务仍会继续执行。$lastUpdated', style: TextStyle(color: scheme.onErrorContainer)),
            ),
            if (onReconnect != null) TextButton(onPressed: onReconnect, child: const Text('重连')),
          ],
        ),
      ),
    );
  }
}
