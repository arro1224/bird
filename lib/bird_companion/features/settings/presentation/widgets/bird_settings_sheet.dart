import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:flutter/material.dart';

Future<T?> showBirdSettingsSheet<T>({
  required BuildContext context,
  required String title,
  required Widget child,
  Widget? footer,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  backgroundColor: AppColors.paperStrong,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(
      top: Radius.circular(AppSpacing.radiusSheet),
    ),
  ),
  builder: (sheetContext) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.ml,
        right: AppSpacing.ml,
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 5,
            margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.outlineStrong,
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
          ),
          Row(
            children: [
              const SizedBox(width: AppSpacing.minimumControl),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                    color: AppColors.forestDeep,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(sheetContext),
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppColors.forestPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Flexible(child: SingleChildScrollView(child: child)),
          if (footer != null) ...[
            const SizedBox(height: AppSpacing.md),
            footer,
          ],
        ],
      ),
    ),
  ),
);

class BirdSettingsValueRow extends StatelessWidget {
  const BirdSettingsValueRow({
    super.key,
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: AppColors.mutedInk),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: AppColors.forestDeep,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
      if (showDivider) const Divider(height: 1, color: AppColors.divider),
    ],
  );
}
