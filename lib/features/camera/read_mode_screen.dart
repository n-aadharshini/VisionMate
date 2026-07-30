import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/services/app_haptics.dart';
import '../../core/services/ocr_memory_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_ui.dart';
import '../../core/widgets/persistent_voice_bar.dart';
import '../assistant/services/conversation_controller.dart';
import 'services/text_recognition_service.dart';
import 'widgets/camera_preview_background.dart';
import 'widgets/scan_brackets.dart';
import 'widgets/text_result_panel.dart';
import 'widgets/voice_status_strip.dart';

enum ReadModeState { idle, detecting, found, reading, speaking, completed }

class ReadModeScreen extends StatefulWidget {
  const ReadModeScreen({super.key});

  @override
  State<ReadModeScreen> createState() => _ReadModeScreenState();
}

class _ReadModeScreenState extends State<ReadModeScreen> {
  static const _ocrInterval = Duration(milliseconds: 750);

  final _cameraKey = GlobalKey<CameraPreviewBackgroundState>();
  final _textRecognitionService = TextRecognitionService();
  ReadModeState _state = ReadModeState.idle;
  DateTime? _lastOcrStart;
  bool _ocrInProgress = false;
  bool _expanded = false;
  bool _flash = false;
  String _recognizedText = '';
  String _normalizedText = '';
  String? _notice;
  DateTime? _detectedAt;
  ConversationController? _registeredConversation;
  double _zoomLevel = 1.0;
  bool _readingPaused = false;
  final OcrMemoryService _ocrMemory = OcrMemoryService();

  BracketState get _bracketState => switch (_state) {
    ReadModeState.idle => BracketState.entering,
    ReadModeState.detecting => BracketState.scanning,
    ReadModeState.found => BracketState.detected,
    ReadModeState.reading || ReadModeState.speaking => BracketState.detected,
    ReadModeState.completed => BracketState.detected,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final conversation = ConversationControllerScope.of(context);
    if (identical(_registeredConversation, conversation)) return;
    _registeredConversation
      ?..setFeatureVoiceCommandHandler(null)
      ..removeListener(_onConversationChanged);
    _registeredConversation = conversation;
    conversation
      ..setFeatureVoiceCommandHandler(_handleReadVoiceCommand)
      ..addListener(_onConversationChanged);
  }

  void _onConversationChanged() {
    if (!mounted || _state != ReadModeState.reading) return;
    final state = _registeredConversation?.state;
    if (state == ConversationState.speaking) {
      setState(() => _state = ReadModeState.speaking);
    } else if (state == ConversationState.idle) {
      setState(() => _state = ReadModeState.completed);
    }
  }

  void _processFrame(CameraImage frame) {
    if (_ocrInProgress ||
        _state == ReadModeState.reading ||
        _state == ReadModeState.speaking) {
      return;
    }
    final now = DateTime.now();
    if (_lastOcrStart != null && now.difference(_lastOcrStart!) < _ocrInterval) {
      return;
    }
    _lastOcrStart = now;
    unawaited(_recognizeFrame(frame));
  }

  Future<void> _recognizeFrame(CameraImage frame) async {
    _ocrInProgress = true;
    if (mounted && _recognizedText.isEmpty) {
      setState(() => _state = ReadModeState.detecting);
    }
    try {
      final rotation = _cameraKey.currentState?.imageRotation;
      if (rotation == null) return;
      final text = await _textRecognitionService.recognizeCameraFrame(
        frame,
        rotation: rotation,
      );
      if (!mounted || text == null || text.isEmpty) return;

      final normalized = _normalize(text);
      if (!_isMeaningfullyNew(normalized)) return;
      setState(() {
        _recognizedText = text;
        _normalizedText = normalized;
        _notice = null;
        _state = ReadModeState.found;
        _detectedAt = DateTime.now();
      });
      _ocrMemory.saveOcr(text);
      AppHaptics.tick();
      debugPrint('[READ OCR] updated text: $text');
    } catch (error, stackTrace) {
      debugPrint('[READ OCR ERROR] $error\n$stackTrace');
      if (mounted && _recognizedText.isEmpty) {
        setState(() {
          _notice = 'Text scanning is temporarily unavailable.';
          _state = ReadModeState.idle;
        });
      }
    } finally {
      _ocrInProgress = false;
    }
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool _isMeaningfullyNew(String candidate) {
    if (_normalizedText.isEmpty) return true;
    if (candidate == _normalizedText) return false;
    final previousWords = _normalizedText.split(' ').toSet();
    final candidateWords = candidate.split(' ').toSet();
    final sharedWords = previousWords.intersection(candidateWords).length;
    final totalWords = previousWords.union(candidateWords).length;
    return totalWords == 0 || sharedWords / totalWords < .82;
  }

  Future<FeatureVoiceCommandResult?> _handleReadVoiceCommand(
    String transcript,
  ) async {
    final command = _normalize(transcript);

    if (command == 'clear' || command == 'clear this' || command == 'clear that') {
      setState(() {
        _recognizedText = '';
        _normalizedText = '';
        _notice = null;
        _state = ReadModeState.idle;
        _detectedAt = null;
      });
      _ocrMemory.clearOcr();
      return const FeatureVoiceCommandResult.handled(
        reply: 'Cleared.',
        shouldSpeak: true,
      );
    }

    final isStop = command == 'stop' || command == 'stop reading';
    if (isStop) {
      if (mounted && _recognizedText.isNotEmpty) {
        setState(() => _state = ReadModeState.found);
      }
      return const FeatureVoiceCommandResult.handled(shouldSpeak: false);
    }

    final wantsRead = command == 'read' ||
        command == 'start reading' ||
        command == 'read again' ||
        command == 'read this' ||
        command == 'read the sign' ||
        command == 'what does it say' ||
        command == 'what does that say' ||
        command == 'repeat that' ||
        command == 'say it again';
    if (!wantsRead) return null;
    if (_recognizedText.isEmpty) {
      return const FeatureVoiceCommandResult.handled(
        reply: 'I have not detected any text yet. Please point the camera at text.',
      );
    }
    if (mounted) {
      setState(() => _state = ReadModeState.reading);
    }
    return FeatureVoiceCommandResult.handled(reply: _recognizedText);
  }

  Future<void> _readRecognizedText() async {
    if (_recognizedText.isEmpty || _state == ReadModeState.speaking) return;
    setState(() => _state = ReadModeState.reading);
    await Future.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    setState(() => _state = ReadModeState.speaking);
    try {
      await ConversationControllerScope.of(context).speak(_recognizedText);
    } catch (error, stackTrace) {
      debugPrint('[READ TTS ERROR] $error\n$stackTrace');
    } finally {
      if (mounted) setState(() => _state = ReadModeState.completed);
    }
  }

  void _stopReading() {
    final c = _registeredConversation;
    if (c != null && (_state == ReadModeState.reading || _state == ReadModeState.speaking)) {
      c.interruptSpeaking();
      setState(() => _state = ReadModeState.found);
      AppHaptics.medium();
    }
  }

  void _togglePause() {
    _readingPaused = !_readingPaused;
    AppHaptics.light();
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (!mounted) return;
    final cameraState = _cameraKey.currentState;
    if (cameraState == null) return;
    _zoomLevel = (_zoomLevel * details.scale).clamp(1.0, 4.0);
  }

  void _onCameraStatus(String status) {
    if (!mounted || status == 'Detecting text') return;
    setState(() => _notice = status);
  }

  @override
  void dispose() {
    _registeredConversation
      ?..setFeatureVoiceCommandHandler(null)
      ..removeListener(_onConversationChanged);
    _textRecognitionService.dispose();
    super.dispose();
  }

  String get _statusLabel {
    if (_registeredConversation?.isListening == true) return 'Listening...';
    if (_registeredConversation?.isThinking == true) return 'Processing...';
    if (_registeredConversation?.isSpeaking == true) return 'Speaking...';
    return switch (_state) {
      ReadModeState.idle => 'Ready',
      ReadModeState.detecting => 'Detecting text',
      ReadModeState.found => 'Text is ready. Say Read.',
      ReadModeState.reading => 'Reading',
      ReadModeState.speaking => 'Speaking',
      ReadModeState.completed => 'Completed',
    };
  }

  @override
  Widget build(BuildContext context) {
    final conversation = _registeredConversation;
    final isSpeaking = conversation?.isSpeaking == true ||
        _state == ReadModeState.speaking;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onScaleUpdate: _onScaleUpdate,
        onSecondaryTap: _togglePause,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraPreviewBackground(
              key: _cameraKey,
              onStatus: _onCameraStatus,
              torchOn: _flash,
              onFrame: _processFrame,
            ),
            ScanBrackets(bracketState: _bracketState),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const AppBackButton(),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Read Mode',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _flash = !_flash),
                          icon: Icon(
                            _flash
                                ? Icons.flash_on_rounded
                                : Icons.flash_off_rounded,
                          ),
                          tooltip: _flash ? 'Turn flash off' : 'Turn flash on',
                        ),
                      ],
                    ),
                    const Spacer(),
                    TextResultPanel(
                      text: _recognizedText,
                      notice: _notice,
                      timestamp: _detectedAt,
                      expanded: _expanded,
                      onToggleExpanded: () =>
                          setState(() => _expanded = !_expanded),
                    ),
                    const SizedBox(height: 12),
                    if (isSpeaking)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.danger,
                            ),
                            onPressed: _stopReading,
                            icon: const Icon(Icons.stop_rounded),
                            label: const Text(
                              'Stop reading',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      )
                    else
                      Row(
                        children: [
                          Semantics(
                            label: 'Read the detected text',
                            button: true,
                            child: Expanded(
                              child: FilledButton.icon(
                                onPressed: _recognizedText.isEmpty
                                    ? null
                                    : _readRecognizedText,
                                icon: const Icon(Icons.volume_up_rounded),
                                label: const Text('Read text'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    VoiceStatusStrip(
                      text: _statusLabel,
                      onTap: () {
                        if (_recognizedText.isNotEmpty) {
                          _readRecognizedText();
                        }
                      },
                    ),
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: PersistentVoiceBar(
                rightAction: _recognizedText.isNotEmpty
                    ? Semantics(
                        label: 'Stop reading',
                        button: true,
                        child: IconButton(
                          icon: const Icon(Icons.stop_circle_outlined),
                          color: AppColors.danger,
                          onPressed: _stopReading,
                          tooltip: 'Stop reading',
                        ),
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
