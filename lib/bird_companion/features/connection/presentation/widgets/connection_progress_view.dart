import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/k7_device_artwork.dart';
import 'package:flutter/material.dart';

class ConnectionProgressView extends StatelessWidget {
  const ConnectionProgressView({
    super.key,
    required this.deviceName,
    required this.onCancel,
  });

  final String deviceName;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.pageHorizontal,
      AppSpacing.md,
      AppSpacing.pageHorizontal,
      AppSpacing.xl,
    ),
    children: [
      SizedBox(
        height: 320,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const SizedBox.square(
              dimension: 270,
              child: CircularProgressIndicator(
                strokeWidth: 8,
                strokeCap: StrokeCap.round,
                backgroundColor: AppColors.brandLight,
              ),
            ),
            const K7DeviceArtwork(size: 205),
            Positioned(
              right: 26,
              bottom: 28,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.paperStrong,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.outline),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  child: Icon(Icons.wifi_find_rounded, color: AppColors.brand),
                ),
              ),
            ),
          ],
        ),
      ),
      Text(
        deviceName,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        '正在验证设备状态，请稍候……',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      const BirdCard(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Column(
          children: [
            _ConnectionStep(
              state: _StepState.done,
              title: '已确认连接地址',
              subtitle: '设备地址格式已验证',
            ),
            Divider(),
            _ConnectionStep(
              state: _StepState.active,
              title: '正在验证设备状态',
              subtitle: '正在建立本地连接，请稍候',
            ),
            Divider(),
            _ConnectionStep(
              state: _StepState.waiting,
              title: '准备同步本地数据',
              subtitle: '连接成功后将自动刷新',
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      const _KeepNearbyNote(),
      const SizedBox(height: AppSpacing.lg),
      BirdButton(
        label: '返回查找设备',
        onPressed: onCancel,
        variant: BirdButtonVariant.outlined,
      ),
    ],
  );
}

enum _StepState { done, active, waiting }

class _ConnectionStep extends StatelessWidget {
  const _ConnectionStep({
    required this.state,
    required this.title,
    required this.subtitle,
  });

  final _StepState state;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final active = state != _StepState.waiting;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 42,
            child: switch (state) {
              _StepState.done => const CircleAvatar(
                backgroundColor: AppColors.brand,
                foregroundColor: AppColors.cream,
                child: Icon(Icons.check_rounded),
              ),
              _StepState.active => const CircularProgressIndicator(strokeWidth: 4),
              _StepState.waiting => const CircleAvatar(backgroundColor: AppColors.outline),
            },
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: active ? null : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            switch (state) {
              _StepState.done => '已完成',
              _StepState.active => '进行中',
              _StepState.waiting => '等待中',
            },
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: active ? AppColors.brand : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _KeepNearbyNote extends StatelessWidget {
  const _KeepNearbyNote();

  @override
  Widget build(BuildContext context) => const BirdCard(
    backgroundColor: AppColors.brandLight,
    padding: EdgeInsets.all(AppSpacing.sm),
    child: Row(
      children: [
        Icon(Icons.near_me_outlined, color: AppColors.brand),
        SizedBox(width: AppSpacing.sm),
        Expanded(child: Text('请保持 App 在前台，并确保手机与盒子网络连接稳定。')),
      ],
    ),
  );
}
