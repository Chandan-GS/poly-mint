import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/classification_result.dart';
import '../../../data/models/popp_proof.dart';
import '../../../data/services/ml_service.dart';
import '../../../data/services/popp_engine.dart';
import '../../../data/services/simulated_weight_sensor.dart';
import '../../../data/services/weight_sensor.dart';

enum ScanPhase { loading, live, classifying, rejected, success, error }

class ScanState extends Equatable {
  final ScanPhase phase;
  final PoppArmState armState;
  final double liveKg;
  final bool simulated;
  final ClassificationResult? result;
  final PoppProof? proof;
  final String? rejectReason;
  final String? error;

  const ScanState({
    this.phase = ScanPhase.loading,
    this.armState = PoppArmState.idle,
    this.liveKg = 0,
    this.simulated = false,
    this.result,
    this.proof,
    this.rejectReason,
    this.error,
  });

  bool get isArmed => armState == PoppArmState.armed;

  ScanState copyWith({
    ScanPhase? phase,
    PoppArmState? armState,
    double? liveKg,
    bool? simulated,
    ClassificationResult? result,
    PoppProof? proof,
    String? rejectReason,
    String? error,
  }) {
    return ScanState(
      phase: phase ?? this.phase,
      armState: armState ?? this.armState,
      liveKg: liveKg ?? this.liveKg,
      simulated: simulated ?? this.simulated,
      result: result ?? this.result,
      proof: proof ?? this.proof,
      rejectReason: rejectReason,
      error: error,
    );
  }

  @override
  List<Object?> get props =>
      [phase, armState, liveKg, simulated, result, proof, rejectReason, error];
}

/// Drives the scan flow: on-device classification + the PoPP sensor-fusion
/// check. The camera lives in the widget; this cubit owns the model, the weight
/// sensor and the arming logic so it stays testable.
class ScanCubit extends Cubit<ScanState> {
  ScanCubit(this._ml, this._sensor)
      : _popp = PoppEngine(_sensor),
        super(ScanState(simulated: _sensor.isSimulated)) {
    _init();
  }

  final MlService _ml;
  final WeightSensor _sensor;
  final PoppEngine _popp;
  StreamSubscription<PoppArmState>? _armSub;
  StreamSubscription<WeightSample>? _sampleSub;

  Future<void> _init() async {
    try {
      await _ml.load();
      await _sensor.connect();
      _popp.start();
      _armSub = _popp.armState.listen((a) {
        if (state.phase == ScanPhase.live || state.phase == ScanPhase.loading) {
          emit(state.copyWith(phase: ScanPhase.live, armState: a));
        }
      });
      _sampleSub = _sensor.samples.listen((s) {
        if (state.phase == ScanPhase.live) {
          emit(state.copyWith(liveKg: s.kg));
        }
      });
      emit(state.copyWith(phase: ScanPhase.live));
    } catch (_) {
      emit(state.copyWith(
        phase: ScanPhase.error,
        error: 'Could not start the scanner. Please restart.',
      ));
    }
  }

  /// Camera fired: bind the capture to the weight window, then classify.
  Future<void> capture(List<Uint8List> frames) async {
    if (state.phase == ScanPhase.classifying) return;

    // 1) Physical-presence check first — reject photos/replays immediately.
    final captureMs =
        _sensor.latest?.timestampMs ?? DateTime.now().millisecondsSinceEpoch;
    final proof = _popp.capture(captureTimeMs: captureMs);
    if (!proof.verdict.isPass) {
      emit(state.copyWith(
        phase: ScanPhase.rejected,
        proof: proof,
        rejectReason: proof.verdict.humanReason,
      ));
      return;
    }

    // 2) Presence verified → run the classifier.
    emit(state.copyWith(phase: ScanPhase.classifying));
    try {
      final result = await _ml.classify(frames);
      emit(state.copyWith(
          phase: ScanPhase.success, result: result, proof: proof));
    } catch (_) {
      emit(state.copyWith(
        phase: ScanPhase.error,
        error: 'Could not read the image. Hold steady and retry.',
      ));
    }
  }

  /// Back to live scanning after a result or rejection was handled.
  void reset() {
    _popp.start();
    emit(ScanState(
        phase: ScanPhase.live,
        simulated: _sensor.isSimulated,
        armState: _popp.state,
        liveKg: _sensor.latest?.kg ?? 0));
  }

  /// Simulator only: re-trigger a placement (wired to a demo button).
  void simulatePlacement() {
    final s = _sensor;
    if (s is SimulatedWeightSensor) s.triggerPlacement();
  }

  @override
  Future<void> close() {
    _armSub?.cancel();
    _sampleSub?.cancel();
    _popp.dispose();
    _sensor.dispose();
    return super.close();
  }
}
