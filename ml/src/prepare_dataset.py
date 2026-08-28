#!/usr/bin/env python3
"""
prepare_dataset.py — build a YOLOv8-cls dataset from public/self-collected images.

Ultralytics classification expects this on-disk layout:

    <root>/
      train/<class>/*.jpg
      val/<class>/*.jpg
      test/<class>/*.jpg

This script ingests one or more ImageFolder-style sources (a directory with one
sub-folder per raw label — the format of TrashNet, RealWaste, WaDaBa-by-folder,
and most Kaggle trash datasets), remaps the raw labels onto PolyMint's target
classes via configs/class_map.yaml, then does a stratified train/val/test split.

Examples
--------
# Polymer classifier from two public sources:
python src/prepare_dataset.py \
    --source ~/datasets/trashnet ~/datasets/realwaste \
    --class-map configs/class_map.yaml \
    --out data/polymer \
    --classes PET HDPE PVC LDPE PP PS Other

# Purity grader from your own folder-per-grade images (no class map needed —
# the source folders are already named clean/mixed/contaminated):
python src/prepare_dataset.py \
    --source ~/datasets/purity_labelled \
    --out data/purity \
    --classes clean mixed contaminated --identity-map

TACO (COCO-JSON) is not folder-per-label; crop its annotations to an ImageFolder
first, then point --source at the result. See README "Datasets".
"""
import argparse
import shutil
from collections import defaultdict
from pathlib import Path

import yaml

try:
    from sklearn.model_selection import train_test_split
except ImportError:  # pragma: no cover
    raise SystemExit("scikit-learn is required: pip install scikit-learn")

IMG_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}


def load_class_map(path: str | None, identity: bool):
    if identity or path is None:
        return {}, [], "Other"
    cfg = yaml.safe_load(Path(path).read_text())
    mapping = {k.lower(): v for k, v in (cfg.get("map") or {}).items()}
    drop = {d.lower() for d in (cfg.get("drop") or [])}
    return mapping, drop, "Other"


def resolve_class(raw_label: str, mapping: dict, drop: set,
                  identity: bool, default_class: str, valid: set):
    key = raw_label.lower()
    if key in drop:
        return None
    if identity:
        # source folder name IS the target class
        return raw_label if raw_label in valid else None
    return mapping.get(key, default_class)


def collect(sources, mapping, drop, identity, default_class, valid):
    """Return {target_class: [Path, ...]} gathered across all sources."""
    buckets: dict[str, list[Path]] = defaultdict(list)
    skipped = defaultdict(int)
    for src in sources:
        src = Path(src).expanduser()
        if not src.is_dir():
            raise SystemExit(f"source not found: {src}")
        for label_dir in sorted(p for p in src.iterdir() if p.is_dir()):
            target = resolve_class(label_dir.name, mapping, drop,
                                   identity, default_class, valid)
            imgs = [p for p in label_dir.rglob("*") if p.suffix.lower() in IMG_EXTS]
            if target is None:
                skipped[label_dir.name] += len(imgs)
                continue
            buckets[target].extend(imgs)
    return buckets, skipped


def split_and_write(buckets, out_root, ratios, seed):
    out_root = Path(out_root).expanduser()
    if out_root.exists():
        shutil.rmtree(out_root)
    train_r, val_r, test_r = ratios
    counts = defaultdict(lambda: defaultdict(int))

    for cls, files in buckets.items():
        files = sorted(set(files))
        if len(files) < 3:
            print(f"  ! {cls}: only {len(files)} images — too few to split cleanly")
        # train vs (val+test)
        train, rest = train_test_split(
            files, test_size=(val_r + test_r), random_state=seed
        ) if len(files) > 2 else (files, [])
        # val vs test out of the remainder
        if rest:
            rel_test = test_r / (val_r + test_r) if (val_r + test_r) > 0 else 0.0
            val, test = train_test_split(
                rest, test_size=rel_test, random_state=seed
            ) if len(rest) > 1 and rel_test > 0 else (rest, [])
        else:
            val, test = [], []

        for split_name, items in (("train", train), ("val", val), ("test", test)):
            dst_dir = out_root / split_name / cls
            dst_dir.mkdir(parents=True, exist_ok=True)
            for i, f in enumerate(items):
                # prefix to avoid name collisions across source folders
                dst = dst_dir / f"{cls}_{split_name}_{i:06d}{f.suffix.lower()}"
                shutil.copy2(f, dst)
            counts[cls][split_name] = len(items)
    return out_root, counts


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", nargs="+", required=True,
                    help="one or more ImageFolder-style source directories")
    ap.add_argument("--out", required=True, help="output dataset root")
    ap.add_argument("--classes", nargs="+", required=True,
                    help="the target class list (defines what's valid)")
    ap.add_argument("--class-map", default=None,
                    help="yaml mapping raw labels -> target classes")
    ap.add_argument("--identity-map", action="store_true",
                    help="source folder names already equal target classes")
    ap.add_argument("--default-class", default="Other",
                    help="fallback class for unmapped labels (default: Other)")
    ap.add_argument("--split", nargs=3, type=float, default=[0.7, 0.15, 0.15],
                    metavar=("TRAIN", "VAL", "TEST"))
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    valid = set(args.classes)
    mapping, drop, _ = load_class_map(args.class_map, args.identity_map)
    if not args.identity_map and args.class_map is None:
        print("! no --class-map and no --identity-map: everything unmapped -> "
              f"{args.default_class}")

    print(f"Ingesting {len(args.source)} source(s)...")
    buckets, skipped = collect(args.source, mapping, drop, args.identity_map,
                               args.default_class, valid)

    # keep only requested classes
    buckets = {c: buckets.get(c, []) for c in args.classes}

    ratios = tuple(r / sum(args.split) for r in args.split)  # normalise
    out_root, counts = split_and_write(buckets, args.out, ratios, args.seed)

    print(f"\nDataset written to: {out_root}")
    print(f"{'class':<14}{'train':>8}{'val':>8}{'test':>8}{'total':>8}")
    grand = 0
    for cls in args.classes:
        c = counts[cls]
        tot = c["train"] + c["val"] + c["test"]
        grand += tot
        print(f"{cls:<14}{c['train']:>8}{c['val']:>8}{c['test']:>8}{tot:>8}")
    print(f"{'TOTAL':<14}{'':>8}{'':>8}{'':>8}{grand:>8}")
    if skipped:
        print("\nSkipped raw labels (dropped/non-plastic):")
        for k, v in sorted(skipped.items()):
            print(f"  {k}: {v}")
    if grand == 0:
        raise SystemExit("No images collected — check --source paths and class map.")


if __name__ == "__main__":
    main()
