#!/usr/bin/env python3
"""
polymint7.py — train PolyMint's 7-class polymer classifier on Kaggle GPU.

Classes: PET HDPE PVC LDPE PP PS Other (the app's labels).

Sources (all public Kaggle datasets, attached to this kernel):
  * WaDaBa            anshagarwal2616/wadaba-plastic       PET HDPE PP PS Other (100 objects x 40 shots)
  * Visual plastic    harshitkandoi7850/dataset-for-visual-plastic-type-recognition
                      PET PS PP; Others+PC -> Other; "PE" is HDPE/LDPE mixed -> dropped
  * Seven plastics    piaoya/plastic-recycling-codes       all 7 classes (only PVC source)
  * TACO              kneroma/tacotrashdataset             object-labelled -> resin by configs/taco_map
                                                           (approximate labels; ablated below)

Leakage control:
  * WaDaBa split by physical object, TACO crops by source photo.
  * Other sources: perceptual-hash near-duplicates clustered and kept to one image;
    clusters whose members disagree on the class are dropped as label noise.
  * One fixed train/val/test split shared by every run.

Runs (same test set): YOLOv8s-cls all sources, YOLOv8s-cls without TACO, YOLO11s-cls all.
Reported: test top-1 / macro-F1 overall, on resin-labelled sources only (excludes
TACO's guessed labels), per source and per class.

Outputs in /kaggle/working: <run>_best.pt, results_polymint7.json, split_manifest.csv
"""
import csv
import json
import os
import random
import re
import shutil
import subprocess
import sys
import time
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from glob import glob
from pathlib import Path

SMOKE = False           # True = 1 epoch per run (pipeline check only)
EPOCHS = 1 if SMOKE else 100
PATIENCE = 30
IMGSZ = 224
SEED = 0
RUNS = [
    {"name": "v8s_all",    "model": "yolov8s-cls.pt", "taco": True},
    {"name": "v8s_noTACO", "model": "yolov8s-cls.pt", "taco": False},
    {"name": "y11s_all",   "model": "yolo11s-cls.pt", "taco": True},
]

subprocess.run([sys.executable, "-m", "pip", "install", "-q", "ultralytics", "imagehash"], check=True)

import imagehash
import numpy as np
from PIL import Image, ImageOps
from sklearn.metrics import confusion_matrix, f1_score
from ultralytics import YOLO

WORK = Path("/kaggle/working")
TMP = Path("/tmp/pm")
CLASSES = ["PET", "HDPE", "PVC", "LDPE", "PP", "PS", "Other"]
SORTED = sorted(CLASSES)                      # Ultralytics class index order
RESIN_SOURCES = {"wadaba", "visual", "seven"}

TACO_MAP = {
    "Clear plastic bottle": "PET", "Other plastic bottle": "PET", "Disposable plastic cup": "PET",
    "Plastic bottle cap": "HDPE", "Plastic lid": "HDPE",
    "Plastic film": "LDPE", "Garbage bag": "LDPE", "Single-use carrier bag": "LDPE",
    "Other plastic wrapper": "LDPE", "Six pack rings": "LDPE", "Crisp packet": "LDPE",
    "Polypropylene bag": "PP", "Spread tub": "PP", "Tupperware": "PP",
    "Disposable food container": "PP", "Other plastic container": "PP",
    "Plastic straw": "PP", "Plastic utensils": "PP",
    "Foam cup": "PS", "Foam food container": "PS", "Styrofoam piece": "PS", "Other plastic cup": "PS",
    "Other plastic": "Other", "Squeezable tube": "Other", "Plastic glooves": "Other",
    "Aluminium blister pack": "Other", "Carded blister pack": "Other",
}


# ---------------------------------------------------------------- ingest
def save_small(im: Image.Image, dst: Path, short: int = 320):
    im = im.convert("RGB")
    w, h = im.size
    s = short / min(w, h)
    if s < 1:
        im = im.resize((max(1, round(w * s)), max(1, round(h * s))), Image.BILINEAR)
    dst.parent.mkdir(parents=True, exist_ok=True)
    im.save(dst, quality=95)


def ingest_files(items, tag):
    """items: (src_path, cls, group) -> resized copies; returns dict records."""
    out = []

    def one(i_item):
        i, (src, cls, group) = i_item
        dst = TMP / "src" / tag / cls / f"{tag}_{i:05d}.jpg"
        try:
            save_small(ImageOps.exif_transpose(Image.open(src)), dst)
            return {"path": str(dst), "cls": cls, "source": tag, "group": f"{tag}:{group}"}
        except Exception as e:
            print(f"  ! {tag}: unreadable {src}: {e}")
            return None

    with ThreadPoolExecutor(16) as ex:
        out = [r for r in ex.map(one, enumerate(items)) if r]
    print(f"{tag}: {len(out)} images {dict(Counter(r['cls'] for r in out))}", flush=True)
    return out


def load_wadaba():
    amap = {"01": "PET", "02": "HDPE", "05": "PP", "06": "PS", "07": "Other"}
    items = []
    for f in sorted(glob("/kaggle/input/**/WaDaBa_*/*.jpg", recursive=True)):
        m = re.search(r"(\d{4})_a(\d{2})", os.path.basename(f))
        if m and m.group(2) in amap:
            items.append((f, amap[m.group(2)], m.group(1)))
    return ingest_files(items, "wadaba")


def load_visual():
    fmap = {"PET": "PET", "PS": "PS", "PP": "PP", "Others": "Other", "PC": "Other"}
    items = []
    for f in sorted(glob("/kaggle/input/**/Plastic types/*/*", recursive=True)):
        cls = fmap.get(Path(f).parent.name)
        if cls and Path(f).suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"}:
            items.append((f, cls, None))
    return ingest_files(items, "visual")


def load_seven():
    dmap = {"1": "PET", "2": "HDPE", "3": "PVC", "4": "LDPE", "5": "PP", "6": "PS", "7": "Other"}
    items = []
    for f in sorted(glob("/kaggle/input/**/seven_plastics/*/*", recursive=True)):
        cls = dmap.get(Path(f).parent.name.split("_")[0])
        if cls and Path(f).suffix.lower() in {".jpg", ".jpeg", ".png"}:
            items.append((f, cls, None))
    return ingest_files(items, "seven")


def load_taco(pad=0.15, min_size=40):
    anns = [a for a in glob("/kaggle/input/**/annotations.json", recursive=True)]
    if not anns:
        print("! TACO annotations.json not found — skipping TACO")
        return []
    ann_path = Path(anns[0])
    coco = json.load(open(ann_path))
    cat = {c["id"]: c["name"] for c in coco["categories"]}
    images = {im["id"]: im for im in coco["images"]}
    by_img = defaultdict(list)
    for a in coco["annotations"]:
        cls = TACO_MAP.get(cat.get(a["category_id"], ""))
        if cls:
            by_img[a["image_id"]].append((cls, a["bbox"]))

    def crop(iid):
        meta = images[iid]
        p = ann_path.parent / meta["file_name"]
        if not p.exists():
            return []
        im = Image.open(p)
        W0, H0 = meta["width"], meta["height"]
        if im.size != (W0, H0):
            im = ImageOps.exif_transpose(im)
        if im.size != (W0, H0):
            return []
        im = im.convert("RGB")
        recs = []
        for j, (cls, (x, y, w, h)) in enumerate(by_img[iid]):
            px, py = w * pad, h * pad
            box = (max(0, int(x - px)), max(0, int(y - py)), min(W0, int(x + w + px)), min(H0, int(y + h + py)))
            if box[2] - box[0] < min_size or box[3] - box[1] < min_size:
                continue
            dst = TMP / "src" / "taco" / cls / f"taco_{iid}_{j}.jpg"
            save_small(im.crop(box), dst)
            recs.append({"path": str(dst), "cls": cls, "source": "taco", "group": f"taco:{iid}"})
        return recs

    with ThreadPoolExecutor(16) as ex:
        out = [r for rs in ex.map(crop, list(by_img)) for r in rs]
    print(f"taco: {len(out)} crops {dict(Counter(r['cls'] for r in out))}", flush=True)
    return out


# ---------------------------------------------------------------- dedupe
def dedupe(recs, max_dist=4):
    """Cluster near-duplicate images (pHash) across non-WaDaBa sources."""
    hashes = []
    for r in recs:
        hashes.append(np.packbits(imagehash.phash(Image.open(r["path"])).hash.flatten()))
    H = np.unpackbits(np.stack(hashes), axis=1).astype(bool)   # n x 64
    n = len(recs)
    parent = list(range(n))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for i in range(n - 1):
        d = (H[i + 1:] != H[i]).sum(1)
        for j in np.nonzero(d <= max_dist)[0]:
            a, b = find(i), find(i + 1 + int(j))
            if a != b:
                parent[b] = a
    clusters = defaultdict(list)
    for i in range(n):
        clusters[find(i)].append(i)

    kept, dup, conflict = [], 0, 0
    for members in clusters.values():
        if len({recs[i]["cls"] for i in members}) > 1:
            conflict += len(members)
            continue
        # prefer the resin-labelled source when a TACO crop duplicates one
        members.sort(key=lambda i: recs[i]["source"] == "taco")
        r = dict(recs[members[0]])
        # keep TACO's photo group so its crops stay together
        kept.append(r)
        dup += len(members) - 1
    print(f"dedupe: {n} -> {len(kept)} (dropped {dup} near-duplicates, {conflict} in label-conflict clusters)")
    return kept


# ---------------------------------------------------------------- split
def assign_splits(recs, val_frac=0.15, test_frac=0.15):
    rng = random.Random(SEED)
    strata = defaultdict(lambda: defaultdict(list))
    for r in recs:
        g = r["group"] if not r["group"].endswith(":None") else f"{r['source']}:{r['path']}"
        strata[(r["source"], r["cls"])][g].append(r)
    for (src, cls), groups in strata.items():
        keys = sorted(groups)
        rng.shuffle(keys)
        total = sum(len(groups[k]) for k in keys)
        if len(keys) < 3:                       # e.g. WaDaBa "Other" = one object
            for k in keys:
                for r in groups[k]:
                    r["split"] = "train"
            continue
        n_test = n_val = 0
        for k in keys:
            if n_test < test_frac * total:
                split, n_test = "test", n_test + len(groups[k])
            elif n_val < val_frac * total:
                split, n_val = "val", n_val + len(groups[k])
            else:
                split = "train"
            for r in groups[k]:
                r["split"] = split
    return recs


def build_run_dir(recs, name, use_taco):
    root = TMP / "data" / name
    if root.exists():
        shutil.rmtree(root)
    train = [r for r in recs if r["split"] == "train" and (use_taco or r["source"] != "taco")]
    counts = Counter(r["cls"] for r in train)
    median = float(np.median([counts[c] for c in CLASSES]))
    for split in ("train", "val"):
        for r in recs:
            if r["split"] != split or (not use_taco and r["source"] == "taco"):
                continue
            reps = 1
            if split == "train":                # oversample minority classes (<= 4x)
                reps = int(min(4, max(1, round(median / counts[r["cls"]]))))
            d = root / split / r["cls"]
            d.mkdir(parents=True, exist_ok=True)
            for k in range(reps):
                os.symlink(r["path"], d / f"{k}_{os.path.basename(r['path'])}")
    eff = {c: len(os.listdir(root / "train" / c)) for c in CLASSES}
    print(f"[{name}] train after oversampling: {eff}", flush=True)
    return root


# ---------------------------------------------------------------- eval
def evaluate(weights, recs):
    model = YOLO(weights)
    paths = [r["path"] for r in recs]
    preds = []
    for i in range(0, len(paths), 128):
        for res in model.predict(paths[i:i + 128], imgsz=IMGSZ, verbose=False):
            preds.append(res.names[res.probs.top1])

    def score(sel):
        yt = [recs[i]["cls"] for i in sel]
        yp = [preds[i] for i in sel]
        if not yt:
            return None
        return {
            "n": len(yt),
            "acc": float(np.mean([a == b for a, b in zip(yt, yp)])),
            "macro_f1": float(f1_score(yt, yp, labels=sorted(set(yt)), average="macro", zero_division=0)),
            "per_class_recall": {c: float(np.mean([p == c for t, p in zip(yt, yp) if t == c]))
                                 for c in CLASSES if c in yt},
            "per_class_n": dict(Counter(yt)),
            "confusion": confusion_matrix(yt, yp, labels=CLASSES).tolist(),
        }

    idx = range(len(recs))
    out = {"all": score(list(idx)),
           "resin_labelled": score([i for i in idx if recs[i]["source"] in RESIN_SOURCES])}
    for s in ("wadaba", "visual", "seven", "taco"):
        out[f"source_{s}"] = score([i for i in idx if recs[i]["source"] == s])
    return out


def main():
    TMP.mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    wadaba = load_wadaba()
    others = dedupe(load_visual() + load_seven() + load_taco())
    recs = assign_splits(wadaba + others)
    print(f"data ready in {(time.time() - t0) / 60:.1f} min", flush=True)

    with open(WORK / "split_manifest.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["path", "cls", "source", "group", "split"])
        w.writeheader()
        w.writerows(recs)
    table = Counter((r["split"], r["source"], r["cls"]) for r in recs)
    summary = {s: {src: {c: table[(s, src, c)] for c in CLASSES}
                   for src in ("wadaba", "visual", "seven", "taco")} for s in ("train", "val", "test")}
    print(json.dumps(summary, indent=1))

    test = [r for r in recs if r["split"] == "test"]
    results = {"config": {"epochs": EPOCHS, "patience": PATIENCE, "imgsz": IMGSZ, "smoke": SMOKE},
               "split_counts": summary, "runs": {}}
    for run in RUNS:
        t1 = time.time()
        root = build_run_dir(recs, run["name"], run["taco"])
        model = YOLO(run["model"])
        model.train(data=str(root), epochs=EPOCHS, imgsz=IMGSZ, batch=64, patience=PATIENCE,
                    seed=SEED, workers=4, project=str(TMP / "runs"), name=run["name"], exist_ok=True,
                    plots=False, verbose=False, degrees=15.0, erasing=0.4)
        best = TMP / "runs" / run["name"] / "weights" / "best.pt"
        shutil.copy(best, WORK / f"{run['name']}_best.pt")
        res = evaluate(str(best), test)
        res["train_minutes"] = round((time.time() - t1) / 60, 1)
        res["model"] = run["model"]
        res["taco_in_train"] = run["taco"]
        results["runs"][run["name"]] = res
        json.dump(results, open(WORK / "results_polymint7.json", "w"), indent=1)
        print(f"== {run['name']}: test all {res['all']['acc']:.4f} | resin-labelled "
              f"{res['resin_labelled']['acc']:.4f} | macroF1 {res['resin_labelled']['macro_f1']:.4f} "
              f"({res['train_minutes']} min)", flush=True)

    print(json.dumps({k: {"all": v["all"]["acc"], "resin": v["resin_labelled"]["acc"],
                          "resin_f1": v["resin_labelled"]["macro_f1"]}
                      for k, v in results["runs"].items()}, indent=1))


if __name__ == "__main__":
    main()
