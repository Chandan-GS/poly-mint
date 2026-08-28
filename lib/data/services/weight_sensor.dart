import 'package:equatable/equatable.dart';

/// Connection lifecycle of a [WeightSensor], independent of transport (BLE/sim).
enum SensorConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

/// One weight reading from the scale. [kg] is tared (zeroed) mass; [stable] is
/// the sensor's own settling flag (mass held within a tolerance band for the
/// firmware's rolling window). [seq] lets the PoPP engine detect dropped
/// samples / replay, and [timestampMs] is the device clock at capture.
class WeightSample extends Equatable {
  final double kg;
  final bool stable;
  final int seq;
  final int timestampMs;

  const WeightSample({
    required this.kg,
    required this.stable,
    required this.seq,
    required this.timestampMs,
  });

  Map<String, dynamic> toJson() => {
        'kg': kg,
        'stable': stable,
        'seq': seq,
        't': timestampMs,
      };

  @override
  List<Object?> get props => [kg, stable, seq, timestampMs];
}

/// Abstraction over the physical scale. The whole PoPP pipeline consumes this
/// interface, so it never knows whether a real BLE load-cell or the simulator
/// is behind it — that switch lives entirely in DI + settings.
///
/// Implementations:
///  * [BleWeightSensor]        — real ESP32 + HX711 over BLE.
///  * [SimulatedWeightSensor]  — replays a realistic settle curve (no hardware).
abstract class WeightSensor {
  /// True for the simulator — surfaced in the UI so a verified batch built on
  /// simulated mass is never mistaken for a hardware-proven one.
  bool get isSimulated;

  /// Live connection state (broadcast).
  Stream<SensorConnectionState> get connectionState;
  SensorConnectionState get currentState;

  /// ~20 Hz stream of tared weight samples (broadcast).
  Stream<WeightSample> get samples;

  /// Most recent sample, or null before the first reading.
  WeightSample? get latest;

  /// Connect: BLE scan+connect+subscribe, or start the simulator.
  Future<void> connect();

  /// Zero the scale at the current load (tare).
  Future<void> tare();

  /// Disconnect / stop streaming (idempotent).
  Future<void> disconnect();

  void dispose();
}

/// Shared BLE contract between [BleWeightSensor] and the ESP32 firmware.
/// Keep these in lockstep with the firmware's GATT definitions.
class PoppBleContract {
  /// Primary service advertised by the PolyMint node.
  static const String serviceUuid = '5f1d0000-9b2a-4e2c-8a1b-2c9f9a0e1d10';

  /// Weight characteristic (NOTIFY). Packet = 12 bytes, little-endian:
  ///   [0..3]  int32  milligrams (tared)
  ///   [4]     uint8  flags (bit0 = stable)
  ///   [5]     uint8  seq (wraps 0..255)
  ///   [6..9]  uint32 device timestamp (ms)
  ///   [10..11] uint16 reserved
  static const String weightCharUuid = '5f1d0001-9b2a-4e2c-8a1b-2c9f9a0e1d10';

  /// Command characteristic (WRITE). 1 byte: 0x01 = tare.
  static const String commandCharUuid = '5f1d0002-9b2a-4e2c-8a1b-2c9f9a0e1d10';

  static const int cmdTare = 0x01;
  static const int flagStable = 0x01;
}
