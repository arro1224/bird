import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class BirdSettingsCard extends StatelessWidget {
  const BirdSettingsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.margin = EdgeInsets.zero,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => Container(
    margin: margin,
    padding: padding,
    decoration: BoxDecoration(
      color: AppColors.settingsSurface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      border: Border.all(color: borderColor ?? AppColors.divider.withValues(alpha: .75)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x10142A1B),
          blurRadius: 18,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: child,
  );
}

class BirdSettingsSectionLabel extends StatelessWidget {
  const BirdSettingsSectionLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.sm),
    child: Text(
      label,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: AppColors.mutedInk,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
