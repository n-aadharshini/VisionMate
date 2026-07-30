import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Offline ML Kit OCR for the Read Mode camera stream.
///
/// Android's ML Kit bridge accepts NV21 camera frames. The camera widget owns
/// the stream and passes each throttled frame here for recognition.
class TextRecognitionService {
  TextRecognitionService()
    : _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  Future<String?> recognizeCameraFrame(
    CameraImage image, {
    required InputImageRotation rotation,
  }) async {
    if (image.format.group != ImageFormatGroup.nv21 || image.planes.isEmpty) {
      return null;
    }

    final plane = image.planes.first;
    final inputImage = InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: ui.Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
    final result = await _recognizer.processImage(inputImage);
    return result.text.trim();
  }

  Future<void> dispose() => _recognizer.close();
}
