import 'package:equatable/equatable.dart';
import 'waste_transaction.dart';

/// One contributor's aggregated standing in the global exchange.
class LeaderboardEntry extends Equatable {
  final String userId;
  final String userName;
  final double totalCredits;
  final double totalWeightKg;
  final int scanCount;
  final int rank;

  const LeaderboardEntry({
    required this.userId,
    required this.userName,
    required this.totalCredits,
    required this.totalWeightKg,
    required this.scanCount,
    required this.rank,
  });

  /// Collapse a flat transaction feed into a ranked, credit-sorted board.
  static List<LeaderboardEntry> rankAll(List<WasteTransaction> txns) {
    final byUser = <String, _Acc>{};
    for (final t in txns) {
      final acc = byUser.putIfAbsent(t.userId, () => _Acc(t.userName));
      acc.credits += t.creditsMinted;
      acc.weight += t.weightKg;
      acc.count += 1;
      acc.name = t.userName; // keep latest name
    }

    final entries = byUser.entries.toList()
      ..sort((a, b) => b.value.credits.compareTo(a.value.credits));

    return [
      for (var i = 0; i < entries.length; i++)
        LeaderboardEntry(
          userId: entries[i].key,
          userName: entries[i].value.name,
          totalCredits: entries[i].value.credits,
          totalWeightKg: entries[i].value.weight,
          scanCount: entries[i].value.count,
          rank: i + 1,
        ),
    ];
  }

  @override
  List<Object?> get props => [userId, totalCredits, rank];
}

class _Acc {
  _Acc(this.name);
  String name;
  double credits = 0;
  double weight = 0;
  int count = 0;
}
