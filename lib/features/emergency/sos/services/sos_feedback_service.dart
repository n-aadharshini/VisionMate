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

  Future<void> alertSent(List<SosContact> contacts, {String? address}) async {
    await _haptics.alertSent();
    await _speak(_sentMessage(contacts, address));
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

  String _sentMessage(List<SosContact> contacts, String? address) {
    final names = contacts.take(2).map((contact) => contact.name).join(' and ');
    final location = address == null || address.isEmpty
        ? 'using coordinates.'
        : 'near $address.';
    return 'Sent to $names, $location';
  }

  Future<void> _speak(String message) => _tts.speak(message);
}
