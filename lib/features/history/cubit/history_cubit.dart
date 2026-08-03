import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/waste_transaction.dart';
import '../../../data/services/transaction_repository.dart';

class HistoryState extends Equatable {
  final bool loading;
  final List<WasteTransaction> all;

  /// Active resin-code filter, or null for "all".
  final String? filter;

  const HistoryState({
    this.loading = true,
    this.all = const [],
    this.filter,
  });

  List<WasteTransaction> get visible =>
      filter == null ? all : all.where((t) => t.polymerCode == filter).toList();

  /// Distinct resin codes present, for building filter chips.
  List<String> get availableCodes =>
      all.map((t) => t.polymerCode).toSet().toList();

  HistoryState copyWith({
    bool? loading,
    List<WasteTransaction>? all,
    String? filter,
    bool clearFilter = false,
  }) {
    return HistoryState(
      loading: loading ?? this.loading,
      all: all ?? this.all,
      filter: clearFilter ? null : (filter ?? this.filter),
    );
  }

  @override
  List<Object?> get props => [loading, all, filter];
}

class HistoryCubit extends Cubit<HistoryState> {
  HistoryCubit(this._repo, this._userId) : super(const HistoryState()) {
    _sub = _repo.watchUserTransactions(_userId).listen(
          (txns) => emit(state.copyWith(loading: false, all: txns)),
          onError: (_) => emit(state.copyWith(loading: false)),
        );
  }

  final TransactionRepository _repo;
  final String _userId;
  StreamSubscription? _sub;

  void setFilter(String? code) {
    if (code == null) {
      emit(state.copyWith(clearFilter: true));
    } else {
      emit(state.copyWith(filter: code));
    }
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
