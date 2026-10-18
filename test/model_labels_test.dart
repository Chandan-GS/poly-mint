import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poly_mint/data/models/polymer_info.dart';

/// `assets/model/labels.txt` maps output index i to a resin code. Ultralytics
/// orders classes by their training-folder names, so the v2 model's outputs
/// are HDPE, LDPE, Other, PET, PP, PS, PVC — a wrong order here would silently
/// mislabel every scan.
void main() {
  final labels = File('assets/model/labels.txt')
      .readAsLinesSync()
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  test('has one known, unique resin code per model output', () {
    expect(labels, hasLength(7));
    expect(labels.toSet(), hasLength(7));
    for (final code in labels) {
      expect(PolymerCatalog.byCode.containsKey(code), isTrue,
          reason: '$code is not in PolymerCatalog');
    }
  });

  test('follows the model class order (training folders, sorted)', () {
    final names = labels.map((c) => c.split('-').last).toList();
    expect(names, ['HDPE', 'LDPE', 'Other', 'PET', 'PP', 'PS', 'PVC']);
  });

  test('is the labels file the app bundles', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('assets/model/labels.txt'));
    expect(pubspec, contains('assets/model/polymer7_v2_float32.tflite'));
  });
}
