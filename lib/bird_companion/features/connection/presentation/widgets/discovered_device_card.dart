import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/widgets/status_badge.dart';
import 'package:flutter/material.dart';

class DiscoveredDeviceCard extends StatelessWidget {
  const DiscoveredDeviceCard({super.key, required this.device, required this.onConnect});

  final DeviceConnection device;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            const CircleAvatar(child: Icon(Icons.memory_outlined)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.name, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(device.baseUri.toString(), style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xxs,
                    children: [
                      StatusBadge(label: device.networkMode.label, type: StatusBadgeType.info),
                      if (device.apiVersion != null) StatusBadge(label: 'API ${device.apiVersion}'),
                      if (device.signalStrength != null) StatusBadge(label: '${device.signalStrength} dBm'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(onPressed: onConnect, child: const Text('连接')),
          ],
        ),
      ),
    );
  }
}
