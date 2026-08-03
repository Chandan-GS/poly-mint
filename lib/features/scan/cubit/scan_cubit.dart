import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/classification_result.dart';
import '../../../data/services/ml_service.dart';

enum ScanStatus { loadingModel, ready, classifying, success, error }

class ScanState extends Equatable {
  final ScanStatus status;
  final ClassificationResult? result;
  final String? error;

  const ScanState({
    this.status = ScanStatus.loadingModel,
    this.result,
    this.error,
  });

  ScanState copyWith({
    ScanStatus? status,
    ClassificationResult? result,
    String? error,
  }) {
    return ScanState(
      status: status ?? this.status,
      result: result ?? this.result,
      error: error,
    );
  }

  @override
  List<Object?> get props => [status, result, error];
}

/// Drives model loading and inference for the scan screen. The camera itself
/// is owned by the widget; this cubit only deals with the ML pipeline so it
/// stays testable.
class ScanCubit extends Cubit<ScanState> {
  ScanCubit(this._ml) : super(const ScanState()) {
    _init();
  }

  final MlService _ml;

  Future<void> _init() async {
    try {
      await _ml.load();
      emit(state.copyWith(status: ScanStatus.ready));
    } catch (e) {
      emit(state.copyWith(
        status: ScanStatus.error,
        error: 'Could not load the AI model. Please restart the app.',
      ));
    }
  }

  /// Run classification over one or more captured frames.
  Future<void> classify(List<Uint8List> frames) async {
    if (state.status == ScanStatus.classifying) return;
    emit(state.copyWith(status: ScanStatus.classifying));
    try {
      final result = await _ml.classify(frames);
      emit(state.copyWith(status: ScanStatus.success, result: result));
    } catch (e) {
      emit(state.copyWith(
        status: ScanStatus.error,
        error: 'Detection failed. Hold steady and try again.',
      ));
    }
  }

  /// Reset back to the live camera after a result was consumed.
  void reset() => emit(const ScanState(status: ScanStatus.ready));
}
