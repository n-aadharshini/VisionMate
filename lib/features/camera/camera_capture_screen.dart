import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_ui.dart';

/// Displays a camera preview and returns the captured image path to its caller.
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _controller;
  String? _error;
  var _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _initialiseCamera();
  }

  Future<void> _initialiseCamera() async {
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        throw StateError(
          status.isPermanentlyDenied
              ? 'Camera permission is permanently denied. Enable it in Android Settings, then try again.'
              : 'Camera permission was not granted.',
        );
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera is available on this device.');
      }
      final backCamera = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      final selectedCamera =
          backCamera.isNotEmpty ? backCamera.first : cameras.first;
      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (error, stackTrace) {
      debugPrint('Camera initialisation failed: $error\n$stackTrace');
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _capturePhoto() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    setState(() => _isCapturing = true);
    try {
      final photo = await controller.takePicture();
      debugPrint('Camera photo captured: ${photo.path}');
      if (mounted) Navigator.of(context).pop(photo.path);
    } catch (error, stackTrace) {
      debugPrint('Camera capture failed: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _error = 'Could not capture the photo. Please try again.';
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return AppPage(
      padded: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 20, 12),
            child: Row(
              children: [
                const AppBackButton(),
                const SizedBox(width: 6),
                const Text(
                  'Camera check-in',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: _error != null
                  ? _CameraError(message: _error!)
                  : controller == null || !controller.value.isInitialized
                      ? const CircularProgressIndicator(color: AppColors.cyan)
                      : AspectRatio(
                          aspectRatio: controller.value.aspectRatio,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: CameraPreview(controller),
                          ),
                        ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: PrimaryButton(
              label: _isCapturing ? 'Capturing...' : 'Capture photo',
              icon: Icons.camera_alt_rounded,
              onPressed: _isCapturing ? () {} : _capturePhoto,
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(28),
        child: AppCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.camera_alt_outlined,
                  color: AppColors.cyan,
                  size: 42,
                ),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
}
