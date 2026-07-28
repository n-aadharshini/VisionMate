import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  String _lastError = '';

  Future<bool> initialize() async {
    // ignore: avoid_print
    print('SPEECH DEBUG - Calling _speech.initialize()...');
    _isInitialized = await _speech.initialize(
      onError: (error) {
        _lastError = error.errorMsg;
        // ignore: avoid_print
        print('SPEECH DEBUG - Error: ${error.errorMsg}');
      },
      onStatus: (status) {
        // ignore: avoid_print
        print('SPEECH DEBUG - Status: $status');
      },
    );
    // ignore: avoid_print
    print('SPEECH DEBUG - Initialized result: $_isInitialized');
    return _isInitialized;
  }

  Future<String> listenOnce() async {
    if (!_isInitialized) {
      final ready = await initialize();
      if (!ready) return '';
    }

    String recognizedText = '';

    // ignore: avoid_print
    print('SPEECH DEBUG - Calling _speech.listen()...');

    await _speech.listen(
      onResult: (result) {
        recognizedText = result.recognizedWords;
        // ignore: avoid_print
        print('SPEECH DEBUG - Result: "$recognizedText"');
      },
      onSoundLevelChange: (level) {
        // ignore: avoid_print
        print('SPEECH DEBUG - Sound level: $level');
      },
      localeId: 'en_IN',
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
        listenMode: stt.ListenMode.confirmation,
      ),
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 4),
    );

    // ignore: avoid_print
    print('SPEECH DEBUG - listen() call returned, waiting for isListening to go false...');

    while (_speech.isListening) {
      await Future.delayed(const Duration(milliseconds: 200));
    }

    // ignore: avoid_print
    print('SPEECH DEBUG - Final recognized text: "$recognizedText"');

    return recognizedText;
  }

  void stopListening() {
    _speech.stop();
  }

  bool get isListening => _speech.isListening;
  String get lastError => _lastError;
}