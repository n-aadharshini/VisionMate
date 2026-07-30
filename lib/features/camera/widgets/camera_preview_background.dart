import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraPreviewBackground extends StatefulWidget {
  const CameraPreviewBackground({super.key, required this.onStatus, required this.torchOn});
  final ValueChanged<String> onStatus;
  final bool torchOn;
  @override
  State<CameraPreviewBackground> createState() => _CameraPreviewBackgroundState();
}

class _CameraPreviewBackgroundState extends State<CameraPreviewBackground>
    with WidgetsBindingObserver {
  CameraController? _controller;
  String _message = 'Preparing camera';

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); _open(); }

  Future<void> _open() async {
    final permission = await Permission.camera.request();
    if (!permission.isGranted) { if (mounted) setState(() => _message = 'Camera permission is needed to read text'); return; }
    final cameras = await availableCameras();
    if (cameras.isEmpty) { if (mounted) setState(() => _message = 'No camera is available'); return; }
    final controller = CameraController(cameras.first, ResolutionPreset.medium, enableAudio: false);
    try { await controller.initialize(); await controller.setFlashMode(widget.torchOn ? FlashMode.torch : FlashMode.off); if (!mounted) { await controller.dispose(); return; } setState(() => _controller = controller); widget.onStatus('Ready'); } catch (_) { await controller.dispose(); if (mounted) setState(() => _message = 'Camera could not start'); }
  }

  @override
  void didUpdateWidget(covariant CameraPreviewBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.torchOn != widget.torchOn) _controller?.setFlashMode(widget.torchOn ? FlashMode.torch : FlashMode.off);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) { _controller?.dispose(); _controller = null; }
    if (state == AppLifecycleState.resumed && _controller == null) _open();
  }

  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); _controller?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return ColoredBox(color: const Color(0xFF0F172A), child: Center(child: Text(_message, textAlign: TextAlign.center)));
    return SizedBox.expand(child: FittedBox(fit: BoxFit.cover, child: SizedBox(width: controller.value.previewSize!.height, height: controller.value.previewSize!.width, child: CameraPreview(controller))));
  }
}
