import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/impact_stats.dart';
import '../../../data/models/waste_transaction.dart';
import '../../../data/services/transaction_repository.dart';

enum DashboardStatus { loading, ready, error }

class DashboardState extends Equatable {
  final DashboardStatus status;
  final ImpactStats userStats;
  final ImpactStats globalStats;
  final List<WasteTransaction> recent;
  final int pendingCount;

  const DashboardState({
    this.status = DashboardStatus.loading,
    this.userStats = const ImpactStats.empty(),
    this.globalStats = const ImpactStats.empty(),
    this.recent = const [],
    this.pendingCount = 0,
  });

  DashboardState copyWith({
    DashboardStatus? status,
    ImpactStats? userStats,
    ImpactStats? globalStats,
    List<WasteTransaction>? recent,
    int? pendingCount,
  }) {
    return DashboardState(
      status: status ?? this.status,
      userStats: userStats ?? this.userStats,
      globalStats: globalStats ?? this.globalStats,
      recent: recent ?? this.recent,
      pendingCount: pendingCount ?? this.pendingCount,
    );
  }

  @override
  List<Object?> get props =>
      [status, userStats, globalStats, recent, pendingCount];
}

/// Streams the current user's transactions and the global feed, deriving
/// personal + exchange-wide impact stats for the dashboard.
class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit(this._repo, this._userId) : super(const DashboardState()) {
    _listen();
  }

  final TransactionRepository _repo;
  final String _userId;
  StreamSubscription? _userSub;
  StreamSubscription? _globalSub;

  void _listen() {
    _userSub = _repo.watchUserTransactions(_userId).listen(
      (txns) {
        emit(state.copyWith(
          status: DashboardStatus.ready,
          userStats: ImpactStats.fromTransactions(txns),
          recent: txns.take(5).toList(),
          pendingCount: _repo.pendingCount,
        ));
      },
      onError: (_) => emit(state.copyWith(status: DashboardStatus.error)),
    );

    _globalSub = _repo.watchGlobalTransactions().listen(
      (txns) => emit(
        state.copyWith(globalStats: ImpactStats.fromTransactions(txns)),
      ),
      onError: (_) {/* global stats are best-effort */},
    );
  }

  @override
  Future<void> close() {
    _userSub?.cancel();
    _globalSub?.cancel();
    return super.close();
  }
}
