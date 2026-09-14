import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

class BatchFilterBar extends StatelessWidget {
  const BatchFilterBar({super.key, required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SegmentedButton<String?>(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(82, 48)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.brand : AppColors.paperStrong,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.cream : AppColors.brandDark,
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected) ? AppColors.brand : AppColors.outlineStrong,
            width: states.contains(WidgetState.selected) ? 1.5 : 1,
          ),
        ),
        textStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w700,
          ),
        ),
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.pressed) ? AppColors.brand.withValues(alpha: .14) : null,
        ),
      ),
      segments: const [
        ButtonSegment(
          value: null,
          label: Text('全部', key: Key('batch-filter-all')),
        ),
        ButtonSegment(
          value: 'in_progress',
          label: Text('进行中', key: Key('batch-filter-in-progress')),
        ),
        ButtonSegment(
          value: 'review',
          label: Text('待挑选', key: Key('batch-filter-review')),
        ),
        ButtonSegment(
          value: 'failed',
          label: Text('异常', key: Key('batch-filter-failed')),
        ),
      ],
      selected: {value},
      emptySelectionAllowed: false,
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.first),
    ),
  );
}
