import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// Natural-voice TTS via Groq's Orpheus TTS endpoint, replacing the earlier
/// ElevenLabs implementation (which itself replaced the original flutter_tts
/// device-voice implementation).
///
/// Sentences are queued and played one at a time via [enqueueSentence] —
/// this is what lets the conversation controller start speech on the first
/// finished sentence of a streaming LLM reply instead of waiting for the
/// whole response. [speak] is kept for callers that just want to say one
/// full block of text (it splits it into sentences and enqueues each).
///
/// Note on "streamed playback": each sentence's audio is fetched as one
/// complete response (Groq's speech endpoint isn't chunked/streaming the
/// way ElevenLabs' was) and buffered to a small temp file before playback
/// starts (just_audio needs a seekable source for reliable play/stop
/// control). Sentences are short, so this adds negligible delay — the
/// perceived streaming comes from not waiting for the *whole reply* before
/// speaking starts.
///
/// Resilience: if Groq TTS fails for any reason (missing/invalid key,
/// terms not accepted on the account, network error, rate limit...), each
/// sentence falls back to the phone's on-device voice via flutter_tts
/// rather than going silent. It sounds more robotic, but "robotic voice"
/// beats "no voice" — the app should never just silently stop talking.
/// [onError] still fires either way, so the fallback firing is visible in
/// logs/UI rather than hiding the underlying problem.
///
/// Speech speed: Orpheus accepts a `speed` field (0.5–5.0, 1.0 = normal).
/// The default here is [_defaultSpeed] (0.85, a bit slower than natural)
/// since 1.0 read noticeably fast for a companion app meant to be easy to
/// follow by ear. Override per-install with GROQ_TTS_SPEED in .env if a
/// user wants it faster/slower. The on-device fallback voice is slowed to
/// roughly match, so pacing doesn't jump around if a sentence falls back
/// mid-reply.
///
/// [stop] truly interrupts mid-sentence — this is the hook barge-in uses.
class TtsService {
  TtsService({http.Client? client, AudioPlayer? audioPlayer, this.onError})
    : _client = client ?? http.Client(),
      _player = audioPlayer ?? AudioPlayer();

  static const _voiceEndpoint = 'https://api.groq.com/openai/v1/audio/speech';
  static const _model = 'canopylabs/orpheus-v1-english';
  // Orpheus voice. Others include "hannah", "troy" — see Groq's TTS docs
  // for the full list if you want to try a different one.
  static const _defaultVoice = 'austin';
  static const _timeout = Duration(seconds: 12);

  // Orpheus speed range is 0.5 (half speed) – 5.0 (5x), 1.0 = normal.
  static const _defaultSpeed = 0.85;
  static const _minSpeed = 0.5;
  static const _maxSpeed = 5.0;

  // flutter_tts speech rate is a 0.0–1.0 scale on both platforms (not the
  // same scale as Orpheus's speed field). ~0.45 reads at a similarly
  // unhurried pace to the 0.85 Orpheus default above; flutter_tts's own
  // default (platform-dependent, generally ~0.5) tends to read fast for
  // this app in the same way the old Orpheus default did.
  static const _fallbackSpeechRate = 0.45;

  final http.Client _client;
  final AudioPlayer _player;
  final FlutterTts _fallbackTts = FlutterTts();
  bool _fallbackReady = false;

  /// Called whenever fetching or playing a sentence's audio fails (e.g. a
  /// missing/invalid ELEVENLABS_API_KEY, or a network error) — without
  /// this, a broken TTS call used to fail completely silently, which
  /// looked like "the assistant only replies in text, never speaks."
  void Function(Object error)? onError;

  final Queue<String> _queue = Queue<String>();
  bool _draining = false;

  /// Bumped every time [stop] is called. Any in-flight fetch/playback
  /// started under an older session is abandoned rather than played,
  /// which is what makes stop() a true interrupt instead of "stop after
  /// the current network call finishes".
  int _session = 0;

  /// True while there is audio queued or actively playing.
  bool get isSpeaking => _queue.isNotEmpty || _player.playing;

  /// Splits [text] into sentences and enqueues each — use this for a
  /// complete, already-final block of text.
  Future<void> speak(String text) async {
    for (final sentence in _splitSentences(text)) {
      enqueueSentence(sentence);
    }
  }

  /// Adds one sentence to the playback queue and kicks off draining if
  /// it isn't already running. Call this as sentences complete while a
  /// streaming reply is still coming in.
  void enqueueSentence(String sentence) {
    final trimmed = sentence.trim();
    if (trimmed.isEmpty) return;
    _queue.add(trimmed);
    _drainQueue(_session);
  }

  /// Waits until the queue is empty and playback has finished (or been
  /// stopped). Lets the conversation controller know when it's safe to
  /// treat the assistant as done speaking.
  Future<void> waitUntilDone() async {
    while (_queue.isNotEmpty || _player.playing) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Immediately interrupts any in-flight fetch and any currently playing
  /// audio, and clears whatever was still queued.
  Future<void> stop() async {
    _session++;
    _queue.clear();
    if (_player.playing) {
      await _player.stop();
    }
    await _fallbackTts.stop();
  }

  Future<void> _drainQueue(int session) async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        if (session != _session) break; // stop() was called — abandon
        final sentence = _queue.removeFirst();
        await _speakNow(sentence, session);
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _speakNow(String text, int session) async {
    try {
      final bytes = await _fetchAudio(text);
      if (session != _session) return; // interrupted while fetching

      final file = await _writeTempFile(bytes);
      if (session != _session) return; // interrupted while writing

      await _player.setFilePath(file.path);
      if (session != _session) return; // interrupted while loading

      await _player.play();
      // Wait for this sentence to finish, or bail out early if stop()
      // bumps the session while it's playing.
      while (_player.playing && session == _session) {
        await Future.delayed(const Duration(milliseconds: 40));
      }
    } catch (e) {
      // Report it (so a missing API key, unaccepted model terms, or a
      // failed call is visible instead of silently producing no audio)...
      onError?.call(e);
      // ...but don't just leave the user with silence. Fall back to the
      // phone's built-in voice for this sentence and keep the queue
      // moving; one bad sentence — or a fully broken Groq TTS setup —
      // shouldn't mean the assistant never speaks at all.
      if (session == _session) {
        await _speakWithFallback(text, session);
      }
    }
  }

  Future<void> _speakWithFallback(String text, int session) async {
    try {
      if (!_fallbackReady) {
        await _fallbackTts.awaitSpeakCompletion(true);
        await _fallbackTts.setSpeechRate(_fallbackSpeechRate);
        _fallbackReady = true;
      }
      if (session != _session) return; // interrupted before we could start
      await _fallbackTts.speak(text);
    } catch (e) {
      // If even the on-device voice fails, there's genuinely nothing left
      // to try for this sentence — the primary error was already reported.
      onError?.call(e);
    }
  }

  Future<List<int>> _fetchAudio(String text) async {
    final apiKey = dotenv.env['GROQ_API_KEY'];
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw StateError('GROQ_API_KEY is not configured.');
    }
    final voice = dotenv.env['GROQ_TTS_VOICE']?.trim().isNotEmpty == true
        ? dotenv.env['GROQ_TTS_VOICE']!.trim()
        : _defaultVoice;
    final speed = _resolveSpeed();

    final response = await _client
        .post(
          Uri.parse(_voiceEndpoint),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body:
              '''
{
  "model": "$_model",
  "input": ${_jsonEscape(text)},
  "voice": "$voice",
  "response_format": "wav",
  "speed": $speed
}''',
        )
        .timeout(_timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Status: ${response.statusCode}\nBody: ${response.body}',
      );
    }
    return response.bodyBytes;
  }

  /// Reads GROQ_TTS_SPEED from .env if present and valid, clamped to
  /// Orpheus's supported 0.5–5.0 range; otherwise falls back to
  /// [_defaultSpeed]. A malformed value (typo, empty string) is treated
  /// the same as "not set" rather than throwing.
  double _resolveSpeed() {
    final raw = dotenv.env['GROQ_TTS_SPEED']?.trim();
    if (raw == null || raw.isEmpty) return _defaultSpeed;
    final parsed = double.tryParse(raw);
    if (parsed == null) return _defaultSpeed;
    return parsed.clamp(_minSpeed, _maxSpeed);
  }

  Future<File> _writeTempFile(List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/vm_tts_${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    return file.writeAsBytes(bytes, flush: true);
  }

  String _jsonEscape(String text) {
    final escaped = text
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', ' ');
    return '"$escaped"';
  }

  List<String> _splitSentences(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const [];
    final matches = RegExp(
      r'[^.!?]*[.!?]+(\s+|$)|[^.!?]+$',
    ).allMatches(trimmed);
    final sentences = matches
        .map((m) => trimmed.substring(m.start, m.end).trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return sentences.isEmpty ? [trimmed] : sentences;
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}
