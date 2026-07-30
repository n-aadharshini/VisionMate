import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../../../core/services/permission_service.dart';
import '../../../../core/services/haptics_service.dart';

enum VoiceSosCommand { sendSos, callAmbulance, cancelSos }

/// Free, device-native short-command recognition for the SOS screen. It uses
/// Android's installed speech recognizer and text-to-speech engine; no audio
/// leaves the device through this service and no paid AI/API is used.
class VoiceSosService {
  VoiceSosService({PermissionService? permissionService})
    : _permissionService = permissionService ?? PermissionService();

  final PermissionService _permissionService;
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final HapticsService _haptics = HapticsService();
  final List<String> _localeCycle = ['en_IN', 'ta_IN'];
  bool _running = false;
  bool _handlingCommand = false;
  int _localeIndex = 0;
  Timer? _restartTimer;
  Future<void> Function(VoiceSosCommand command)? _onCommand;
  void Function(String status)? _onStatus;

  Future<void> start({
    required Future<void> Function(VoiceSosCommand command) onCommand,
    required void Function(String status) onStatus,
  }) async {
    _onCommand = onCommand;
    _onStatus = onStatus;
    if (_running) return;
    if (!await _permissionService.requestMicrophonePermission()) {
      onStatus('Microphone permission was denied. Voice SOS is unavailable.');
      await speak('Microphone permission is needed for voice SOS.');
      return;
    }
    _running = true;
    await _haptics.listeningStarted();
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(0.42);
    await _tts.setPitch(1.0);
    await speak(
      'Voice SOS is ready. Say help, SOS, emergency, call one zero eight, '
      'or say uthavi or avasaram.',
    );
    await _listen();
  }

  Future<void> _listen() async {
    if (!_running || _handlingCommand || _speech.isListening) return;
    final available = await _speech.initialize(
      onStatus: _onSpeechStatus,
      onError: _onSpeechError,
    );
    if (!available || !_running) {
      _onStatus?.call('Speech recognition is unavailable on this device.');
      return;
    }
    final locales = await _speech.locales();
    final requested = _localeCycle[_localeIndex++ % _localeCycle.length];
    final localeId = locales.any((locale) => locale.localeId == requested)
        ? requested
        : null;
    _onStatus?.call('Listening for SOS voice commands.');
    await _speech.listen(
      onResult: _onResult,
      listenOptions: stt.SpeechListenOptions(
        localeId: localeId,
        listenFor: const Duration(seconds: 8),
        pauseFor: const Duration(seconds: 2),
        partialResults: false,
        cancelOnError: false,
      ),
    );
  }

  void _onResult(SpeechRecognitionResult result) {
    if (!result.finalResult || !_running) return;
    final command = _matchCommand(result.recognizedWords);
    if (command == null) {
      _onStatus?.call('Command not recognised. Listening again.');
      return;
    }
    unawaited(_handleCommand(command));
  }

  VoiceSosCommand? _matchCommand(String spoken) {
    final phrase = spoken
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0B80-\u0BFF ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final call108 = RegExp(
      r'(call|dial|phone|கால்).*(108|one zero eight|one oh eight|ஒன் ஜீரோ எய்ட்)',
    ).hasMatch(phrase);
    if (call108) return VoiceSosCommand.callAmbulance;
    if (phrase.contains('i am safe') ||
        phrase.contains('im safe') ||
        phrase.contains('cancel sos') ||
        phrase.contains('நான் பாதுகாப்பாக'))
      return VoiceSosCommand.cancelSos;
    if (phrase.contains('help') ||
        phrase.contains('sos') ||
        phrase.contains('emergency') ||
        phrase.contains('uthavi') ||
        phrase.contains('avasaram') ||
        phrase.contains('உதவி') ||
        phrase.contains('அவசரம்') ||
        phrase.contains('எமர்ஜென்சி'))
      return VoiceSosCommand.sendSos;
    return null;
  }

  Future<void> _handleCommand(VoiceSosCommand command) async {
    if (_handlingCommand) return;
    _handlingCommand = true;
    await _speech.stop();
    switch (command) {
      case VoiceSosCommand.sendSos:
        await speak('Emergency command received. Sending SOS now.');
        break;
      case VoiceSosCommand.callAmbulance:
        await speak('Opening the dialer for ambulance, one zero eight.');
        break;
      case VoiceSosCommand.cancelSos:
        await speak('SOS cancelled. You are marked safe.');
        break;
    }
    await _onCommand?.call(command);
    _handlingCommand = false;
    _scheduleRestart();
  }

  void _onSpeechStatus(String status) {
    if ((status == 'done' || status == 'notListening') && !_handlingCommand) {
      _scheduleRestart();
    }
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (!_running) return;
    _onStatus?.call('Voice recognition paused. Listening again.');
    _scheduleRestart();
  }

  void _scheduleRestart() {
    _restartTimer?.cancel();
    if (!_running) return;
    _restartTimer = Timer(const Duration(milliseconds: 500), _listen);
  }

  Future<void> speak(String message) => _tts.speak(message);

  Future<void> dispose() async {
    _running = false;
    _restartTimer?.cancel();
    await _speech.stop();
    await _tts.stop();
  }
}
