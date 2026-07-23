import 'package:speech_to_text/speech_to_text.dart';

class SpeechService {
  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;

  Future<bool> init() async {
    _isInitialized = await _speech.initialize(
      onError: (error) => print('Speech error: $error'),
    );
    return _isInitialized;
  }

  Future<String> listen() async {
    if (!_isInitialized) return '';

    String result = '';

    await _speech.listen(
      onResult: (value) {
        result = value.recognizedWords;
      },
      localeId: 'en_IN',
      listenFor: Duration(seconds: 5),
    );

    await Future.delayed(Duration(seconds: 6));
    await _speech.stop();

    return result;
  }

  bool get isListening => _speech.isListening;

  Future<void> stop() async {
    await _speech.stop();
  }
}
