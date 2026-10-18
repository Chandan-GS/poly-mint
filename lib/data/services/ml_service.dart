import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/classification_result.dart';
import '../models/polymer_info.dart';
import 'image_preprocessor.dart';

/// On-device polymer classifier.
///
/// Improvements over the original inline implementation:
///  * Reads the input geometry from the model instead of hard-coding 224.
///  * Converts raw logits into calibrated probabilities with a numerically
///    stable soft-max, so "confidence" is meaningful.
///  * Returns a ranked top-K candidate list (enables manual correction).
///  * Optional multi-frame averaging to smooth out a single bad frame.
///  * Matches the exported YOLO classifier's contract: inputs scaled to
///    `[0, 1]`, and outputs that are already probabilities are not
///    soft-maxed a second time (which flattened every result to ~31%).
///  * Preprocesses frames exactly like training (see [ImagePreprocessor]).
class MlService {
  /// Identifies the bundled model in every recorded transaction.
  /// Model v2: YOLOv8s-cls, 7 classes; 76.3% top-1 on held-out
  /// resin-labelled test images (PolyMint_ML/kaggle/results/RESULTS.md).
  static const String modelVersion = 'polymer7-v2';
  static const String _modelAsset = 'assets/model/polymer7_v2_float32.tflite';
  static const String _labelsAsset = 'assets/model/labels.txt';

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
      _modelAsset,
      options: InterpreterOptions()..threads = 2,
    );

    final inputShape = _interpreter!.getInputTensor(0).shape;
    // Expect NHWC: [1, H, W, 3]. Fall back gracefully otherwise.
    if (inputShape.length == 4) {
      _inputHeight = inputShape[1];
      _inputWidth = inputShape[2];
    }
    if (_inputHeight != _inputWidth) {
      throw StateError('Expected a square model input, got '
          '${_inputHeight}x$_inputWidth.');
    }
    _outputClasses = _interpreter!.getOutputTensor(0).shape.last;

    final raw = await rootBundle.loadString(_labelsAsset);
    _labels = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (_outputClasses != 0 && _labels.length != _outputClasses) {
      throw StateError('labels.txt has ${_labels.length} entries but the model '
          'outputs $_outputClasses classes.');
    }
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
      final input = ImagePreprocessor.toTensor(bytes, _inputWidth);
      if (input == null) continue;

      final output = List.filled(1 * _outputClasses, 0.0)
          .reshape([1, _outputClasses]);
      _interpreter!.run(input, output);

      final scores = List<double>.from(output[0]).sublist(0, classes);
      final probs = _toProbabilities(scores);
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
      probabilities: {
        for (var i = 0; i < classes; i++) _labels[i]: mean[i],
      },
      modelVersion: modelVersion,
      inferenceTime: sw.elapsed,
    );
  }

  /// The exported model already ends in a soft-max; only apply one when the
  /// scores are raw logits.
  List<double> _toProbabilities(List<double> scores) {
    final sum = scores.fold<double>(0, (a, b) => a + b);
    final isDistribution =
        scores.every((v) => v >= 0 && v <= 1) && (sum - 1).abs() < 1e-3;
    return isDistribution ? scores : _softmax(scores);
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
