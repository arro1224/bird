import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/k7_device_artwork.dart';
import 'package:flutter/material.dart';

class ConnectionEmptyView extends StatelessWidget {
  const ConnectionEmptyView({
    super.key,
    required this.onRetry,
    required this.onScan,
    required this.onManual,
  });

  final VoidCallback? onRetry;
  final VoidCallback? onScan;
  final VoidCallback? onManual;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const _EmptyArtwork(),
      const SizedBox(height: AppSpacing.sm),
      Text(
        '暂未发现新的拍鸟伴侣',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        '请按以下步骤检查，或尝试其他连接方式',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: AppSpacing.ml),
      const BirdCard(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Column(
          children: [
            _GuideStep(
              number: 1,
              icon: Icons.battery_charging_full_rounded,
              title: '检查盒子电源',
              description: '确保盒子已开机，电量充足',
            ),
            Divider(),
            _GuideStep(
              number: 2,
              icon: Icons.router_outlined,
              title: '确认盒子网络状态',
              description: '让手机与盒子连接到同一个 Wi-Fi',
            ),
            Divider(),
            _GuideStep(
              number: 3,
              icon: Icons.security_rounded,
              title: '检查本地网络权限',
              description: '允许 App 访问网络后重新搜索',
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.ml),
      BirdButton(label: '重新搜索', onPressed: onRetry, icon: const Icon(Icons.radar_rounded)),
      const SizedBox(height: AppSpacing.sm),
      BirdButton(
        label: '扫码连接',
        onPressed: onScan,
        icon: const Icon(Icons.qr_code_scanner_rounded),
        variant: BirdButtonVariant.outlined,
      ),
      const SizedBox(height: AppSpacing.xs),
      TextButton.icon(
        onPressed: onManual,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('手动输入地址'),
      ),
    ],
  );
}

class _EmptyArtwork extends StatelessWidget {
  const _EmptyArtwork();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 220,
    child: Stack(
      alignment: Alignment.center,
      children: [
        for (final size in [210.0, 162.0, 114.0])
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brandSoft.withValues(alpha: .2)),
            ),
          ),
        Positioned(
          top: 22,
          child: Icon(Icons.search_rounded, size: 70, color: AppColors.brandMid.withValues(alpha: .9)),
        ),
        const Positioned(bottom: 0, child: K7DeviceArtwork(size: 150)),
      ],
    ),
  );
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.description,
  });

  final int number;
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Row(
      children: [
        CircleAvatar(
          radius: 19,
          backgroundColor: AppColors.brandLight,
          foregroundColor: AppColors.brand,
          child: Text('$number', style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(width: AppSpacing.md),
        Icon(icon, size: 30, color: AppColors.brand),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
