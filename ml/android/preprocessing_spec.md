# On-Device Preprocessing Spec (Flutter / Dart)

**This is a contract.** The `.tflite` models were trained + validated against the
exact preprocessing below (`src/preprocessing.py`). The Flutter app **must**
reproduce it byte-for-byte, or on-device accuracy drops even though the model is
correct. Mismatched preprocessing is the single most common on-device bug.

The Python parity check (`src/verify_parity.py`) is the source of truth — keep it
green, and mirror whatever it validates here.

## Model I/O

| | Value |
|---|---|
| Input shape | `[1, 224, 224, 3]` (NHWC) — read the actual shape from the interpreter to be safe |
| Input dtype | `float32` |
| Color order | **RGB** (not BGR) |
| Pixel scale | `pixel / 255.0` → range `[0.0, 1.0]` |
| Mean / Std | mean `(0,0,0)`, std `(1,1,1)` → **no ImageNet normalization** |
| Output | `[1, numClasses]` probabilities (already softmaxed by the head) |
| Class order | from the sidecar `*.labels.txt` (index = row number, 0-based) |
| Confidence gate | `< 0.85` → `MANUAL_REVIEW` (never auto-mint) |

## Steps (must match exactly)

1. Decode camera image → RGB, drop alpha.
2. Resize **shorter side** to 224 (bilinear), preserve aspect ratio.
3. **Center-crop** 224×224.
4. `float32`, divide each channel by `255.0`.
5. Fill an NHWC `[1,224,224,3]` buffer, channel order R,G,B.

## Dart reference (using `tflite_flutter` + `image` package)

```dart
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

const int kSize = 224;
const double kGate = 0.85;

/// Resize shorter side -> kSize, then center-crop kSize x kSize (matches Python).
img.Image _resizeCenterCrop(img.Image src) {
  final scale = kSize / (src.width < src.height ? src.width : src.height);
  final resized = img.copyResize(
    src,
    width: (src.width * scale).round(),
    height: (src.height * scale).round(),
    interpolation: img.Interpolation.linear, // bilinear
  );
  final left = ((resized.width - kSize) / 2).floor();
  final top = ((resized.height - kSize) / 2).floor();
  return img.copyCrop(resized, x: left, y: top, width: kSize, height: kSize);
}

/// Build NHWC [1,224,224,3] float32 tensor, RGB, scaled to [0,1].
List<List<List<List<double>>>> preprocess(img.Image raw) {
  final im = _resizeCenterCrop(raw);
  return [
    List.generate(kSize, (y) => List.generate(kSize, (x) {
      final p = im.getPixel(x, y);
      return [p.r / 255.0, p.g / 255.0, p.b / 255.0]; // R,G,B order
    })),
  ];
}

/// Run the polymer model and apply the confidence gate.
({String polymer, double confidence, String status}) classify(
    Interpreter interp, List<String> labels, img.Image raw) {
  final input = preprocess(raw);
  final output = List.filled(labels.length, 0.0).reshape([1, labels.length]);
  interp.run(input, output);

  final probs = (output[0] as List).cast<double>();
  var best = 0;
  for (var i = 1; i < probs.length; i++) {
    if (probs[i] > probs[best]) best = i;
  }
  final conf = probs[best];
  return (
    polymer: labels[best],
    confidence: conf,
    status: conf >= kGate ? 'AI_VERIFIED' : 'MANUAL_REVIEW',
  );
}
```

## Ship these together
- `models/polymer_float32.tflite` + `models/polymer.labels.txt`
- `models/purity_float32.tflite`  + `models/purity.labels.txt`  (run the same pipeline twice)
- Load labels from the `.txt` at runtime — never hard-code class order in Dart.

## Sanity checklist before demo
- [ ] `verify_parity.py` is green for both models on your machine.
- [ ] Same image → same top-1 class in Python and in the app.
- [ ] Inference latency measured on the **actual target phone** (< 1 s target).
- [ ] Gate wired: a low-confidence capture routes to MANUAL_REVIEW, not mint.
