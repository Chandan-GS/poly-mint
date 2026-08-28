#!/usr/bin/env python3
"""
verify_parity.py — prove the TFLite + our preprocessing == Ultralytics PyTorch.

This is the guardrail against the "works in Python, wrong on phone" trap. It runs
the SAME image through:
  (A) Ultralytics YOLO(best.pt).predict()          <- ground truth
  (B) our tflite + src/preprocessing.preprocess()  <- what the phone will do
and asserts the top-1 class matches and the probability vectors are close.

If this passes, android/preprocessing_spec.md is trustworthy and you can port it
to Dart with confidence. If it fails, fix preprocessing.py (and the Dart port)
until it passes — do NOT ship a model whose parity check is red.

Usage
-----
python src/verify_parity.py \
    --weights runs/polymer/weights/best.pt \
    --tflite models/polymer_float32.tflite \
    --img sample.jpg
"""
import argparse
from pathlib import Path

import numpy as np

from infer import _load_interpreter, _run


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--weights", required=True)
    ap.add_argument("--tflite", required=True)
    ap.add_argument("--img", required=True)
    ap.add_argument("--imgsz", type=int, default=224)
    ap.add_argument("--atol", type=float, default=0.05,
                    help="max allowed abs diff in probabilities")
    args = ap.parse_args()

    from ultralytics import YOLO
    model = YOLO(args.weights)
    r = model.predict(args.img, imgsz=args.imgsz, verbose=False)[0]
    ref = r.probs.data.cpu().numpy().astype(np.float32)
    names = model.names

    interp = _load_interpreter(args.tflite)
    got = _run(interp, args.img, args.imgsz)

    ref_i, got_i = int(ref.argmax()), int(got.argmax())
    max_diff = float(np.max(np.abs(ref - got)))

    print(f"{'class':<12}{'ultralytics':>14}{'tflite':>12}")
    for i in range(len(names)):
        print(f"{names[i]:<12}{ref[i]:>14.4f}{got[i]:>12.4f}")
    print(f"\nUltralytics top-1: {names[ref_i]} ({ref[ref_i]:.1%})")
    print(f"TFLite      top-1: {names[got_i]} ({got[got_i]:.1%})")
    print(f"max abs prob diff : {max_diff:.4f}  (tol {args.atol})")

    ok = (ref_i == got_i) and (max_diff <= args.atol)
    print("\n" + ("✅ PARITY OK — safe to port preprocessing to Dart"
                  if ok else
                  "❌ PARITY FAILED — fix preprocessing.py before shipping"))
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()
