import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class BirdSettingsAssetIcon extends StatelessWidget {
  const BirdSettingsAssetIcon(this.asset, {super.key, required this.label, this.size = 26});
  final String asset;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: label,
    child: Image.asset(asset, width: size, height: size, fit: BoxFit.contain, excludeFromSemantics: true),
  );
}

class BirdSettingsDeviceIcon extends StatelessWidget {
  const BirdSettingsDeviceIcon({super.key, this.size = 88});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: '拍鸟设备',
    child: Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.forestSoft.withValues(alpha: .78),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.forestPrimary.withValues(alpha: .14)),
      ),
      child: Icon(Icons.router_rounded, size: size * .5, color: AppColors.forestPrimary),
    ),
  );
}

class BirdSettingsPrimaryButton extends StatelessWidget {
  const BirdSettingsPrimaryButton({super.key, required this.label, required this.onPressed, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 52,
    child: FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.forestPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSmall)),
      ),
      icon: icon == null ? const SizedBox.shrink() : Icon(icon),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    ),
  );
}

class BirdSettingsOutlineButton extends StatelessWidget {
  const BirdSettingsOutlineButton({super.key, required this.label, required this.onPressed, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 54,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    ),
  );
}

class BirdSettingsDropdownFrame extends StatelessWidget {
  const BirdSettingsDropdownFrame({super.key, required this.child, this.width});

  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    constraints: const BoxConstraints(minHeight: AppSpacing.minimumControl),
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
    decoration: BoxDecoration(
      color: AppColors.settingsSurface,
      border: Border.all(color: AppColors.divider),
      borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
    ),
    alignment: Alignment.center,
    child: child,
  );
}

class BirdChevron extends StatelessWidget {
  const BirdChevron({super.key});
  @override
  Widget build(BuildContext context) => const Icon(Icons.chevron_right_rounded, color: AppColors.mutedInk);
}
