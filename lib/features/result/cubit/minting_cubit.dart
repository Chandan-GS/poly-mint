import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/classification_result.dart';
import '../../../data/models/polymer_info.dart';
import '../../../data/models/waste_transaction.dart';
import '../../../data/services/location_service.dart';
import '../../../data/services/preferences_service.dart';
import '../../../data/services/transaction_repository.dart';

enum MintingStatus { editing, minting, mintedOnline, mintedOffline, error }

class MintingState extends Equatable {
  final MintingStatus status;

  /// Resin the user has confirmed (defaults to the AI's top pick, can be
  /// overridden from the candidate list).
  final PolymerInfo selectedPolymer;
  final double weightKg;
  final String? error;

  const MintingState({
    required this.status,
    required this.selectedPolymer,
    required this.weightKg,
    this.error,
  });

  double get creditsPreview => weightKg * selectedPolymer.creditRate;
  double get co2Preview => weightKg * selectedPolymer.co2SavedPerKg;
  bool get canMint => weightKg > 0 && status != MintingStatus.minting;

  MintingState copyWith({
    MintingStatus? status,
    PolymerInfo? selectedPolymer,
    double? weightKg,
    String? error,
  }) {
    return MintingState(
      status: status ?? this.status,
      selectedPolymer: selectedPolymer ?? this.selectedPolymer,
      weightKg: weightKg ?? this.weightKg,
      error: error,
    );
  }

  @override
  List<Object?> get props => [status, selectedPolymer.code, weightKg, error];
}

/// Handles confirming the polymer, computing credits/CO₂ and writing the
/// transaction through the offline-first repository.
class MintingCubit extends Cubit<MintingState> {
  MintingCubit({
    required ClassificationResult result,
    required TransactionRepository repo,
    required LocationService location,
    required PreferencesService prefs,
  })  : _result = result,
        _repo = repo,
        _location = location,
        _prefs = prefs,
        super(MintingState(
          status: MintingStatus.editing,
          selectedPolymer: result.polymer,
          weightKg: 0,
        ));

  final ClassificationResult _result;
  final TransactionRepository _repo;
  final LocationService _location;
  final PreferencesService _prefs;

  void selectPolymer(PolymerInfo polymer) {
    emit(state.copyWith(selectedPolymer: polymer, status: MintingStatus.editing));
  }

  void setWeight(String raw) {
    final w = double.tryParse(raw.trim()) ?? 0;
    emit(state.copyWith(weightKg: w));
  }

  Future<void> mint() async {
    if (state.weightKg <= 0) {
      emit(state.copyWith(
          status: MintingStatus.error, error: 'Enter a valid weight in kg.'));
      return;
    }
    emit(state.copyWith(status: MintingStatus.minting));

    final polymer = state.selectedPolymer;
    final geo = await _location.currentPosition();

    final tx = WasteTransaction(
      id: const Uuid().v4(),
      userId: _prefs.userId,
      userName: _prefs.displayName,
      polymerCode: polymer.code,
      // If the user manually overrode the AI pick, record full confidence.
      confidence: polymer.code == _result.polymer.code ? _result.confidence : 1.0,
      weightKg: state.weightKg,
      creditsMinted: state.creditsPreview,
      co2SavedKg: state.co2Preview,
      lat: geo?.lat,
      lng: geo?.lng,
      timestamp: DateTime.now(),
      status: TransactionStatus.verified,
    );

    try {
      final syncedOnline = await _repo.mint(tx);
      emit(state.copyWith(
        status: syncedOnline
            ? MintingStatus.mintedOnline
            : MintingStatus.mintedOffline,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: MintingStatus.error,
        error: 'Minting failed. Please try again.',
      ));
    }
  }
}
