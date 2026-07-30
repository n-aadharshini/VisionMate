import 'package:vibration/vibration.dart';

/// SOS-specific tactile patterns. Every method safely no-ops on devices that
/// do not expose a vibration motor or do not support custom patterns.
class HapticsService {
  Future<void> listeningStarted() => _vibrate(const [0, 35]);

  Future<void> alertSent() => _vibrate(const [0, 70, 70, 70]);

  Future<void> fallDetected() => _vibrate(const [0, 300, 250, 300]);

  Future<void> callUnanswered() => _vibrate(const [0, 45, 50, 45, 50, 45]);

  Future<void> countdownEscalated() => _vibrate(const [0, 550]);

  Future<void> safeConfirmed() => _vibrate(const [0, 25]);

  Future<void> _vibrate(List<int> pattern) async {
    try {
      if (!await Vibration.hasVibrator()) return;
      if (await Vibration.hasCustomVibrationsSupport()) {
        await Vibration.vibrate(pattern: pattern);
      } else {
        await Vibration.vibrate(duration: pattern.last);
      }
    } catch (_) {
      // Haptics are supplemental feedback and must never interrupt SOS.
    }
  }
}
