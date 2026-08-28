import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:poly_mint/data/models/popp_proof.dart';
import 'package:poly_mint/data/services/crypto_service.dart';
import 'package:poly_mint/data/services/popp_engine.dart';
import 'package:poly_mint/data/services/weight_sensor.dart';

/// Controllable sensor so we can drive the engine deterministically (real time
/// comes from sample timestamps, so tests are fast and stable).
class FakeWeightSensor implements WeightSensor {
  final _samples = StreamController<WeightSample>.broadcast();
  WeightSample? _latest;
  @override
  bool isSimulated;

  FakeWeightSensor({this.isSimulated = false});

  void push({required double kg, required bool stable, required int seq, required int t}) {
    _latest = WeightSample(kg: kg, stable: stable, seq: seq, timestampMs: t);
    _samples.add(_latest!);
  }

  @override
  Stream<WeightSample> get samples => _samples.stream;
  @override
  WeightSample? get latest => _latest;
  @override
  Stream<SensorConnectionState> get connectionState => const Stream.empty();
  @override
  SensorConnectionState get currentState => SensorConnectionState.connected;
  @override
  Future<void> connect() async {}
  @override
  Future<void> tare() async {}
  @override
  Future<void> disconnect() async {}
  @override
  void dispose() => _samples.close();
}

/// Let queued stream events flush.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('PoppEngine — sensor-fusion verdicts', () {
    test('PASS: mass placed, held steady, capture inside window', () async {
      final sensor = FakeWeightSensor();
      final engine = PoppEngine(sensor, stableWindowMs: 600)..start();

      // batch placed, settling then stable across 700 ms (> 600 window)
      sensor.push(kg: 0.0, stable: false, seq: 0, t: 900);
      await settle();
      for (var i = 0; i <= 7; i++) {
        sensor.push(kg: 1.20, stable: true, seq: i + 1, t: 1000 + i * 100);
        await settle();
      }
      expect(engine.isArmed, isTrue, reason: 'held steady long enough to arm');

      final proof = engine.capture(captureTimeMs: 1700);
      expect(proof.verdict, PoppVerdict.pass);
      expect(proof.weightKg, closeTo(1.20, 0.001));
      expect(proof.sampleCount, greaterThan(0));
      expect(proof.sampleHashChain, isNotEmpty);
      engine.dispose();
    });

    test('FAIL_NO_MASS: printed photo — nothing on the scale at capture',
        () async {
      final sensor = FakeWeightSensor();
      final engine = PoppEngine(sensor, stableWindowMs: 600)..start();

      // arm with real mass...
      for (var i = 0; i <= 7; i++) {
        sensor.push(kg: 0.8, stable: true, seq: i, t: 1000 + i * 100);
        await settle();
      }
      // ...then the batch is lifted and a photo is shown -> mass returns to 0
      sensor.push(kg: 0.0, stable: false, seq: 99, t: 1800);
      await settle();

      final proof = engine.capture(captureTimeMs: 1800);
      expect(proof.verdict, PoppVerdict.failNoMass,
          reason: 'no correlated mass => rejected as photo/replay');
      engine.dispose();
    });

    test('FAIL_UNSTABLE: weight never settles', () async {
      final sensor = FakeWeightSensor();
      final engine = PoppEngine(sensor, stableWindowMs: 600)..start();
      for (var i = 0; i < 6; i++) {
        sensor.push(kg: 0.5 + i * 0.1, stable: false, seq: i, t: 1000 + i * 100);
        await settle();
      }
      expect(engine.isArmed, isFalse);
      final proof = engine.capture(captureTimeMs: 1500);
      expect(proof.verdict, PoppVerdict.failUnstable);
      engine.dispose();
    });
  });

  group('CryptoService', () {
    final crypto = CryptoService();

    test('payloadSha256 is deterministic regardless of key order', () {
      final a = crypto.payloadSha256({'b': 2, 'a': 1, 'nested': {'y': 9, 'x': 8}});
      final b = crypto.payloadSha256({'a': 1, 'nested': {'x': 8, 'y': 9}, 'b': 2});
      expect(a, equals(b));
      expect(a.length, 64);
    });

    test('pHash: identical image -> distance 0; different -> larger', () {
      final base = img.Image(width: 64, height: 64);
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          base.setPixelRgb(x, y, (x * 4) % 256, (y * 4) % 256, 128);
        }
      }
      final other = img.Image(width: 64, height: 64);
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          other.setPixelRgb(x, y, 255 - (x * 4) % 256, 20, (y * 2) % 256);
        }
      }
      final hBase = crypto.perceptualHash(img.encodePng(base))!;
      final hSame = crypto.perceptualHash(img.encodePng(base))!;
      final hDiff = crypto.perceptualHash(img.encodePng(other))!;

      expect(crypto.hammingDistance(hBase, hSame), 0);
      expect(crypto.hammingDistance(hBase, hDiff), greaterThan(0));
      expect(hBase.length, 16); // 64-bit hash
    });
  });
}
