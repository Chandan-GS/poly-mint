import 'dart:math' as math;

/// Temperature scaling for the classifier's probabilities.
///
/// The raw model is overconfident: on held-out images only 77% of its
/// "≥ 85% sure" calls were right. Rescaling the probabilities by a single
/// temperature T fitted on the validation split (q_i ∝ p_i^(1/T), i.e. softmax
/// of log p / T) makes confidence track accuracy, so 95.5% of "≥ 85% sure" calls
/// on the held-out test set are right. It never changes which class wins.
/// Fitted in `ml/kaggle/calibrate.py`; see `ml/kaggle/results/RESULTS.md`.
class ConfidenceCalibration {
  const ConfidenceCalibration._();

  /// Temperature for the bundled `polymer7-v2` model.
  static const double polymer7V2Temperature = 4.077;

  static List<double> apply(List<double> probs, double temperature) {
    if (probs.isEmpty || temperature == 1.0) return List.of(probs);
    final logits = probs
        .map((p) => math.log(p.clamp(1e-12, 1.0)) / temperature)
        .toList();
    final maxLogit = logits.reduce(math.max);
    final exps = logits.map((l) => math.exp(l - maxLogit)).toList();
    final sum = exps.fold<double>(0, (a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }
}
