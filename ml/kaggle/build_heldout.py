#!/usr/bin/env python3
"""
build_heldout.py — rebuild the exact held-out test images of the polymint-7class
run from the public Kaggle datasets, for on-device evaluation.

The Kaggle job named its copies <source>_<index>.jpg, where index is the
position in the sorted file list. This script repeats that ingest order and
pulls the test-split files listed in split_manifest.csv.

Sources covered: seven_plastics (piaoya/plastic-recycling-codes, all 7 classes)
and the visual-plastic set (harshitkandoi7850/...). WaDaBa and TACO are left
out (3.3 GB and approximate labels).

    kaggle datasets download piaoya/plastic-recycling-codes -p dl/seven --unzip
    kaggle datasets download harshitkandoi7850/dataset-for-visual-plastic-type-recognition -p dl/visual --unzip
    python ml/kaggle/build_heldout.py --downloads dl --out heldout

Then push heldout/ into the app and run integration_test/eval_on_device_test.dart
(see results/RESULTS.md, "On-device evaluation").
"""
import argparse
import csv
import glob
import shutil
from collections import Counter
from pathlib import Path

SEVEN = {"1": "PET", "2": "HDPE", "3": "PVC", "4": "LDPE", "5": "PP", "6": "PS", "7": "Other"}
VISUAL = {"PET": "PET", "PS": "PS", "PP": "PP", "Others": "Other", "PC": "Other"}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--downloads", required=True, help="dir with seven/ and visual/ downloads")
    ap.add_argument("--manifest", default=str(Path(__file__).parent / "results/polymint7_v2/split_manifest.csv"))
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    items = {"seven": [], "visual": []}
    for f in sorted(glob.glob(f"{args.downloads}/seven/**/seven_plastics/*/*", recursive=True)):
        c = SEVEN.get(Path(f).parent.name.split("_")[0])
        if c and Path(f).suffix.lower() in {".jpg", ".jpeg", ".png"}:
            items["seven"].append((f, c))
    for f in sorted(glob.glob(f"{args.downloads}/visual/**/Plastic types/*/*", recursive=True)):
        c = VISUAL.get(Path(f).parent.name)
        if c and Path(f).suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"}:
            items["visual"].append((f, c))

    out = Path(args.out)
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    labels, mismatched = [], 0
    for r in csv.DictReader(open(args.manifest)):
        if r["split"] != "test" or r["source"] not in items:
            continue
        idx = int(Path(r["path"]).stem.split("_")[1])
        src, cls = items[r["source"]][idx]
        if cls != r["cls"]:
            mismatched += 1
            continue
        name = f"{r['source']}_{idx:05d}{Path(src).suffix.lower()}"
        shutil.copy(src, out / name)
        labels.append((name, cls, r["source"]))
    with open(out / "labels.csv", "w") as fh:
        fh.write("file,class,source\n")
        fh.writelines(",".join(l) + "\n" for l in labels)
    print(f"{len(labels)} held-out images -> {out}  (class mismatches: {mismatched})")
    print(dict(Counter(c for _, c, _ in labels)))


if __name__ == "__main__":
    main()
