import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/services/app_earcons.dart';
import '../../core/services/app_haptics.dart';
import '../../core/services/ocr_memory_service.dart';
import '../../core/services/vision_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_ui.dart';
import '../../core/widgets/persistent_voice_bar.dart';
import '../assistant/services/conversation_controller.dart';
import '../camera/widgets/camera_preview_background.dart';

enum SceneState { idle, capturing, processing, result }

class SceneModeScreen extends StatefulWidget {
  const SceneModeScreen({super.key});

  @override
  State<SceneModeScreen> createState() => _SceneModeScreenState();
}

class _SceneModeScreenState extends State<SceneModeScreen> {
  final _cameraKey = GlobalKey<CameraPreviewBackgroundState>();
  final _visionService = GroqVisionService();
  final _ocrMemory = OcrMemoryService();
  SceneState _sceneState = SceneState.idle;
  String? _lastDescription;
  DateTime? _lastCaptureAt;
  bool _flash = false;

  static const _rateLimitInterval = Duration(seconds: 6);

  bool get _canCapture {
    if (_lastCaptureAt == null) return true;
    return DateTime.now().difference(_lastCaptureAt!) >= _rateLimitInterval;
  }

  Future<void> _capture() async {
    if (_sceneState == SceneState.processing || !_canCapture) return;

    final cameraState = _cameraKey.currentState;
    if (cameraState == null) return;

    AppHaptics.medium();
    AppEarcons.shutter();
    _flashScreen();

    _lastCaptureAt = DateTime.now();
    setState(() => _sceneState = SceneState.capturing);

    try {
      final image = await _captureImage();
      if (!mounted || image == null) return;

      setState(() => _sceneState = SceneState.processing);

      final description = await _visionService.describeImage(image);
      if (!mounted) return;

      _ocrMemory.saveScene(description);
      setState(() {
        _lastDescription = description;
        _sceneState = SceneState.result;
      });

      final c = ConversationControllerScope.of(context);
      c.speak(description);
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastDescription = 'I could not get a look at that, try again.';
          _sceneState = SceneState.result;
        });
      }
    }
  }

  Future<Uint8List?> _captureImage() async {
    final cameraState = _cameraKey.currentState;
    if (cameraState == null) return null;
    return cameraState.captureImage();
  }

  void _flashScreen() {
    if (!mounted) return;
    setState(() {});
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _visionService.dispose();
    _ocrMemory.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreviewBackground(
            key: _cameraKey,
            onStatus: (_) {},
            torchOn: _flash,
          ),
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
                          'Scene Mode',
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
                  if (_sceneState == SceneState.processing)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 60),
                      child: Column(
                        children: [
                          SizedBox(
                            width: 80,
                            height: 80,
                            child: reduce
                                ? const CircularProgressIndicator(color: AppColors.cyan)
                                : Container(
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: SweepGradient(
                                        colors: [
                                          AppColors.blue,
                                          AppColors.cyan,
                                          AppColors.blue,
                                          AppColors.deep,
                                          AppColors.blue,
                                        ],
                                      ),
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.auto_awesome_rounded,
                                        color: Colors.white,
                                        size: 30,
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Looking...',
                            style: TextStyle(
                              color: AppColors.cyan,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_sceneState == SceneState.result &&
                      _lastDescription != null)
                    AppCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.success,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Scene',
                                  style: TextStyle(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'Scene',
                                  style: TextStyle(
                                    color: AppColors.muted.withValues(alpha: 0.7),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _lastDescription!,
                              style: const TextStyle(
                                fontSize: 18,
                                color: AppColors.text,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Semantics(
                                  label: 'Describe again',
                                  button: true,
                                  child: Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _capture,
                                      icon: const Icon(Icons.refresh_rounded),
                                      label: const Text('Describe again'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_sceneState == SceneState.idle ||
                      _sceneState == SceneState.capturing)
                    Column(
                      children: [
                        Semantics(
                          label: 'Capture scene to describe',
                          hint: 'Takes a photo and describes what is there',
                          button: true,
                          child: GestureDetector(
                            onTap: !_canCapture ? null : _capture,
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                border: Border.all(
                                  color: AppColors.cyan,
                                  width: 4,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.cyan.withValues(alpha: 0.3),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                color: Colors.black87,
                                size: 36,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          !_canCapture
                              ? 'Wait...'
                              : 'Tap to describe scene',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: PersistentVoiceBar(),
          ),
        ],
      ),
    );
  }
}
