import 'dart:math' as math;

import 'package:image/image.dart' as image;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Performs semantic segmentation for a single still image with DeepLab v3.
///
/// The returned classes describe broad image regions. They are informative
/// only and must not be treated as an obstacle detector or navigation command.
class SemanticSegmentationService {
  static const _modelAsset = 'assets/models/deeplabv3.tflite';

  Interpreter? _interpreter;

  Future<SemanticSegmentationResult> segment(image.Image source) async {
    final interpreter = await _loadInterpreter();
    final inputTensor = interpreter.getInputTensor(0);
    final shape = inputTensor.shape;
    if (inputTensor.type != TensorType.float32 ||
        shape.length != 4 ||
        shape[0] != 1 ||
        shape[3] != 3) {
      throw StateError('The segmentation model has an unsupported input.');
    }

    final resized = image.copyResize(
      source,
      width: shape[2],
      height: shape[1],
    );
    final outputTensor = interpreter.getOutputTensor(0);
    final output = _createBuffer(outputTensor.shape, outputTensor.type);
    interpreter.run(_createInput(resized), output);

    return _summarise(output);
  }

  Future<Interpreter> _loadInterpreter() async {
    return _interpreter ??= await Interpreter.fromAsset(_modelAsset);
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }

  List<List<List<List<double>>>> _createInput(image.Image source) => [
        List.generate(
          source.height,
          (y) => List.generate(
            source.width,
            (x) {
              final pixel = source.getPixel(x, y);
              return [
                pixel.r / 127.5 - 1.0,
                pixel.g / 127.5 - 1.0,
                pixel.b / 127.5 - 1.0,
              ];
            },
          ),
        ),
      ];

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

  SemanticSegmentationResult _summarise(dynamic output) {
    final rows = _stripBatch(output);
    if (rows.isEmpty || rows.first is! List) {
      throw const FormatException('The segmentation model returned no mask.');
    }

    final pixelCounts = <int, int>{};
    var pixelCount = 0;
    for (final row in rows) {
      if (row is! List) continue;
      for (final value in row) {
        final classId = _classForPixel(value);
        if (classId == null) continue;
        pixelCounts.update(classId, (count) => count + 1, ifAbsent: () => 1);
        pixelCount++;
      }
    }
    if (pixelCount == 0) {
      throw const FormatException('The segmentation mask contained no pixels.');
    }

    final regions = pixelCounts.entries
        .where((entry) => entry.key != 0)
        .map(
          (entry) => SegmentedRegion(
            label: _pascalVocLabel(entry.key),
            coverage: entry.value / pixelCount,
          ),
        )
        .where((region) => region.coverage >= .01)
        .toList()
      ..sort((a, b) => b.coverage.compareTo(a.coverage));

    return SemanticSegmentationResult(
      regions: regions.take(math.min(3, regions.length)).toList(growable: false),
    );
  }

  List<dynamic> _stripBatch(dynamic output) {
    var value = output;
    while (value is List && value.length == 1) {
      value = value.first;
    }
    return value is List ? value : const [];
  }

  int? _classForPixel(dynamic value) {
    if (value is num) return value.round();
    if (value is! List || value.isEmpty) return null;
    if (value.length == 1 && value.first is num) {
      return (value.first as num).round();
    }

    var classId = 0;
    var bestScore = double.negativeInfinity;
    for (var index = 0; index < value.length; index++) {
      final score = value[index];
      if (score is num && score > bestScore) {
        bestScore = score.toDouble();
        classId = index;
      }
    }
    return classId;
  }

  String _pascalVocLabel(int classId) {
    const labels = <String>[
      'background', 'aeroplane', 'bicycle', 'bird', 'boat', 'bottle', 'bus',
      'car', 'cat', 'chair', 'cow', 'dining table', 'dog', 'horse',
      'motorcycle', 'person', 'potted plant', 'sheep', 'sofa', 'train', 'TV',
    ];
    return classId >= 0 && classId < labels.length
        ? labels[classId]
        : 'unknown region';
  }
}

class SemanticSegmentationResult {
  const SemanticSegmentationResult({required this.regions});

  final List<SegmentedRegion> regions;
}

class SegmentedRegion {
  const SegmentedRegion({required this.label, required this.coverage});

  final String label;
  final double coverage;
}
