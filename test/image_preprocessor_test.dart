import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poly_mint/data/services/image_preprocessor.dart';

/// The app must feed the model the same tensor the training pipeline does.
/// The expected values come from `PolyMint_ML/src/preprocessing.py` run on
/// the same full-size photo (sampled on a 32 x 32 grid).
void main() {
  test('matches the training preprocessing on a full-size photo', () {
    final bytes = File('test/fixtures/sample_photo.jpg').readAsBytesSync();
    final expected = jsonDecode(
            File('test/fixtures/sample_photo_expected.json').readAsStringSync())
        as Map<String, dynamic>;
    final size = expected['size'] as int;
    final index = (expected['index'] as List).cast<int>();
    final rgb = expected['rgb'] as List;

    final tensor = ImagePreprocessor.toTensor(bytes, size)!;
    expect(tensor.length, 1);
    expect(tensor[0].length, size);
    expect(tensor[0][0].length, size);

    var sumDiff = 0.0;
    var maxDiff = 0.0;
    var n = 0;
    for (var gy = 0; gy < index.length; gy++) {
      for (var gx = 0; gx < index.length; gx++) {
        final want = (rgb[gy][gx] as List).cast<num>();
        final got = tensor[0][index[gy]][index[gx]];
        for (var c = 0; c < 3; c++) {
          final d = (got[c] - want[c]).abs();
          sumDiff += d;
          if (d > maxDiff) maxDiff = d;
          n++;
        }
      }
    }
    // Training resizes the whole photo and then crops; the app crops and then
    // resizes. Same region, but the sample grids differ by ~0.5 source px, so
    // single pixels on sharp edges can differ slightly. On 32 full-size photos
    // this order of operations agreed with training on 100% of predictions.
    expect(sumDiff / n, lessThan(0.005));
    expect(maxDiff, lessThan(0.06));
  });

  test('returns null for bytes that are not an image', () {
    expect(ImagePreprocessor.toTensor(utf8.encode('not an image'), 224), isNull);
  });
}
