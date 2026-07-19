import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_shadows.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class BirdConnectionLine extends StatelessWidget {
  const BirdConnectionLine({super.key, this.label = '本地连接稳定'});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.circle, color: Theme.of(context).colorScheme.primary, size: 12),
      const SizedBox(width: AppSpacing.xs),
      Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    ],
  );
}

class BirdPill extends StatelessWidget {
  const BirdPill({
    super.key,
    required this.label,
    this.color = AppColors.brandLight,
    this.textColor = AppColors.brand,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: textColor),
      ),
    ),
  );
}

class BirdSectionTitle extends StatelessWidget {
  const BirdSectionTitle({super.key, required this.text, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      children: [
        Expanded(child: Text(text, style: Theme.of(context).textTheme.headlineSmall)),
        ?trailing,
      ],
    ),
  );
}

class BirdTopBar extends StatelessWidget implements PreferredSizeWidget {
  const BirdTopBar({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.centerTitle = true,
  });

  final String title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool centerTitle;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) => AppBar(
    leading: leading,
    title: Text(title),
    centerTitle: centerTitle,
    actions: actions,
  );
}

class BirdPageHeader extends StatelessWidget {
  const BirdPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.pageHorizontal,
      AppSpacing.pageVertical,
      AppSpacing.pageHorizontal,
      AppSpacing.md,
    ),
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.displaySmall),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.sm),
          trailing!,
        ],
      ],
    ),
  );
}

class BirdCard extends StatelessWidget {
  const BirdCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.cardPadding),
    this.margin,
    this.backgroundColor,
    this.radius = AppSpacing.radiusCard,
    this.showBorder = true,
    this.shadow,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final double radius;
  final bool showBorder;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(radius);
    final content = Padding(padding: padding, child: child);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.colorScheme.surface,
        borderRadius: borderRadius,
        border: showBorder ? Border.all(color: theme.colorScheme.outlineVariant) : null,
        boxShadow: shadow ?? AppShadows.cardFor(theme.brightness),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? content
            : InkWell(
                onTap: onTap,
                borderRadius: borderRadius,
                child: content,
              ),
      ),
    );
  }
}

enum BirdButtonVariant { filled, outlined, tonal }

class BirdButton extends StatelessWidget {
  const BirdButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = BirdButtonVariant.filled,
    this.expanded = true,
    this.busy = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final BirdButtonVariant variant;
  final bool expanded;
  final bool busy;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveOnPressed = busy ? null : onPressed;
    final effectiveIcon = busy
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : icon;
    final labelWidget = Text(label);
    final destructiveStyle = destructive
        ? ButtonStyle(
            backgroundColor: WidgetStatePropertyAll(
              variant == BirdButtonVariant.outlined ? Colors.transparent : scheme.error,
            ),
            foregroundColor: WidgetStatePropertyAll(
              variant == BirdButtonVariant.outlined ? scheme.error : scheme.onError,
            ),
            side: WidgetStatePropertyAll(BorderSide(color: scheme.error)),
          )
        : null;

    final Widget button = switch (variant) {
      BirdButtonVariant.filled =>
        effectiveIcon == null
            ? FilledButton(
                onPressed: effectiveOnPressed,
                style: destructiveStyle,
                child: labelWidget,
              )
            : FilledButton.icon(
                onPressed: effectiveOnPressed,
                style: destructiveStyle,
                icon: effectiveIcon,
                label: labelWidget,
              ),
      BirdButtonVariant.outlined =>
        effectiveIcon == null
            ? OutlinedButton(
                onPressed: effectiveOnPressed,
                style: destructiveStyle,
                child: labelWidget,
              )
            : OutlinedButton.icon(
                onPressed: effectiveOnPressed,
                style: destructiveStyle,
                icon: effectiveIcon,
                label: labelWidget,
              ),
      BirdButtonVariant.tonal =>
        effectiveIcon == null
            ? FilledButton.tonal(
                onPressed: effectiveOnPressed,
                style: destructiveStyle,
                child: labelWidget,
              )
            : FilledButton.tonalIcon(
                onPressed: effectiveOnPressed,
                style: destructiveStyle,
                icon: effectiveIcon,
                label: labelWidget,
              ),
    };

    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class BirdListItem extends StatelessWidget {
  const BirdListItem({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.showDivider = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final tile = ListTile(
      leading: leading,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing,
      onTap: onTap,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tile,
        if (showDivider)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Divider(),
          ),
      ],
    );
  }
}

class BirdTag extends StatelessWidget {
  const BirdTag({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onSelected,
  });

  final String label;
  final Widget? icon;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) => FilterChip(
    avatar: icon,
    label: Text(label),
    selected: selected,
    showCheckmark: false,
    onSelected: onSelected,
  );
}

class BirdBottomNavigation extends StatelessWidget {
  const BirdBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final List<NavigationDestination> destinations;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      boxShadow: Theme.of(context).brightness == Brightness.light ? AppShadows.navigation : AppShadows.darkCard,
    ),
    child: SafeArea(
      top: false,
      child: NavigationBar(
        selectedIndex: selectedIndex,
        destinations: destinations,
        onDestinationSelected: onDestinationSelected,
      ),
    ),
  );
}

class BirdDarkTheme extends StatelessWidget {
  const BirdDarkTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(
          surface: AppColors.darkSurfaceRaised,
          onSurface: AppColors.cream,
          onSurfaceVariant: AppColors.brandLight,
          outline: AppColors.darkOutline,
          outlineVariant: AppColors.darkOutline,
        ),
        textTheme: base.textTheme.apply(bodyColor: AppColors.cream, displayColor: AppColors.cream),
        cardTheme: base.cardTheme.copyWith(color: AppColors.darkSurfaceRaised),
        dividerColor: AppColors.darkOutline,
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: AppColors.darkSurfaceRaised,
          hintStyle: base.textTheme.bodyMedium?.copyWith(color: AppColors.brandLight),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
            borderSide: const BorderSide(color: AppColors.darkOutline),
          ),
        ),
      ),
      child: child,
    );
  }
}
