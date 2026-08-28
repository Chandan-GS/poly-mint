#!/usr/bin/env python3
"""
download_hf_resin.py — fetch a real RESIN-labelled image set from HuggingFace.

Dataset: aytvill/plastic-recycling-codes (public, not gated) — ~606 images in
folders named by resin code, INCLUDING PVC (which TACO lacks). Images are stored
via git-LFS, so we pull them through HF's `resolve` URLs (no git-lfs needed) and
normalise the folder names to PolyMint's classes.

Usage
-----
python src/download_hf_resin.py --out data/hf_crops

Then combine with TACO and split:
    python src/prepare_dataset.py --source data/taco_crops data/hf_crops \
        --identity-map --out data/polymer7 \
        --classes PET HDPE PVC LDPE PP PS Other --cap 350
"""
import argparse
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = "aytvill/plastic-recycling-codes"
API = f"https://huggingface.co/api/datasets/{REPO}"
BASE = f"https://huggingface.co/datasets/{REPO}/resolve/main"

# HF folder name -> PolyMint class ( "8_no_plastic" intentionally dropped )
FOLDER_TO_CLASS = {
    "1_polyethylene_PET": "PET",
    "2_high_density_polyethylene_PE-HD": "HDPE",
    "3_polyvinylchloride_PVC": "PVC",
    "4_low_density_polyethylene_PE-LD": "LDPE",
    "5_polypropylene_PP": "PP",
    "6_polystyrene_PS": "PS",
    "7_other_resins": "Other",
}
IMG_EXT = (".jpg", ".jpeg", ".png")


def list_files() -> list[str]:
    import json
    with urllib.request.urlopen(API, timeout=30) as r:
        meta = json.load(r)
    return [s["rfilename"] for s in meta.get("siblings", [])
            if s.get("rfilename", "").lower().endswith(IMG_EXT)]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default="data/hf_crops")
    ap.add_argument("--workers", type=int, default=16)
    args = ap.parse_args()

    files = list_files()
    print(f"{len(files)} images listed on HF")
    out = Path(args.out)

    def fetch(f: str):
        top = f.split("/")[0]
        cls = FOLDER_TO_CLASS.get(top)
        if cls is None:
            return None
        d = out / cls
        d.mkdir(parents=True, exist_ok=True)
        dst = d / f"hf_{Path(f).name}"
        try:
            urllib.request.urlretrieve(f"{BASE}/{urllib.parse.quote(f)}", dst)
            return cls if dst.stat().st_size > 1000 else None
        except Exception:
            return None

    from collections import Counter
    counts = Counter()
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        for cls in ex.map(fetch, files):
            if cls:
                counts[cls] += 1

    print(f"\nHF resin images -> {out}")
    for cls in ["PET", "HDPE", "PVC", "LDPE", "PP", "PS", "Other"]:
        print(f"  {cls:<6}{counts.get(cls,0):>5}")
    print(f"  {'TOTAL':<6}{sum(counts.values()):>5}")
    if not counts:
        raise SystemExit("Nothing downloaded — check network / HF availability.")


if __name__ == "__main__":
    main()
