import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Turns a camera frame into the classifier's input tensor, matching the
/// training-time preprocessing in `PolyMint_ML/src/preprocessing.py`:
///
///  1. decode and apply the EXIF orientation,
///  2. center-crop the largest square,
///  3. resize to the model size with PIL-style *antialiased* bilinear
///     resampling (a triangle filter whose support widens when downscaling),
///  4. scale to `[0, 1]`, NHWC.
///
/// Step 3 matters: `package:image`'s nearest/linear resize skips most source
/// pixels on a large downscale, which flipped about 1 in 6 predictions of the
/// v2 model on full-size photos compared with the training preprocessing.
class ImagePreprocessor {
  const ImagePreprocessor._();

  /// Returns a `[1, size, size, 3]` tensor, or null if [bytes] can't be decoded.
  static List<List<List<List<double>>>>? toTensor(Uint8List bytes, int size) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final oriented = img.bakeOrientation(decoded);

    final side = math.min(oriented.width, oriented.height);
    final square = img.copyCrop(
      oriented,
      x: (oriented.width - side) ~/ 2,
      y: (oriented.height - side) ~/ 2,
      width: side,
      height: side,
    );

    final rgb = _resizeAntialiased(_toRgbFloats(square), side, side, size, size);
    return [
      List.generate(size, (y) {
        return List.generate(size, (x) {
          final i = (y * size + x) * 3;
          return [rgb[i], rgb[i + 1], rgb[i + 2]];
        });
      }),
    ];
  }

  /// Interleaved RGB in `[0, 1]`.
  static Float32List _toRgbFloats(img.Image image) {
    final out = Float32List(image.width * image.height * 3);
    var i = 0;
    for (final p in image) {
      out[i++] = p.rNormalized.toDouble();
      out[i++] = p.gNormalized.toDouble();
      out[i++] = p.bNormalized.toDouble();
    }
    return out;
  }

  /// Separable triangle-filter resample (PIL `Image.BILINEAR` semantics):
  /// horizontal pass, then vertical pass.
  static Float32List _resizeAntialiased(
      Float32List src, int inW, int inH, int outW, int outH) {
    final horizontal = Float32List(outW * inH * 3);
    final xs = _weights(inW, outW);
    for (var y = 0; y < inH; y++) {
      for (var x = 0; x < outW; x++) {
        final k = xs[x];
        var r = 0.0, g = 0.0, b = 0.0;
        for (var j = 0; j < k.weights.length; j++) {
          final s = (y * inW + k.start + j) * 3;
          final w = k.weights[j];
          r += src[s] * w;
          g += src[s + 1] * w;
          b += src[s + 2] * w;
        }
        final d = (y * outW + x) * 3;
        horizontal[d] = r;
        horizontal[d + 1] = g;
        horizontal[d + 2] = b;
      }
    }

    final out = Float32List(outW * outH * 3);
    final ys = _weights(inH, outH);
    for (var y = 0; y < outH; y++) {
      final k = ys[y];
      for (var x = 0; x < outW; x++) {
        var r = 0.0, g = 0.0, b = 0.0;
        for (var j = 0; j < k.weights.length; j++) {
          final s = ((k.start + j) * outW + x) * 3;
          final w = k.weights[j];
          r += horizontal[s] * w;
          g += horizontal[s + 1] * w;
          b += horizontal[s + 2] * w;
        }
        final d = (y * outW + x) * 3;
        out[d] = r.clamp(0.0, 1.0);
        out[d + 1] = g.clamp(0.0, 1.0);
        out[d + 2] = b.clamp(0.0, 1.0);
      }
    }
    return out;
  }

  /// Per-output-pixel source range and normalised triangle weights,
  /// following Pillow's `precompute_coeffs`.
  static List<_Kernel> _weights(int inSize, int outSize) {
    final scale = inSize / outSize;
    final filterScale = math.max(scale, 1.0);
    final support = 1.0 * filterScale; // bilinear filter support is 1
    return List.generate(outSize, (i) {
      final center = (i + 0.5) * scale;
      final start = math.max((center - support + 0.5).floor(), 0);
      final end = math.min((center + support + 0.5).floor(), inSize);
      final weights = List<double>.generate(end - start, (j) {
        final t = ((start + j) - center + 0.5) / filterScale;
        return math.max(0.0, 1.0 - t.abs());
      });
      final total = weights.fold<double>(0, (a, b) => a + b);
      return _Kernel(
          start, total == 0 ? weights : weights.map((w) => w / total).toList());
    });
  }
}

class _Kernel {
  final int start;
  final List<double> weights;
  const _Kernel(this.start, this.weights);
}
