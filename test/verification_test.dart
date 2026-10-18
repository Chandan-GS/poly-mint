import 'package:flutter_test/flutter_test.dart';
import 'package:poly_mint/data/models/classification_result.dart';
import 'package:poly_mint/data/models/polymer_info.dart';
import 'package:poly_mint/data/models/waste_transaction.dart';
import 'package:poly_mint/features/result/cubit/minting_cubit.dart';

ClassificationResult _result(Map<String, double> probs) {
  final ranked = probs.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return ClassificationResult(
    predictions: ranked
        .take(3)
        .map((e) => PolymerPrediction(
            polymer: PolymerCatalog.lookup(e.key), confidence: e.value))
        .toList(),
    probabilities: probs,
    modelVersion: 'polymer7-v2',
    inferenceTime: const Duration(milliseconds: 40),
  );
}

void main() {
  final pet = PolymerCatalog.lookup('1-PET');
  final pp = PolymerCatalog.lookup('5-PP');

  group('verificationOf', () {
    test('AI pick at or above the 0.85 gate is AI-verified', () {
      final r = _result({'1-PET': 0.91, '5-PP': 0.05, '2-HDPE': 0.04});
      expect(verificationOf(r, pet), VerificationMethod.aiVerified);
    });

    test('AI pick below the gate needs manual review', () {
      final r = _result({'1-PET': 0.70, '5-PP': 0.20, '2-HDPE': 0.10});
      expect(verificationOf(r, pet), VerificationMethod.manualReview);
    });

    test('overriding a confident AI pick needs manual review', () {
      final r = _result({'1-PET': 0.95, '5-PP': 0.03, '2-HDPE': 0.02});
      expect(verificationOf(r, pp), VerificationMethod.manualReview);
    });
  });

  test('confidenceFor reports the model probability of an override', () {
    final r = _result({
      '1-PET': 0.80, '5-PP': 0.10, '2-HDPE': 0.05, '3-PVC': 0.03, '6-PS': 0.02,
    });
    expect(r.confidenceFor('5-PP'), 0.10);
    expect(r.confidenceFor('3-PVC'), 0.03); // outside the top 3, still known
  });

  group('WasteTransaction verification fields', () {
    final tx = WasteTransaction(
      id: 'a',
      userId: 'u',
      userName: 'n',
      polymerCode: '5-PP',
      confidence: 0.10,
      weightKg: 1.5,
      creditsMinted: 3,
      co2SavedKg: 2,
      lat: null,
      lng: null,
      timestamp: DateTime(2026, 10, 18),
      status: TransactionStatus.verified,
      verification: VerificationMethod.manualReview,
      aiPolymerCode: '1-PET',
      aiConfidence: 0.80,
      modelVersion: 'polymer7-v2',
      popp: const {
        'settleDeltaKg': 1.5,
        'stableWindowMs': 900,
        'captureOffsetMs': 300,
        'sampleHashChain': 'abc123',
        'sampleCount': 18,
        'simulated': true,
        'verdict': 'PASS',
      },
    );

    test('keep the PoPP proof through the offline queue', () {
      final back = WasteTransaction.fromJson(tx.toJson());
      expect(back.popp?['verdict'], 'PASS');
      expect(back.popp?['sampleHashChain'], 'abc123');
      expect(back.popp?['simulated'], isTrue);
    });

    test('survive the offline-queue JSON round trip and status changes', () {
      final back = WasteTransaction.fromJson(tx.toJson())
          .copyWith(status: TransactionStatus.pendingSync);
      expect(back.verification, VerificationMethod.manualReview);
      expect(back.aiPolymerCode, '1-PET');
      expect(back.aiConfidence, 0.80);
      expect(back.modelVersion, 'polymer7-v2');
    });

    test('use the ML contract wire values', () {
      expect(tx.toJson()['verification'], 'MANUAL_REVIEW');
      expect(VerificationMethod.aiVerified.wire, 'AI_VERIFIED');
    });

    test('legacy records without the fields read as unknown', () {
      final legacy = tx.toJson()
        ..remove('verification')
        ..remove('ai_polymer');
      final back = WasteTransaction.fromJson(legacy);
      expect(back.verification, VerificationMethod.unknown);
      expect(back.aiPolymerCode, isNull);
    });
  });
}
