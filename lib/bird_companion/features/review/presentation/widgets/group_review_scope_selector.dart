import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

class GroupReviewScopeSelector extends StatelessWidget {
  const GroupReviewScopeSelector({
    super.key,
    required this.applyToWholeGroup,
    required this.memberCount,
    required this.onChanged,
  });

  final bool applyToWholeGroup;
  final int memberCount;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Text(
        '操作范围',
        style: TextStyle(
          color: AppColors.brandDark,
          fontWeight: FontWeight.w800,
        ),
      ),
      const Spacer(),
      Flexible(
        child: SegmentedButton<bool>(
          key: const Key('group-review-action-scope'),
          showSelectedIcon: false,
          segments: [
            const ButtonSegment<bool>(
              value: false,
              label: Text('当前照片'),
            ),
            ButtonSegment<bool>(
              value: true,
              label: Text('整组 $memberCount 张'),
            ),
          ],
          selected: {applyToWholeGroup},
          onSelectionChanged: onChanged == null ? null : (values) => onChanged!(values.first),
        ),
      ),
    ],
  );
}
