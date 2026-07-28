import 'package:flutter/material.dart';

const groupReviewComparisonActionKey = ValueKey('group-review-compare-action');

class GroupReviewComparisonAction extends StatelessWidget {
  const GroupReviewComparisonAction({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: groupReviewComparisonActionKey,
    onPressed: onPressed,
    icon: const Icon(Icons.compare_rounded),
    label: const Text('对比最推荐的 2 张'),
  );
}
