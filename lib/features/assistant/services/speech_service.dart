import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService {
  SpeechService({stt.SpeechToText? speechToText})
      : _speechToText = speechToText ?? stt.SpeechToText();

  final stt.SpeechToText _speechToText;
  bool _isInitialized = false;

  bool get isListening => _speechToText.isListening;
  bool get isAvailable => _isInitialized;

  Future<bool> initialize() async {
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      _isInitialized = false;
      return false;
    }

    _isInitialized = await _speechToText.initialize(
      onStatus: _handleStatus,
      onError: _handleError,
    );
    return _isInitialized;
  }

  Future<void> startListening(
    ValueChanged<String> onResult, {
    ValueChanged<String>? onPartialResult,
  }) async {
    if (!_isInitialized && !await initialize()) {
      throw StateError('Microphone or speech recognition permission was not granted.');
    }

    await _speechToText.listen(
      onResult: (result) {
        if (result.finalResult) {
          onResult(result.recognizedWords);
        } else {
          onPartialResult?.call(result.recognizedWords);
        }
      },
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        listenMode: stt.ListenMode.confirmation,
        cancelOnError: true,
      ),
    );
  }

  Future<void> stopListening() async {
    if (_speechToText.isListening) {
      await _speechToText.stop();
    }
  }

  void _handleStatus(String status) {
    debugPrint('Speech recognition status: $status');
  }

  void _handleError(Object error) {
    debugPrint('Speech recognition error: $error');
  }
}
