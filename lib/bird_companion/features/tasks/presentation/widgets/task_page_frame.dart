import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_nature_background.dart';
import 'package:flutter/material.dart';

class TaskPageFrame extends StatelessWidget {
  const TaskPageFrame({super.key, required this.title, required this.child, this.subtitle, this.actions});
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.paper,
    body: Stack(
      children: [
        const Positioned.fill(child: TaskNatureBackground()),
        SafeArea(
          bottom: false,
          child: Column(
            children: [
              TaskFlowHeader(
                title: title,
                subtitle: subtitle,
                actions: actions,
                onBack: () => Navigator.maybePop(context),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24, subtitle == null ? 14 : 1, 24, 28),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class TaskFlowHeader extends StatelessWidget {
  const TaskFlowHeader({
    super.key,
    required this.title,
    required this.onBack,
    this.subtitle,
    this.actions,
    this.backButtonKey = const Key('task-page-back-button'),
  });

  final String title;
  final String? subtitle;
  final VoidCallback onBack;
  final List<Widget>? actions;
  final Key backButtonKey;

  @override
  Widget build(BuildContext context) {
    final actionCount = actions?.length ?? 0;
    final sideWidth = actionCount == 0 ? 56.0 : (actionCount * 48.0).clamp(56.0, 112.0).toDouble();
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final baseHeight = subtitle == null ? 68.0 : 105.0;
    final scaleAllowance = subtitle == null ? 128.0 : 76.0;
    final headerHeight = (baseHeight + scaleAllowance * (textScale - 1)).clamp(baseHeight, subtitle == null ? 164.0 : 160.0).toDouble();

    return Container(
      key: const Key('task-flow-header'),
      width: double.infinity,
      height: headerHeight,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: NavigationToolbar(
        centerMiddle: true,
        middleSpacing: 0,
        leading: SizedBox(
          width: sideWidth,
          child: Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              key: backButtonKey,
              onPressed: onBack,
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: AppColors.forestDeep,
              ),
            ),
          ),
        ),
        middle: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                key: const Key('task-flow-title'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.forestDeep,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 7),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.mutedInk, fontSize: 15),
                ),
              ],
            ],
          ),
        ),
        trailing: SizedBox(
          width: sideWidth,
          child: Align(
            alignment: Alignment.centerRight,
            child: actionCount == 0 ? const SizedBox.shrink() : Row(mainAxisSize: MainAxisSize.min, children: actions!),
          ),
        ),
      ),
    );
  }
}

class TaskActionButton extends StatelessWidget {
  const TaskActionButton(this.label, {super.key, required this.onPressed, this.filled = true});
  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: double.infinity, minHeight: 56),
    child: filled
        ? FilledButton(
            onPressed: onPressed,
            child: Text(label, textAlign: TextAlign.center),
          )
        : OutlinedButton(
            onPressed: onPressed,
            child: Text(label, textAlign: TextAlign.center),
          ),
  );
}
