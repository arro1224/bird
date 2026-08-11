import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class BirdSettingsRow extends StatelessWidget {
  const BirdSettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.showDivider = true,
    this.minHeight = 48,
    this.titleFontSize,
    this.subtitleFontSize,
    this.titleColor,
    this.titleFontWeight,
    this.leadingSize = 44,
    this.leadingGap = AppSpacing.sm,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;
  final double minHeight;
  final double? titleFontSize;
  final double? subtitleFontSize;
  final Color? titleColor;
  final FontWeight? titleFontWeight;
  final double leadingSize;
  final double leadingGap;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          child: Padding(
            padding: EdgeInsets.zero,
            child: Row(
              children: [
                if (leading != null) ...[
                  SizedBox.square(
                    dimension: leadingSize,
                    child: Center(child: leading),
                  ),
                  SizedBox(width: leadingGap),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: titleColor ?? AppColors.forestDeep,
                          fontWeight: titleFontWeight ?? FontWeight.w700,
                          height: 1.2,
                          fontSize: titleFontSize,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.mutedInk,
                            fontSize: subtitleFontSize ?? 14,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
      if (showDivider) const Divider(height: 1, color: AppColors.divider),
    ],
  );
}
