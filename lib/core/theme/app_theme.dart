import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFF061126);
  static const surface = Color(0xFF0B1830);
  static const surfaceLight = Color(0xFF11213D);
  static const outline = Color(0xFF263957);
  static const cyan = Color(0xFF12D5D5);
  static const blue = Color(0xFF4C83FF);
  static const text = Color(0xFFF4F8FF);
  static const muted = Color(0xFFA7B8D2);
  static const danger = Color(0xFFFF425D);
}

abstract final class AppTheme {
  static final dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.cyan,
      secondary: AppColors.blue,
      surface: AppColors.surface,
      error: AppColors.danger,
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: AppColors.text),
      bodySmall: TextStyle(color: AppColors.muted),
      titleLarge: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: Color(0x554C83FF),
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 10)),
    ),
  );
}
