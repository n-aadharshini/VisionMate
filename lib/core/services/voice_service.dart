import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/assistant/services/speech_service.dart';
import '../../features/assistant/services/tts_service.dart';

enum VoiceState { idle, listening, thinking, speaking }

class VoiceService {
  static VoiceService? _instance;
  factory VoiceService({SpeechService? speechService, TtsService? ttsService}) {
    _instance ??= VoiceService._(speechService: speechService, ttsService: ttsService);
    return _instance!;
  }
  VoiceService._({SpeechService? speechService, TtsService? ttsService})
    : _speech = speechService ?? SpeechService(),
      _tts = ttsService ?? TtsService();

  static VoiceService get instance => _instance!;

  final SpeechService _speech;
  final TtsService _tts;

  VoiceState _state = VoiceState.idle;
  VoiceState get state => _state;

  final StreamController<VoiceState> _stateController =
      StreamController<VoiceState>.broadcast();
  Stream<VoiceState> get stateChanges => _stateController.stream;

  final StreamController<String> _transcriptController =
      StreamController<String>.broadcast();
  Stream<String> get transcript => _transcriptController.stream;

  String _lastUtterance = '';

  Future<bool> initialize() => _speech.initialize();

  Future<void> listen({
    ValueChanged<String>? onResult,
    ValueChanged<String>? onPartialResult,
  }) async {
    _setState(VoiceState.listening);
    try {
      await _speech.startListening(
        (text) {
          _transcriptController.add(text);
          onResult?.call(text);
        },
        onPartialResult: onPartialResult,
      );
    } catch (e) {
      _setState(VoiceState.idle);
      rethrow;
    }
  }

  Future<void> speak(String text, {bool interruptible = true}) async {
    if (text.trim().isEmpty) return;
    if (interruptible) {
      await _tts.stop();
    }
    _lastUtterance = text;
    _setState(VoiceState.speaking);
    try {
      await _tts.speak(text);
    } finally {
      _setState(VoiceState.idle);
    }
  }

  Future<void> stop() async {
    await _speech.stopListening();
    await _tts.stop();
    _setState(VoiceState.idle);
  }

  Future<String> stopListeningAndGetTranscript() async {
    final transcript = await _speech.stopListeningAndGetTranscript();
    _setState(VoiceState.thinking);
    return transcript;
  }

  void repeatLastUtterance() {
    if (_lastUtterance.isNotEmpty) {
      unawaited(speak(_lastUtterance, interruptible: true));
    }
  }

  void _setState(VoiceState next) {
    _state = next;
    _stateController.add(next);
    debugPrint('[VOICE] state: $next');
  }

  void dispose() async {
    await stop();
    await _stateController.close();
    await _transcriptController.close();
  }
}
