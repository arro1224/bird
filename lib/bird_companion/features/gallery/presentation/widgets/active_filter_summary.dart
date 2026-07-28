import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// A compact summary of the filters currently applied to the gallery.
///
/// The collapsed state deliberately occupies a single row. Users can expand
/// the summary when they need to inspect every active condition.
class ActiveFilterSummary extends StatefulWidget {
  const ActiveFilterSummary({
    super.key,
    required this.labels,
    required this.onClear,
  });

  final List<String> labels;
  final VoidCallback onClear;

  @override
  State<ActiveFilterSummary> createState() => _ActiveFilterSummaryState();
}

class _ActiveFilterSummaryState extends State<ActiveFilterSummary> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.labels.isEmpty) return const SizedBox.shrink();

    final borderRadius = BorderRadius.circular(AppSpacing.radiusCard);
    final visibleLabels = widget.labels.take(2).join(' · ');
    final remainingCount = widget.labels.length - 2;
    final compactSummary = remainingCount > 0 ? '$visibleLabels · +$remainingCount' : visibleLabels;
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: DecoratedBox(
        key: const ValueKey('active-filter-summary'),
        decoration: BoxDecoration(
          color: AppColors.paperStrong.withValues(alpha: .82),
          borderRadius: borderRadius,
          border: Border.all(color: AppColors.outlineStrong),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              button: true,
              expanded: _expanded,
              label: _expanded ? '收起筛选条件' : '展开筛选条件',
              child: InkWell(
                key: const ValueKey('active-filter-toggle'),
                borderRadius: borderRadius,
                onTap: () => setState(() => _expanded = !_expanded),
                child: SizedBox(
                  height: AppSpacing.minimumTouchTarget,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.filter_alt_outlined,
                          size: 19,
                          color: AppColors.brand,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            compactSummary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: AppColors.brandDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('active-filter-clear'),
                          tooltip: '清除全部筛选',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 38,
                            height: 38,
                          ),
                          onPressed: widget.onClear,
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 19,
                            color: AppColors.inkMuted,
                          ),
                        ),
                        Icon(
                          _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          color: AppColors.brand,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_expanded) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.sm,
                  AppSpacing.sm,
                  AppSpacing.xs,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final label in widget.labels)
                        Chip(
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: const VisualDensity(
                            horizontal: -2,
                            vertical: -2,
                          ),
                          label: Text(label),
                        ),
                      TextButton.icon(
                        onPressed: widget.onClear,
                        icon: const Icon(Icons.clear_all_rounded, size: 18),
                        label: const Text('清除全部'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
