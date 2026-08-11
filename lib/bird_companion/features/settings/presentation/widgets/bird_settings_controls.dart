import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_atmosphere.dart';
import 'package:flutter/material.dart';

abstract final class BirdSettingsControlStyles {
  static final segmented = ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected) ? AppColors.forestPrimary : AppColors.settingsSurface,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected) ? Colors.white : AppColors.forestDeep,
    ),
    side: WidgetStateProperty.resolveWith(
      (states) => BorderSide(
        color: states.contains(WidgetState.selected) ? AppColors.forestPrimary : AppColors.divider,
      ),
    ),
  );
}

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
  Widget build(BuildContext context) => BirdDeviceLineArt(size: size);
}

class BirdSettingsPrimaryButton extends StatelessWidget {
  const BirdSettingsPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 52,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: height,
    child: FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.forestPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusCompact)),
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
    height: 58,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.forestPrimary,
        side: const BorderSide(color: AppColors.forestPrimary, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusCompact)),
      ),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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
  const BirdChevron({super.key, this.color = AppColors.mutedInk});

  final Color color;

  @override
  Widget build(BuildContext context) => Icon(Icons.chevron_right_rounded, color: color);
}
