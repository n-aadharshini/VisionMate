import 'package:flutter_tts/flutter_tts.dart';

import '../../../../core/services/haptics_service.dart';
import '../domain/sos_contact.dart';

/// Owns concise spoken SOS read-backs and their paired tactile feedback.
class SosFeedbackService {
  SosFeedbackService({FlutterTts? tts, HapticsService? haptics})
    : _tts = tts ?? FlutterTts(),
      _haptics = haptics ?? HapticsService();

  final FlutterTts _tts;
  final HapticsService _haptics;

  Future<void> listeningStarted() => _haptics.listeningStarted();

  /// Speaks as soon as the resolved SOS action begins, before permissions,
  /// location lookup, and delivery complete.
  Future<void> alertSending(
    List<SosContact> contacts, {
    required bool includesLocation,
  }) {
    final names = _recipientNames(contacts);
    final message = includesLocation
        ? 'Sending your location to $names.'
        : 'Sending SOS to $names.';
    return _speak(message);
  }

  /// Keeps the existing success haptic timing, with a concise completion
  /// read-back that intentionally contains no recipient or address details.
  Future<void> alertSent() async {
    await _haptics.alertSent();
    await _speak('Sent.');
  }

  Future<void> callPlaced(String name) => _speak('Calling $name now.');

  Future<void> callUnanswered(String nextName) async {
    await _haptics.callUnanswered();
    await _speak('No answer. Trying $nextName.');
  }

  Future<void> fallDetected() => _haptics.fallDetected();

  Future<void> countdownEscalated() => _haptics.countdownEscalated();

  Future<void> safeConfirmed() async {
    await _haptics.safeConfirmed();
    await _speak("Great, glad you're safe.");
  }

  Future<void> failure(String message) => _speak(message);

  Future<void> simulatedCall(String number) =>
      _speak('Calling $number, please wait.');

  Future<void> dispose() => _tts.stop();

  String _recipientNames(List<SosContact> contacts) => contacts
      .take(2)
      .map((contact) => contact.name)
      .join(' and ');

  Future<void> _speak(String message) => _tts.speak(message);
}
