import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as image;
import 'package:tflite_flutter/tflite_flutter.dart';

/// A small, on-demand wrapper around the bundled EfficientDet Lite model.
///
/// This service intentionally accepts a single still image. It does not open a
/// camera stream or keep the camera active, which keeps the navigation flow
/// battery-conscious.
class ObjectDetectionService {
  static const _modelAsset = 'assets/models/efficientdet_lite0.tflite';

  Interpreter? _interpreter;

  Future<List<DetectedObject>> detectFromFile(
    String imagePath, {
    double minimumConfidence = .45,
    int maximumResults = 5,
  }) async {
    final bytes = await File(imagePath).readAsBytes();
    final source = image.decodeImage(bytes);
    if (source == null) {
      throw const FormatException('The captured photo could not be decoded.');
    }

    return detectImage(
      source,
      minimumConfidence: minimumConfidence,
      maximumResults: maximumResults,
    );
  }

  Future<List<DetectedObject>> detectImage(
    image.Image source, {
    double minimumConfidence = .45,
    int maximumResults = 5,
  }) async {
    final interpreter = await _loadInterpreter();
    final inputTensor = interpreter.getInputTensor(0);
    final shape = inputTensor.shape;
    if (shape.length != 4 || shape[0] != 1 || shape[3] != 3) {
      throw StateError('The object-detection model has an unsupported input.');
    }

    final height = shape[1];
    final width = shape[2];
    final resized = image.copyResize(source, width: width, height: height);
    final input = _createInput(resized, inputTensor.type);

    final outputs = <int, Object>{
      for (var index = 0; index < interpreter.getOutputTensors().length; index++)
        index: _createBuffer(
          interpreter.getOutputTensor(index).shape,
          interpreter.getOutputTensor(index).type,
        ),
    };

    interpreter.runForMultipleInputs([input], outputs);
    return _parseDetections(
      outputs,
      minimumConfidence: minimumConfidence,
      maximumResults: maximumResults,
    );
  }

  Future<Interpreter> _loadInterpreter() async {
    return _interpreter ??= await Interpreter.fromAsset(_modelAsset);
  }

  /// Releases the native TensorFlow Lite interpreter when its owner is done.
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }

  List<List<List<List<num>>>> _createInput(
    image.Image source,
    TensorType type,
  ) {
    final normalise = type == TensorType.float32;
    return [
      List.generate(
        source.height,
        (y) => List.generate(
          source.width,
          (x) {
            final pixel = source.getPixel(x, y);
            num value(int channel) {
              final raw = switch (channel) {
                0 => pixel.r,
                1 => pixel.g,
                _ => pixel.b,
              };
              return normalise ? raw / 255.0 : raw;
            }

            return [value(0), value(1), value(2)];
          },
        ),
      ),
    ];
  }

  dynamic _createBuffer(List<int> shape, TensorType type, [int depth = 0]) {
    if (depth == shape.length - 1) {
      final fill = type == TensorType.float32 ? 0.0 : 0;
      return List<dynamic>.filled(shape[depth], fill, growable: false);
    }
    return List<dynamic>.generate(
      shape[depth],
      (_) => _createBuffer(shape, type, depth + 1),
      growable: false,
    );
  }

  List<DetectedObject> _parseDetections(
    Map<int, Object> outputs, {
    required double minimumConfidence,
    required int maximumResults,
  }) {
    // EfficientDet Lite TFLite exports four tensors in this order:
    // boxes [1, N, 4], class IDs [1, N], scores [1, N], and count [1].
    final rawBoxes = _asList(outputs[0]);
    final rawClasses = _flatten(outputs[1]);
    final rawScores = _flatten(outputs[2]);
    final countValues = _flatten(outputs[3]);
    final count = countValues.isEmpty
        ? rawBoxes.length
        : countValues.first.round().clamp(0, rawBoxes.length);
    final result = <DetectedObject>[];

    for (var index = 0;
        index < count && index < rawClasses.length && index < rawScores.length;
        index++) {
      final score = rawScores[index];
      if (score < minimumConfidence) continue;

      final coordinates = _flatten(rawBoxes[index]);
      if (coordinates.length < 4) continue;
      final top = coordinates[0].clamp(0.0, 1.0).toDouble();
      final left = coordinates[1].clamp(0.0, 1.0).toDouble();
      final bottom = coordinates[2].clamp(0.0, 1.0).toDouble();
      final right = coordinates[3].clamp(0.0, 1.0).toDouble();
      if (bottom <= top || right <= left) continue;

      final classId = rawClasses[index].round();
      result.add(
        DetectedObject(
          label: _cocoLabel(classId),
          confidence: score,
          top: top,
          left: left,
          bottom: bottom,
          right: right,
        ),
      );
    }

    result.sort((a, b) => b.confidence.compareTo(a.confidence));
    return result.take(math.max(0, maximumResults)).toList(growable: false);
  }

  List<dynamic> _asList(dynamic value) => value is List ? value : const [];

  List<double> _flatten(dynamic value) {
    if (value is num) return [value.toDouble()];
    if (value is! List) return const [];
    return value.expand(_flatten).toList(growable: false);
  }

  String _cocoLabel(int classId) {
    const labels = <String>[
      'person', 'bicycle', 'car', 'motorcycle', 'airplane', 'bus', 'train',
      'truck', 'boat', 'traffic light', 'fire hydrant', 'stop sign',
      'parking meter', 'bench', 'bird', 'cat', 'dog', 'horse', 'sheep', 'cow',
      'elephant', 'bear', 'zebra', 'giraffe', 'backpack', 'umbrella', 'handbag',
      'tie', 'suitcase', 'frisbee', 'skis', 'snowboard', 'sports ball', 'kite',
      'baseball bat', 'baseball glove', 'skateboard', 'surfboard', 'tennis racket',
      'bottle', 'wine glass', 'cup', 'fork', 'knife', 'spoon', 'bowl', 'banana',
      'apple', 'sandwich', 'orange', 'broccoli', 'carrot', 'hot dog', 'pizza',
      'donut', 'cake', 'chair', 'couch', 'potted plant', 'bed', 'dining table',
      'toilet', 'TV', 'laptop', 'mouse', 'remote', 'keyboard', 'cell phone',
      'microwave', 'oven', 'toaster', 'sink', 'refrigerator', 'book', 'clock',
      'vase', 'scissors', 'teddy bear', 'hair drier', 'toothbrush',
    ];
    return classId >= 0 && classId < labels.length
        ? labels[classId]
        : 'object $classId';
  }
}

class DetectedObject {
  const DetectedObject({
    required this.label,
    required this.confidence,
    required this.top,
    required this.left,
    required this.bottom,
    required this.right,
  });

  final String label;
  final double confidence;
  final double top;
  final double left;
  final double bottom;
  final double right;
}
