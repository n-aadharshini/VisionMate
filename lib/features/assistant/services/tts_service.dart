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
    await _selectWarmEnglishVoice();
    await _flutterTts.setSpeechRate(0.46);
    await _flutterTts.setPitch(1.06);
    await _flutterTts.setVolume(1.0);
    _isConfigured = true;
  }

  Future<void> _selectWarmEnglishVoice() async {
    final voices = await _flutterTts.getVoices;
    if (voices is! List) return;

    final candidates = voices
        .whereType<Map>()
        .map(
          (voice) => <String, String>{
            'name': voice['name']?.toString() ?? '',
            'locale': voice['locale']?.toString() ?? '',
          },
        )
        .where((voice) => voice['locale']!.toLowerCase().startsWith('en'))
        .toList();
    if (candidates.isEmpty) return;

    candidates.sort((a, b) => _voiceScore(b).compareTo(_voiceScore(a)));
    final voice = candidates.first;
    if (voice['name']!.isNotEmpty && voice['locale']!.isNotEmpty) {
      await _flutterTts.setVoice(voice);
    }
  }

  int _voiceScore(Map<String, String> voice) {
    final locale = voice['locale']!.toLowerCase();
    final name = voice['name']!.toLowerCase();
    var score = locale.startsWith('en-in') ? 20 : 10;
    for (final qualityMarker in ['natural', 'neural', 'enhanced', 'online']) {
      if (name.contains(qualityMarker)) score += 5;
    }
    return score;
  }
}
