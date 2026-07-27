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
              SizedBox(
                width: double.infinity,
                height: subtitle == null ? 68 : 92,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      left: 8,
                      top: 5,
                      child: IconButton(
                        key: const Key('task-page-back-button'),
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.forestDeep),
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(color: AppColors.forestDeep, fontSize: 24, fontWeight: FontWeight.w700),
                        ),
                        if (subtitle != null) ...[const SizedBox(height: 7), Text(subtitle!, style: const TextStyle(color: AppColors.mutedInk, fontSize: 15))],
                      ],
                    ),
                    if (actions != null) Positioned(right: 8, top: 5, child: Row(children: actions!)),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 14, 24, 28), child: child),
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
