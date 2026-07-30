import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_result.dart' as stt_result;
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Active speech-to-text path. This uses the platform recognizer directly:
/// it is the only STT implementation instantiated by the app.

/// Explicit lifecycle for the native recognizer session. Needed because
/// `_speechToText.isListening` reflects the plugin's own belief about its
/// state, which can lag behind reality on Android — starting a new
/// `listen()` call before the OS has actually released the previous
/// session throws `error_busy`/`error_client`. Tracking this ourselves lets
/// [startListening] refuse to start (rather than silently no-op, which
/// used to leave the caller's completer hanging forever) until a session
/// has fully reached [_SessionState.idle].
enum _SessionState { idle, starting, listening }

class SpeechService {
  SpeechService({stt.SpeechToText? speechToText})
    : _speechToText = speechToText ?? stt.SpeechToText();

  // PTT ends the session explicitly on button release. These are only safety
  // limits, deliberately longer than a normal utterance so a natural pause
  // does not send a request before the user releases Volume Up.
  static const _pauseFor = Duration(seconds: 60);
  static const _listenFor = Duration(seconds: 60);
  static const _minimumConfidence = 0.45;

  final stt.SpeechToText _speechToText;
  bool _isInitialized = false;
  bool _hasDeliveredFinal = false;
  bool _hasStoppedSession = false;
  _SessionState _sessionState = _SessionState.idle;
  ValueChanged<String>? _onResult;
  ValueChanged<String>? _onPartialResult;
  ValueChanged<double?>? _onFinalConfidence;
  VoidCallback? _onRecordingStopped;
  String _latestTranscript = '';

  double? lastFinalConfidence;
  bool get isListening => _speechToText.isListening;
  bool get isAvailable => _isInitialized;

  /// True while a session is starting, active, or still tearing down —
  /// i.e. anything other than fully idle. Callers should not attempt to
  /// start a new session while this is true.
  bool get isBusy => _sessionState != _SessionState.idle;

  DateTime? _lastErrorAt;
  Object? _lastErrorObject;

  /// When the most recent native-recognizer error fired. Deliberately
  /// never reset by [startListening] — the error for a given session
  /// consistently arrives *after* that session's 'done'/'notListening'
  /// status has already resolved the caller's result as empty (confirmed
  /// from device logs: the error line always trails the status line by
  /// tens to hundreds of ms). A caller that checks this immediately after
  /// its result resolves will almost always see nothing yet. Poll this
  /// (and [lastError]) again after a short wait instead.
  DateTime? get lastErrorAt => _lastErrorAt;

  /// The most recent native-recognizer error object (e.g. a
  /// `SpeechRecognitionError` with msg `error_busy`/`error_client`/...).
  Object? get lastError => _lastErrorObject;

  /// Initializes microphone permission and the native recognizer. Cached
  /// after the first successful call — re-initializing on every PTT press
  /// (the old behavior) re-requests permission and re-inits the recognizer
  /// every time, adding avoidable latency and occasional flakiness on some
  /// devices. A later call only re-runs the real init if it previously
  /// failed (e.g. permission was denied and might now be granted).
  Future<bool> initialize() async {
    if (_isInitialized) return true;
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
    ValueChanged<double?>? onFinalConfidence,
    VoidCallback? onRecordingStopped,
  }) async {
    if (!_isInitialized && !await initialize()) {
      throw StateError(
        'Microphone or speech recognition permission was not granted.',
      );
    }
    // Refuse to start unless the previous session has fully torn down.
    // Previously this checked `_speechToText.isListening` and silently
    // returned on a false positive — which left the caller's completer
    // waiting forever, since `onResult` was never invoked. Throwing here
    // instead makes the failure visible so the caller's own retry/backoff
    // logic (see ConversationSessionController.beginPushToTalk) runs.
    if (_sessionState != _SessionState.idle) {
      throw StateError(
        'SpeechService: cannot start listening, previous session is '
        'still $_sessionState.',
      );
    }

    _sessionState = _SessionState.starting;
    _hasDeliveredFinal = false;
    _hasStoppedSession = false;
    _onResult = onResult;
    _onPartialResult = onPartialResult;
    _onFinalConfidence = onFinalConfidence;
    _onRecordingStopped = onRecordingStopped;
    _latestTranscript = '';

    try {
      await _speechToText.listen(
        onResult: _handleResult,
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
          cancelOnError: true,
          pauseFor: _pauseFor,
          listenFor: _listenFor,
        ),
      );
    } catch (e) {
      _sessionState = _SessionState.idle;
      rethrow;
    }
    _sessionState = _SessionState.listening;
    debugPrint('[LISTEN START] ${DateTime.now().toIso8601String()}');
    debugPrint(
      'VM_TIMING native_stt_started pause_ms=${_pauseFor.inMilliseconds} '
      'listen_max_ms=${_listenFor.inMilliseconds}',
    );
  }

  void _handleResult(stt_result.SpeechRecognitionResult result) {
    _latestTranscript = result.recognizedWords.trim();
    if (!result.finalResult) {
      final partial = result.recognizedWords;
      debugPrint(
        '[PARTIAL] ${DateTime.now().toIso8601String()} text="$partial"',
      );
      _onPartialResult?.call(partial);
      return;
    }
    unawaited(_completeFinalResult(result));
  }

  Future<void> _completeFinalResult(
    stt_result.SpeechRecognitionResult result,
  ) async {
    if (_hasDeliveredFinal) return;
    _hasDeliveredFinal = true;

    // Do not rely only on the recognizer's final callback: explicitly release
    // its microphone before the controller enters processing/speaking.
    if (_speechToText.isListening) await _speechToText.stop();
    _notifyRecordingStopped();

    final confidence = result.confidence > 0 ? result.confidence : null;
    lastFinalConfidence = confidence;
    final text = result.recognizedWords.trim();
    debugPrint(
      '[LISTEN END] ${DateTime.now().toIso8601String()} text="$text" '
      'confidence=${confidence?.toStringAsFixed(2) ?? 'unavailable'}',
    );
    debugPrint(
      'VM_TIMING native_stt_final confidence='
      '${confidence?.toStringAsFixed(2) ?? 'unavailable'}',
    );
    _onFinalConfidence?.call(confidence);

    if (text.isEmpty ||
        (confidence != null && confidence < _minimumConfidence)) {
      debugPrint(
        'Native STT rejected final input: '
        'confidence=${confidence?.toStringAsFixed(2) ?? 'unavailable'} '
        'threshold=$_minimumConfidence',
      );
      _onResult?.call('');
      return;
    }
    _onResult?.call(text);
  }

  /// Stops a PTT capture and returns the most recent live transcript. Android
  /// does not reliably emit a `finalResult` after an app-initiated stop, so
  /// keeping the latest partial result is what makes button release immediate.
  Future<String> stopListeningAndGetTranscript() async {
    if (_speechToText.isListening) await _speechToText.stop();
    _notifyRecordingStopped();
    _sessionState = _SessionState.idle;
    return _latestTranscript;
  }

  Future<void> stopListening() async {
    await stopListeningAndGetTranscript();
  }

  void _handleStatus(String status) {
    debugPrint('Native STT status: $status');
    if (status == 'listening') {
      _sessionState = _SessionState.listening;
      return;
    }
    if (status == 'done' || status == 'notListening') {
      _sessionState = _SessionState.idle;
      if (!_hasDeliveredFinal) {
        _notifyRecordingStopped();
        _onResult?.call('');
      }
    }
  }

  void _notifyRecordingStopped() {
    if (_hasStoppedSession) return;
    _hasStoppedSession = true;
    _onRecordingStopped?.call();
  }

  void _handleError(Object error) {
    debugPrint('Native STT error: $error');
    // cancelOnError:true means the plugin has already torn the session
    // down by the time this fires — reflect that immediately so a new
    // session isn't blocked from starting. The error itself is recorded
    // with a timestamp (not pushed via callback) because on-device it
    // consistently arrives *after* the 'done'/'notListening' status that
    // already resolved this attempt's result — a caller correlating it
    // synchronously would see nothing. See [lastErrorAt] doc.
    _sessionState = _SessionState.idle;
    _lastErrorAt = DateTime.now();
    _lastErrorObject = error;
  }
}
