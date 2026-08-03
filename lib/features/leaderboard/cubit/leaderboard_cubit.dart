import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/leaderboard_entry.dart';
import '../../../data/services/transaction_repository.dart';

class LeaderboardState extends Equatable {
  final bool loading;
  final List<LeaderboardEntry> entries;

  const LeaderboardState({this.loading = true, this.entries = const []});

  LeaderboardState copyWith({bool? loading, List<LeaderboardEntry>? entries}) =>
      LeaderboardState(
        loading: loading ?? this.loading,
        entries: entries ?? this.entries,
      );

  @override
  List<Object?> get props => [loading, entries];
}

class LeaderboardCubit extends Cubit<LeaderboardState> {
  LeaderboardCubit(this._repo) : super(const LeaderboardState()) {
    _sub = _repo.watchLeaderboard().listen(
          (entries) => emit(LeaderboardState(loading: false, entries: entries)),
          onError: (_) => emit(const LeaderboardState(loading: false)),
        );
  }

  final TransactionRepository _repo;
  StreamSubscription? _sub;

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
