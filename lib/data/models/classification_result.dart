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

  /// Probability of every class the model knows, keyed by resin code
  /// (e.g. `1-PET`), so the confidence of a manually chosen resin can be
  /// recorded truthfully.
  final Map<String, double> probabilities;

  /// Version tag of the model that produced this result.
  final String modelVersion;

  /// Wall-clock inference time, surfaced for transparency/debugging.
  final Duration inferenceTime;

  const ClassificationResult({
    required this.predictions,
    required this.inferenceTime,
    this.probabilities = const {},
    this.modelVersion = 'unknown',
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

  /// Model probability for [code]; 0 if the model never considered it.
  double confidenceFor(String code) => probabilities[code] ??
      predictions
          .where((p) => p.polymer.code == code)
          .map((p) => p.confidence)
          .fold(0.0, (a, b) => a > b ? a : b);

  @override
  List<Object?> get props =>
      [predictions, probabilities, modelVersion, inferenceTime];
}
