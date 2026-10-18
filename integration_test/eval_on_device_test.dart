import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:poly_mint/data/services/ml_service.dart';

/// Per-class evaluation of the bundled model through the real app pipeline
/// (ImagePreprocessor + tflite_flutter) on a device.
///
/// Put images plus a `labels.csv` (`file,class,source`) in the app's support
/// directory under `eval/`, then run this test. It writes
/// `eval/device_preds.json` (file -> predicted class + confidence) for the host
/// to pull and score. Without that data the test does nothing, so the normal
/// integration run is unaffected. See `ml/kaggle/results/RESULTS.md` for how the
/// held-out set is built and pushed.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('evaluate the bundled model on eval/ images', (tester) async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/eval');
    final labelsFile = File('${dir.path}/labels.csv');
    if (!labelsFile.existsSync()) {
      // ignore: avoid_print
      print('eval: no ${labelsFile.path}; nothing to evaluate');
      return;
    }

    final ml = MlService();
    await ml.load();

    final rows = labelsFile.readAsLinesSync().skip(1).where((l) => l.isNotEmpty);
    final preds = <String, Map<String, Object>>{};
    final perClass = <String, List<int>>{}; // class -> [correct, total]
    var totalMs = 0;
    for (final row in rows) {
      final parts = row.split(',');
      final file = parts[0];
      final truth = parts[1];
      final result =
          await ml.classify([File('${dir.path}/$file').readAsBytesSync()]);
      final pred = result.polymer.code.split('-').last;
      totalMs += result.inferenceTime.inMilliseconds;
      preds[file] = {'pred': pred, 'conf': result.confidence};
      final c = perClass.putIfAbsent(truth, () => [0, 0]);
      if (pred == truth) c[0]++;
      c[1]++;
    }
    File('${dir.path}/device_preds.json').writeAsStringSync(jsonEncode(preds));

    final n = preds.length;
    // ignore: avoid_print
    print('eval: $n images, mean ${(totalMs / n).toStringAsFixed(0)} ms/image');
    perClass.forEach((cls, c) {
      // ignore: avoid_print
      print('eval: $cls ${c[0]}/${c[1]}');
    });
    expect(n, greaterThan(0));
    ml.dispose();
  });
}
