#!/usr/bin/env python3
"""
make_synthetic_dataset.py — generate a tiny FAKE dataset so the whole pipeline
runs end-to-end offline (smoke test) before you have real images.

This produces solid-colour + noise images per class. It is ONLY for verifying the
train -> export -> infer -> parity plumbing works. It teaches the model nothing
useful — replace with real data (see README "Datasets") before trusting outputs.

Usage
-----
python src/make_synthetic_dataset.py --out data/polymer \
    --classes PET HDPE PVC LDPE PP PS Other --per-class 40
python src/make_synthetic_dataset.py --out data/purity \
    --classes clean mixed contaminated --per-class 40
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--classes", nargs="+", required=True)
    ap.add_argument("--per-class", type=int, default=40)
    ap.add_argument("--size", type=int, default=256)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    rng = np.random.default_rng(args.seed)
    out = Path(args.out)
    splits = {"train": 0.7, "val": 0.15, "test": 0.15}

    for ci, cls in enumerate(args.classes):
        # give each class a distinct base hue so a model CAN separate them
        base = np.array([(ci * 37) % 256, (ci * 91) % 256, (ci * 53) % 256])
        for split, frac in splits.items():
            n = max(1, round(args.per_class * frac))
            d = out / split / cls
            d.mkdir(parents=True, exist_ok=True)
            for i in range(n):
                noise = rng.integers(-30, 30, (args.size, args.size, 3))
                arr = np.clip(base + noise, 0, 255).astype(np.uint8)
                Image.fromarray(arr, "RGB").save(d / f"{cls}_{split}_{i:04d}.jpg")
    print(f"Synthetic dataset written to {out} for classes {args.classes}")
    print("⚠️  SYNTHETIC ONLY — replace with real images before trusting results.")


if __name__ == "__main__":
    main()
