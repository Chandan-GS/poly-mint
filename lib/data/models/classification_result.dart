import 'package:equatable/equatable.dart';
import 'polymer_info.dart';

/// A single candidate produced by the ML model.
class PolymerPrediction extends Equatable {
  final PolymerInfo polymer;

  /// Calibrated probability in 0..1 (after softmax).
  final double confidence;

  const PolymerPrediction({required this.polymer, required this.confidence});

  @override
  List<Object?> get props => [polymer.code, confidence];
}

/// Full result of an on-device classification pass, including the ranked
/// candidate list so the UI can offer manual correction.
class ClassificationResult extends Equatable {
  final List<PolymerPrediction> predictions;

  /// Wall-clock inference time, surfaced for transparency/debugging.
  final Duration inferenceTime;

  const ClassificationResult({
    required this.predictions,
    required this.inferenceTime,
  });

  PolymerPrediction get top => predictions.first;

  PolymerInfo get polymer => top.polymer;
  double get confidence => top.confidence;

  /// Below this the model is not trusting its own call; UI nudges the user to
  /// retake or manually confirm.
  static const double lowConfidenceThreshold = 0.60;
  static const double highConfidenceThreshold = 0.85;

  bool get isConfident => confidence >= highConfidenceThreshold;
  bool get isUncertain => confidence < lowConfidenceThreshold;

  /// Margin between the top-1 and top-2 candidate. A small margin means the
  /// model is torn between two resins even if top-1 confidence looks fine.
  double get margin =>
      predictions.length < 2 ? 1.0 : confidence - predictions[1].confidence;

  bool get isAmbiguous => margin < 0.15;

  @override
  List<Object?> get props => [predictions, inferenceTime];
}
