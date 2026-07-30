import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:flutter/material.dart';

abstract final class TaskDesign {
  static const pagePadding = EdgeInsets.fromLTRB(24, 18, 24, 24);
  static const green = AppColors.forestPrimary;
  static const deepGreen = AppColors.forestDeep;
  static const muted = AppColors.mutedInk;
  static const surface = AppColors.surface;
  static const divider = AppColors.divider;
  static const shadow = BoxShadow(
    color: Color(0x160E351D),
    blurRadius: 22,
    offset: Offset(0, 8),
  );

  static Color stateColor(TaskRunState state) => switch (state) {
    TaskRunState.failed || TaskRunState.cancelled => AppColors.danger,
    TaskRunState.paused || TaskRunState.queued => AppColors.warning,
    TaskRunState.running || TaskRunState.completed => AppColors.forestPrimary,
  };
}

class TaskSectionTitle extends StatelessWidget {
  const TaskSectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.forestDeep,
        fontSize: 21,
        fontWeight: FontWeight.w800,
        height: 1.15,
      ),
    ),
  );
}

class TaskSurface extends StatelessWidget {
  const TaskSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 18,
    this.withBorder = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final bool withBorder;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: .965),
        borderRadius: borderRadius,
        border: withBorder ? Border.all(color: AppColors.divider.withValues(alpha: .82)) : null,
        boxShadow: const [TaskDesign.shadow],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class TaskStatusChip extends StatelessWidget {
  const TaskStatusChip({super.key, required this.label, required this.icon, this.color = AppColors.forestPrimary});

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class TaskGroupFilter extends StatelessWidget {
  const TaskGroupFilter({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final TaskGroup selected;
  final ValueChanged<TaskGroup> onSelected;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surface.withValues(alpha: .72),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: AppColors.divider.withValues(alpha: .72)),
    ),
    child: Row(
      children: [
        _item(TaskGroup.active, '进行中'),
        _item(TaskGroup.attention, '需处理'),
        _item(TaskGroup.completed, '已完成'),
      ],
    ),
  );

  Widget _item(TaskGroup group, String label) {
    final isSelected = selected == group;
    return Expanded(
      child: SizedBox(
        key: Key('task-group-${group.name}'),
        height: 48,
        child: Material(
          color: isSelected ? AppColors.forestPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => onSelected(group),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.forestDeep,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TaskDisconnectedNotice extends StatelessWidget {
  const TaskDisconnectedNotice({super.key});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.amberLight.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.warning.withValues(alpha: .34)),
    ),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 22,
            color: AppColors.warning,
          ),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              '连接已断开，盒子任务可能仍在运行；重新连接后刷新任务进度。',
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class TaskPrimaryButton extends StatelessWidget {
  const TaskPrimaryButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.icon,
    this.filled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 56,
    child: icon == null
        ? filled
              ? FilledButton(onPressed: onPressed, child: Text(label))
              : OutlinedButton(onPressed: onPressed, child: Text(label))
        : filled
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          ),
  );
}

class TaskBottomActions extends StatelessWidget {
  const TaskBottomActions({
    super.key,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.secondaryFirst = false,
  });

  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool secondaryFirst;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(24, 10, 24, 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (secondaryFirst && secondaryLabel != null) ...[
          TaskPrimaryButton(
            secondaryLabel!,
            filled: false,
            onPressed: onSecondary,
          ),
          const SizedBox(height: 10),
        ],
        TaskPrimaryButton(primaryLabel, onPressed: onPrimary),
        if (!secondaryFirst && secondaryLabel != null) ...[
          const SizedBox(height: 10),
          TaskPrimaryButton(
            secondaryLabel!,
            filled: false,
            onPressed: onSecondary,
          ),
        ],
      ],
    ),
  );
}

class TaskMetricRow extends StatelessWidget {
  const TaskMetricRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
    this.valueColor = AppColors.forestPrimary,
    this.divider = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;
  final Color valueColor;
  final bool divider;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 62),
        child: Row(
          children: [
            Icon(icon, color: AppColors.forestPrimary, size: 28),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: AppColors.ink, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: TextStyle(color: valueColor, fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing!],
          ],
        ),
      ),
      if (divider) const Divider(height: 1),
    ],
  );
}
