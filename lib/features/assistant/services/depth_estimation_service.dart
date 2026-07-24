import 'dart:math' as math;

import 'package:image/image.dart' as image;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Runs the bundled MiDaS model against one still image.
///
/// MiDaS predicts relative depth: it can compare which portions of one image
/// look nearer or farther away, but it cannot provide a physical distance in
/// metres. Callers must not use this as an obstacle-clearance measurement.
class DepthEstimationService {
  static const _modelAsset = 'assets/models/midas_v21_small.tflite';

  Interpreter? _interpreter;

  Future<RelativeDepthEstimate> estimate(image.Image source) async {
    final interpreter = await _loadInterpreter();
    final inputTensor = interpreter.getInputTensor(0);
    final inputShape = inputTensor.shape;
    if (inputTensor.type != TensorType.float32 ||
        inputShape.length != 4 ||
        inputShape[0] != 1 ||
        inputShape[3] != 3) {
      throw StateError('The depth model has an unsupported input tensor.');
    }

    final resized = image.copyResize(
      source,
      width: inputShape[2],
      height: inputShape[1],
    );
    final outputTensor = interpreter.getOutputTensor(0);
    final output = _createBuffer(outputTensor.shape);

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
              // MiDaS v2.1 expects RGB normalised to [-1, 1].
              return [
                pixel.r / 127.5 - 1.0,
                pixel.g / 127.5 - 1.0,
                pixel.b / 127.5 - 1.0,
              ];
            },
          ),
        ),
      ];

  dynamic _createBuffer(List<int> shape, [int depth = 0]) {
    if (depth == shape.length - 1) {
      return List<double>.filled(shape[depth], 0.0, growable: false);
    }
    return List<dynamic>.generate(
      shape[depth],
      (_) => _createBuffer(shape, depth + 1),
      growable: false,
    );
  }

  RelativeDepthEstimate _summarise(dynamic output) {
    final grid = _toDepthGrid(output);
    if (grid.isEmpty || grid.first.isEmpty) {
      throw const FormatException('The depth model returned an empty depth map.');
    }

    final means = <String, double>{
      'left': _meanArea(grid, 0, 1, 0, 1 / 3),
      'centre': _meanArea(grid, 0, 1, 1 / 3, 2 / 3),
      'right': _meanArea(grid, 0, 1, 2 / 3, 1),
    };
    final nearest = means.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final maximumDepth = means.values.reduce((a, b) => a > b ? a : b);
    final minimumDepth = means.values.reduce((a, b) => a < b ? a : b);
    final span = (maximumDepth - minimumDepth).abs();

    return RelativeDepthEstimate(
      nearestArea: nearest.key,
      hasMeaningfulSeparation: span > 0.03,
    );
  }

  List<List<double>> _toDepthGrid(dynamic output) {
    var value = output;
    while (value is List && value.length == 1) {
      value = value.first;
    }
    if (value is! List || value.isEmpty || value.first is! List) return const [];

    return value.map<List<double>>((row) {
      if (row is! List) return const [];
      return row.map<double>((cell) {
        if (cell is num) return cell.toDouble();
        if (cell is List && cell.isNotEmpty && cell.first is num) {
          return (cell.first as num).toDouble();
        }
        return 0;
      }).toList(growable: false);
    }).toList(growable: false);
  }

  double _meanArea(
    List<List<double>> grid,
    double topFraction,
    double bottomFraction,
    double leftFraction,
    double rightFraction,
  ) {
    final height = grid.length;
    final width = grid.first.length;
    final top = (height * topFraction).floor();
    final bottom = math.max(top + 1, (height * bottomFraction).ceil());
    final left = (width * leftFraction).floor();
    final right = math.max(left + 1, (width * rightFraction).ceil());
    var sum = 0.0;
    var count = 0;

    for (var y = top; y < math.min(bottom, height); y++) {
      for (var x = left; x < math.min(right, width); x++) {
        sum += grid[y][x];
        count++;
      }
    }
    return count == 0 ? 0 : sum / count;
  }
}

class RelativeDepthEstimate {
  const RelativeDepthEstimate({
    required this.nearestArea,
    required this.hasMeaningfulSeparation,
  });

  /// The horizontal part of this single photo with the highest relative depth.
  final String nearestArea;

  /// Whether the model found a clear enough relative-depth contrast to report.
  final bool hasMeaningfulSeparation;
}
