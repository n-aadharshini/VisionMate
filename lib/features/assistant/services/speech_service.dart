import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_recognition_result.dart' as stt_result;
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Speech-to-text via Groq's hosted Whisper API (whisper-large-v3-turbo),
/// replacing the old on-device `speech_to_text` implementation.
///
/// The big architectural difference: Groq's transcription endpoint is a
/// plain file upload, not a streaming session — there is no live partial
/// transcript. So instead of "start a recognizer session, get words as
/// they're spoken", this service:
///
///   1. Starts recording microphone audio to a local file.
///   2. Spends a brief calibration window measuring the ambient noise
///      floor on THIS device/mic, and derives a silence threshold from
///      it (see "Adaptive silence threshold" below) rather than using a
///      single number that was only ever tuned against one phone.
///   3. Watches the recorder's amplitude stream against that threshold
///      for silence.
///   4. Once the user has been quiet for [_silenceDuration] — after having
///      recorded for at least [_minRecordingDuration], so a stray cough at
///      the very start doesn't end the turn — stops recording.
///   5. Uploads the finished clip to Groq and returns the transcript via
///      [onResult].
///
/// Adaptive silence threshold:
/// A fixed dB number (e.g. "-35") doesn't generalize across devices — on
/// a phone whose mic runs quiet, real speech can sit below that floor and
/// get discarded as silence (looks like "it's not listening to me"); on a
/// phone in a noisy room, ambient sound can spike above it and get
/// mistaken for speech (looks like "it's sending random messages", since
/// Whisper then transcribes near-silence/noise and sometimes hallucinates
/// a plausible-sounding phrase — see the hallucination gates below).
/// Instead, each recording opens with a short [_calibrationDuration]
/// window where amplitude samples are collected without judging them as
/// "loud" or "quiet" yet. Once that window ends, the average ambient
/// level is computed and the working threshold is set to
/// `ambientAvg + _calibrationMarginDb`, clamped between [_minThresholdDb]
/// and [_maxThresholdDb] so a pathological calibration (e.g. calibrating
/// during a loud honk) can't produce an unusable threshold in either
/// direction.
///
/// [onPartialResult] stays in the signature for compatibility with
/// existing callers (ConversationSessionController, ListeningScreen) but
/// is intentionally never invoked with real text — Groq gives no partial
/// words back. Callers that showed live captions from it will just show
/// nothing until the final transcript arrives; that's expected, not a bug.
/// Retained Groq Whisper recording implementation. It is intentionally not
/// instantiated: native STT is active below because PTT needs live captions.
class GroqWhisperSpeechService {
  GroqWhisperSpeechService({http.Client? client, AudioRecorder? recorder})
    : _client = client ?? http.Client(),
      _recorder = recorder ?? AudioRecorder();

  static const _endpoint =
      'https://api.groq.com/openai/v1/audio/transcriptions';
  static const _model = 'whisper-large-v3-turbo';
  static const _requestTimeout = Duration(seconds: 15);

  // --- Adaptive silence-threshold tuning ---
  // Amplitude is dBFS: roughly -160 (silence) to 0 (max).
  //
  // How long to just listen and measure ambient noise before judging
  // anything as "loud" or "quiet". Long enough to get a stable read on
  // the room/mic, short enough that it doesn't meaningfully delay
  // silence detection on a short utterance.
  static const _calibrationDuration = Duration(milliseconds: 400);
  // How far above the measured ambient floor counts as "someone is
  // talking". Widen this (e.g. 16-18dB) if quiet rooms are still
  // triggering on ambient noise; narrow it (e.g. 8-10dB) if a device
  // with a quiet mic still isn't picking up soft speech.
  static const _calibrationMarginDb = 12.0;
  // Hard floor/ceiling so a bad calibration sample (e.g. a slammed door
  // during the calibration window) can't push the threshold somewhere
  // unusable.
  static const _minThresholdDb = -50.0;
  static const _maxThresholdDb = -20.0;
  // Used only if calibration somehow collects zero samples (e.g. the
  // amplitude stream hiccups) — the old fixed value, as a last resort.
  static const _fallbackThresholdDb = -35.0;

  static const _silenceDuration = Duration(milliseconds: 800);
  static const _minRecordingDuration = Duration(milliseconds: 400);
  static const _maxRecordingDuration = Duration(seconds: 30);
  static const _amplitudeSampleInterval = Duration(milliseconds: 200);

  /// Whisper (all versions, including Groq's) hallucinates short plausible
  /// phrases — "Thank you.", "You don't like that." — when fed near-silent
  /// or pure-ambient-noise audio; it was trained to always produce *some*
  /// text. Two defenses against that, both applied before a transcript is
  /// ever handed back to the caller:
  ///
  /// 1. Client-side gate: track how much of the recording was actually
  ///    above the (now adaptive) threshold — a rough VAD. If less than
  ///    [_minVoicedDuration] of real signal was ever seen, don't even call
  ///    the API — it was silence, full stop.
  /// 2. Server-side gate: request `verbose_json` so Groq returns
  ///    per-segment `no_speech_prob`/`avg_logprob`. If the average
  ///    `no_speech_prob` across segments is above [_noSpeechProbThreshold],
  ///    treat the "transcript" as a hallucination and discard it even
  ///    though Groq did return text.
  static const _minVoicedDuration = Duration(milliseconds: 350);
  static const _noSpeechProbThreshold = 0.5;

  final http.Client _client;
  final AudioRecorder _recorder;

  bool _isInitialized = false;
  bool get isAvailable => _isInitialized;

  // Compatibility diagnostics for the controller's restart logging. The
  // active Groq upload path has no recognizer-specific error object.
  DateTime? get lastErrorAt => null;
  Object? get lastError => null;

  bool _isRecording = false;
  bool get isListening => _isRecording;

  StreamSubscription<Amplitude>? _amplitudeSub;
  Timer? _silenceTimer;
  Timer? _maxDurationTimer;

  /// The threshold actually used by the most recently completed
  /// recording. Exposed only for debugging/telemetry — nothing in this
  /// class depends on callers reading it.
  double? lastCalibratedThresholdDb;

  Future<bool> initialize() async {
    final permission = await Permission.microphone.request();
    _isInitialized = permission.isGranted;
    return _isInitialized;
  }

  /// Starts recording. Returns as soon as recording has begun — same
  /// "fire and let the callback fire later" shape as the old
  /// speech_to_text-based version, so callers awaiting this don't block
  /// for the whole utterance.
  Future<void> startListening(
    ValueChanged<String> onResult, {
    ValueChanged<String>? onPartialResult,
    VoidCallback? onRecordingStopped,
  }) async {
    if (!_isInitialized && !await initialize()) {
      throw StateError(
        'Microphone or speech recognition permission was not granted.',
      );
    }
    if (_isRecording) return;

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/vm_stt_${DateTime.now().microsecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
        // Let the phone's own mic pipeline do what it's good at before
        // any of our amplitude-based logic ever sees the signal —
        // echoCancel strips out the device's own speaker output (so the
        // assistant's own voice bleeding into the mic doesn't confuse
        // things), noiseSuppress reduces steady background noise (fans,
        // traffic hum, AC). Neither of these is speaker isolation (they
        // won't distinguish "you" from "another person talking nearby"),
        // but they meaningfully clean up the signal before we do our own
        // sustained-noise filtering below.
        echoCancel: true,
        noiseSuppress: true,
      ),
      path: path,
    );
    _isRecording = true;

    final recordingStarted = DateTime.now();
    debugPrint('[LISTEN START] ${recordingStarted.toIso8601String()}');
    debugPrint('SpeechService: recording started');
    var lastLoudAt = DateTime.now();
    var voicedMs = 0;
    var finished = false;

    // How many consecutive amplitude samples above threshold are needed
    // before we treat it as "someone is actually talking" rather than a
    // brief noise spike (a door, a cough, a plate clinking). At the
    // default 200ms sample interval this is ~400ms of sustained sound —
    // short blips no longer reset the silence timer or count as voiced,
    // which both filters out ambient noise AND stops noise from
    // artificially extending the recording (i.e. makes it faster).
    const _consecutiveLoudRequired = 2;
    var _consecutiveLoud = 0;

    // Calibration state — collected during the first _calibrationDuration
    // of this recording, then frozen into a single threshold for the
    // rest of the turn.
    final calibrationSamples = <double>[];
    var calibrated = false;
    var thresholdDb = _fallbackThresholdDb;

    _amplitudeSub = _recorder
        .onAmplitudeChanged(_amplitudeSampleInterval)
        .listen((amp) {
          final elapsed = DateTime.now().difference(recordingStarted);

          if (!calibrated) {
            if (elapsed < _calibrationDuration) {
              // Still in the calibration window — just observe, don't
              // judge this sample as loud/quiet yet.
              calibrationSamples.add(amp.current);
              return;
            }
            // Calibration window just closed — derive the working
            // threshold from what we measured.
            calibrated = true;
            if (calibrationSamples.isNotEmpty) {
              final avg =
                  calibrationSamples.reduce((a, b) => a + b) /
                  calibrationSamples.length;
              thresholdDb = (avg + _calibrationMarginDb).clamp(
                _minThresholdDb,
                _maxThresholdDb,
              );
            }
            lastCalibratedThresholdDb = thresholdDb;
            // Reset the silence clock so the calibration window itself
            // (during which the user may well have already started
            // talking) isn't counted against them as "quiet time".
            lastLoudAt = DateTime.now();
          }

          if (amp.current > thresholdDb) {
            _consecutiveLoud++;
            if (_consecutiveLoud >= _consecutiveLoudRequired) {
              lastLoudAt = DateTime.now();
              voicedMs += _amplitudeSampleInterval.inMilliseconds;
            }
          } else {
            _consecutiveLoud = 0;
          }
        });

    Future<void> finish() async {
      if (finished) return;
      finished = true;
      _silenceTimer?.cancel();
      _maxDurationTimer?.cancel();
      await _amplitudeSub?.cancel();
      _isRecording = false;
      await _recorder.stop();
      onRecordingStopped?.call();
      final recordedMs = DateTime.now()
          .difference(recordingStarted)
          .inMilliseconds;
      debugPrint(
        'SpeechService: recording stopped after ${recordedMs}ms '
        '(threshold=${thresholdDb.toStringAsFixed(1)}dB, voiced=${voicedMs}ms)',
      );

      // Gate 1: never so much as spoke — don't spend an API call on it.
      if (voicedMs < _minVoicedDuration.inMilliseconds) {
        debugPrint('SpeechService: discarded as silence, skipping API call');
        unawaited(File(path).delete().catchError((_) => File(path)));
        onResult('');
        return;
      }
      debugPrint(
        'VM_TIMING stt_upload_started ${DateTime.now().toIso8601String()}',
      );
      await _transcribeAndReport(path, onResult);
    }

    // Polling rather than a single-shot Timer so the silence window keeps
    // resetting cleanly any time fresh sound arrives. Also gated on
    // `calibrated` so we never call silence before we've even finished
    // measuring the room.
    _silenceTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (!calibrated) return;
      final now = DateTime.now();
      final recordedFor = now.difference(recordingStarted);
      final quietFor = now.difference(lastLoudAt);
      if (recordedFor >= _minRecordingDuration &&
          quietFor >= _silenceDuration) {
        timer.cancel();
        unawaited(finish());
      }
    });

    // Hard ceiling so a stuck-open mic (e.g. constant background noise
    // that never reads as "silence") can't record forever.
    _maxDurationTimer = Timer(_maxRecordingDuration, () {
      unawaited(finish());
    });
  }

  Future<void> _transcribeAndReport(
    String path,
    ValueChanged<String> onResult,
  ) async {
    final apiCallStarted = DateTime.now();
    try {
      final transcript = await _transcribe(File(path));
      final apiMs = DateTime.now().difference(apiCallStarted).inMilliseconds;
      debugPrint(
        'VM_TIMING stt_completed ${DateTime.now().toIso8601String()} '
        'duration_ms=$apiMs',
      );
      onResult(transcript);
    } catch (e) {
      debugPrint('Groq transcription error: $e');
      onResult('');
    } finally {
      unawaited(File(path).delete().catchError((_) => File(path)));
    }
  }

  Future<String> _transcribe(File audioFile) async {
    final apiKey = dotenv.env['GROQ_API_KEY'];
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw StateError('GROQ_API_KEY is not configured.');
    }

    final request = http.MultipartRequest('POST', Uri.parse(_endpoint))
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['model'] = _model
      ..fields['language'] = 'en'
      ..fields['response_format'] = 'verbose_json'
      ..files.add(await http.MultipartFile.fromPath('file', audioFile.path));

    final streamed = await _client.send(request).timeout(_requestTimeout);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Groq STT failed: ${response.statusCode} ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final text = (body['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) return '';

    // Gate 2: Groq's own per-segment confidence. High no_speech_prob means
    // Whisper itself wasn't sure anyone was talking — that's the signature
    // of a hallucinated filler phrase, so drop it rather than act on it.
    final segments = body['segments'] as List<dynamic>?;
    if (segments != null && segments.isNotEmpty) {
      final probs = segments
          .map((s) => (s as Map<String, dynamic>)['no_speech_prob'])
          .whereType<num>()
          .map((p) => p.toDouble())
          .toList();
      if (probs.isNotEmpty) {
        final avgNoSpeechProb = probs.reduce((a, b) => a + b) / probs.length;
        if (avgNoSpeechProb > _noSpeechProbThreshold) {
          debugPrint(
            'Groq STT: discarding likely hallucination '
            '(no_speech_prob=$avgNoSpeechProb): "$text"',
          );
          return '';
        }
      }
    }

    return text;
  }

  /// Manual stop — e.g. the user tapped "Cancel". Discards whatever was
  /// captured rather than transcribing it; this is deliberately different
  /// from the silence-triggered path in [startListening], which always
  /// transcribes.
  Future<void> stopListening() async {
    if (!_isRecording) return;
    _isRecording = false;
    _silenceTimer?.cancel();
    _maxDurationTimer?.cancel();
    await _amplitudeSub?.cancel();
    final path = await _recorder.stop();
    if (path != null) {
      unawaited(File(path).delete().catchError((_) => File(path)));
    }
  }
}

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
enum _SessionState { idle, starting, listening, stopping }

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
    // logic (see ConversationSessionController._captureUtterance) runs.
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
