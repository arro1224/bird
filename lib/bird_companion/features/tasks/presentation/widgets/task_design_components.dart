import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:flutter/material.dart';

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
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class TaskSurface extends StatelessWidget {
  const TaskSurface({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surface.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(color: Color(0x120E351D), blurRadius: 14, offset: Offset(0, 4)),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class TaskStatusChip extends StatelessWidget {
  const TaskStatusChip({super.key, required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.forestSoft.withValues(alpha: .65),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.forestPrimary),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: AppColors.forestPrimary)),
        ],
      ),
    ),
  );
}

class TaskMetricRow extends StatelessWidget {
  const TaskMetricRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.divider = true,
    this.valueStyle,
  });

  final String label;
  final String value;
  final IconData? icon;
  final bool divider;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 240 || MediaQuery.textScalerOf(context).scale(1) >= 1.3;
          final labelWidget = Text(label);
          final valueWidget = Text(
            value,
            key: ValueKey('task-metric-value-$label'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: stacked ? TextAlign.start : TextAlign.end,
            style: valueStyle ?? const TextStyle(color: AppColors.forestPrimary, fontWeight: FontWeight.w700),
          );
          return ConstrainedBox(
            key: ValueKey('task-metric-row-$label'),
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: AppColors.forestPrimary),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: stacked
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [labelWidget, const SizedBox(height: 4), valueWidget],
                          )
                        : Row(
                            children: [
                              labelWidget,
                              const SizedBox(width: 12),
                              Expanded(child: valueWidget),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      if (divider) const Divider(height: 1),
    ],
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
      color: AppColors.surface.withValues(alpha: .82),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: AppColors.divider),
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
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
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
