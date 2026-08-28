#!/usr/bin/env python3
"""
download_taco.py — build a REAL polymer ImageFolder dataset from TACO.

TACO (http://tacodataset.org, pedropro/TACO) is ~1500 litter photos with 4784
COCO-style annotations across 60 fine categories — including real plastic
subtypes (clear bottle, film, foam, straw, ...). This script:

  1. reads TACO's annotations.json (clone the repo first, see below),
  2. downloads each needed image (from its flickr URL) with caching,
  3. crops every annotated object whose category maps to a PolyMint resin class
     (via configs/taco_map.yaml) into <out>/<CLASS>/*.jpg,
  4. leaves the train/val/test split to prepare_dataset.py.

Prereqs
-------
git clone --depth 1 https://github.com/pedropro/TACO.git data/taco_repo

Usage
-----
python src/download_taco.py \
    --ann data/taco_repo/data/annotations.json \
    --map configs/taco_map.yaml \
    --out data/taco_crops \
    --pad 0.15 --min-size 40

Then split into the training layout:
    python src/prepare_dataset.py --source data/taco_crops --identity-map \
        --out data/polymer --classes PET HDPE PVC LDPE PP PS Other
"""
import argparse
import json
import urllib.request
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import yaml
from PIL import Image
from tqdm import tqdm

UA = {"User-Agent": "Mozilla/5.0 (PolyMint dataset builder)"}
TIMEOUT = 8  # short so dead flickr URLs fail fast instead of stalling


def cache_path(img_meta: dict, cache_dir: Path) -> Path:
    return cache_dir / img_meta["file_name"].replace("/", "_")


def download_image(img_meta: dict, cache_dir: Path) -> Path | None:
    """Fetch a TACO image to cache; return local path (or None on failure)."""
    dst = cache_path(img_meta, cache_dir)
    if dst.exists() and dst.stat().st_size > 0:
        return dst
    # TACO images carry flickr URLs; prefer the 640px variant for speed.
    for key in ("flickr_640_url", "flickr_url"):
        url = img_meta.get(key)
        if not url:
            continue
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
                data = r.read()
            if data:
                dst.write_bytes(data)
                return dst
        except Exception:
            continue
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ann", required=True, help="TACO annotations.json")
    ap.add_argument("--map", required=True, help="configs/taco_map.yaml")
    ap.add_argument("--out", required=True, help="output ImageFolder root")
    ap.add_argument("--cache", default=None, help="image cache dir (default <out>/../taco_cache)")
    ap.add_argument("--pad", type=float, default=0.15, help="bbox padding fraction")
    ap.add_argument("--min-size", type=int, default=40, help="skip crops smaller than this (px)")
    ap.add_argument("--limit", type=int, default=0, help="debug: cap number of images")
    ap.add_argument("--workers", type=int, default=16, help="concurrent downloads")
    ap.add_argument("--timeout", type=int, default=TIMEOUT, help="per-image timeout (s)")
    args = ap.parse_args()
    globals()["TIMEOUT"] = args.timeout

    coco = json.load(open(args.ann))
    cat_name = {c["id"]: c["name"] for c in coco["categories"]}
    mapping = {k: v for k, v in yaml.safe_load(open(args.map))["map"].items()}
    images = {im["id"]: im for im in coco["images"]}

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    cache = Path(args.cache) if args.cache else out.parent / "taco_cache"
    cache.mkdir(parents=True, exist_ok=True)

    # group annotations by image so we download each image once
    by_img: dict[int, list] = {}
    for ann in coco["annotations"]:
        cls = mapping.get(cat_name.get(ann["category_id"], ""), None)
        if cls is None:
            continue
        by_img.setdefault(ann["image_id"], []).append((cls, ann["bbox"]))

    img_ids = list(by_img.keys())
    if args.limit:
        img_ids = img_ids[: args.limit]
    print(f"{len(img_ids)} images carry mappable plastic annotations")

    # --- Phase 1: download all needed images concurrently (short timeout) ---
    ok_ids = []
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(download_image, images[iid], cache): iid for iid in img_ids}
        for fut in tqdm(as_completed(futs), total=len(futs), desc="download"):
            iid = futs[fut]
            try:
                if fut.result() is not None:
                    ok_ids.append(iid)
            except Exception:
                pass
    print(f"{len(ok_ids)}/{len(img_ids)} images available; cropping...")

    # --- Phase 2: crop annotated objects from cached images (fast, local) ---
    counts, saved, failed = Counter(), 0, len(img_ids) - len(ok_ids)
    for iid in tqdm(ok_ids, desc="crop"):
        meta = images[iid]
        path = cache_path(meta, cache)
        try:
            im = Image.open(path).convert("RGB")
        except Exception:
            failed += 1
            continue
        W, H = im.size
        # COCO bboxes are in ORIGINAL-resolution coords; the flickr_640 variant we
        # download is smaller, so scale bboxes by downloaded/original ratio.
        sx = W / meta.get("width", W)
        sy = H / meta.get("height", H)
        for j, (cls, (x, y, w, h)) in enumerate(by_img[iid]):
            x, y, w, h = x * sx, y * sy, w * sx, h * sy
            px, py = w * args.pad, h * args.pad
            box = (max(0, int(x - px)), max(0, int(y - py)),
                   min(W, int(x + w + px)), min(H, int(y + h + py)))
            if box[2] - box[0] < args.min_size or box[3] - box[1] < args.min_size:
                continue
            d = out / cls
            d.mkdir(parents=True, exist_ok=True)
            im.crop(box).save(d / f"{cls}_{iid}_{j}.jpg", quality=90)
            counts[cls] += 1
            saved += 1

    print(f"\nSaved {saved} crops to {out}  ({failed} images failed to download)")
    print(f"{'class':<10}{'crops':>8}")
    for cls in ["PET", "HDPE", "PVC", "LDPE", "PP", "PS", "Other"]:
        print(f"{cls:<10}{counts.get(cls, 0):>8}")
    if saved == 0:
        raise SystemExit("No crops saved — check internet + annotation/map paths.")


if __name__ == "__main__":
    main()
