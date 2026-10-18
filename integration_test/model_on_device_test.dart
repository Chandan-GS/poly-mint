import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:poly_mint/data/services/ml_service.dart';

import 'fixture_photo.dart';

/// Runs the bundled model through the real on-device path (asset loading,
/// labels, preprocessing, tflite_flutter). Expected values come from running
/// the same photo through PolyMint_ML's TFLite + canonical preprocessing:
/// LDPE, raw probability ~1.0, 0.836 after temperature calibration.
///
///   `flutter test integration_test -d <device-id>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bundled polymer7-v2 model classifies the fixture like Python',
      (tester) async {
    final ml = MlService();
    await ml.load();
    expect(ml.labels, hasLength(7));

    final result = await ml.classify([base64Decode(samplePhotoBase64)]);

    expect(result.modelVersion, MlService.modelVersion);
    expect(result.polymer.code, '4-LDPE');
    expect(result.confidence, closeTo(0.836, 0.02));
    final total = result.probabilities.values.fold<double>(0, (a, b) => a + b);
    expect(total, closeTo(1.0, 1e-3));
    // ignore: avoid_print
    print('on-device: ${result.polymer.code} '
        '${result.confidence.toStringAsFixed(4)} '
        'in ${result.inferenceTime.inMilliseconds} ms');
    ml.dispose();
  });
}
