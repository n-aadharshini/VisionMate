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

/// Orchestrates the single push-to-talk (PTT) conversation flow:
///
///   idle --(press)--> listening --(release)--> processing --> speaking --> idle
///
/// PTT is triggered either by the hardware Volume Up button (via
/// [_volumeButtonChannel]) or the in-app mic control — both call
/// [beginPushToTalk] / [endPushToTalk]. There is intentionally exactly one
/// capture flow in this controller: an earlier always-on/continuous
/// listening loop has been removed so PTT and continuous listening can no
/// longer run concurrently and fight over the microphone.
///
/// Every PTT turn is tagged with a monotonically increasing [_turnId].
/// Async work (STT stop, Groq classification, TTS playback, navigation)
/// checks its captured turn id against the current one before touching
/// state — so a stale completion from a turn that's since been cancelled
/// (app backgrounded, user started a new turn, controller disposed) is
/// discarded instead of corrupting the UI.
///
/// Barge-in note: an earlier version of this controller tried to start the
/// *next* listening session concurrently with the current turn's
/// processing/speaking, so a partial transcript during playback could cut
/// TTS off immediately. `speech_to_text` only supports one active session
/// on its underlying recognizer, though — starting a second `listen()`
/// before the first has fully torn down leaves the plugin unable to start
/// any further session. This version is strictly sequential (one mic
/// session per turn) and exposes [interruptSpeaking] instead: call it
/// (e.g. from a tap on the mic orb) to cut the assistant off and return to
/// idle immediately. True hands-free barge-in (detecting the user's voice
/// while the assistant is mid-sentence) needs either a VAD-based approach
/// or careful session handoff and is a good candidate to revisit once the
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
    // Registered once here, at controller construction, and explicitly
    // cleared in dispose() — previously the handler was never cleared, so
    // a platform event arriving after teardown could reach a disposed
    // controller.
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
  /// failures (e.g. a missing GROQ_API_KEY) are no longer silent.
  final void Function(Object error)? onError;

  final StreamController<Object> _errorsController =
      StreamController<Object>.broadcast();

  /// Every STT/Groq/TTS/channel error also flows through here, in addition
  /// to [onError]. [onError] is a single callback fixed at construction
  /// (set once in main.dart); this stream lets *any* number of widgets —
  /// e.g. the screen currently showing the conversation — subscribe and
  /// display the error themselves, which a single fixed callback can't do
  /// on its own.
  Stream<Object> get errors => _errorsController.stream;

  void _reportError(Object error) {
    onError?.call(error);
    if (!_disposed) _errorsController.add(error);
  }

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
  DateTime? _replyReceivedAt;

  bool _isActive = false;
  bool get isActive => _isActive;

  bool _pushToTalkHeld = false;

  /// True from the moment a press is accepted until [initialize] and the
  /// native `startListening` call have both completed. This is a
  /// *synchronous* guard — set before any `await` — so two rapid presses
  /// can't both pass the "am I already starting?" check before the first
  /// one has had a chance to record that it's starting.
  bool _pushToTalkStarting = false;

  /// Set when [endPushToTalk] is called while [_pushToTalkStarting] is
  /// still true (release-before-start-finished). [beginPushToTalk] checks
  /// this once it's safe to do so and immediately ends the turn itself,
  /// instead of leaving the mic open with no matching release.
  bool _pendingRelease = false;

  /// Bumped at the start of every PTT turn and whenever a turn is
  /// cancelled. Async continuations compare their captured id against the
  /// current value before applying state changes.
  int _turnId = 0;

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Prepares microphone permission without starting a capture session.
  Future<bool> initialize() async {
    final ok = await _speechService.initialize();
    if (!ok) {
      _reportError(StateError('Microphone permission was not granted.'));
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
    if (_pushToTalkHeld ||
        _pushToTalkStarting ||
        _state != ConversationState.idle) {
      debugPrint(
        '[PTT] ignored duplicate press (held=$_pushToTalkHeld, '
        'starting=$_pushToTalkStarting, state=$_state)',
      );
      return false;
    }

    _pushToTalkStarting = true;
    _pendingRelease = false;
    final turnId = ++_turnId;
    debugPrint('[PTT PRESS] ${DateTime.now().toIso8601String()} turn=$turnId');

    bool ok;
    try {
      ok = await initialize();
    } catch (error) {
      _pushToTalkStarting = false;
      _reportError(error);
      return false;
    }

    if (_disposed || turnId != _turnId) {
      // Superseded (stop()/dispose()/a new turn) while awaiting initialize().
      debugPrint('[PTT] turn=$turnId superseded during initialize()');
      _pushToTalkStarting = false;
      return false;
    }
    if (!ok) {
      _pushToTalkStarting = false;
      return false;
    }

    _pushToTalkHeld = true;
    _isActive = true;
    _partialTranscript = '';
    _finalTranscript = '';
    _setState(ConversationState.listening);

    try {
      await _speechService.startListening(
        (_) {},
        onPartialResult: (partial) {
          if (turnId != _turnId) return; // stale session, ignore
          _partialTranscript = partial;
          _upsertPartialUserBubble(partial);
          _safeNotify();
        },
        onRecordingStopped: _onRecordingStopped,
      );
    } catch (error) {
      _pushToTalkHeld = false;
      _isActive = false;
      _pushToTalkStarting = false;
      _setState(ConversationState.idle);
      _reportError(error);
      return false;
    }

    _pushToTalkStarting = false;

    if (turnId != _turnId) {
      // Cancelled while startListening() was in flight — whatever
      // cancelled us already reset _pushToTalkHeld/state, so just bail.
      debugPrint('[PTT] turn=$turnId superseded during startListening()');
      return false;
    }

    if (_pendingRelease) {
      // Volume Up was released before we even finished starting — this is
      // the press/release race: without this check, endPushToTalk() would
      // have already returned early (because _pushToTalkHeld was still
      // false at the time), leaving the mic listening with no matching
      // release. Handle it now instead.
      _pendingRelease = false;
      debugPrint(
        '[PTT] turn=$turnId handling release deferred during start-up',
      );
      unawaited(endPushToTalk());
    }
    return true;
  }

  /// Ends the PTT capture immediately, locks its live transcript, then runs
  /// the existing Groq intent/reply pipeline. Nothing listens while it runs.
  Future<void> endPushToTalk() async {
    if (_pushToTalkStarting) {
      // Release arrived before begin's async initialize()/startListening()
      // finished. Defer it — beginPushToTalk() checks _pendingRelease once
      // it's safe to touch state again.
      _pendingRelease = true;
      debugPrint('[PTT RELEASE] deferred — still starting up');
      return;
    }
    if (!_pushToTalkHeld || _state != ConversationState.listening) {
      debugPrint(
        '[PTT] ignored release (held=$_pushToTalkHeld, state=$_state)',
      );
      return;
    }

    final turnId = _turnId;
    debugPrint(
      '[PTT RELEASE] ${DateTime.now().toIso8601String()} turn=$turnId',
    );
    _pushToTalkHeld = false;

    var transcript = '';
    try {
      transcript = (await _speechService.stopListeningAndGetTranscript())
          .trim();
    } catch (error) {
      _reportError(error);
    } finally {
      // Always settle these, even if stopListeningAndGetTranscript()
      // throws — previously a throw here left the controller stuck in
      // `listening` with _pushToTalkHeld already false, an inconsistent
      // combination that blocked any further presses.
      _isActive = false;
      _finalTranscript = transcript;
      _partialTranscript = '';
    }
    debugPrint(
      '[LISTEN END] ${DateTime.now().toIso8601String()} text="$transcript"',
    );
    _safeNotify();

    if (transcript.isEmpty) {
      if (turnId == _turnId) _setState(ConversationState.idle);
      return;
    }

    try {
      await _handleTurn(transcript, turnId);
    } finally {
      if (!_disposed && turnId == _turnId) _setState(ConversationState.idle);
    }
  }

  /// Cuts the assistant off mid-reply and returns to idle. This is the
  /// practical stand-in for automatic barge-in in this version — wire it
  /// to a tap on the mic orb, or call it from anywhere else a manual
  /// interrupt is wanted.
  Future<void> interruptSpeaking() async {
    if (_state != ConversationState.speaking) return;
    _turnId++; // discard whatever's left of the current turn
    await _ttsService.stop();
    if (!_disposed) _setState(ConversationState.idle);
  }

  /// Cancels whatever PTT turn is currently in flight — bumps the turn id
  /// so any in-flight Groq/TTS/navigation completion for it is discarded,
  /// stops the mic and TTS, clears PTT flags, and returns to idle. Used by
  /// [stop] and by app-lifecycle handling (backgrounding).
  Future<void> cancelCurrentTurn() async {
    _turnId++;
    _pushToTalkHeld = false;
    _pushToTalkStarting = false;
    _pendingRelease = false;
    _isActive = false;
    await _speechService.stopListening();
    await _ttsService.stop();
    if (_disposed) return;
    _setState(ConversationState.idle);
  }

  /// Public stop — cancels any in-flight turn and returns to idle. Safe to
  /// call at any point, including when nothing is in progress.
  Future<void> stop() => cancelCurrentTurn();

  /// Call from the app's lifecycle observer when the app is paused,
  /// inactive, or detached. Stops the mic immediately and cancels whatever
  /// PTT turn is in flight, so a stale Groq/TTS completion that arrives
  /// after backgrounding can't flip state or speak unexpectedly.
  Future<void> handleAppBackgrounded() async {
    if (_state == ConversationState.idle && !_isActive) return;
    debugPrint('[LIFECYCLE] app backgrounded — cancelling current turn');
    await cancelCurrentTurn();
  }

  /// Call from the app's lifecycle observer on resume. PTT never
  /// auto-restarts on its own, so this just makes sure state is
  /// consistent (idle, mic off) after whatever happened while
  /// backgrounded, rather than leaving a stale non-idle state on screen.
  void handleAppResumed() {
    if (_disposed) return;
    if (_state != ConversationState.idle) {
      debugPrint('[LIFECYCLE] app resumed — resetting to idle');
      _setState(ConversationState.idle);
    }
  }

  Future<void> _handleTurn(String transcript, int turnId) async {
    _finalizeUserMessage(transcript);
    if (turnId != _turnId) return;
    _setState(ConversationState.processing);

    VisionMateResponse response;
    final apiStartedAt = DateTime.now();
    debugPrint(
      '[SENDING TO GROQ] ${apiStartedAt.toIso8601String()} text="$transcript"',
    );
    try {
      response = await _brain.classify(transcript);
    } catch (error) {
      _reportError(error);
      response = const VisionMateResponse(
        intent: IntentType.unknown,
        destination: null,
        reply: 'Sorry, I ran into a problem there. Could you try again?',
        confidence: 0,
        source: 'controller-fallback',
      );
    }

    if (_disposed || turnId != _turnId) {
      // The app was backgrounded/stopped, or a new turn started, while
      // Groq was still in flight. Discard the stale reply rather than
      // flipping into `speaking` or saying something out loud for a turn
      // that's no longer current.
      debugPrint(
        '[TURN] discarding stale Groq reply for turn=$turnId (current=$_turnId)',
      );
      return;
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

    if (_disposed || turnId != _turnId) return; // cancelled mid-speech

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

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  void _setState(ConversationState next) {
    if (_disposed) return;
    if (_state != next) {
      debugPrint('[STATE] ${_state.name} -> ${next.name}');
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _isActive = false;
    // Clear the platform handler explicitly so a late Volume Up event
    // can't reach this controller after teardown.
    _volumeButtonChannel.setMethodCallHandler(null);
    unawaited(_speechService.stopListening());
    unawaited(_ttsService.dispose());
    unawaited(_navigationRequests.close());
    unawaited(_errorsController.close());
    super.dispose();
  }

  void _onRecordingStopped() {
    debugPrint('VM_TIMING mic_stopped ${DateTime.now().toIso8601String()}');
    // Deliberately no state change here — see _handleTurn / endPushToTalk
    // for where `processing`/`speaking` transitions actually happen.
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
