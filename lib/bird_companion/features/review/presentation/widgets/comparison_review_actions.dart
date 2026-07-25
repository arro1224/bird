import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

class ComparisonReviewActions extends StatelessWidget {
  const ComparisonReviewActions({
    super.key,
    required this.leftRetained,
    required this.rightRetained,
    required this.selectedFeatured,
    required this.busy,
    required this.onKeepLeft,
    required this.onKeepRight,
    required this.onKeepBoth,
    required this.onFeatureSelected,
  });

  final bool leftRetained;
  final bool rightRetained;
  final bool selectedFeatured;
  final bool busy;
  final VoidCallback onKeepLeft;
  final VoidCallback onKeepRight;
  final VoidCallback onKeepBoth;
  final VoidCallback onFeatureSelected;

  @override
  Widget build(BuildContext context) {
    final bothRetained = leftRetained && rightRetained;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ComparisonActionButton(
                label: '保留左图',
                selected: leftRetained && !bothRetained,
                onPressed: busy ? null : onKeepLeft,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ComparisonActionButton(
                label: '保留右图',
                selected: rightRetained && !bothRetained,
                onPressed: busy ? null : onKeepRight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ComparisonActionButton(
                label: '保留两张',
                selected: bothRetained,
                onPressed: busy ? null : onKeepBoth,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ComparisonActionButton(
                label: '设为精选',
                selected: selectedFeatured,
                featured: true,
                onPressed: busy ? null : onFeatureSelected,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ComparisonActionButton extends StatelessWidget {
  const _ComparisonActionButton({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.featured = false,
  });

  final String label;
  final bool selected;
  final bool featured;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = featured ? AppColors.amber : AppColors.brand;
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? Colors.white : color,
        backgroundColor: selected ? color : Colors.transparent,
        side: BorderSide(color: selected ? color : AppColors.outline),
        minimumSize: const Size.fromHeight(56),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      icon: Icon(
        featured ? Icons.star_outline_rounded : Icons.check_circle_outline,
      ),
      label: Text(
        selected ? (featured ? '已设为精选' : '$label（已选）') : label,
        maxLines: 2,
        textAlign: TextAlign.center,
      ),
    );
  }
}
