#!/usr/bin/env python3
"""
train.py — train a YOLOv8-cls classifier (polymer or purity) from a config.

Usage
-----
python src/train.py --config configs/polymer.yaml
python src/train.py --config configs/purity.yaml
python src/train.py --config configs/polymer.yaml --epochs 5   # quick smoke test

Outputs Ultralytics run artifacts to runs/<name>/ ; the trained weights land at
runs/<name>/weights/best.pt  (feed that to src/export_tflite.py).
"""
import argparse
from pathlib import Path

import yaml

try:
    from ultralytics import YOLO
except ImportError:
    raise SystemExit("ultralytics is required: pip install -r requirements.txt")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", required=True)
    # optional CLI overrides (handy for smoke tests / sweeps)
    ap.add_argument("--epochs", type=int, default=None)
    ap.add_argument("--batch", type=int, default=None)
    ap.add_argument("--model", default=None)
    ap.add_argument("--device", default=None)
    args = ap.parse_args()

    cfg = yaml.safe_load(Path(args.config).read_text())
    if args.epochs is not None: cfg["epochs"] = args.epochs
    if args.batch is not None:  cfg["batch"] = args.batch
    if args.model is not None:  cfg["model"] = args.model
    if args.device is not None: cfg["device"] = args.device

    data_dir = Path(cfg["data"])
    if not (data_dir / "train").is_dir():
        raise SystemExit(
            f"Dataset not found at {data_dir}/train.\n"
            f"Run src/prepare_dataset.py first (see README)."
        )

    print(f"== Training '{cfg['name']}' :: {cfg['model']} on {cfg['data']} ==")
    model = YOLO(cfg["model"])
    model.train(
        data=str(data_dir),
        epochs=cfg["epochs"],
        imgsz=cfg["imgsz"],
        batch=cfg["batch"],
        patience=cfg.get("patience", 20),
        lr0=cfg.get("lr0", 0.001),
        dropout=cfg.get("dropout", 0.0),
        device=cfg.get("device", "") or None,
        workers=cfg.get("workers", 8),
        seed=cfg.get("seed", 42),
        project=cfg.get("project", "runs"),
        name=cfg["name"],
        exist_ok=True,
        verbose=True,
    )

    # Report top-1/top-5 on the held-out val set against the plan's targets.
    metrics = model.val(split="val")
    top1 = getattr(metrics, "top1", None)
    top5 = getattr(metrics, "top5", None)
    print("\n== Validation ==")
    print(f"top1 = {top1}   top5 = {top5}")
    if top1 is not None:
        target = 0.85
        flag = "PASS ✅" if top1 >= target else "below target ⚠️"
        print(f"Plan target top-1 >= {target:.0%}  ->  {flag}")

    best = Path(cfg.get("project", "runs")) / cfg["name"] / "weights" / "best.pt"
    print(f"\nBest weights: {best}")
    print(f"Next: python src/export_tflite.py --weights {best} --imgsz {cfg['imgsz']}")


if __name__ == "__main__":
    main()
