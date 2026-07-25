import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
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
  }

  final SpeechService _speechService;
  final TtsService _ttsService;
  final VisionMateBrain _brain;

  /// Surfaced for UI feedback (e.g. a toast or subtle earcon) — never
  /// throws past this controller. Also wired into [TtsService] so TTS
  /// failures (e.g. a missing ELEVENLABS_API_KEY) are no longer silent.
  final void Function(Object error)? onError;

  ConversationState _state = ConversationState.idle;
  ConversationState get state => _state;

  // Guards against calling notifyListeners() (or touching platform
  // services) after dispose() has run. Needed because stop() is async
  // and UI code (e.g. State.dispose(), which can't be awaited) may call
  // stop() and then dispose() back-to-back without waiting for stop()
  // to actually finish — without this guard, stop()'s trailing
  // notifyListeners() call throws once dispose() has already run.
  bool _disposed = false;

  String _partialTranscript = '';
  String get partialTranscript => _partialTranscript;

  bool get isSpeaking => _state == ConversationState.speaking;

  bool _isActive = false;
  bool get isActive => _isActive;

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

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
            if (!completer.isCompleted) completer.complete(finalText);
          },
          onPartialResult: (partial) {
            _partialTranscript = partial;
            _upsertPartialUserBubble(partial);
            _safeNotify();
          },
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
      // Silence timeout with nothing said — brief pause, then relisten.
      // The short gap matters on Android: starting a new session
      // immediately after the previous one ends can throw "error_busy".
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return '';
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
    super.dispose();
  }
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
