import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();

  TtsService() {
    _tts.setLanguage("en-IN");
    _tts.setSpeechRate(0.5);
    _tts.awaitSpeakCompletion(true);
  }

  /// Speaks the given text aloud
  Future<void> speak(String text) async {
    await _tts.speak(text);
  }

  /// Stops any ongoing speech
  Future<void> stop() async {
    await _tts.stop();
  }
}
