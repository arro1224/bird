import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:flutter/material.dart';

class DeviceMetricsGrid extends StatelessWidget {
  const DeviceMetricsGrid({super.key, required this.status});
  final DeviceStatus status;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 22),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _Metric(label: '电量', value: status.batteryPercent == null ? '—' : '${status.batteryPercent}%'),
        _Metric(label: '温度', value: status.temperatureCelsius == null ? '—' : '${status.temperatureCelsius!.toStringAsFixed(0)}℃'),
        _Metric(label: '剩余容量', value: status.storageFreeBytes == null ? '—' : _storage(status.storageFreeBytes!)),
      ],
    ),
  );
  static String _storage(int bytes) => bytes >= 1000000000000 ? '${(bytes / 1000000000000).toStringAsFixed(1)} TB' : '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(0)} GB';
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 6),
      Text(value, style: Theme.of(context).textTheme.titleLarge),
    ],
  );
}
