import 'package:flutter/material.dart';

const double authControlHeight = 48;
const double authCornerRadius = 14;

/// Shared auth and recovery form theme. Colors come from [ColorScheme].
ThemeData authFormTheme(ThemeData theme) {
  theme = theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'NotoSansArabic'),
    primaryTextTheme: theme.primaryTextTheme.apply(
      fontFamily: 'NotoSansArabic',
    ),
  );
  final scheme = theme.colorScheme;
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(authCornerRadius),
    borderSide: BorderSide(color: scheme.outlineVariant),
  );
  final buttonText = theme.textTheme.titleMedium;
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(authCornerRadius),
  );
  return theme.copyWith(
    visualDensity: VisualDensity.standard,
    appBarTheme: theme.appBarTheme.copyWith(
      centerTitle: false,
      toolbarHeight: authControlHeight + 8,
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface.withValues(alpha: 0.88),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      floatingLabelBehavior: FloatingLabelBehavior.never,
      errorMaxLines: 8,
      helperMaxLines: 4,
      border: border,
      enabledBorder: border,
      disabledBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: border.copyWith(borderSide: BorderSide(color: scheme.error)),
      focusedErrorBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
      hintStyle: theme.textTheme.bodyLarge?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      helperStyle: theme.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
        height: 1.5,
      ),
      errorStyle: theme.textTheme.bodyMedium?.copyWith(
        color: scheme.error,
        height: 1.5,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(authControlHeight),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: buttonShape,
        textStyle: buttonText,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, authControlHeight),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: buttonShape,
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.55)),
        foregroundColor: scheme.onSurface,
        textStyle: buttonText,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, authControlHeight),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        foregroundColor: scheme.primary,
        textStyle: theme.textTheme.titleSmall,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(authControlHeight, authControlHeight),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
  );
}
