import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:flutter/material.dart';

class DeviceMetricsGrid extends StatelessWidget {
  const DeviceMetricsGrid({super.key, required this.status, this.onTap});

  final DeviceStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _Metric(icon: Icons.battery_5_bar_rounded, label: '电量', value: status.batteryPercent == null ? '—' : '${status.batteryPercent}%'),
              ),
              const VerticalDivider(),
              Expanded(
                child: _Metric(icon: Icons.thermostat_rounded, label: '温度', value: status.temperatureCelsius == null ? '—' : '${status.temperatureCelsius!.toStringAsFixed(0)}°C'),
              ),
              const VerticalDivider(),
              Expanded(
                child: _Metric(icon: Icons.storage_rounded, label: '内部存储', value: status.storageFreeBytes == null ? '—' : _storage(status.storageFreeBytes!), note: '可用'),
              ),
              const VerticalDivider(),
              Expanded(
                child: _Metric(icon: Icons.sd_card_rounded, label: 'SD 卡', value: status.card.inserted ? '已插入' : '未插入'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  static String _storage(int bytes) => bytes >= 1000000000000 ? '${(bytes / 1000000000000).toStringAsFixed(1)} TB' : '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(0)} GB';
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value, this.note});

  final IconData icon;
  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: AppColors.brand, size: 25),
      const SizedBox(height: 5),
      Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
      ),
      const SizedBox(height: 3),
      FittedBox(
        child: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      if (note != null) Text(note!, style: const TextStyle(color: AppColors.inkMuted, fontSize: 12)),
    ],
  );
}
