import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Account-free, dependency-free alternative to [WakeWordService].
///
/// Instead of a dedicated on-device keyword spotter (Porcupine), this
/// runs short, auto-restarting listen sessions using the same
/// `speech_to_text` package your SpeechService already depends on, and
/// checks each transcript for the wake phrase.
///
/// Trade-offs vs. a real wake-word engine:
/// - Heavier on battery — full speech recognition running repeatedly,
///   not a tiny purpose-built keyword model
/// - `speech_to_text` sessions time out after a period of silence and
///   need restarting, which this handles automatically, but there's a
///   small gap (usually well under a second) between sessions where a
///   "Hey VisionMate" could theoretically be missed
/// - iOS/Android's built-in recognizer may briefly use cloud processing
///   depending on device/OS settings — check Settings if fully local
///   processing matters for your privacy requirement
///
/// Good enough to demo hands-free activation today; swap in a real
/// wake-word engine (Porcupine, Vosk, openWakeWord) later without
/// changing anything else — [ConversationSessionController] only needs
/// initialize/start/pause/resume/dispose from whichever you use.
class PhraseWakeWordService {
  PhraseWakeWordService({
    this.wakePhrase = 'hey vision mate',
    stt.SpeechToText? speechToText,
  }) : _speechToText = speechToText ?? stt.SpeechToText();

  /// Lowercase phrase to listen for. Keep it distinctive enough to avoid
  /// accidental matches in ordinary conversation.
  final String wakePhrase;

  final stt.SpeechToText _speechToText;

  bool _isInitialized = false;
  bool _isActive = false; // true once start() has been called
  bool _isPaused = false;
  bool _isCycling = false; // guards against overlapping restart calls
  int _consecutiveErrors = 0;
  void Function()? _onWakeWordDetected;
  void Function(Object error)? _onError;

  /// Base gap before restarting a listen session after it ends normally.
  /// Android's SpeechRecognizer needs a moment to actually release the
  /// previous session — restarting immediately causes "error_busy".
  static const _restartDelay = Duration(milliseconds: 600);

  /// Longer gap used after an error, growing with consecutive failures,
  /// so a persistent problem (e.g. mic held by another app) doesn't spin
  /// in a tight, battery-draining loop.
  Duration _errorBackoff() {
    final capped = _consecutiveErrors.clamp(1, 5);
    return Duration(milliseconds: 600 * capped);
  }

  bool get isListening => _isActive && !_isPaused;

  Future<bool> initialize({
    required void Function() onWakeWordDetected,
    void Function(Object error)? onError,
  }) async {
    _onWakeWordDetected = onWakeWordDetected;
    _onError = onError;

    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      onError?.call(StateError('Microphone permission was not granted.'));
      return false;
    }

    _isInitialized = await _speechToText.initialize(
      onStatus: _handleStatus,
      onError: (error) => onError?.call(error),
    );
    return _isInitialized;
  }

  Future<void> start() async {
    if (!_isInitialized || _isActive) return;
    _isActive = true;
    _isPaused = false;
    await _listenCycle();
  }

  Future<void> pause() async {
    if (!_isActive || _isPaused) return;
    _isPaused = true;
    if (_speechToText.isListening) {
      await _speechToText.stop();
    }
  }

  Future<void> resume() async {
    if (!_isActive || !_isPaused) return;
    _isPaused = false;
    await _listenCycle();
  }

  Future<void> dispose() async {
    _isActive = false;
    if (_speechToText.isListening) {
      await _speechToText.stop();
    }
  }

  /// Schedules a restart after [delay], guarded so only one pending
  /// restart can exist at a time — this is what stops the busy-error
  /// tight loop.
  void _scheduleRestart(Duration delay) {
    if (_isCycling || !_isActive || _isPaused) return;
    _isCycling = true;
    Future.delayed(delay, () {
      _isCycling = false;
      if (_isActive && !_isPaused) {
        _listenCycle();
      }
    });
  }

  Future<void> _listenCycle() async {
    if (!_isActive || _isPaused) return;
    if (_speechToText.isListening) {
      return; // already running, don't double-start
    }

    try {
      await _speechToText.listen(
        onResult: (result) {
          final heard = result.recognizedWords.toLowerCase();
          if (heard.contains(wakePhrase)) {
            _onWakeWordDetected?.call();
            // Caller is expected to pause() this service right away
            // (ConversationSessionController does this) before it
            // starts real conversation listening — so we don't
            // auto-restart here.
          }
        },
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
          cancelOnError: true,
        ),
      );
      _consecutiveErrors = 0; // successful start — reset backoff
    } catch (e) {
      _consecutiveErrors++;
      _onError?.call(e);
      // Back off before trying again instead of hammering the recognizer.
      _scheduleRestart(_errorBackoff());
    }
  }

  void _handleStatus(String status) {
    debugPrint('Wake phrase listener status: $status');
    // speech_to_text sessions end on their own (silence timeout / OS
    // limit) — restart automatically, but only after a short delay so
    // Android's SpeechRecognizer has time to actually release the
    // previous session first.
    if (status == 'done' || status == 'notListening') {
      if (_isActive && !_isPaused) {
        _scheduleRestart(_restartDelay);
      }
    }
  }
}
