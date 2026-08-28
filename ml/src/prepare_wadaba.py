#!/usr/bin/env python3
"""
prepare_wadaba.py — turn WaDaBa archives into a resin-labelled ImageFolder.

WaDaBa (http://wadaba.pcz.pl) is ~4000 images of single plastic objects, labelled
by RESIN CODE in the filename — exactly PolyMint's classes (and, unlike TACO, it
includes PVC). Filenames look like:  0001_a01b00c1d0e0f0g1h0.jpg  where the `aNN`
field is the resin code:

    a01 PET   a02 HDPE (PE-HD)   a03 PVC   a04 LDPE (PE-LD)   a05 PP   a06 PS

This script extracts the downloaded zips and copies each image into
<out>/<CLASS>/ so prepare_dataset.py can split it. (There is no `a07/Other` in
WaDaBa — get the Other class from TACO.)

Usage
-----
python src/prepare_wadaba.py --zips data/wadaba_zips --out data/wadaba_crops
"""
import argparse
import re
import shutil
import zipfile
from collections import Counter
from pathlib import Path

A_TO_CLASS = {
    "01": "PET", "02": "HDPE", "03": "PVC",
    "04": "LDPE", "05": "PP", "06": "PS",
}
A_RE = re.compile(r"_a(\d{2})")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--zips", default="data/wadaba_zips", help="dir of WaDaBa_*.zip")
    ap.add_argument("--out", default="data/wadaba_crops")
    ap.add_argument("--extract-dir", default="data/wadaba_extracted")
    args = ap.parse_args()

    zips = sorted(Path(args.zips).glob("WaDaBa_*.zip"))
    if not zips:
        raise SystemExit(f"no WaDaBa_*.zip in {args.zips}")
    ext = Path(args.extract_dir)
    ext.mkdir(parents=True, exist_ok=True)

    print(f"Extracting {len(zips)} archives...")
    for z in zips:
        try:
            with zipfile.ZipFile(z) as zf:
                zf.extractall(ext)
        except zipfile.BadZipFile:
            print(f"  ! bad/incomplete zip skipped: {z.name}")

    out = Path(args.out)
    if out.exists():
        shutil.rmtree(out)
    counts = Counter()
    for img in ext.rglob("*.jpg"):
        m = A_RE.search(img.name)
        if not m:
            continue
        cls = A_TO_CLASS.get(m.group(1))
        if cls is None:
            continue
        d = out / cls
        d.mkdir(parents=True, exist_ok=True)
        shutil.copy2(img, d / img.name)
        counts[cls] += 1

    print(f"\nWaDaBa -> {out}")
    total = 0
    for cls in ["PET", "HDPE", "PVC", "LDPE", "PP", "PS"]:
        print(f"  {cls:<6}{counts.get(cls,0):>6}")
        total += counts.get(cls, 0)
    print(f"  {'TOTAL':<6}{total:>6}")
    if total == 0:
        raise SystemExit("No images mapped — check archives extracted correctly.")


if __name__ == "__main__":
    main()
