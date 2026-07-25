import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  TtsService({FlutterTts? flutterTts}) : _flutterTts = flutterTts ?? FlutterTts();

  final FlutterTts _flutterTts;
  bool _isConfigured = false;

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) {
      return;
    }

    await _configure();
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  Future<void> stop() => _flutterTts.stop();

  Future<void> _configure() async {
    if (_isConfigured) {
      return;
    }

    await _flutterTts.setLanguage('en-IN');
    await _flutterTts.awaitSpeakCompletion(true);
    await _flutterTts.setSpeechRate(0.48);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setVolume(1.0);
    _isConfigured = true;
  }

}
