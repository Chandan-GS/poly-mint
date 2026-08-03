import 'package:flutter_test/flutter_test.dart';
import 'package:poly_mint/data/models/impact_stats.dart';
import 'package:poly_mint/data/models/waste_transaction.dart';

WasteTransaction _tx({
  required String code,
  required double weight,
  required double credits,
  required double co2,
  DateTime? at,
}) {
  return WasteTransaction(
    id: '$code-$weight',
    userId: 'u1',
    userName: 'Tester',
    polymerCode: code,
    confidence: 0.9,
    weightKg: weight,
    creditsMinted: credits,
    co2SavedKg: co2,
    lat: null,
    lng: null,
    timestamp: at ?? DateTime(2026, 8, 1),
    status: TransactionStatus.verified,
  );
}

void main() {
  group('ImpactStats.fromTransactions', () {
    test('empty input yields the empty stats', () {
      expect(ImpactStats.fromTransactions([]).scanCount, 0);
      expect(ImpactStats.fromTransactions([]).totalCredits, 0);
    });

    test('aggregates totals and per-polymer weight', () {
      final stats = ImpactStats.fromTransactions([
        _tx(code: '1-PET', weight: 2, credits: 3, co2: 4),
        _tx(code: '1-PET', weight: 1, credits: 1.5, co2: 2),
        _tx(code: '5-PP', weight: 5, credits: 5, co2: 8),
      ]);

      expect(stats.scanCount, 3);
      expect(stats.totalWeightKg, 8);
      expect(stats.totalCredits, closeTo(9.5, 1e-9));
      expect(stats.totalCo2SavedKg, 14);
      expect(stats.weightByPolymer['1-PET'], 3);
      expect(stats.weightByPolymer['5-PP'], 5);
      expect(stats.topPolymerCode, '5-PP');
    });

    test('real-world equivalences derive from CO₂', () {
      final stats = ImpactStats.fromTransactions([
        _tx(code: '1-PET', weight: 10, credits: 15, co2: 21.7),
      ]);
      expect(stats.treesEquivalent, closeTo(1.0, 1e-6));
    });
  });

  group('WasteTransaction JSON round-trip', () {
    test('survives serialize → deserialize for the offline queue', () {
      final original = _tx(code: '2-HDPE', weight: 3.2, credits: 3.84, co2: 5.7);
      final restored = WasteTransaction.fromJson(original.toJson());

      expect(restored.polymerCode, original.polymerCode);
      expect(restored.weightKg, original.weightKg);
      expect(restored.creditsMinted, original.creditsMinted);
      expect(restored.userName, original.userName);
      expect(restored.isLocalOnly, isTrue);
    });
  });
}
