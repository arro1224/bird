import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/core/widgets/page_back_button.dart';
import 'package:flutter/material.dart';

/// Shared secondary-page title bar used inside the three-tab shell.
class BirdSecondaryAppBar extends AppBar {
  BirdSecondaryAppBar({
    super.key,
    required String title,
    String? subtitle,
    VoidCallback? onHelp,
    String helpTooltip = '页面说明',
    List<Widget> trailing = const [],
    Widget? leading,
  }) : super(
         leading: leading ?? const BirdPageBackButton(),
         centerTitle: true,
         toolbarHeight: subtitle == null ? 64 : 72,
         title: Column(
           mainAxisSize: MainAxisSize.min,
           children: [
             Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
             if (subtitle != null)
               Text(
                 subtitle,
                 maxLines: 1,
                 overflow: TextOverflow.ellipsis,
                 style: const TextStyle(
                   fontSize: 12,
                   color: AppColors.inkMuted,
                   fontWeight: FontWeight.w400,
                 ),
               ),
           ],
         ),
         actions: [
           ...trailing,
           if (onHelp != null)
             IconButton(
               tooltip: helpTooltip,
               onPressed: onHelp,
               icon: const Icon(Icons.help_outline_rounded),
             ),
           const SizedBox(width: AppSpacing.xs),
         ],
       );
}

enum BirdReviewLevel { batch, scene, group, photo }

/// A narrow-screen-safe, visible path through the review hierarchy.
class BirdReviewBreadcrumb extends StatelessWidget {
  const BirdReviewBreadcrumb({
    super.key,
    required this.current,
    this.onBatch,
    this.onScene,
    this.onGroup,
    this.onPhoto,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.pageHorizontal,
    ),
  });

  final BirdReviewLevel current;
  final VoidCallback? onBatch;
  final VoidCallback? onScene;
  final VoidCallback? onGroup;
  final VoidCallback? onPhoto;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    const steps = <(BirdReviewLevel, String)>[
      (BirdReviewLevel.batch, '拍摄记录'),
      (BirdReviewLevel.scene, '场景'),
      (BirdReviewLevel.group, '连拍照片'),
      (BirdReviewLevel.photo, '单张照片'),
    ];
    return Semantics(
      label: '当前位置：${steps[current.index].$2}',
      child: SingleChildScrollView(
        key: const ValueKey('review-breadcrumb-scroll'),
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.paperStrong.withValues(alpha: .88),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.outline),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120C2915),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: AppSpacing.xs),
                  child: Icon(
                    Icons.account_tree_outlined,
                    size: 18,
                    color: AppColors.brand,
                  ),
                ),
                for (var index = 0; index < steps.length; index++) ...[
                  if (index > 0)
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 17,
                      color: AppColors.inkMuted,
                    ),
                  _BreadcrumbStep(
                    label: steps[index].$2,
                    active: steps[index].$1 == current,
                    onTap: _handler(steps[index].$1),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  VoidCallback? _handler(BirdReviewLevel level) => switch (level) {
    BirdReviewLevel.batch => onBatch,
    BirdReviewLevel.scene => onScene,
    BirdReviewLevel.group => onGroup,
    BirdReviewLevel.photo => onPhoto,
  };
}

class _BreadcrumbStep extends StatelessWidget {
  const _BreadcrumbStep({
    required this.label,
    required this.active,
    this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      foregroundColor: active ? AppColors.brandDark : AppColors.inkMuted,
      disabledForegroundColor: active ? AppColors.brandDark : AppColors.inkMuted,
      textStyle: TextStyle(
        fontSize: 14,
        fontWeight: active ? FontWeight.w800 : FontWeight.w500,
      ),
    ),
    child: Text(label),
  );
}
