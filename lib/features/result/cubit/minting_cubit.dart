import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/classification_result.dart';
import '../../../data/models/polymer_info.dart';
import '../../../data/models/popp_proof.dart';
import '../../../data/models/waste_transaction.dart';
import '../../../data/models/weight_estimate.dart';
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

  /// Scale reading (bound to the photo by PoPP) or typed in by the operator.
  final WeightSource weightSource;

  /// Items in the batch, for the suggested weight when typing it in.
  final int itemCount;

  /// True once the operator has typed a weight; until then the weight follows
  /// the suggestion as the material or item count changes.
  final bool weightEdited;
  final String? error;

  const MintingState({
    required this.status,
    required this.selectedPolymer,
    required this.weightKg,
    this.weightSource = WeightSource.scale,
    this.itemCount = 1,
    this.weightEdited = false,
    this.error,
  });

  bool get isManualWeight => weightSource == WeightSource.manual;

  /// Suggested weight: [itemCount] typical items of the selected material.
  WeightEstimate get estimate =>
      WeightEstimate.of(selectedPolymer.code, itemCount);

  double get creditsPreview => weightKg * selectedPolymer.creditRate;

  /// Whether this record will be AI-verified or sent for manual review.
  VerificationMethod verificationFor(ClassificationResult result) =>
      verificationOf(result, selectedPolymer);
  double get co2Preview => weightKg * selectedPolymer.co2SavedPerKg;
  bool get canMint =>
      weightKg > 0 && weightKg < maxWeightKg && status != MintingStatus.minting;

  MintingState copyWith({
    MintingStatus? status,
    PolymerInfo? selectedPolymer,
    double? weightKg,
    WeightSource? weightSource,
    int? itemCount,
    bool? weightEdited,
    String? error,
  }) {
    return MintingState(
      status: status ?? this.status,
      selectedPolymer: selectedPolymer ?? this.selectedPolymer,
      weightKg: weightKg ?? this.weightKg,
      weightSource: weightSource ?? this.weightSource,
      itemCount: itemCount ?? this.itemCount,
      weightEdited: weightEdited ?? this.weightEdited,
      error: error,
    );
  }

  @override
  List<Object?> get props => [
    status,
    selectedPolymer.code,
    weightKg,
    weightSource,
    itemCount,
    weightEdited,
    error,
  ];
}

/// Upper bound the ledger rules accept for one record.
const double maxWeightKg = 100000;

/// AI-verified only when the recorded resin is the model's own pick and the
/// model is at or above the confidence gate; everything else needs review.
VerificationMethod verificationOf(
  ClassificationResult result,
  PolymerInfo recorded,
) {
  final isAiPick = recorded.code == result.polymer.code;
  return isAiPick && result.isConfident
      ? VerificationMethod.aiVerified
      : VerificationMethod.manualReview;
}

/// Handles confirming the polymer, computing credits/CO₂ and writing the
/// transaction through the offline-first repository.
class MintingCubit extends Cubit<MintingState> {
  MintingCubit({
    required ClassificationResult result,
    required TransactionRepository repo,
    required LocationService location,
    required PreferencesService prefs,
    double weightKg = 0,
    PoppProof? proof,
  }) : _result = result,
       _proof = proof,
       _repo = repo,
       _location = location,
       _prefs = prefs,
       super(
         proof != null
             // Weight comes from the signed scale reading.
             ? MintingState(
                 status: MintingStatus.editing,
                 selectedPolymer: result.polymer,
                 weightKg: weightKg,
               )
             // No scale: start from the suggestion; the operator types the
             // real weight.
             : MintingState(
                 status: MintingStatus.editing,
                 selectedPolymer: result.polymer,
                 weightKg: WeightEstimate.of(result.polymer.code, 1).kg,
                 weightSource: WeightSource.manual,
               ),
       );

  final ClassificationResult _result;
  final PoppProof? _proof;
  final TransactionRepository _repo;
  final LocationService _location;
  final PreferencesService _prefs;

  void selectPolymer(PolymerInfo polymer) {
    final next = state.copyWith(
      selectedPolymer: polymer,
      status: MintingStatus.editing,
    );
    emit(_followEstimate(next));
  }

  /// Operator typed a weight: it stays as typed from now on.
  void setWeight(String raw) {
    emit(
      state.copyWith(
        weightKg: parseWeightKg(raw),
        weightSource: WeightSource.manual,
        weightEdited: true,
        status: MintingStatus.editing,
      ),
    );
  }

  void setItemCount(int count) {
    emit(_followEstimate(state.copyWith(itemCount: count.clamp(1, 9999))));
  }

  /// Replace the typed weight with the suggestion.
  void useEstimate() {
    emit(
      state.copyWith(
        weightKg: state.estimate.kg,
        weightSource: WeightSource.manual,
        weightEdited: false,
      ),
    );
  }

  /// Drop the scale reading and type the weight instead. The record is then
  /// saved without the scale proof.
  void enterWeightManually() {
    emit(
      state.copyWith(
        weightKg: state.estimate.kg,
        weightSource: WeightSource.manual,
        weightEdited: false,
      ),
    );
  }

  MintingState _followEstimate(MintingState s) =>
      s.isManualWeight && !s.weightEdited
      ? s.copyWith(weightKg: s.estimate.kg)
      : s;

  Future<void> mint() async {
    if (state.weightKg <= 0 || state.weightKg >= maxWeightKg) {
      emit(
        state.copyWith(
          status: MintingStatus.error,
          error: 'Enter a valid weight in kg.',
        ),
      );
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
      // The model's probability for the resin actually recorded, so a manual
      // override never shows up as a confident AI call.
      confidence: _result.confidenceFor(polymer.code),
      weightKg: state.weightKg,
      creditsMinted: state.creditsPreview,
      co2SavedKg: state.co2Preview,
      lat: geo?.lat,
      lng: geo?.lng,
      timestamp: DateTime.now(),
      status: TransactionStatus.verified,
      verification: verificationOf(_result, polymer),
      aiPolymerCode: _result.polymer.code,
      aiConfidence: _result.confidence,
      modelVersion: _result.modelVersion,
      // The scale proof only backs a weight that came from the scale.
      popp: state.isManualWeight ? null : _proof?.toJson(),
      weightSource: state.weightSource.wire,
      weightEstimate: state.isManualWeight ? state.estimate.toJson() : null,
    );

    try {
      final syncedOnline = await _repo.mint(tx);
      emit(
        state.copyWith(
          status: syncedOnline
              ? MintingStatus.mintedOnline
              : MintingStatus.mintedOffline,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: MintingStatus.error,
          error: 'Minting failed. Please try again.',
        ),
      );
    }
  }
}
