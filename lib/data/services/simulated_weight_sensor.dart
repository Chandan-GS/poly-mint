import 'dart:async';
import 'dart:math' as math;

import 'weight_sensor.dart';

/// A [WeightSensor] with no hardware behind it — it replays a physically
/// plausible "place a batch on the scale" curve so the whole PoPP pipeline runs
/// (and demos) without the ESP32 rig. This is the plan's de-risking "replay
/// sensor" mode.
///
/// Lifecycle after [connect]:
///   idle(~0 kg) → [triggerPlacement] (or auto) → ramp up → noisy settle →
///   `stable=true` once held within a tolerance band → hold → optional lift.
///
/// [isSimulated] is true so the UI can badge any batch built on it as
/// "SIMULATED — not hardware-proven".
class SimulatedWeightSensor implements WeightSensor {
  SimulatedWeightSensor({
    this.sampleRateHz = 20,
    this.autoPlaceOnConnect = true,
    math.Random? random,
  }) : _rng = random ?? math.Random();

  final int sampleRateHz;
  final bool autoPlaceOnConnect;
  final math.Random _rng;

  final _stateCtrl = StreamController<SensorConnectionState>.broadcast();
  final _sampleCtrl = StreamController<WeightSample>.broadcast();

  Timer? _timer;
  SensorConnectionState _state = SensorConnectionState.disconnected;
  WeightSample? _latest;

  // --- physical model state ---
  double _targetKg = 0; // where the mass is heading
  double _kg = 0; // current true mass
  double _tareOffset = 0; // subtracted from reported mass
  int _seq = 0;
  int _stableSamples = 0; // consecutive in-band samples
  static const _bandKg = 0.010; // ±10 g settling band
  static const _stableNeeded = 8; // ~0.4 s at 20 Hz

  @override
  bool get isSimulated => true;

  @override
  Stream<SensorConnectionState> get connectionState => _stateCtrl.stream;

  @override
  SensorConnectionState get currentState => _state;

  @override
  Stream<WeightSample> get samples => _sampleCtrl.stream;

  @override
  WeightSample? get latest => _latest;

  void _setState(SensorConnectionState s) {
    _state = s;
    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
  }

  @override
  Future<void> connect() async {
    if (_state == SensorConnectionState.connected) return;
    _setState(SensorConnectionState.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _setState(SensorConnectionState.connected);

    final periodMs = (1000 / sampleRateHz).round();
    _timer?.cancel();
    _timer = Timer.periodic(Duration(milliseconds: periodMs), (_) => _tick());

    if (autoPlaceOnConnect) {
      // Auto-run one place-and-settle a moment after connecting, so a demo
      // "just works". A UI button can also call [triggerPlacement] manually.
      Future<void>.delayed(
        const Duration(milliseconds: 1200),
        () => triggerPlacement(),
      );
    }
  }

  /// Simulate placing a plastic batch on the scale. [kg] defaults to a random
  /// realistic batch mass. Call again to simulate a new batch.
  void triggerPlacement({double? kg}) {
    _targetKg = kg ?? (0.15 + _rng.nextDouble() * 1.85); // 0.15–2.0 kg
    _stableSamples = 0;
  }

  /// Simulate lifting the batch off (mass returns toward zero).
  void triggerLift() {
    _targetKg = 0;
    _stableSamples = 0;
  }

  void _tick() {
    // First-order approach to target + small sensor noise.
    final delta = _targetKg - _kg;
    _kg += delta * 0.25; // ~4-sample time constant
    if (delta.abs() < 0.002) _kg = _targetKg;

    final noise = (_rng.nextDouble() - 0.5) * 0.004; // ±2 g
    final reported = math.max(0.0, _kg + noise - _tareOffset);

    // Stable when loaded and held within the band for enough samples.
    final loaded = reported > 0.03;
    final settledNow = loaded && (_targetKg - _kg).abs() < _bandKg;
    _stableSamples = settledNow ? _stableSamples + 1 : 0;
    final stable = _stableSamples >= _stableNeeded;

    final sample = WeightSample(
      kg: double.parse(reported.toStringAsFixed(3)),
      stable: stable,
      seq: _seq,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
    _seq = (_seq + 1) & 0xFF;
    _latest = sample;
    if (!_sampleCtrl.isClosed) _sampleCtrl.add(sample);
  }

  @override
  Future<void> tare() async {
    _tareOffset = _kg;
    _stableSamples = 0;
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _timer = null;
    _kg = 0;
    _targetKg = 0;
    _tareOffset = 0;
    _setState(SensorConnectionState.disconnected);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stateCtrl.close();
    _sampleCtrl.close();
  }
}
