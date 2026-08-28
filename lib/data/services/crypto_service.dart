import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

/// Cryptographic fingerprinting for the anti-fraud layer.
///
///  * [sha256Hex]        — exact tamper-evidence over the payload / image bytes.
///  * [perceptualHash]   — DCT-based 64-bit pHash; near-duplicate detection so
///    the same bale re-photographed slightly differently is flagged cloud-side.
///  * [payloadSha256]    — canonical hash over the outgoing signed JSON.
///
/// Why both SHA-256 and pHash: SHA-256 changes completely on a single-pixel
/// edit (great for tamper-detection, useless for "same bale, new photo").
/// Perceptual hashing yields *similar* hashes for *similar* images, catching
/// re-photograph double-mints. Using both gives tamper-evidence AND dedup.
class CryptoService {
  static const _pDctSize = 32; // DCT input resolution
  static const _pHashSize = 8; // low-freq block edge -> 64-bit hash

  /// Hex SHA-256 of raw bytes.
  String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

  /// Canonical SHA-256 over a JSON map (keys sorted for determinism).
  String payloadSha256(Map<String, dynamic> payload) {
    final sorted = _sortedJson(payload);
    return sha256Hex(utf8.encode(sorted));
  }

  String _sortedJson(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      final buf = StringBuffer('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) buf.write(',');
        buf.write(jsonEncode(keys[i]));
        buf.write(':');
        buf.write(_sortedJson(v[keys[i]]));
      }
      buf.write('}');
      return buf.toString();
    }
    if (v is List) return '[${v.map(_sortedJson).join(',')}]';
    return jsonEncode(v);
  }

  /// 64-bit DCT perceptual hash as a 16-char hex string. Returns null if the
  /// image can't be decoded.
  String? perceptualHash(Uint8List imageBytes) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return null;

    // grayscale, shrink to DCT input size
    final small = img.copyResize(
      img.grayscale(decoded),
      width: _pDctSize,
      height: _pDctSize,
    );
    final g = List.generate(
      _pDctSize,
      (y) => List.generate(_pDctSize, (x) => small.getPixel(x, y).r.toDouble()),
    );

    final dct = _dct2dLowFreq(g, _pHashSize);

    // average of the low-freq block excluding the DC term
    var sum = 0.0;
    for (var u = 0; u < _pHashSize; u++) {
      for (var v = 0; v < _pHashSize; v++) {
        if (u == 0 && v == 0) continue;
        sum += dct[u][v];
      }
    }
    final avg = sum / (_pHashSize * _pHashSize - 1);

    // bit = coefficient > average
    final bits = <int>[];
    for (var u = 0; u < _pHashSize; u++) {
      for (var v = 0; v < _pHashSize; v++) {
        bits.add(dct[u][v] > avg ? 1 : 0);
      }
    }
    return _bitsToHex(bits);
  }

  /// Hamming distance between two hex pHashes (0 = identical). Cloud dedup flags
  /// pairs below a small threshold (e.g. ≤ 8/64) as the same physical batch.
  int hammingDistance(String hexA, String hexB) {
    if (hexA.length != hexB.length) return 64;
    var d = 0;
    for (var i = 0; i < hexA.length; i++) {
      var x = int.parse(hexA[i], radix: 16) ^ int.parse(hexB[i], radix: 16);
      while (x != 0) {
        d += x & 1;
        x >>= 1;
      }
    }
    return d;
  }

  /// Separable 2D DCT-II, computing only the top-left [k]×[k] low-freq block.
  List<List<double>> _dct2dLowFreq(List<List<double>> g, int k) {
    final n = g.length;
    // cosine table: cos[(2i+1)·u·π / 2n] for u<k, i<n
    final cos = List.generate(
      k,
      (u) => List.generate(
        n,
        (i) => math.cos((2 * i + 1) * u * math.pi / (2 * n)),
      ),
    );
    final out = List.generate(k, (_) => List.filled(k, 0.0));
    for (var u = 0; u < k; u++) {
      for (var v = 0; v < k; v++) {
        var acc = 0.0;
        for (var x = 0; x < n; x++) {
          for (var y = 0; y < n; y++) {
            acc += g[x][y] * cos[u][x] * cos[v][y];
          }
        }
        out[u][v] = acc;
      }
    }
    return out;
  }

  String _bitsToHex(List<int> bits) {
    final buf = StringBuffer();
    for (var i = 0; i < bits.length; i += 4) {
      var nibble = 0;
      for (var j = 0; j < 4; j++) {
        nibble = (nibble << 1) | bits[i + j];
      }
      buf.write(nibble.toRadixString(16));
    }
    return buf.toString();
  }
}
