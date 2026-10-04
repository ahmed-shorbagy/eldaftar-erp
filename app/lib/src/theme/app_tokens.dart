import 'package:flutter/material.dart';

/// Shared color tokens for the light and dark shells.
abstract final class AppTokens {
  static const Color seed = Color(0xFF6F4E1B);
  static const Color lightSurface = Color(0xFFFFFBF5);
  static const Color lightOnSurface = Color(0xFF1C1915);
  static const Color darkSurface = Color(0xFF141210);
  static const Color darkOnSurface = Color(0xFFF6F1E8);
  static const Color darkPrimaryContainer = Color(0xFF3A2C18);

  /// Gold used only inside the brand mark, on the brown field.
  static const Color brandGold = Color(0xFFE6C36A);

  static const double wideBreakpoint = 840;
  static const double contentMaxWidth = 720;
  static const double minControlSize = 48;
}
