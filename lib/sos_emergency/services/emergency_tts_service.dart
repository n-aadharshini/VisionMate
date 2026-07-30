import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

class EmergencyTtsService {
  EmergencyTtsService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();
  final FlutterTts _tts;

  Future<void> emergencyActivated() async {
    await HapticFeedback.mediumImpact();
    await speak('Emergency mode activated.');
  }

  Future<void> sendingLocation() => speak('Sending your location.');
  Future<void> callingContact() => speak('Calling emergency contact.');
  Future<void> speak(String message) => _tts.speak(message);
  Future<void> dispose() => _tts.stop();
}
