import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/classification_result.dart';
import '../models/polymer_info.dart';

/// On-device polymer classifier.
///
/// Improvements over the original inline implementation:
///  * Reads the input geometry from the model instead of hard-coding 224.
///  * Converts raw logits into calibrated probabilities with a numerically
///    stable soft-max, so "confidence" is meaningful.
///  * Returns a ranked top-K candidate list (enables manual correction).
///  * Optional multi-frame averaging to smooth out a single bad frame.
class MlService {
  Interpreter? _interpreter;
  List<String> _labels = [];
  int _inputWidth = 224;
  int _inputHeight = 224;
  int _outputClasses = 0;

  bool get isReady => _interpreter != null && _labels.isNotEmpty;
  List<String> get labels => List.unmodifiable(_labels);

  Future<void> load() async {
    if (isReady) return;
    _interpreter = await Interpreter.fromAsset(
      'assets/best_float32.tflite',
      options: InterpreterOptions()..threads = 2,
    );

    final inputShape = _interpreter!.getInputTensor(0).shape;
    // Expect NHWC: [1, H, W, 3]. Fall back gracefully otherwise.
    if (inputShape.length == 4) {
      _inputHeight = inputShape[1];
      _inputWidth = inputShape[2];
    }
    _outputClasses = _interpreter!.getOutputTensor(0).shape.last;

    final raw = await rootBundle.loadString('assets/labels.txt');
    _labels = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  /// Classify one or more frames of the same object. Passing several frames
  /// (high-accuracy mode) averages their probability distributions.
  Future<ClassificationResult> classify(
    List<Uint8List> frames, {
    int topK = 3,
  }) async {
    if (!isReady) {
      throw StateError('MlService.load() must complete before classify().');
    }
    if (frames.isEmpty) {
      throw ArgumentError('At least one frame is required.');
    }

    final sw = Stopwatch()..start();

    // Number of usable classes = min(model outputs, provided labels).
    final classes =
        math.min(_labels.length, _outputClasses == 0 ? _labels.length : _outputClasses);

    // Accumulate probabilities across frames.
    final accumulated = List<double>.filled(classes, 0.0);
    var usedFrames = 0;

    for (final bytes in frames) {
      final input = _preprocess(bytes);
      if (input == null) continue;

      final output = List.filled(1 * _outputClasses, 0.0)
          .reshape([1, _outputClasses]);
      _interpreter!.run(input, output);

      final logits = List<double>.from(output[0]).sublist(0, classes);
      final probs = _softmax(logits);
      for (var i = 0; i < classes; i++) {
        accumulated[i] += probs[i];
      }
      usedFrames++;
    }

    if (usedFrames == 0) {
      throw Exception('Could not decode any of the captured frames.');
    }

    final mean = accumulated.map((v) => v / usedFrames).toList();

    // Rank candidates.
    final ranked = List.generate(
      classes,
      (i) => MapEntry(i, mean[i]),
    )..sort((a, b) => b.value.compareTo(a.value));

    final predictions = ranked
        .take(topK)
        .map((e) => PolymerPrediction(
              polymer: PolymerCatalog.lookup(_labels[e.key]),
              confidence: e.value,
            ))
        .toList();

    sw.stop();
    return ClassificationResult(
      predictions: predictions,
      inferenceTime: sw.elapsed,
    );
  }

  /// Decode → center-crop square → resize → normalize to [-1, 1].
  /// Returns a `[1, H, W, 3]` tensor, or null if the frame can't be decoded.
  List<List<List<List<double>>>>? _preprocess(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    final cropSize =
        decoded.width < decoded.height ? decoded.width : decoded.height;
    final offsetX = (decoded.width - cropSize) ~/ 2;
    final offsetY = (decoded.height - cropSize) ~/ 2;

    final cropped = img.copyCrop(
      decoded,
      x: offsetX,
      y: offsetY,
      width: cropSize,
      height: cropSize,
    );
    final resized =
        img.copyResize(cropped, width: _inputWidth, height: _inputHeight);

    return [
      List.generate(_inputHeight, (y) {
        return List.generate(_inputWidth, (x) {
          final p = resized.getPixel(x, y);
          return [
            (p.r - 127.5) / 127.5,
            (p.g - 127.5) / 127.5,
            (p.b - 127.5) / 127.5,
          ];
        });
      }),
    ];
  }

  /// Numerically stable soft-max.
  List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce(math.max);
    final exps = logits.map((l) => math.exp(l - maxLogit)).toList();
    final sum = exps.fold<double>(0, (a, b) => a + b);
    if (sum == 0) {
      return List.filled(logits.length, 1 / logits.length);
    }
    return exps.map((e) => e / sum).toList();
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}
