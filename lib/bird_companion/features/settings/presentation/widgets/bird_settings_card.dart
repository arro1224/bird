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
      color: AppColors.settingsSurface.withValues(alpha: .96),
      borderRadius: BorderRadius.circular(16),
      border: borderColor == null ? null : Border.all(color: borderColor!),
      boxShadow: const [
        BoxShadow(
          color: Color(0x15142A1B),
          blurRadius: 22,
          offset: Offset(0, 7),
        ),
      ],
    ),
    child: Material(type: MaterialType.transparency, child: child),
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
        color: AppColors.forestDeep,
        fontWeight: FontWeight.w800,
        fontSize: 20,
      ),
    ),
  );
}
