import 'package:flutter/material.dart';

/// VisionMate color tokens — dark theme is primary.
/// Values match the VisionMate design system (royal blue + teal on deep navy).
abstract final class AppColors {
  // Base surfaces
  static const background = Color(0xFF0E1330);
  static const surface = Color(0xFF171C3A);
  static const surfaceLight = Color(0xFF222850);
  static const surfaceHigh = Color(0xFF2D3460);

  // Borders / hairlines
  static const outline = Color(0x2EFFFFFF); // white @ 18%
  static const border = Color(0x1AFFFFFF); // white @ 10%

  // Brand
  static const cyan = Color(0xFF3FD0D4); // accent teal
  static const blue = Color(0xFF4A5CFF); // primary royal blue
  static const deep = Color(0xFF2A2E86); // indigo, used for aurora glow

  // Text
  static const text = Color(0xFFF6F7FB);
  static const muted = Color(0xFFB9BFD4);

  // Status
  static const success = Color(0xFF37D399);
  static const warning = Color(0xFFF3C64B);
  static const danger = Color(0xFFFF4B3E);

  // "on" colors — for content sitting on top of brand-colored fills
  static const onPrimary = Color(0xFFFDFDFF);
  static const onAccent = Color(0xFF0E1330);
}

abstract final class AppTheme {
  static final dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    splashFactory: InkRipple.splashFactory,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.blue,
      secondary: AppColors.cyan,
      surface: AppColors.surface,
      error: AppColors.danger,
      onPrimary: AppColors.onPrimary,
      onSecondary: AppColors.onAccent,
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        color: AppColors.text,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.5,
      ),
      titleLarge: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800),
      bodyLarge: TextStyle(color: AppColors.text, height: 1.4),
      bodyMedium: TextStyle(color: AppColors.text, height: 1.4),
      bodySmall: TextStyle(color: AppColors.muted, height: 1.35),
      labelLarge: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700),
    ),
    iconTheme: const IconThemeData(color: AppColors.text),
    dividerColor: AppColors.border,
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceLight,
      labelStyle: const TextStyle(color: AppColors.text, fontSize: 12),
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.cyan
            : AppColors.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.cyan.withValues(alpha: .35)
            : AppColors.surfaceHigh,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.cyan),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      textColor: AppColors.text,
      iconColor: AppColors.cyan,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: AppColors.blue.withValues(alpha: .32),
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.cyan
              : AppColors.muted,
        ),
      ),
    ),
  );
}
