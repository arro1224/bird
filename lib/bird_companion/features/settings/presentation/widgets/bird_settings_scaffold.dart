import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_atmosphere.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BirdSettingsScaffold extends StatelessWidget {
  const BirdSettingsScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.onBack,
    this.bottomNavigationBar,
    this.titleFontSize,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final VoidCallback? onBack;
  final Widget? bottomNavigationBar;
  final double? titleFontSize;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.paperStrong,
    extendBodyBehindAppBar: true,
    appBar: AppBar(
      centerTitle: true,
      toolbarHeight: 72,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.paperStrong,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      title: Text(
        key: const Key('settings-page-title'),
        title,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: AppColors.forestDeep,
          fontWeight: FontWeight.w800,
          fontSize: titleFontSize ?? 25,
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.forestPrimary, size: 28),
        ),
      ),
      actions: actions,
    ),
    body: Stack(
      children: [
        const Positioned.fill(child: BirdSettingsAtmosphere()),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 72),
            child: body,
          ),
        ),
      ],
    ),
    bottomNavigationBar: bottomNavigationBar,
  );
}
