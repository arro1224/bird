import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:flutter/material.dart';

class ProvisioningMethodCard extends StatelessWidget {
  const ProvisioningMethodCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.disabledReason,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final foreground = enabled ? AppColors.brand : AppColors.inkMuted;
    return BirdCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: enabled ? AppColors.brandLight : AppColors.mist,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: foreground, size: 28),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (!enabled && disabledReason != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    disabledReason!,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Icon(
              enabled ? Icons.chevron_right_rounded : Icons.lock_outline_rounded,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}
