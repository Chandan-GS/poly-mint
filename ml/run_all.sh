#!/usr/bin/env bash
# run_all.sh — end-to-end smoke test on SYNTHETIC data (no downloads needed).
# Proves the plumbing: synthetic data -> train (few epochs) -> export -> infer -> parity.
# Replace the synthetic step with real data (see README) for a real model.
set -euo pipefail
cd "$(dirname "$0")"

echo "== 1/5  synthetic polymer + purity datasets =="
python src/make_synthetic_dataset.py --out data/polymer \
  --classes PET HDPE PVC LDPE PP PS Other --per-class 40
python src/make_synthetic_dataset.py --out data/purity \
  --classes clean mixed contaminated --per-class 40

echo "== 2/5  train (5 epochs, smoke test) =="
python src/train.py --config configs/polymer.yaml --epochs 5
python src/train.py --config configs/purity.yaml  --epochs 5

echo "== 3/5  export float32 tflite =="
python src/export_tflite.py --weights runs/polymer/weights/best.pt --imgsz 224
python src/export_tflite.py --weights runs/purity/weights/best.pt  --imgsz 224

echo "== 4/5  inference on one sample =="
SAMPLE=$(find data/polymer/test -name '*.jpg' | head -n1)
python src/infer.py \
  --tflite models/polymer_float32.tflite --labels models/polymer.labels.txt \
  --purity-tflite models/purity_float32.tflite --purity-labels models/purity.labels.txt \
  --img "$SAMPLE"

echo "== 5/5  parity check (tflite vs pytorch) =="
python src/verify_parity.py --weights runs/polymer/weights/best.pt \
  --tflite models/polymer_float32.tflite --img "$SAMPLE" || true

echo "== DONE — plumbing verified. Now swap in real data. =="
