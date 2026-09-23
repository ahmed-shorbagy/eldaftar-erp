import 'package:flutter/material.dart';

/// Shared color tokens for the light and dark shells.
abstract final class AppTokens {
  static const Color seed = Color(0xFF6F4E1B);
  static const Color lightSurface = Color(0xFFFFFBF5);
  static const Color lightOnSurface = Color(0xFF1C1915);
  static const Color darkSurface = Color(0xFF141210);
  static const Color darkOnSurface = Color(0xFFF6F1E8);

  static const double wideBreakpoint = 840;
  static const double contentMaxWidth = 720;
}
