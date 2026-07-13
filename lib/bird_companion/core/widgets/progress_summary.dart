import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class ProgressSummary extends StatelessWidget {
  const ProgressSummary({
    super.key,
    required this.completed,
    required this.total,
    this.label,
    this.trailing,
  });

  final int completed;
  final int total;
  final String? label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final safeTotal = total <= 0 ? 1 : total;
    final progress = (completed / safeTotal).clamp(0.0, 1.0);
    final percent = (progress * 100).round();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (label case final label?) Expanded(child: Text(label, style: Theme.of(context).textTheme.titleSmall)),
            ?trailing,
            Text('$completed / $total · $percent%', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Semantics(
          label: '${label ?? '进度'}：$completed / $total，$percent%',
          value: '$percent%',
          child: LinearProgressIndicator(value: progress, minHeight: 8, borderRadius: BorderRadius.circular(99)),
        ),
      ],
    );
  }
}
