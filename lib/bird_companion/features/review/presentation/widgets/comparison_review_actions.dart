import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:flutter/material.dart';

class ComparisonReviewActions extends StatelessWidget {
  const ComparisonReviewActions({
    super.key,
    required this.selectedState,
    required this.itemCount,
    required this.busy,
    required this.onDiscardSelected,
    required this.onKeepSelected,
    required this.onKeepAll,
    required this.onFeatureSelected,
  });

  final KeepState selectedState;
  final int itemCount;
  final bool busy;
  final VoidCallback onDiscardSelected;
  final VoidCallback onKeepSelected;
  final VoidCallback onKeepAll;
  final VoidCallback onFeatureSelected;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: _ComparisonActionButton(
              label: '弃用当前',
              icon: Icons.delete_outline_rounded,
              color: AppColors.danger,
              selected: selectedState == KeepState.discard,
              onPressed: busy ? null : onDiscardSelected,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ComparisonActionButton(
              label: '保留当前',
              icon: Icons.check_circle_outline_rounded,
              color: AppColors.brand,
              selected: selectedState == KeepState.keep,
              onPressed: busy ? null : onKeepSelected,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ComparisonActionButton(
              label: '设为精选',
              icon: Icons.star_outline_rounded,
              color: AppColors.amber,
              selected: selectedState == KeepState.featured,
              onPressed: busy ? null : onFeatureSelected,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: _ComparisonActionButton(
          label: '保留全部 $itemCount 张',
          icon: Icons.library_add_check_outlined,
          color: AppColors.brand,
          selected: false,
          onPressed: busy ? null : onKeepAll,
        ),
      ),
    ],
  );
}

class _ComparisonActionButton extends StatelessWidget {
  const _ComparisonActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: selected ? Colors.white : color,
      backgroundColor: selected ? color : Colors.transparent,
      side: BorderSide(color: selected ? color : AppColors.outline),
      minimumSize: const Size.fromHeight(56),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    ),
    icon: Icon(icon, size: 20),
    label: Text(
      selected ? '$label（已选）' : label,
      maxLines: 2,
      textAlign: TextAlign.center,
    ),
  );
}
