import 'package:flutter_test/flutter_test.dart';
import 'package:poly_mint/data/models/classification_result.dart';
import 'package:poly_mint/data/models/polymer_info.dart';
import 'package:poly_mint/data/models/popp_proof.dart';
import 'package:poly_mint/data/models/weight_estimate.dart';
import 'package:poly_mint/data/services/location_service.dart';
import 'package:poly_mint/data/services/preferences_service.dart';
import 'package:poly_mint/data/services/transaction_repository.dart';
import 'package:poly_mint/features/result/cubit/minting_cubit.dart';

// Never called by these tests: they stop before minting.
class _Unused
    implements TransactionRepository, LocationService, PreferencesService {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

ClassificationResult _pet() => ClassificationResult(
  predictions: [
    PolymerPrediction(
      polymer: PolymerCatalog.lookup('1-PET'),
      confidence: 0.97,
    ),
    PolymerPrediction(
      polymer: PolymerCatalog.lookup('4-LDPE'),
      confidence: 0.02,
    ),
  ],
  probabilities: const {'1-PET': 0.97, '4-LDPE': 0.02, '5-PP': 0.01},
  modelVersion: 'polymer7-v2-cal1',
  inferenceTime: const Duration(milliseconds: 40),
);

MintingCubit _cubit({PoppProof? proof, double weightKg = 0}) {
  final u = _Unused();
  return MintingCubit(
    result: _pet(),
    repo: u,
    location: u,
    prefs: u,
    proof: proof,
    weightKg: weightKg,
  );
}

const _proof = PoppProof(
  settleDeltaKg: 1.2,
  stableWindowMs: 900,
  captureOffsetMs: 300,
  sampleHashChain: 'abc',
  sampleCount: 18,
  simulated: true,
  verdict: PoppVerdict.pass,
);

void main() {
  group('WeightEstimate', () {
    test('every model class has a typical item', () {
      for (final p in PolymerCatalog.all) {
        expect(typicalItems.containsKey(p.code), isTrue, reason: p.code);
      }
    });

    test('is item count times the typical item weight, to the gram', () {
      final e = WeightEstimate.of('1-PET', 12);
      expect(e.unitKg, 0.025);
      expect(e.kg, 0.3);
      expect(e.toJson()['estimate_kg'], 0.3);
    });

    test('parseWeightKg accepts a comma and rejects junk', () {
      expect(parseWeightKg('1,25'), 1.25);
      expect(parseWeightKg(' 0.4 '), 0.4);
      expect(parseWeightKg('-2'), 0);
      expect(parseWeightKg('abc'), 0);
    });
  });

  group('manual weight (no scale)', () {
    test('starts from the suggestion for one item of the AI pick', () {
      final c = _cubit();
      expect(c.state.weightSource, WeightSource.manual);
      expect(c.state.weightKg, 0.025);
      expect(c.state.weightEdited, isFalse);
    });

    test('suggestion follows item count and material until typed', () {
      final c = _cubit();
      c.setItemCount(10);
      expect(c.state.weightKg, 0.25);
      c.selectPolymer(PolymerCatalog.lookup('4-LDPE'));
      expect(c.state.weightKg, 0.08);
    });

    test('a typed weight sticks; use suggestion restores it', () {
      final c = _cubit();
      c.setWeight('2.4');
      c.setItemCount(5);
      expect(c.state.weightKg, 2.4);
      expect(c.state.weightEdited, isTrue);
      c.useEstimate();
      expect(c.state.weightKg, 0.125);
      expect(c.state.weightEdited, isFalse);
    });

    test('an empty or zero weight cannot be minted', () {
      final c = _cubit();
      c.setWeight('');
      expect(c.state.canMint, isFalse);
    });
  });

  group('scale weight', () {
    test('uses the scale reading and ignores item count', () {
      final c = _cubit(proof: _proof, weightKg: 1.2);
      expect(c.state.weightSource, WeightSource.scale);
      c.setItemCount(3);
      expect(c.state.weightKg, 1.2);
    });

    test('switching to manual entry drops the scale weight', () {
      final c = _cubit(proof: _proof, weightKg: 1.2);
      c.enterWeightManually();
      expect(c.state.weightSource, WeightSource.manual);
      expect(c.state.weightKg, 0.025);
    });
  });
}
