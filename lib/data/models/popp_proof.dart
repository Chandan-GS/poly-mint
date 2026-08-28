import 'package:equatable/equatable.dart';

/// Outcome of the sensor-fusion check that binds vision to mass.
enum PoppVerdict {
  /// Mass present, weight settled, capture happened inside the stable window.
  pass,

  /// No mass on the load-cell at capture time — a printed photo or replayed
  /// video. This is the rejection the whole pitch is built on.
  failNoMass,

  /// Weight never settled, or the capture fell outside the stable window.
  failUnstable,
}

extension PoppVerdictX on PoppVerdict {
  bool get isPass => this == PoppVerdict.pass;
  String get wire => switch (this) {
        PoppVerdict.pass => 'PASS',
        PoppVerdict.failNoMass => 'FAIL_NO_MASS',
        PoppVerdict.failUnstable => 'FAIL_UNSTABLE',
      };
  String get humanReason => switch (this) {
        PoppVerdict.pass => 'Physical presence verified.',
        PoppVerdict.failNoMass =>
          'No mass detected on the scale — rejected as photo/replay.',
        PoppVerdict.failUnstable =>
          'Weight never settled — hold the batch steady and retry.',
      };
}

/// Proof-of-Physical-Presence record. Every value that a credit's trust rests
/// on is carried here so the cloud (and any future auditor) can independently
/// re-verify the physical event, not just take our word for it.
class PoppProof extends Equatable {
  /// Mass added while arming (plateau − baseline), kg.
  final double settleDeltaKg;

  /// How long the weight was held steady before capture, ms.
  final int stableWindowMs;

  /// Offset of the image capture from the start of the stable window, ms.
  /// Positive and within [stableWindowMs] for a valid PASS.
  final int captureOffsetMs;

  /// SHA-256 hash chain folded over the weight samples in the stable window —
  /// tamper-evident: altering any sample breaks the chain.
  final String sampleHashChain;

  /// Number of samples folded into the chain.
  final int sampleCount;

  /// Whether a simulated sensor produced this (never hardware-proven).
  final bool simulated;

  final PoppVerdict verdict;

  const PoppProof({
    required this.settleDeltaKg,
    required this.stableWindowMs,
    required this.captureOffsetMs,
    required this.sampleHashChain,
    required this.sampleCount,
    required this.simulated,
    required this.verdict,
  });

  double get weightKg => double.parse(settleDeltaKg.toStringAsFixed(3));

  Map<String, dynamic> toJson() => {
        'settleDeltaKg': settleDeltaKg,
        'stableWindowMs': stableWindowMs,
        'captureOffsetMs': captureOffsetMs,
        'sampleHashChain': sampleHashChain,
        'sampleCount': sampleCount,
        'simulated': simulated,
        'verdict': verdict.wire,
      };

  @override
  List<Object?> get props => [
        settleDeltaKg,
        stableWindowMs,
        captureOffsetMs,
        sampleHashChain,
        sampleCount,
        simulated,
        verdict,
      ];
}
