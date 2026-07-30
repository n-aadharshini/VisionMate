import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';

/// Owns the single Read Mode camera preview and optionally forwards a live
/// NV21 image stream to the offline OCR service.
class CameraPreviewBackground extends StatefulWidget {
  const CameraPreviewBackground({
    super.key,
    required this.onStatus,
    required this.torchOn,
    this.onFrame,
  });

  final ValueChanged<String> onStatus;
  final bool torchOn;
  final ValueChanged<CameraImage>? onFrame;

  @override
  State<CameraPreviewBackground> createState() => CameraPreviewBackgroundState();
}

class CameraPreviewBackgroundState extends State<CameraPreviewBackground>
    with WidgetsBindingObserver {
  CameraController? _controller;
  String _message = 'Preparing camera';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  Future<void> _open() async {
    final permission = await Permission.camera.request();
    if (!permission.isGranted) {
      if (mounted) {
        setState(() => _message = 'Camera permission is needed to read text');
      }
      widget.onStatus('Camera permission needed');
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _message = 'No camera is available');
        widget.onStatus('No camera available');
        return;
      }
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await controller.initialize();
      await controller.setFlashMode(widget.torchOn ? FlashMode.torch : FlashMode.off);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      await _startImageStream(controller);
      widget.onStatus('Detecting text');
    } catch (error, stackTrace) {
      debugPrint('[READ CAMERA ERROR] $error\n$stackTrace');
      if (mounted) setState(() => _message = 'Camera could not start');
      widget.onStatus('Camera unavailable');
    }
  }

  Future<void> _startImageStream(CameraController controller) async {
    if (widget.onFrame == null || controller.value.isStreamingImages) return;
    await controller.startImageStream((image) => widget.onFrame?.call(image));
  }

  InputImageRotation get imageRotation {
    final orientation = _controller?.description.sensorOrientation ?? 0;
    return InputImageRotationValue.fromRawValue(orientation) ??
        InputImageRotation.rotation0deg;
  }

  Future<Uint8List?> captureImage() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    try {
      final xfile = await controller.takePicture();
      return xfile.readAsBytes();
    } catch (e) {
      debugPrint('[CAMERA CAPTURE ERROR] $e');
      return null;
    }
  }

  @override
  void didUpdateWidget(covariant CameraPreviewBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.torchOn != widget.torchOn) {
      _controller?.setFlashMode(widget.torchOn ? FlashMode.torch : FlashMode.off);
    }
    final controller = _controller;
    if (oldWidget.onFrame == null && widget.onFrame != null && controller != null) {
      _startImageStream(controller);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _controller?.dispose();
      _controller = null;
    }
    if (state == AppLifecycleState.resumed && _controller == null) _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return ColoredBox(
        color: const Color(0xFF0F172A),
        child: Center(child: Text(_message, textAlign: TextAlign.center)),
      );
    }
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.previewSize!.height,
          height: controller.value.previewSize!.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}
