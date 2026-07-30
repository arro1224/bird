import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_nature_background.dart';
import 'package:flutter/material.dart';

class TaskPageFrame extends StatelessWidget {
  const TaskPageFrame({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions,
    this.bottomNavigationBar,
    this.padding = const EdgeInsets.fromLTRB(24, 14, 24, 24),
    this.centerTitle = true,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;
  final EdgeInsets padding;
  final bool centerTitle;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.paper,
    bottomNavigationBar: bottomNavigationBar,
    body: Stack(
      children: [
        const Positioned.fill(child: TaskNatureBackground()),
        SafeArea(
          bottom: false,
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: subtitle == null ? 72 : 100,
                child: Stack(
                  alignment: centerTitle ? Alignment.center : Alignment.centerLeft,
                  children: [
                    Positioned(
                      left: 0,
                      top: 8,
                      child: SizedBox(
                        key: const Key('task-page-back-button'),
                        width: 56,
                        height: 56,
                        child: IconButton(
                          tooltip: '返回',
                          onPressed: () => Navigator.maybePop(context),
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: AppColors.forestDeep,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: centerTitle ? 76 : 58,
                      right: centerTitle ? 76 : 58,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.forestDeep, fontSize: 24, fontWeight: FontWeight.w700),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 7),
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.mutedInk, fontSize: 15),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (actions != null) Positioned(right: 8, top: 8, child: Row(children: actions!)),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(padding: padding, child: child),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class TaskActionButton extends StatelessWidget {
  const TaskActionButton(this.label, {super.key, required this.onPressed, this.filled = true});
  final String label;
  final VoidCallback onPressed;
  final bool filled;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 56,
    child: filled ? FilledButton(onPressed: onPressed, child: Text(label)) : OutlinedButton(onPressed: onPressed, child: Text(label)),
  );
}
