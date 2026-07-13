import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:flutter/material.dart';

class DeviceHeader extends StatelessWidget {
  const DeviceHeader({super.key, required this.status});
  final DeviceStatus status;
  @override
  Widget build(BuildContext context) {
    final job = status.currentJob;
    final progress = job?.progress ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BirdConnectionLine(),
        const SizedBox(height: 36),
        Text('设备状态', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text('${status.connection.name} · ${status.connection.id}', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 24),
        Card(
          color: AppColors.brand,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '状态良好',
                  style: TextStyle(fontSize: 27, color: Colors.white, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(job == null ? '盒子已就绪，等待新照片' : '正在${job.type.label} SD 卡中的新照片', style: const TextStyle(color: Color(0xFFD9F0D8), fontSize: 17)),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(value: progress, minHeight: 12, color: const Color(0xFF338D70), backgroundColor: const Color(0xFFD9F0D8)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '${(progress * 100).round()}%',
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
