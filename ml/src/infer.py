#!/usr/bin/env python3
"""
infer.py — run the exported .tflite exactly like the phone will, incl. the gate.

Mirrors the plan's on-device inference flow:

    image -> resize 224 -> /255 -> tflite.run() -> softmax -> argmax
    IF confidence < 0.85 -> status = MANUAL_REVIEW   (never auto-mint)
    ELSE                  -> status = AI_VERIFIED     -> proceed to PoPP + hashing

Usage
-----
python src/infer.py --tflite models/polymer_float32.tflite \
    --labels models/polymer.labels.txt --img sample.jpg

# Combined polymer + purity (the full ML output the app consumes):
python src/infer.py \
    --tflite models/polymer_float32.tflite --labels models/polymer.labels.txt \
    --purity-tflite models/purity_float32.tflite --purity-labels models/purity.labels.txt \
    --img sample.jpg
"""
import argparse
import json
from pathlib import Path

import numpy as np

from preprocessing import preprocess, softmax

CONFIDENCE_GATE = 0.85  # plan: <85% -> MANUAL_REVIEW, never auto-mint


def _load_interpreter(path: str):
    # Prefer the standalone LiteRT runtime; fall back to TF's bundled one.
    try:
        from ai_edge_litert.interpreter import Interpreter  # newer package
    except ImportError:
        try:
            from tflite_runtime.interpreter import Interpreter
        except ImportError:
            from tensorflow.lite import Interpreter
    interp = Interpreter(model_path=str(path))
    interp.allocate_tensors()
    return interp


def _run(interp, img_path: str, size: int) -> np.ndarray:
    inp = interp.get_input_details()[0]
    out = interp.get_output_details()[0]
    h = inp["shape"][1] if len(inp["shape"]) == 4 else size
    x = preprocess(img_path, size=h)                       # NHWC [1,h,h,3]
    if list(inp["shape"])[1] == 3:                         # model wants NCHW
        x = np.transpose(x, (0, 3, 1, 2))
    interp.set_tensor(inp["index"], x.astype(inp["dtype"]))
    interp.invoke()
    probs = interp.get_tensor(out["index"])[0].astype(np.float32)
    if not np.isclose(probs.sum(), 1.0, atol=1e-2):        # logits -> probs
        probs = softmax(probs)
    return probs


def classify(interp, labels, img_path, size):
    probs = _run(interp, img_path, size)
    idx = int(np.argmax(probs))
    return labels[idx], float(probs[idx]), probs


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tflite", required=True, help="polymer model")
    ap.add_argument("--labels", required=True)
    ap.add_argument("--img", required=True)
    ap.add_argument("--purity-tflite", default=None)
    ap.add_argument("--purity-labels", default=None)
    ap.add_argument("--imgsz", type=int, default=224)
    ap.add_argument("--gate", type=float, default=CONFIDENCE_GATE)
    args = ap.parse_args()

    labels = Path(args.labels).read_text().split()
    interp = _load_interpreter(args.tflite)
    polymer, conf, probs = classify(interp, labels, args.img, args.imgsz)

    result = {
        "polymer": polymer,
        "confidence": round(conf, 4),
        "purity": None,
        "status": "AI_VERIFIED" if conf >= args.gate else "MANUAL_REVIEW",
        "gate": args.gate,
        "probs": {labels[i]: round(float(p), 4) for i, p in enumerate(probs)},
    }

    if args.purity_tflite:
        p_labels = Path(args.purity_labels).read_text().split()
        p_interp = _load_interpreter(args.purity_tflite)
        grade, p_conf, _ = classify(p_interp, p_labels, args.img, args.imgsz)
        result["purity"] = {"grade": grade, "confidence": round(p_conf, 4)}

    print(json.dumps(result, indent=2))
    if result["status"] == "MANUAL_REVIEW":
        print(f"\n⚠️  confidence {conf:.1%} < gate {args.gate:.0%} -> "
              f"MANUAL_REVIEW (would NOT auto-mint)")
    else:
        print(f"\n✅ {polymer} @ {conf:.1%} -> AI_VERIFIED "
              f"(proceed to PoPP + hashing)")


if __name__ == "__main__":
    main()
