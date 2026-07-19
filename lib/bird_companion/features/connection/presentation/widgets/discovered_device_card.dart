import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/k7_device_artwork.dart';
import 'package:flutter/material.dart';

class DiscoveredDeviceCard extends StatelessWidget {
  const DiscoveredDeviceCard({
    super.key,
    required this.device,
    required this.onConnect,
    this.isRecent = false,
    this.connecting = false,
  });

  final DeviceConnection device;
  final VoidCallback onConnect;
  final bool isRecent;
  final bool connecting;

  @override
  Widget build(BuildContext context) => BirdCard(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 290;
        final details = _DeviceDetails(device: device, isRecent: isRecent);
        final button = BirdButton(
          label: connecting ? '连接中' : '连接',
          onPressed: connecting ? null : onConnect,
          busy: connecting,
          expanded: narrow,
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const K7DeviceArtwork(size: 84),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: details),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              button,
            ],
          );
        }

        return Row(
          children: [
            const K7DeviceArtwork(size: 92),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: details),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(width: 82, child: button),
          ],
        );
      },
    ),
  );
}

class _DeviceDetails extends StatelessWidget {
  const _DeviceDetails({required this.device, required this.isRecent});

  final DeviceConnection device;
  final bool isRecent;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(device.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        '设备号：${_shortId(device.id)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isRecent ? Icons.history_rounded : Icons.wifi_rounded,
            color: isRecent ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.primary,
            size: 17,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              isRecent ? '最近使用 · 状态待确认' : '${device.networkMode.label}发现',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: isRecent ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    ],
  );

  static String _shortId(String value) {
    final id = value.trim();
    if (id.isEmpty) return '—';
    return id.length <= 12 ? id : '…${id.substring(id.length - 8)}';
  }
}
