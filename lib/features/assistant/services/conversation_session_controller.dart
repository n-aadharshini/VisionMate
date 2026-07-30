import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/chat_message.dart';
import '../models/intent_type.dart';
import '../models/vision_mate_response.dart';
import 'speech_service.dart';
import 'tts_service.dart';
import 'vision_mate_brain.dart';

enum ConversationState { idle, listening, processing, speaking }

/// Orchestrates the single push-to-talk (PTT) conversation flow:
///
///   idle -> (press)   -> listening
///        -> (release) -> processing -> speaking -> idle
///
/// This is now the ONLY capture flow in the app. The previous always-on
/// `start()` / `_mainLoop()` continuous-listening loop has been removed —
/// it was reachable from `ListeningScreen` at the same time as PTT and the
/// two fought over the same native speech-recognizer session (a confirmed
/// bug). Both the hardware Volume Up button and the in-app mic call the
/// same [beginPushToTalk] / [endPushToTalk] pair.
///
/// Race safety: a monotonically increasing [_generation] identifies each
/// PTT turn. Every async STT/Groq/TTS step checks its captured generation
/// against the current one before touching state, so a stale callback
/// from a turn that was cancelled (app backgrounded mid-reply, a new press
/// started before the previous turn's async work landed, etc.) can never
/// resurrect state that has already moved on.
///
/// Lifecycle: this controller mixes in [WidgetsBindingObserver] and
/// registers/unregisters itself in its constructor/[dispose] — when the
/// app is paused, inactive, detached, or hidden, any active PTT turn is
/// cancelled and the mic/TTS are stopped immediately, rather than leaving
/// a capture running in the background.
class ConversationSessionController extends ChangeNotifier
    with WidgetsBindingObserver {
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
    _ttsService.onError ??= _reportError;
    _ttsService.onPlaybackStarted ??= _onTtsPlaybackStarted;
    _volumeButtonChannel.setMethodCallHandler(_handleVolumeButtonEvent);
    WidgetsBinding.instance.addObserver(this);
  }

  static const _volumeButtonChannel = MethodChannel('visionmate/volume_button');

  final SpeechService _speechService;
  final TtsService _ttsService;
  final VisionMateBrain _brain;
  final StreamController<NavigationRequest> _navigationRequests =
      StreamController<NavigationRequest>.broadcast();
  final StreamController<Object> _errors = StreamController<Object>.broadcast();

  /// The root app listens here and performs intent-driven route changes.
  Stream<NavigationRequest> get navigationRequests =>
      _navigationRequests.stream;

  /// Broadcast stream of every error this controller reports (mic init,
  /// STT, Groq, TTS, or the platform channel). UI code can subscribe to
  /// show error banners without polling [lastErrorMessage] off of
  /// [notifyListeners] — e.g. SpeakScreen listens here directly.
  Stream<Object> get errors => _errors.stream;

  /// Surfaced for UI feedback (e.g. a toast or subtle earcon) — never
  /// throws past this controller. Also wired into [TtsService] so TTS
  /// failures (e.g. a missing GROQ_API_KEY) are no longer silent.
  final void Function(Object error)? onError;

  ConversationState _state = ConversationState.idle;
  ConversationState get state => _state;
  bool get isListening => _state == ConversationState.listening;
  bool get isThinking => _state == ConversationState.processing;
  bool get isSpeaking => _state == ConversationState.speaking;

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

  /// The most recent error surfaced anywhere in this controller (mic init,
  /// STT, Groq, TTS, or the platform channel), as a display-ready string.
  /// UI code (e.g. SpeakScreen) can read this after any [notifyListeners]
  /// call to show it, instead of relying on [onError] alone.
  String? _lastErrorMessage;
  String? get lastErrorMessage => _lastErrorMessage;

  bool _isActive = false;
  bool get isActive => _isActive;

  // --- PTT race-safety state ---
  bool _pushToTalkHeld = false;
  // True from the moment a press is accepted until initialize() +
  // startListening() have both completed. A synchronous guard set before
  // any awaiting happens, so two rapid presses can't both pass the idle
  // check before the first one has had a chance to flip state.
  bool _isStarting = false;
  // Set when a release arrives while `_isStarting` is still true — the
  // release is honored as soon as the in-flight start sequence finishes,
  // instead of being silently dropped (which used to leave the mic open
  // with no matching release).
  bool _pendingRelease = false;
  // Cached after the first successful mic/STT permission + init, so
  // every subsequent press doesn't pay the native re-initialization cost.
  bool _micInitialized = false;
  // Bumped on every new PTT press and on every cancellation. Async
  // callbacks/awaits captured a generation at the time they started and
  // check it against this before mutating state — see class doc.
  int _generation = 0;

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  List<Map<String, String>> recentHistory({int limit = 20}) => _messages
      .where((message) => message.text.trim().isNotEmpty)
      .skip(_messages.length > limit ? _messages.length - limit : 0)
      .map((message) => {'role': message.role == ChatRole.user ? 'user' : 'assistant', 'content': message.text})
      .toList(growable: false);

  /// Shared speech entry point for feature controllers such as Travel.
  /// It deliberately reuses the app-wide TTS instance instead of letting a
  /// feature construct a competing player or queue.
  Future<void> speak(String text) => _ttsService.speak(text);

  /// Prepares microphone permission without starting a capture session.
  /// Safe to call repeatedly — the actual native init only happens once.
  Future<bool> initialize() async {
    if (_micInitialized) return true;
    final ok = await _speechService.initialize();
    if (!ok) {
      _reportError(StateError('Microphone permission was not granted.'));
      return false;
    }
    _micInitialized = true;
    return true;
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
  /// Returns false (and leaves state untouched) if a press is already in
  /// flight, already held, mic permission fails, or the controller isn't
  /// idle.
  Future<bool> beginPushToTalk() async {
    if (_isStarting || _pushToTalkHeld) {
      debugPrint(
        '[PTT PRESS] ignored — already ${_isStarting ? 'starting' : 'held'}',
      );
      return false;
    }
    if (_state != ConversationState.idle) {
      debugPrint('[PTT PRESS] ignored — state is ${_state.name}, not idle');
      return false;
    }

    // Set synchronously, before any `await`, so a second rapid press
    // cannot also pass the checks above while this one is still setting up.
    _isStarting = true;
    _pendingRelease = false;
    final generation = ++_generation;
    debugPrint('[PTT PRESS] gen=$generation');

    final micOk = await initialize();
    if (generation != _generation) {
      // Cancelled while awaiting permission/init (e.g. app backgrounded).
      _isStarting = false;
      return false;
    }
    if (!micOk) {
      _isStarting = false;
      return false;
    }

    _pushToTalkHeld = true;
    _isActive = true;
    _isStarting = false;
    _partialTranscript = '';
    _finalTranscript = '';
    _setState(ConversationState.listening);

    try {
      await _speechService.startListening(
        (_) {},
        onPartialResult: (partial) {
          if (generation != _generation) return;
          _partialTranscript = partial;
          _upsertPartialUserBubble(partial);
          _safeNotify();
        },
        onRecordingStopped: _onRecordingStopped,
      );
    } catch (error) {
      if (generation == _generation) {
        _pushToTalkHeld = false;
        _isActive = false;
        _setState(ConversationState.idle);
      }
      _reportError(error);
      return false;
    }

    // A release that arrived while the above was still in flight is
    // honored now, rather than being lost with the mic left open.
    if (_pendingRelease && generation == _generation) {
      _pendingRelease = false;
      debugPrint('[PTT RELEASE] applying release queued during start');
      unawaited(endPushToTalk());
    }
    return true;
  }

  /// Ends the PTT capture immediately, locks its live transcript, then runs
  /// the existing Groq intent/reply pipeline. Nothing listens while it runs.
  Future<void> endPushToTalk() async {
    if (_isStarting) {
      // beginPushToTalk() hasn't finished its async setup yet — record
      // the release and let beginPushToTalk() apply it the moment it's
      // safe to, instead of dropping it (the confirmed press/release race).
      debugPrint('[PTT RELEASE] arrived mid-start — queued');
      _pendingRelease = true;
      return;
    }
    if (!_pushToTalkHeld || _state != ConversationState.listening) {
      debugPrint(
        '[PTT RELEASE] ignored — not in an active PTT session '
        '(state=${_state.name})',
      );
      return;
    }

    final generation = _generation;
    _pushToTalkHeld = false;
    debugPrint('[PTT RELEASE] gen=$generation');

    try {
      final transcript = (await _speechService.stopListeningAndGetTranscript())
          .trim();
      if (generation != _generation) return; // superseded mid-stop

      _finalTranscript = transcript;
      _partialTranscript = '';
      debugPrint(
        '[LISTEN END] ${DateTime.now().toIso8601String()} text="$transcript"',
      );
      _safeNotify();

      if (transcript.isEmpty) return;
      await _handleTurn(transcript, generation);
    } catch (error) {
      _reportError(error);
    } finally {
      // Always clears held/active and returns to idle, even if STT or the
      // turn pipeline threw — the confirmed "stuck in listening" bug.
      _isActive = false;
      if (!_disposed && generation == _generation) {
        _setState(ConversationState.idle);
      }
    }
  }

  /// Cuts the assistant off mid-reply and returns to listening. This is
  /// the practical stand-in for automatic barge-in in this version — wire
  /// it to a tap on the mic orb, or call it from anywhere else you want a
  /// manual interrupt.
  Future<void> interruptSpeaking() async {
    if (_state != ConversationState.speaking) return;
    await _ttsService.stop();
  }

  /// General-purpose cancel: stops any active PTT capture or in-flight
  /// turn and returns to idle. Safe to call from any state.
  Future<void> stop() async {
    _cancelActiveTurn(reason: 'stop_called');
  }

  void _cancelActiveTurn({required String reason}) {
    debugPrint('[STATE] cancelling active turn ($reason), was ${_state.name}');
    _generation++; // invalidates any in-flight callbacks/awaits
    _pushToTalkHeld = false;
    _isStarting = false;
    _pendingRelease = false;
    _isActive = false;
    unawaited(_speechService.stopListeningAndGetTranscript());
    unawaited(_ttsService.stop());
    if (!_disposed) _setState(ConversationState.idle);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[STATE] app lifecycle -> $state');
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // Don't let the mic, an in-flight Groq call, or TTS keep running
        // once the app isn't in the foreground — there was previously no
        // lifecycle handling at all, so backgrounding mid-turn could leave
        // stale work that resolves later and clobbers state.
        if (_state != ConversationState.idle || _pushToTalkHeld) {
          _cancelActiveTurn(reason: 'app_lifecycle_$state');
        }
      case AppLifecycleState.resumed:
        break;
    }
  }

  Future<void> _handleTurn(String transcript, int generation) async {
    _finalizeUserMessage(transcript);
    if (generation != _generation) return;
    _setState(ConversationState.processing);

    VisionMateResponse response;
    final apiStartedAt = DateTime.now();
    debugPrint(
      '[SENDING TO GROQ] ${apiStartedAt.toIso8601String()} text="$transcript"',
    );
    try {
      response = await _brain.classify(transcript, history: recentHistory());
    } catch (error) {
      _reportError(error);
      response = const VisionMateResponse(
        intent: IntentType.chat,
        destination: null,
        reply: 'Sorry, I ran into a problem there. Could you try again?',
        confidence: 0,
        source: 'controller-fallback',
      );
    }
    if (generation != _generation) return; // cancelled while Groq was in flight

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
    if (generation != _generation) return; // cancelled mid-speech

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
      IntentType.chat => null,
    };
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

  /// Records the error for UI display and forwards it to the caller's
  /// [onError], if any. Every error path in this controller goes through
  /// here now instead of calling `onError?.call(...)` directly, so
  /// `lastErrorMessage` is always in sync with what's been logged.
  void _reportError(Object error) {
    _lastErrorMessage = error.toString();
    debugPrint('[APP ERROR] $error');
    onError?.call(error);
    if (!_disposed && !_errors.isClosed) _errors.add(error);
    _safeNotify();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  void _setState(ConversationState next) {
    if (_disposed) return;
    debugPrint('[STATE] ${_state.name} -> ${next.name}');
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++; // invalidate anything still in flight
    _isActive = false;
    WidgetsBinding.instance.removeObserver(this);
    _volumeButtonChannel.setMethodCallHandler(null);
    unawaited(_speechService.stopListening());
    unawaited(_ttsService.dispose());
    unawaited(_navigationRequests.close());
    unawaited(_errors.close());
    super.dispose();
  }

  void _onRecordingStopped() {
    _recordingStoppedAt = DateTime.now();
    debugPrint(
      'VM_TIMING mic_stopped ${_recordingStoppedAt!.toIso8601String()}',
    );
    // Deliberately no state change here — this fires on every session end
    // (including one superseded by cancellation), and the transition to
    // `processing` only happens in `_handleTurn`, once there's an actual
    // non-empty transcript to act on.
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
