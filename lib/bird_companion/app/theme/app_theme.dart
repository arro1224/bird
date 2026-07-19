import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/app_typography.dart';
import 'package:flutter/material.dart';

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final background = isLight ? AppColors.paper : AppColors.darkSurface;
    final surface = isLight ? AppColors.paperStrong : AppColors.darkSurfaceRaised;
    final foreground = isLight ? AppColors.ink : AppColors.cream;
    final mutedForeground = isLight ? AppColors.inkMuted : AppColors.brandLight;
    final outline = isLight ? AppColors.outline : AppColors.darkOutline;

    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.brand,
          brightness: brightness,
          error: AppColors.danger,
        ).copyWith(
          primary: isLight ? AppColors.brand : AppColors.brandLight,
          onPrimary: isLight ? AppColors.cream : AppColors.brandDark,
          primaryContainer: isLight ? AppColors.brandLight : AppColors.brandMid,
          onPrimaryContainer: isLight ? AppColors.brandDark : AppColors.cream,
          secondary: isLight ? AppColors.brandSoft : AppColors.brandLight,
          onSecondary: isLight ? AppColors.cream : AppColors.brandDark,
          secondaryContainer: isLight ? AppColors.mist : AppColors.brandMid,
          onSecondaryContainer: foreground,
          surface: surface,
          onSurface: foreground,
          onSurfaceVariant: mutedForeground,
          outline: outline,
          outlineVariant: outline,
          error: AppColors.danger,
          onError: AppColors.cream,
          errorContainer: isLight ? AppColors.dangerSoft : const Color(0xFF6B302A),
          onErrorContainer: isLight ? AppColors.danger : AppColors.cream,
        );

    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
    );
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
      side: BorderSide(color: outline),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: AppTypography.textTheme(brightness),
      scaffoldBackgroundColor: background,
      canvasColor: background,
      dividerColor: outline,
      disabledColor: mutedForeground.withValues(alpha: .45),
      shadowColor: isLight ? const Color(0x1A0F2E1A) : Colors.black54,
      splashColor: scheme.primary.withValues(alpha: .08),
      highlightColor: scheme.primary.withValues(alpha: .04),
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        toolbarHeight: 64,
        backgroundColor: background,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: AppTypography.textTheme(brightness).titleLarge?.copyWith(
          color: foreground,
        ),
        iconTheme: IconThemeData(color: foreground, size: AppSpacing.iconSize),
        actionsIconTheme: IconThemeData(color: foreground, size: AppSpacing.iconSize),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: surface,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: cardShape,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isLight ? AppColors.cream : AppColors.darkSurfaceRaised,
        selectedColor: isLight ? AppColors.brand : AppColors.brandMid,
        disabledColor: scheme.surfaceContainerHighest,
        side: BorderSide(color: outline),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        labelStyle: AppTypography.textTheme(brightness).labelMedium?.copyWith(color: foreground),
        secondaryLabelStyle: AppTypography.textTheme(brightness).labelMedium?.copyWith(color: AppColors.cream),
        checkmarkColor: AppColors.cream,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: AppTypography.textTheme(brightness).bodyMedium?.copyWith(color: mutedForeground),
        labelStyle: AppTypography.textTheme(brightness).bodyMedium?.copyWith(color: mutedForeground),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusControl)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: isLight ? AppColors.brand : AppColors.brandLight,
          foregroundColor: isLight ? AppColors.cream : AppColors.brandDark,
          disabledBackgroundColor: scheme.surfaceContainerHighest,
          disabledForegroundColor: mutedForeground,
          textStyle: AppTypography.textTheme(brightness).labelLarge,
          minimumSize: const Size(0, AppSpacing.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          shape: controlShape,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isLight ? AppColors.brand : AppColors.brandLight,
          disabledForegroundColor: mutedForeground,
          textStyle: AppTypography.textTheme(brightness).labelLarge,
          minimumSize: const Size(0, AppSpacing.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          side: BorderSide(color: isLight ? AppColors.brand : AppColors.brandLight, width: 1.25),
          shape: controlShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isLight ? AppColors.brand : AppColors.brandLight,
          textStyle: AppTypography.textTheme(brightness).labelLarge,
          minimumSize: const Size(AppSpacing.minimumTouchTarget, AppSpacing.minimumTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          shape: controlShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: foreground,
          minimumSize: const Size.square(AppSpacing.minimumTouchTarget),
          iconSize: AppSpacing.iconSize,
          shape: const CircleBorder(),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
        minVerticalPadding: AppSpacing.sm,
        minLeadingWidth: AppSpacing.minimumTouchTarget,
        iconColor: isLight ? AppColors.brand : AppColors.brandLight,
        textColor: foreground,
        titleTextStyle: AppTypography.textTheme(brightness).titleMedium?.copyWith(color: foreground),
        subtitleTextStyle: AppTypography.textTheme(brightness).bodySmall?.copyWith(color: mutedForeground),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusCompact)),
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: mutedForeground.withValues(alpha: .55),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusSheet)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusCard)),
        titleTextStyle: AppTypography.textTheme(brightness).titleLarge?.copyWith(color: foreground),
        contentTextStyle: AppTypography.textTheme(brightness).bodyMedium?.copyWith(color: mutedForeground),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: AppSpacing.navigationBarHeight,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? scheme.primary : mutedForeground,
            size: states.contains(WidgetState.selected) ? 26 : 25,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => AppTypography.textTheme(brightness).labelSmall?.copyWith(
            color: states.contains(WidgetState.selected) ? scheme.primary : mutedForeground,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: isLight ? AppColors.mist : AppColors.darkOutline,
        circularTrackColor: isLight ? AppColors.mist : AppColors.darkOutline,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLight ? AppColors.brandDark : AppColors.cream,
        contentTextStyle: AppTypography.textTheme(brightness).bodyMedium?.copyWith(
          color: isLight ? AppColors.cream : AppColors.brandDark,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusControl)),
      ),
    );
  }
}
