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
    return base.copyWith(
      visualDensity: VisualDensity.adaptivePlatformDensity,
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
      textTheme: base.textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
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
