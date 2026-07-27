import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class BirdSettingsScaffold extends StatelessWidget {
  const BirdSettingsScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.onBack,
    this.bottomNavigationBar,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final VoidCallback? onBack;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.settingsCanvas,
    appBar: AppBar(
      centerTitle: true,
      toolbarHeight: 76,
      backgroundColor: AppColors.settingsCanvas,
      title: Text(
        title,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: AppColors.forestDeep,
          fontWeight: FontWeight.w700,
        ),
      ),
      leadingWidth: 72,
      leading: Padding(
        padding: const EdgeInsets.only(left: AppSpacing.sm),
        child: IconButton(
          key: const Key('settings-back'),
          tooltip: '返回',
          onPressed: onBack ?? () => Navigator.maybePop(context),
          constraints: const BoxConstraints.tightFor(
            width: AppSpacing.minimumControl,
            height: AppSpacing.minimumControl,
          ),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.forestPrimary),
        ),
      ),
      actions: actions,
    ),
    body: SafeArea(top: false, child: body),
    bottomNavigationBar: bottomNavigationBar,
  );
}
