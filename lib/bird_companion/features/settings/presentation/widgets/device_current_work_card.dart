import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class DeviceCurrentWorkCard extends StatelessWidget {
  const DeviceCurrentWorkCard({
    super.key,
    required this.batchTitle,
    required this.batchSummary,
    required this.taskTitle,
    required this.taskSummary,
    required this.onOpenBatch,
    required this.onOpenTask,
    this.isDemo = false,
  });

  final String batchTitle;
  final String batchSummary;
  final String taskTitle;
  final String taskSummary;
  final VoidCallback onOpenBatch;
  final VoidCallback onOpenTask;
  final bool isDemo;

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('device-current-work-card'),
    color: AppColors.surface.withValues(alpha: .97),
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    elevation: 3,
    shadowColor: const Color(0x15142A1B),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CurrentWorkRow(
          key: const Key('device-current-work-batch'),
          icon: Icons.photo_library_outlined,
          title: batchTitle,
          summary: batchSummary,
          onTap: onOpenBatch,
          badge: isDemo ? '演示数据' : null,
        ),
        const Divider(height: 1, color: AppColors.divider),
        _CurrentWorkRow(
          key: const Key('device-current-work-task'),
          icon: Icons.assignment_outlined,
          title: taskTitle,
          summary: taskSummary,
          onTap: onOpenTask,
        ),
      ],
    ),
  );
}

class _CurrentWorkRow extends StatelessWidget {
  const _CurrentWorkRow({
    super.key,
    required this.icon,
    required this.title,
    required this.summary,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String summary;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 60),
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 36,
              child: Center(
                child: Icon(icon, size: 21, color: AppColors.forestPrimary),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.forestDeep,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.mutedInk,
                      fontSize: 14,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: AppSpacing.xs),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.forestSoft,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs,
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      color: AppColors.forestDeep,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(width: AppSpacing.xxs),
            const Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: AppColors.forestDeep,
            ),
          ],
        ),
      ),
    ),
  );
}
