import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/popp_proof.dart';
import 'weight_sensor.dart';

/// Arming state of the physical-presence check, surfaced to the scan UI.
enum PoppArmState {
  /// Sensor not delivering usable data yet.
  idle,

  /// Scale is empty — waiting for a batch to be placed.
  waitingForMass,

  /// Mass detected, waiting for it to settle within the stable band.
  settling,

  /// Weight held steady long enough — camera may fire now.
  armed,
}

/// The sensor-fusion core. Consumes a [WeightSensor] stream, tracks when a real
/// mass has been placed and held steady ("armed"), and — when the camera fires
/// — emits a [PoppProof] binding that weight window to the capture instant.
///
/// Attacks it defeats:
///  * printed photo / replayed video → no mass on the cell → FAIL_NO_MASS
///  * typed / faked weight            → weight is streamed+hashed, not entered
///  * capture outside the steady window → FAIL_UNSTABLE
class PoppEngine {
  PoppEngine(
    this._sensor, {
    this.massThresholdKg = 0.03,
    this.stableWindowMs = 600,
  });

  final WeightSensor _sensor;

  /// Minimum mass to consider "something is on the scale".
  final double massThresholdKg;

  /// How long the weight must stay `stable` before we arm the camera.
  final int stableWindowMs;

  final _armCtrl = StreamController<PoppArmState>.broadcast();
  StreamSubscription<WeightSample>? _sub;

  PoppArmState _state = PoppArmState.idle;
  double _baselineKg = 0;
  double _plateauKg = 0;
  int? _stableSinceMs; // when the current stable run began
  final List<WeightSample> _windowSamples = []; // samples during the stable run

  Stream<PoppArmState> get armState => _armCtrl.stream;
  PoppArmState get state => _state;
  bool get isArmed => _state == PoppArmState.armed;
  double get currentKg => _sensor.latest?.kg ?? 0;

  void _setState(PoppArmState s) {
    if (s == _state) return;
    _state = s;
    if (!_armCtrl.isClosed) _armCtrl.add(s);
  }

  /// Begin watching the sensor. Call after the sensor is connected.
  void start() {
    _reset();
    _sub?.cancel();
    _sub = _sensor.samples.listen(_onSample);
  }

  void _reset() {
    _setState(_sensor.latest == null
        ? PoppArmState.idle
        : PoppArmState.waitingForMass);
    _baselineKg = _sensor.latest?.kg ?? 0;
    _plateauKg = 0;
    _stableSinceMs = null;
    _windowSamples.clear();
  }

  void _onSample(WeightSample s) {
    if (s.kg < massThresholdKg) {
      // Scale (near) empty — track baseline, disarm.
      _baselineKg = s.kg;
      _stableSinceMs = null;
      _windowSamples.clear();
      _setState(PoppArmState.waitingForMass);
      return;
    }

    // Something is loaded.
    if (!s.stable) {
      _stableSinceMs = null;
      _windowSamples.clear();
      _setState(PoppArmState.settling);
      return;
    }

    // Loaded AND stable — accumulate the steady window.
    _stableSinceMs ??= s.timestampMs;
    _windowSamples.add(s);
    _plateauKg = s.kg;

    final heldMs = s.timestampMs - _stableSinceMs!;
    if (heldMs >= stableWindowMs) {
      _setState(PoppArmState.armed);
    } else {
      _setState(PoppArmState.settling);
    }
  }

  /// Fold the sample stream into a SHA-256 hash chain:
  ///   h₀ = SHA256(sample₀);  hᵢ = SHA256(hᵢ₋₁ ‖ sampleᵢ)
  /// Altering, dropping or reordering any sample changes the final digest.
  String _hashChain(List<WeightSample> samples) {
    var acc = '';
    for (final s in samples) {
      final payload = '$acc|${jsonEncode(s.toJson())}';
      acc = sha256.convert(utf8.encode(payload)).toString();
    }
    return acc;
  }

  /// Called the moment the camera captures. Correlates the capture time with
  /// the steady-weight window and returns the signed proof. This is where a
  /// photo/replay (no mass) is rejected.
  PoppProof capture({required int captureTimeMs}) {
    final loaded = currentKg >= massThresholdKg;

    if (!loaded) {
      return PoppProof(
        settleDeltaKg: 0,
        stableWindowMs: 0,
        captureOffsetMs: 0,
        sampleHashChain: _hashChain(_windowSamples),
        sampleCount: _windowSamples.length,
        simulated: _sensor.isSimulated,
        verdict: PoppVerdict.failNoMass,
      );
    }

    if (_state != PoppArmState.armed || _stableSinceMs == null) {
      return PoppProof(
        settleDeltaKg: _plateauKg - _baselineKg,
        stableWindowMs: 0,
        captureOffsetMs: 0,
        sampleHashChain: _hashChain(_windowSamples),
        sampleCount: _windowSamples.length,
        simulated: _sensor.isSimulated,
        verdict: PoppVerdict.failUnstable,
      );
    }

    final windowStart = _stableSinceMs!;
    final heldMs = (_sensor.latest?.timestampMs ?? captureTimeMs) - windowStart;
    final offset = captureTimeMs - windowStart;

    // Capture must land inside the steady window.
    final withinWindow = offset >= 0 && offset <= heldMs + stableWindowMs;
    final verdict = withinWindow ? PoppVerdict.pass : PoppVerdict.failUnstable;

    return PoppProof(
      settleDeltaKg: _plateauKg - _baselineKg,
      stableWindowMs: heldMs,
      captureOffsetMs: offset,
      sampleHashChain: _hashChain(_windowSamples),
      sampleCount: _windowSamples.length,
      simulated: _sensor.isSimulated,
      verdict: verdict,
    );
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  void dispose() {
    _sub?.cancel();
    _armCtrl.close();
  }
}
