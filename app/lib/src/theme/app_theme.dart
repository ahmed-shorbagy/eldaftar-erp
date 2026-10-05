import 'package:flutter/material.dart';

import 'app_tokens.dart';

abstract final class AppTheme {
  static ThemeData light() => _theme(Brightness.light);

  static ThemeData dark() => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final seeded = ColorScheme.fromSeed(
      seedColor: AppTokens.seed,
      brightness: brightness,
    );
    final scheme = brightness == Brightness.light
        ? seeded.copyWith(
            primary: AppTokens.lightAccent,
            onPrimary: AppTokens.lightSurface,
            tertiary: AppTokens.lightSuccess,
            surface: AppTokens.lightSurface,
            onSurface: AppTokens.lightOnSurface,
          )
        : seeded.copyWith(
            primary: AppTokens.darkAccent,
            onPrimary: AppTokens.darkSurface,
            tertiary: AppTokens.darkSuccess,
            surfaceContainerLow: AppTokens.darkCard,
            surfaceContainer: AppTokens.darkCard,
            primaryContainer: AppTokens.darkPrimaryContainer,
            surface: AppTokens.darkSurface,
            onSurface: AppTokens.darkOnSurface,
            outlineVariant: AppTokens.darkOutline,
          );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Cairo',
    );
    final text = base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    TextStyle role(TextStyle? original, double size, FontWeight weight) =>
        (original ?? const TextStyle()).copyWith(
          fontSize: size,
          fontWeight: weight,
          height: 1.5,
          letterSpacing: 0,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTokens.fieldRadius),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );
    return base.copyWith(
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      textTheme: text.copyWith(
        titleLarge: role(text.titleLarge, AppTokens.titleSize, FontWeight.w700),
        titleMedium: role(
          text.titleMedium,
          AppTokens.bodySize,
          FontWeight.w700,
        ),
        titleSmall: role(
          text.titleSmall,
          AppTokens.detailSize,
          FontWeight.w600,
        ),
        bodyLarge: role(text.bodyLarge, AppTokens.bodySize, FontWeight.w400),
        bodyMedium: role(
          text.bodyMedium,
          AppTokens.detailSize,
          FontWeight.w400,
        ),
        bodySmall: role(text.bodySmall, AppTokens.labelSize, FontWeight.w400),
        labelLarge: role(
          text.labelLarge,
          AppTokens.detailSize,
          FontWeight.w600,
        ),
        labelMedium: role(
          text.labelMedium,
          AppTokens.labelSize,
          FontWeight.w600,
        ),
        labelSmall: role(text.labelSmall, AppTokens.labelSize, FontWeight.w500),
        headlineSmall: role(
          text.headlineSmall,
          AppTokens.figureSize,
          FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        errorMaxLines: 6,
        helperMaxLines: 4,
        labelStyle: role(text.bodyLarge, AppTokens.bodySize, FontWeight.w400),
        helperStyle: role(text.bodySmall, AppTokens.labelSize, FontWeight.w400),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        modalBackgroundColor: scheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.cardRadius),
        ),
      ),
      iconTheme: IconThemeData(color: scheme.onSurface),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const CircleBorder(),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(
            AppTokens.minControlSize,
            AppTokens.minControlSize,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          minimumSize: const Size(
            AppTokens.minControlSize,
            AppTokens.minControlSize,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          minimumSize: const Size(
            AppTokens.minControlSize,
            AppTokens.minControlSize,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(
            AppTokens.minControlSize,
            AppTokens.minControlSize,
          ),
        ),
      ),
    );
  }
}
