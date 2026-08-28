import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'weight_sensor.dart';

/// Real [WeightSensor] backed by the ESP32 + HX711 rig over BLE.
///
/// Protocol is defined in [PoppBleContract] and must match the firmware:
/// subscribe to the weight NOTIFY characteristic (12-byte packets at ~20 Hz),
/// write 0x01 to the command characteristic to tare.
///
/// This is written to be correct against the flutter_blue_plus 1.32 API; it
/// needs on-device testing once the hardware exists (BLE can't be exercised in
/// CI or the simulator).
class BleWeightSensor implements WeightSensor {
  BleWeightSensor({this.scanTimeout = const Duration(seconds: 12)});

  final Duration scanTimeout;

  final _stateCtrl = StreamController<SensorConnectionState>.broadcast();
  final _sampleCtrl = StreamController<WeightSample>.broadcast();

  SensorConnectionState _state = SensorConnectionState.disconnected;
  WeightSample? _latest;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _weightChar;
  BluetoothCharacteristic? _commandChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  @override
  bool get isSimulated => false;

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
    try {
      if (!(await FlutterBluePlus.isSupported)) {
        _setState(SensorConnectionState.error);
        throw StateError('BLE not supported on this device.');
      }
      _setState(SensorConnectionState.scanning);

      final serviceGuid = Guid(PoppBleContract.serviceUuid);
      final found = Completer<BluetoothDevice>();

      _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          if (!found.isCompleted) {
            found.complete(r.device);
          }
        }
      });

      await FlutterBluePlus.startScan(
        withServices: [serviceGuid],
        timeout: scanTimeout,
      );

      final device = await found.future.timeout(
        scanTimeout,
        onTimeout: () => throw TimeoutException('No PolyMint node found.'),
      );
      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();

      _setState(SensorConnectionState.connecting);
      _device = device;
      _connSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected &&
            _state == SensorConnectionState.connected) {
          _setState(SensorConnectionState.disconnected);
        }
      });
      await device.connect(timeout: const Duration(seconds: 10));

      await _discover(device);
      _setState(SensorConnectionState.connected);
    } catch (e) {
      _setState(SensorConnectionState.error);
      rethrow;
    }
  }

  Future<void> _discover(BluetoothDevice device) async {
    final services = await device.discoverServices();
    final svc = services.firstWhere(
      (s) => s.uuid == Guid(PoppBleContract.serviceUuid),
      orElse: () => throw StateError('PoPP service not found on node.'),
    );
    for (final c in svc.characteristics) {
      if (c.uuid == Guid(PoppBleContract.weightCharUuid)) _weightChar = c;
      if (c.uuid == Guid(PoppBleContract.commandCharUuid)) _commandChar = c;
    }
    if (_weightChar == null) {
      throw StateError('Weight characteristic missing.');
    }
    await _weightChar!.setNotifyValue(true);
    _notifySub?.cancel();
    _notifySub = _weightChar!.lastValueStream.listen(_onPacket);
  }

  /// Parse a 12-byte little-endian weight packet (see [PoppBleContract]).
  void _onPacket(List<int> data) {
    if (data.length < 10) return;
    final bytes = ByteData.sublistView(Uint8List.fromList(data));
    final milligrams = bytes.getInt32(0, Endian.little);
    final flags = bytes.getUint8(4);
    final seq = bytes.getUint8(5);
    final deviceTs = bytes.getUint32(6, Endian.little);

    final sample = WeightSample(
      kg: milligrams / 1e6,
      stable: (flags & PoppBleContract.flagStable) != 0,
      seq: seq,
      timestampMs: deviceTs,
    );
    _latest = sample;
    if (!_sampleCtrl.isClosed) _sampleCtrl.add(sample);
  }

  @override
  Future<void> tare() async {
    final cmd = _commandChar;
    if (cmd == null) return;
    await cmd.write([PoppBleContract.cmdTare], withoutResponse: false);
  }

  @override
  Future<void> disconnect() async {
    await _notifySub?.cancel();
    await _connSub?.cancel();
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
    _weightChar = null;
    _commandChar = null;
    _setState(SensorConnectionState.disconnected);
  }

  @override
  void dispose() {
    _notifySub?.cancel();
    _connSub?.cancel();
    _scanSub?.cancel();
    _stateCtrl.close();
    _sampleCtrl.close();
  }
}
