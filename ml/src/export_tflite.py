#!/usr/bin/env python3
"""
export_tflite.py — export trained weights to a float32 .tflite for on-phone use.

Phase 1 is phone-only, so we export FLOAT32 (no int8 quantization) to keep
maximum accuracy. int8 is a Phase-2 concern (ESP32-S3 / Pi edge box) and is
intentionally left out here — pass --int8 only if you want to experiment.

Usage
-----
python src/export_tflite.py --weights runs/polymer/weights/best.pt --imgsz 224
python src/export_tflite.py --weights runs/purity/weights/best.pt  --imgsz 224

Ultralytics writes the .tflite inside a  <weights_dir>/best_saved_model/  folder
(e.g. best_float32.tflite). This script copies it out to models/ with a clean,
predictable name and writes a sidecar <name>.labels.txt with the class order.
"""
import argparse
import shutil
from pathlib import Path

import yaml

try:
    from ultralytics import YOLO
except ImportError:
    raise SystemExit("ultralytics is required: pip install -r requirements.txt")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--weights", required=True, help="path to best.pt")
    ap.add_argument("--imgsz", type=int, default=224)
    ap.add_argument("--out-dir", default="models")
    ap.add_argument("--name", default=None,
                    help="output basename (default: parent run name)")
    ap.add_argument("--int8", action="store_true",
                    help="Phase-2 only: post-training int8 quantization")
    args = ap.parse_args()

    weights = Path(args.weights)
    if not weights.is_file():
        raise SystemExit(f"weights not found: {weights}")
    # run name = the folder two levels up (runs/<name>/weights/best.pt)
    run_name = args.name or weights.parent.parent.name

    model = YOLO(str(weights))
    names = model.names  # {idx: class_name} — THE canonical class order
    print(f"Exporting '{run_name}'  classes={list(names.values())}")

    export_path = model.export(format="tflite", imgsz=args.imgsz, int8=args.int8)
    export_path = Path(export_path)
    print(f"Ultralytics produced: {export_path}")

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    suffix = "int8" if args.int8 else "float32"
    tflite_out = out_dir / f"{run_name}_{suffix}.tflite"

    # export_path may be the .tflite itself or the *_saved_model dir
    if export_path.suffix == ".tflite":
        src = export_path
    else:
        cands = sorted(export_path.glob(f"*{suffix}.tflite")) or \
                sorted(export_path.glob("*.tflite"))
        if not cands:
            raise SystemExit(f"no .tflite found under {export_path}")
        src = cands[0]
    shutil.copy2(src, tflite_out)

    # sidecar label file (index-ordered) — ship this alongside the .tflite
    labels_out = out_dir / f"{run_name}.labels.txt"
    labels_out.write_text("\n".join(names[i] for i in range(len(names))) + "\n")

    # sidecar meta for the app / parity check
    meta_out = out_dir / f"{run_name}.meta.yaml"
    yaml.safe_dump(
        {"name": run_name, "imgsz": args.imgsz, "dtype": suffix,
         "classes": [names[i] for i in range(len(names))],
         "input_layout": "NHWC [1,H,W,3]", "scale": "pixels / 255.0",
         "color": "RGB", "confidence_gate": 0.85},
        meta_out.open("w"), sort_keys=False,
    )

    print(f"\n✅ Model : {tflite_out}  ({tflite_out.stat().st_size/1e6:.1f} MB)")
    print(f"✅ Labels: {labels_out}")
    print(f"✅ Meta  : {meta_out}")
    print(f"\nVerify parity: python src/verify_parity.py "
          f"--weights {weights} --tflite {tflite_out} --img <some_test.jpg>")


if __name__ == "__main__":
    main()
