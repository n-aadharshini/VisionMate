import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/chat_message.dart';
import '../models/intent_type.dart';
import '../models/vision_mate_response.dart';
import 'speech_service.dart';
import 'tts_service.dart';
import 'vision_mate_brain.dart';

enum ConversationState { idle, listening, processing, speaking }

/// Orchestrates the always-on companion loop:
///
///   listening -> (final transcript) -> processing -> speaking -> listening
///
/// No wake word — the mic stays live for as long as [start] has been
/// called, restarting listening sessions automatically after each turn.
///
/// Barge-in note: an earlier version of this controller tried to start the
/// *next* listening session concurrently with the current turn's
/// processing/speaking, so a partial transcript during playback could cut
/// TTS off immediately. `speech_to_text` only supports one active session
/// on its underlying recognizer, though — starting a second `listen()`
/// before the first has fully torn down leaves the plugin unable to start
/// any further session, which is why listening appeared to stop after the
/// first turn. This version is strictly sequential (one mic session per
/// turn) and exposes [interruptSpeaking] instead: call it (e.g. from a tap
/// on the mic orb) to cut the assistant off and return to listening
/// immediately. True hands-free barge-in (detecting the user's voice while
/// the assistant is mid-sentence) needs either a VAD-based approach or
/// careful session handoff and is a good candidate to revisit once the
/// core loop is solid — flagging rather than re-attempting it silently.
class ConversationSessionController extends ChangeNotifier {
  ConversationSessionController({
    SpeechService? speechService,
    TtsService? ttsService,
    VisionMateBrain? brain,
    this.onError,
  }) : _speechService = speechService ?? SpeechService(),
       _brain = brain ?? VisionMateBrain(),
       _ttsService = ttsService ?? TtsService(onError: onError) {
    // If a ttsService instance was passed in explicitly, still wire up
    // error reporting so silent playback failures surface to the caller.
    _ttsService.onError ??= onError;
    _ttsService.onPlaybackStarted ??= _onTtsPlaybackStarted;
    _volumeButtonChannel.setMethodCallHandler(_handleVolumeButtonEvent);
  }

  static const _volumeButtonChannel = MethodChannel('visionmate/volume_button');

  final SpeechService _speechService;
  final TtsService _ttsService;
  final VisionMateBrain _brain;
  final StreamController<NavigationRequest> _navigationRequests =
      StreamController<NavigationRequest>.broadcast();

  /// The root app listens here and performs intent-driven route changes.
  Stream<NavigationRequest> get navigationRequests =>
      _navigationRequests.stream;

  /// Surfaced for UI feedback (e.g. a toast or subtle earcon) — never
  /// throws past this controller. Also wired into [TtsService] so TTS
  /// failures (e.g. a missing ELEVENLABS_API_KEY) are no longer silent.
  final void Function(Object error)? onError;

  ConversationState _state = ConversationState.idle;
  ConversationState get state => _state;
  bool get isListening => _state == ConversationState.listening;
  bool get isThinking => _state == ConversationState.processing;

  // Guards against calling notifyListeners() (or touching platform
  // services) after dispose() has run. Needed because stop() is async
  // and UI code (e.g. State.dispose(), which can't be awaited) may call
  // stop() and then dispose() back-to-back without waiting for stop()
  // to actually finish — without this guard, stop()'s trailing
  // notifyListeners() call throws once dispose() has already run.
  bool _disposed = false;

  String _partialTranscript = '';
  String get partialTranscript => _partialTranscript;

  String _finalTranscript = '';
  String get finalTranscript => _finalTranscript;
  DateTime? _recordingStoppedAt;
  DateTime? _replyReceivedAt;

  bool get isSpeaking => _state == ConversationState.speaking;

  bool _isActive = false;
  bool get isActive => _isActive;
  bool _pushToTalkHeld = false;

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Prepares microphone permission without starting a capture session.
  Future<bool> initialize() async {
    final ok = await _speechService.initialize();
    if (!ok) {
      onError?.call(StateError('Microphone permission was not granted.'));
    }
    return ok;
  }

  Future<void> _handleVolumeButtonEvent(MethodCall call) async {
    switch (call.method) {
      case 'volumeUpPressed':
        await beginPushToTalk();
        return;
      case 'volumeUpReleased':
        await endPushToTalk();
        return;
    }
  }

  /// Starts the same foreground PTT capture used by the in-app mic control.
  Future<bool> beginPushToTalk() async {
    if (_pushToTalkHeld || _state != ConversationState.idle) return false;
    if (!await initialize()) return false;

    _pushToTalkHeld = true;
    _isActive = true;
    _partialTranscript = '';
    _finalTranscript = '';
    _setState(ConversationState.listening);
    try {
      await _speechService.startListening(
        (_) {},
        onPartialResult: (partial) {
          _partialTranscript = partial;
          _upsertPartialUserBubble(partial);
          _safeNotify();
        },
        onRecordingStopped: _onRecordingStopped,
      );
      return true;
    } catch (error) {
      _pushToTalkHeld = false;
      _isActive = false;
      _setState(ConversationState.idle);
      onError?.call(error);
      return false;
    }
  }

  /// Ends the PTT capture immediately, locks its live transcript, then runs
  /// the existing Groq intent/reply pipeline. Nothing listens while it runs.
  Future<void> endPushToTalk() async {
    if (!_pushToTalkHeld || _state != ConversationState.listening) return;
    _pushToTalkHeld = false;
    final transcript = (await _speechService.stopListeningAndGetTranscript())
        .trim();
    _isActive = false;
    _finalTranscript = transcript;
    _partialTranscript = '';
    debugPrint(
      '[LISTEN END] ${DateTime.now().toIso8601String()} text="$transcript"',
    );
    _safeNotify();

    if (transcript.isEmpty) {
      _setState(ConversationState.idle);
      return;
    }

    await _handleTurn(transcript);
    if (!_disposed) _setState(ConversationState.idle);
  }

  /// Starts the always-on loop. Returns false if mic permission or speech
  /// recognition initialization failed.
  Future<bool> start() async {
    if (_isActive) return true;

    final ok = await _speechService.initialize();
    if (!ok) {
      onError?.call(StateError('Microphone permission was not granted.'));
      return false;
    }

    _isActive = true;
    _setState(ConversationState.listening);
    unawaited(_mainLoop());
    return true;
  }

  Future<void> stop() async {
    _isActive = false;
    _pushToTalkHeld = false;
    await _speechService.stopListening();
    await _ttsService.stop();
    if (_disposed) return;
    _setState(ConversationState.idle);
  }

  /// Cuts the assistant off mid-reply and returns to listening. This is
  /// the practical stand-in for automatic barge-in in this version — wire
  /// it to a tap on the mic orb, or call it from anywhere else you want a
  /// manual interrupt.
  Future<void> interruptSpeaking() async {
    if (_state != ConversationState.speaking) return;
    await _ttsService.stop();
  }

  Future<void> _mainLoop() async {
    while (_isActive) {
      _setState(ConversationState.listening);
      final String transcript;
      try {
        transcript = await _captureUtterance();
      } catch (e) {
        onError?.call(e);
        await Future.delayed(const Duration(milliseconds: 600));
        continue;
      }
      if (!_isActive) break;
      if (transcript.isEmpty) continue;
      await _handleTurn(transcript);
    }
  }

  Future<void> _handleTurn(String transcript) async {
    _finalizeUserMessage(transcript);
    _setState(ConversationState.processing);

    VisionMateResponse response;
    final apiStartedAt = DateTime.now();
    debugPrint(
      '[SENDING TO GROQ] ${apiStartedAt.toIso8601String()} text="$transcript"',
    );
    try {
      response = await _brain.classify(transcript);
    } catch (error) {
      onError?.call(error);
      response = const VisionMateResponse(
        intent: IntentType.unknown,
        destination: null,
        reply: 'Sorry, I ran into a problem there. Could you try again?',
        confidence: 0,
        source: 'controller-fallback',
      );
    }

    _replyReceivedAt = DateTime.now();
    debugPrint(
      '[GROQ RESPONSE RECEIVED] ${_replyReceivedAt!.toIso8601String()} '
      'reply="${response.reply}" intent=${response.intent.name} '
      'confidence=${response.confidence}',
    );
    debugPrint(
      'VM_TIMING reply_ready ${_replyReceivedAt!.toIso8601String()} '
      'duration_ms=${_replyReceivedAt!.difference(apiStartedAt).inMilliseconds} '
      'source=${response.source}',
    );

    _messages.add(ChatMessage(role: ChatRole.assistant, text: response.reply));
    _setState(ConversationState.speaking);
    _safeNotify();
    await _speechService.stopListening();
    debugPrint(
      '[TTS START] ${DateTime.now().toIso8601String()} text="${response.reply}"',
    );
    await _ttsService.speak(response.reply);
    debugPrint('[TTS END] ${DateTime.now().toIso8601String()}');

    if (response.confidence >= 0.5) {
      final request = _navigationFor(response);
      if (request != null) _navigationRequests.add(request);
    }
    await _ttsService.waitUntilDone();
  }

  NavigationRequest? _navigationFor(VisionMateResponse response) {
    return switch (response.intent) {
      IntentType.navigate => NavigationRequest(
        routeName: '/navigate',
        arguments: response.destination,
      ),
      IntentType.travel => NavigationRequest(
        routeName: '/travel',
        arguments: response.destination,
      ),
      IntentType.read => const NavigationRequest(routeName: '/read'),
      IntentType.help => const NavigationRequest(routeName: '/help'),
      IntentType.chat || IntentType.unknown => null,
    };
  }

  // ignore: unused_element
  Future<void> _legacyStreamTurn(String transcript) async {
    _finalizeUserMessage(transcript);
    _setState(ConversationState.processing);

    final assistantMessage = ChatMessage(
      role: ChatRole.assistant,
      text: '',
      isPartial: true,
    );
    _messages.add(assistantMessage);
    _safeNotify();

    var pending = '';
    var enteredSpeaking = false;
    try {
      await for (final token in _brain.streamCompanionReply(transcript)) {
        pending += token;
        final split = _splitCompleteSentences(pending);
        for (final sentence in split.complete) {
          _ttsService.enqueueSentence(sentence);
          _appendToMessage(assistantMessage, sentence);
          if (!enteredSpeaking) {
            enteredSpeaking = true;
            _setState(ConversationState.speaking);
          }
        }
        pending = split.remainder;
      }
      final leftover = pending.trim();
      if (leftover.isNotEmpty) {
        _ttsService.enqueueSentence(leftover);
        _appendToMessage(assistantMessage, leftover);
      }
    } catch (e) {
      onError?.call(e);
      const fallback =
          "Sorry, I ran into a problem there. Could you try again?";
      _ttsService.enqueueSentence(fallback);
      assistantMessage.text = fallback;
    }

    assistantMessage.isPartial = false;
    if (_state != ConversationState.speaking) {
      _setState(ConversationState.speaking);
    }
    _safeNotify();

    // Blocks until playback finishes naturally OR interruptSpeaking()/stop()
    // cuts it short — either way, the main loop resumes listening next.
    await _ttsService.waitUntilDone();
  }

  /// Runs one listen-and-restart cycle: keeps starting fresh recordings
  /// (each one ends on its own once [SpeechService] detects silence, is
  /// transcribed via Groq Whisper, and returns) until a non-empty final
  /// transcript comes back, or the controller is stopped. Exactly one
  /// recording is ever active at a time.
  ///
  /// Note: [SpeechService] no longer reports partial results (Groq's
  /// transcription endpoint isn't streaming, so there's nothing to report
  /// mid-utterance) — `onPartialResult` below simply won't fire anymore.
  /// It's left wired up rather than removed so the live-caption UI keeps
  /// working automatically if a streaming STT provider is swapped back in
  /// later.
  Future<String> _captureUtterance() async {
    while (_isActive) {
      final completer = Completer<String>();
      try {
        await _speechService.startListening(
          (finalText) {
            _finalTranscript = finalText.trim();
            final completedAt = DateTime.now();
            final stoppedAt = _recordingStoppedAt;
            debugPrint(
              'VM_TIMING controller_final_transcript_ready '
              '${completedAt.toIso8601String()} '
              'stt_delay_ms=${stoppedAt == null ? 'unknown' : completedAt.difference(stoppedAt).inMilliseconds} '
              'text="$_finalTranscript"',
            );
            _safeNotify();
            if (!completer.isCompleted) completer.complete(_finalTranscript);
          },
          onPartialResult: (partial) {
            _partialTranscript = partial;
            _upsertPartialUserBubble(partial);
            _safeNotify();
          },
          onRecordingStopped: _onRecordingStopped,
        );
      } catch (error) {
        onError?.call(error);
        await Future.delayed(const Duration(milliseconds: 600));
        continue;
      }

      final result = (await completer.future).trim();
      _partialTranscript = '';
      if (result.isNotEmpty) return result;
      if (!_isActive) return '';
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return '';
  }

  // ignore: unused_element
  Future<String> _legacyNativeCaptureUtterance() async {
    // Tracks repeated same-type native-recognizer errors (error_busy,
    // error_client, ...) across restarts within this capture, so a real
    // fault backs off harder than an ordinary silence timeout instead of
    // both being treated the same way. Reset whenever a session ends
    // cleanly (no error) or a different error type shows up.
    var consecutiveSameError = 0;
    String? lastErrorType;
    // The timestamp of the last error we've already accounted for, so a
    // single error doesn't get counted twice across loop iterations.
    DateTime? consumedErrorAt;

    while (_isActive) {
      // Re-assert listening on every retry, not just the first attempt —
      // makes the UI state self-correcting even if something else in the
      // loop below changes it, instead of relying on nothing ever doing
      // so (which was the actual bug: see _onRecordingStopped).
      _setState(ConversationState.listening);
      final completer = Completer<String>();
      try {
        await _speechService.startListening(
          (finalText) {
            _finalTranscript = finalText.trim();
            final completedAt = DateTime.now();
            final stoppedAt = _recordingStoppedAt;
            debugPrint(
              'VM_TIMING controller_final_transcript_ready '
              '${completedAt.toIso8601String()} '
              'stt_delay_ms=${stoppedAt == null ? 'unknown' : completedAt.difference(stoppedAt).inMilliseconds} '
              'text="$_finalTranscript"',
            );
            _safeNotify();
            if (!completer.isCompleted) completer.complete(_finalTranscript);
          },
          onPartialResult: (partial) {
            _partialTranscript = partial;
            debugPrint(
              '[PARTIAL] ${DateTime.now().toIso8601String()} text="$partial"',
            );
            _upsertPartialUserBubble(partial);
            _safeNotify();
          },
          onRecordingStopped: _onRecordingStopped,
        );
      } catch (e) {
        onError?.call(e);
        await Future.delayed(const Duration(milliseconds: 600));
        continue;
      }

      final result = (await completer.future).trim();
      _partialTranscript = '';
      if (result.isNotEmpty) return result;
      if (!_isActive) return '';

      // Base gap before relistening — Android needs a moment to release
      // the previous recognizer session. IMPORTANT: this wait must come
      // *before* checking for an error below, not after. Device logs
      // showed the native error (error_busy/error_client) consistently
      // arriving asynchronously, shortly AFTER the 'done'/'notListening'
      // status already resolved `result` above as empty — checking
      // immediately here would see nothing yet, every single time, which
      // is exactly what made the earlier version always log
      // "error_type=none" even while errors were firing constantly.
      await Future.delayed(const Duration(milliseconds: 500));

      final latestErrorAt = _speechService.lastErrorAt;
      final sawNewError =
          latestErrorAt != null &&
          (consumedErrorAt == null || latestErrorAt.isAfter(consumedErrorAt!));
      final errorType = sawNewError
          ? _classifySttError(_speechService.lastError)
          : null;
      if (sawNewError) consumedErrorAt = latestErrorAt;

      if (errorType != null) {
        consecutiveSameError = errorType == lastErrorType
            ? consecutiveSameError + 1
            : 1;
        lastErrorType = errorType;
      } else {
        consecutiveSameError = 0;
        lastErrorType = null;
      }

      debugPrint(
        'VM_TIMING stt_restart_decision error_type=${errorType ?? 'none'} '
        'consecutive=$consecutiveSameError',
      );

      if (consecutiveSameError >= 3) {
        // Same failure 3+ times in a row means this isn't Android's
        // normal teardown lag anymore — retrying immediately would just
        // spin. Stop the tight loop, tell the caller so it can surface
        // something to the user, then cool down before trying again.
        onError?.call(
          StateError(
            'Speech recognizer repeatedly failed ($lastErrorType) — '
            'pausing before retrying.',
          ),
        );
        await Future.delayed(const Duration(seconds: 3));
        consecutiveSameError = 0;
        lastErrorType = null;
        continue;
      }

      if (errorType != null) {
        // Already waited the base 500ms gap above; add an escalating
        // amount on top so repeated errors in a row back off harder,
        // without penalizing the very first retry after an error.
        final extra = Duration(milliseconds: 600 * (consecutiveSameError - 1));
        if (extra > Duration.zero) await Future.delayed(extra);
      }
    }
    return '';
  }

  /// Buckets a session error into a coarse type so repeated *same-kind*
  /// failures can be counted for backoff, without depending on the exact
  /// wording of platform error objects.
  String? _classifySttError(Object? error) {
    if (error == null) return null;
    final text = error.toString().toLowerCase();
    if (text.contains('busy')) return 'busy';
    if (text.contains('client')) return 'client';
    return 'other';
  }

  void _upsertPartialUserBubble(String text) {
    if (text.trim().isEmpty) return;
    if (_messages.isNotEmpty &&
        _messages.last.role == ChatRole.user &&
        _messages.last.isPartial) {
      _messages.last.text = text;
    } else {
      _messages.add(
        ChatMessage(role: ChatRole.user, text: text, isPartial: true),
      );
    }
  }

  void _finalizeUserMessage(String transcript) {
    if (_messages.isNotEmpty &&
        _messages.last.role == ChatRole.user &&
        _messages.last.isPartial) {
      _messages.last.text = transcript;
      _messages.last.isPartial = false;
    } else {
      _messages.add(
        ChatMessage(role: ChatRole.user, text: transcript, isPartial: false),
      );
    }
    _safeNotify();
  }

  void _appendToMessage(ChatMessage message, String sentence) {
    message.text = message.text.isEmpty
        ? sentence
        : '${message.text} $sentence';
    _safeNotify();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  void _setState(ConversationState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _isActive = false;
    unawaited(_speechService.stopListening());
    unawaited(_ttsService.dispose());
    unawaited(_navigationRequests.close());
    super.dispose();
  }

  void _onRecordingStopped() {
    _recordingStoppedAt = DateTime.now();
    debugPrint(
      'VM_TIMING mic_stopped ${_recordingStoppedAt!.toIso8601String()}',
    );
    // Deliberately no state change here. This fires on EVERY session end,
    // including a failed/empty one (silence timeout, error_busy,
    // error_client) that _captureUtterance is about to silently retry —
    // not just a real captured utterance. Flipping to `processing` here
    // used to leave the UI stuck showing "Thinking..." for the entire STT
    // retry loop, since nothing set it back to `listening` in between
    // retries (that only happens once, at the top of `_mainLoop`, before
    // `_captureUtterance`'s own retry loop even starts). The transition to
    // `processing` now only happens in `_handleTurn`, once there's an
    // actual non-empty transcript to act on.
  }

  void _onTtsPlaybackStarted() {
    final startedAt = DateTime.now();
    final replyAt = _replyReceivedAt;
    debugPrint(
      'VM_TIMING tts_playback_started ${startedAt.toIso8601String()} '
      'tts_start_delay_ms=${replyAt == null ? 'unknown' : startedAt.difference(replyAt).inMilliseconds}',
    );
  }
}

class NavigationRequest {
  const NavigationRequest({required this.routeName, this.arguments});

  final String routeName;
  final Object? arguments;
}

class _SentenceSplit {
  _SentenceSplit(this.complete, this.remainder);
  final List<String> complete;
  final String remainder;
}

/// Pulls out sentences that are already complete (end in . ! or ?) from a
/// growing token buffer, leaving whatever's left (an in-progress sentence)
/// as the remainder to keep accumulating.
_SentenceSplit _splitCompleteSentences(String buffer) {
  final matches = RegExp(r'[^.!?]*[.!?]+(\s+|$)').allMatches(buffer);
  final complete = <String>[];
  var consumed = 0;
  for (final m in matches) {
    final sentence = buffer.substring(m.start, m.end).trim();
    if (sentence.isNotEmpty) complete.add(sentence);
    consumed = m.end;
  }
  return _SentenceSplit(complete, buffer.substring(consumed));
}
