import 'package:equatable/equatable.dart';
import 'waste_transaction.dart';

/// Aggregated impact metrics derived from a set of transactions. Used by both
/// the personal dashboard and the global exchange view.
class ImpactStats extends Equatable {
  final double totalCredits;
  final double totalWeightKg;
  final double totalCo2SavedKg;
  final int scanCount;

  /// Weight recovered per resin code, for the breakdown chart.
  final Map<String, double> weightByPolymer;

  /// Total weight per calendar day (last 7 entries), for the trend chart.
  final Map<DateTime, double> weightByDay;

  const ImpactStats({
    required this.totalCredits,
    required this.totalWeightKg,
    required this.totalCo2SavedKg,
    required this.scanCount,
    required this.weightByPolymer,
    required this.weightByDay,
  });

  const ImpactStats.empty()
      : totalCredits = 0,
        totalWeightKg = 0,
        totalCo2SavedKg = 0,
        scanCount = 0,
        weightByPolymer = const {},
        weightByDay = const {};

  /// Rough real-world equivalences to make impact tangible for users.
  /// ~21.7 kg CO₂ absorbed by a mature tree per year.
  double get treesEquivalent => totalCo2SavedKg / 21.7;

  /// ~2.3 kg CO₂ per litre of petrol burned.
  double get litresPetrolEquivalent => totalCo2SavedKg / 2.3;

  String? get topPolymerCode {
    if (weightByPolymer.isEmpty) return null;
    return weightByPolymer.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
  }

  factory ImpactStats.fromTransactions(List<WasteTransaction> txns) {
    if (txns.isEmpty) return const ImpactStats.empty();

    double credits = 0, weight = 0, co2 = 0;
    final byPolymer = <String, double>{};
    final byDay = <DateTime, double>{};

    for (final t in txns) {
      credits += t.creditsMinted;
      weight += t.weightKg;
      co2 += t.co2SavedKg;
      byPolymer.update(t.polymerCode, (v) => v + t.weightKg,
          ifAbsent: () => t.weightKg);
      final day =
          DateTime(t.timestamp.year, t.timestamp.month, t.timestamp.day);
      byDay.update(day, (v) => v + t.weightKg, ifAbsent: () => t.weightKg);
    }

    return ImpactStats(
      totalCredits: credits,
      totalWeightKg: weight,
      totalCo2SavedKg: co2,
      scanCount: txns.length,
      weightByPolymer: byPolymer,
      weightByDay: byDay,
    );
  }

  @override
  List<Object?> get props =>
      [totalCredits, totalWeightKg, totalCo2SavedKg, scanCount];
}
