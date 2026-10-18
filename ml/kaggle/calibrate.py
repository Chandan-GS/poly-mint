#!/usr/bin/env python3
"""
calibrate.py — fit the temperature that calibrates the classifier's confidence.

The raw model is overconfident: on held-out images only ~77% of its
">= 0.85" calls are right. Temperature scaling, q_i ∝ p_i^(1/T), fixes the
confidence without changing the argmax. T is fitted (minimum NLL) on the
**val** split, and the gate is reported on the **test** split.

Both splits come from build_heldout.py. Images that are broken scrapes (min side < 64 px or
aspect ratio > 4) are skipped.

    python ml/kaggle/build_heldout.py --downloads dl --out val --split val
    python ml/kaggle/build_heldout.py --downloads dl --out heldout
    python ml/kaggle/calibrate.py --model assets/model/polymer7_v2_float32.tflite \
        --labels ml/models/polymer7_v2.labels.txt --val val --test heldout

The app's preprocessing (square center crop + PIL bilinear) is used. Put the
result in lib/data/services/confidence_calibration.dart and the model meta.
"""
import argparse
import csv

import numpy as np
from PIL import Image, ImageOps

try:
    from ai_edge_litert.interpreter import Interpreter
except ImportError:  # pragma: no cover
    from tensorflow.lite import Interpreter


def app_preprocess(path, size=224):
    im = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    w, h = im.size
    s = min(w, h)
    im = im.crop(((w - s) // 2, (h - s) // 2, (w - s) // 2 + s, (h - s) // 2 + s))
    im = im.resize((size, size), Image.BILINEAR)
    return (np.asarray(im, dtype=np.float32) / 255.0)[None]


def predict(model, labels, folder):
    it = Interpreter(model_path=model)
    it.allocate_tensors()
    ii, oi = it.get_input_details()[0]["index"], it.get_output_details()[0]["index"]
    probs, ys = [], []
    for r in csv.DictReader(open(f"{folder}/labels.csv")):
        w, h = Image.open(f"{folder}/{r['file']}").size
        if min(w, h) < 64 or max(w, h) / min(w, h) > 4:
            continue
        it.set_tensor(ii, app_preprocess(f"{folder}/{r['file']}"))
        it.invoke()
        probs.append(it.get_tensor(oi)[0].astype(np.float64))
        ys.append(labels.index(r["class"]))
    return np.array(probs), np.array(ys)


def scale(p, t):
    logits = np.log(np.clip(p, 1e-12, 1)) / t
    logits -= logits.max(1, keepdims=True)
    q = np.exp(logits)
    return q / q.sum(1, keepdims=True)


def nll(p, y):
    return -np.mean(np.log(np.clip(p[np.arange(len(y)), y], 1e-12, 1)))


def ece(p, y, bins=10):
    conf, ok, e = p.max(1), p.argmax(1) == y, 0.0
    for lo in np.linspace(0, 1, bins, endpoint=False):
        m = (conf > lo) & (conf <= lo + 1 / bins)
        if m.any():
            e += m.mean() * abs(ok[m].mean() - conf[m].mean())
    return e


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", required=True)
    ap.add_argument("--labels", required=True)
    ap.add_argument("--val", required=True)
    ap.add_argument("--test", required=True)
    ap.add_argument("--gate", type=float, default=0.85)
    args = ap.parse_args()
    labels = open(args.labels).read().split()

    pv, yv = predict(args.model, labels, args.val)
    pt, yt = predict(args.model, labels, args.test)
    grid = np.exp(np.linspace(np.log(0.5), np.log(8), 400))
    t = grid[int(np.argmin([nll(scale(pv, g), yv) for g in grid]))]
    print(f"val n={len(yv)}  test n={len(yt)}  fitted T = {t:.3f}")
    for name, (p, y) in {"val": (pv, yv), "test": (pt, yt)}.items():
        for tag, q in (("raw", p), ("calibrated", scale(p, t))):
            conf, ok = q.max(1), q.argmax(1) == y
            g = conf >= args.gate
            prec = ok[g].mean() * 100 if g.any() else float("nan")
            print(f"  {name:4s} {tag:10s} acc {ok.mean()*100:5.1f}%  ECE {ece(q, y)*100:5.1f}  "
                  f"NLL {nll(q, y):.3f}  gate>={args.gate}: auto {g.mean()*100:3.0f}%  precision {prec:5.1f}%")


if __name__ == "__main__":
    main()
