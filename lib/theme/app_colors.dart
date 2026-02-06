import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color background = Color(0xFF1A1A1D);
  static const Color surface = Color(0xFF2B2B2E);
  static const Color surfaceLight = Color(0xFF3C3C40);
  static const Color primaryWarm = Color(0xFFFFB088);
  static const Color secondaryWarm = Color(0xFFFF8B94);
  static const Color tealAccent = Color(0xFF88D5C3);
  static const Color textPrimary = Color(0xFFF5F1ED);
  static const Color textSecondary = Color(0xFFB8B4B0);
  static const Color liveRed = Color(0xFFFF4444);
  static const Color successGreen = Color(0xFF4CAF50);

  static const LinearGradient warmGradient = LinearGradient(
    colors: [primaryWarm, secondaryWarm],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
