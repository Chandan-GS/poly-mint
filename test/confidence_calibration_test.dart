import 'package:flutter_test/flutter_test.dart';
import 'package:poly_mint/data/services/confidence_calibration.dart';

void main() {
  const t = ConfidenceCalibration.polymer7V2Temperature;
  final raw = [0.97, 0.02, 0.005, 0.003, 0.001, 0.0005, 0.0005];

  test('keeps the winning class and sums to one', () {
    final q = ConfidenceCalibration.apply(raw, t);
    expect(q.indexOf(q.reduce((a, b) => a > b ? a : b)), 0);
    expect(q.fold<double>(0, (a, b) => a + b), closeTo(1.0, 1e-9));
  });

  test('softens an overconfident call below the 85% gate', () {
    // A 97% raw call is not 97% reliable for this model; after calibration it
    // drops under the gate and goes to manual review.
    expect(ConfidenceCalibration.apply(raw, t).first, lessThan(0.85));
  });

  test('a near-certain call stays above the gate', () {
    final q = ConfidenceCalibration.apply(
        [0.99999994, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8], t);
    expect(q.first, greaterThan(0.85));
  });

  test('temperature 1 is the identity', () {
    final q = ConfidenceCalibration.apply(raw, 1.0);
    for (var i = 0; i < raw.length; i++) {
      expect(q[i], closeTo(raw[i], 1e-12));
    }
  });
}
