import 'package:flutter/services.dart';

abstract final class AppHaptics {
  static void light() {
    HapticFeedback.selectionClick();
  }

  static void medium() {
    HapticFeedback.mediumImpact();
  }

  static void heavy() {
    HapticFeedback.heavyImpact();
  }

  static void tick() {
    HapticFeedback.lightImpact();
  }

  static void tripleTick() {
    HapticFeedback.lightImpact();
    Future.delayed(const Duration(milliseconds: 80), () {
      HapticFeedback.lightImpact();
    });
    Future.delayed(const Duration(milliseconds: 160), () {
      HapticFeedback.lightImpact();
    });
  }

  static void shortShortLong() {
    HapticFeedback.lightImpact();
    Future.delayed(const Duration(milliseconds: 100), () {
      HapticFeedback.lightImpact();
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      HapticFeedback.heavyImpact();
    });
  }
}
