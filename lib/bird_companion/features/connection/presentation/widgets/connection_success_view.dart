import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/k7_device_artwork.dart';
import 'package:flutter/material.dart';

class ConnectionSuccessView extends StatelessWidget {
  const ConnectionSuccessView({
    super.key,
    required this.status,
    required this.onOpenGallery,
    required this.onOpenDevice,
  });

  final DeviceStatus status;
  final VoidCallback onOpenGallery;
  final VoidCallback onOpenDevice;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.pageHorizontal,
      AppSpacing.sm,
      AppSpacing.pageHorizontal,
      AppSpacing.xl,
    ),
    children: [
      const Center(
        child: CircleAvatar(
          radius: 38,
          backgroundColor: AppColors.brand,
          foregroundColor: AppColors.cream,
          child: Icon(Icons.check_rounded, size: 50),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      Text(
        status.connection.name,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.displaySmall,
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        status.connection.isPaired ? '已绑定并完成连接' : '已完成连接',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      const Center(child: K7DeviceArtwork(size: 260)),
      const SizedBox(height: AppSpacing.sm),
      BirdCard(
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _SuccessMetric(
                  label: '电量',
                  value: status.batteryPercent == null ? '—' : '${status.batteryPercent}%',
                ),
              ),
              const VerticalDivider(),
              Expanded(
                child: _SuccessMetric(
                  label: '存储可用',
                  value: status.storageFreeBytes == null ? '—' : _storage(status.storageFreeBytes!),
                ),
              ),
              const VerticalDivider(),
              Expanded(
                child: _SuccessMetric(
                  label: 'SD 卡',
                  value: status.card.inserted
                      ? status.card.readable
                            ? '已识别'
                            : '不可读'
                      : '未插入',
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      const BirdCard(
        backgroundColor: AppColors.brandLight,
        padding: EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            Icon(Icons.sync_rounded, color: AppColors.brand),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: Text('以后打开 App 时，将自动尝试连接最近使用的设备。')),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      BirdButton(label: '进入相册', onPressed: onOpenGallery),
      const SizedBox(height: AppSpacing.sm),
      BirdButton(
        label: '查看设备状态',
        onPressed: onOpenDevice,
        variant: BirdButtonVariant.outlined,
      ),
    ],
  );

  static String _storage(int bytes) {
    final gib = bytes / 1024 / 1024 / 1024;
    return gib >= 1024 ? '${(gib / 1024).toStringAsFixed(1)}TB' : '${gib.toStringAsFixed(0)}GB';
  }
}

class _SuccessMetric extends StatelessWidget {
  const _SuccessMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppColors.brand)),
      ),
    ],
  );
}
