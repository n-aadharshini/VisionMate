import 'dart:async';

import 'package:flutter/services.dart';

abstract final class AppEarcons {
  static const _successFrequency1 = 523.25; // C5
  static const _successFrequency2 = 659.25; // E5
  static const _errorFrequency = 220.0; // A3
  static const _listeningFrequency = 783.99; // G5

  static const _successDuration1 = Duration(milliseconds: 100);
  static const _successDuration2 = Duration(milliseconds: 120);
  static const _errorDuration = Duration(milliseconds: 180);
  static const _listeningDuration = Duration(milliseconds: 120);

  static Future<void> success() async {
    await _playTone(_successFrequency1, _successDuration1);
    await Future.delayed(const Duration(milliseconds: 50));
    await _playTone(_successFrequency2, _successDuration2);
  }

  static Future<void> error() async {
    await _playTone(_errorFrequency, _errorDuration);
  }

  static Future<void> listeningStart() async {
    await _playTone(_listeningFrequency, _listeningDuration);
  }

  static Future<void> shutter() async {
    await _playTone(800.0, const Duration(milliseconds: 60));
  }

  static Future<void> _playTone(double frequency, Duration duration) async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }
}
