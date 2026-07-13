import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

enum StatusBadgeType { neutral, success, warning, error, info }

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.type = StatusBadgeType.neutral,
    this.icon,
  });

  final String label;
  final StatusBadgeType type;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: colors.$1, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: colors.$2),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.$2, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  (Color, Color) _colors(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (type) {
      StatusBadgeType.success => (AppColors.success.withValues(alpha: .14), AppColors.success),
      StatusBadgeType.warning => (AppColors.warning.withValues(alpha: .14), AppColors.warning),
      StatusBadgeType.error => (scheme.errorContainer, scheme.onErrorContainer),
      StatusBadgeType.info => (AppColors.info.withValues(alpha: .14), AppColors.info),
      StatusBadgeType.neutral => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
  }
}
