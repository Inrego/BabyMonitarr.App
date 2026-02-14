import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static TextStyle get display => GoogleFonts.nunito(
    fontSize: 48,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static TextStyle get title => GoogleFonts.nunito(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
    color: AppColors.textPrimary,
  );

  static TextStyle get subtitle => GoogleFonts.nunito(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle get body => GoogleFonts.nunito(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
  );

  static TextStyle get caption => GoogleFonts.nunito(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
  );

  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primaryWarm,
      secondary: AppColors.tealAccent,
      surface: AppColors.surface,
      error: AppColors.liveRed,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: subtitle,
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
    ),
    textTheme: TextTheme(
      displayLarge: display,
      titleLarge: title,
      titleMedium: subtitle,
      bodyLarge: body,
      bodySmall: caption,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.tealAccent;
        }
        return AppColors.surfaceLight;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.tealAccent.withValues(alpha: 0.3);
        }
        return AppColors.surface;
      }),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.primaryWarm,
      inactiveTrackColor: AppColors.surfaceLight,
      thumbColor: AppColors.primaryWarm,
      overlayColor: AppColors.primaryWarm.withValues(alpha: 0.2),
    ),
  );
}
