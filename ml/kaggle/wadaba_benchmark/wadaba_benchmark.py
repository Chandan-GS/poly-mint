#!/usr/bin/env python3
"""
wadaba_benchmark.py — PolyMint vs. the base paper on WaDaBa (Kaggle GPU job).

Base paper: Chazhoor et al. 2022, "Deep transfer learning benchmark for plastic
waste classification" (Intelligence & Robotics). Their protocol:
  * WaDaBa, 5 classes (PET, PE-HD, PP, PS, Other) — PVC and PE-LD dropped
  * 224x224 input, 5-fold cross-validation, 80/20 split, mean accuracy reported
  * best model ResNeXt 87.44%, MobileNetV2 87.35%

We run the same 5-fold protocol with YOLOv8s-cls (the model the app ships) under
two splits:
  * "random" — split by IMAGE, exactly like the paper. WaDaBa photographs each of
    its 100 physical objects ~40 times, so the same object lands in train AND test.
  * "object" — split by OBJECT (StratifiedGroupKFold). No object is seen in both,
    which is the honest generalisation number.

Accuracy is reported from the LAST epoch (fixed schedule, no checkpoint picked on
the test fold), so it is not optimistic.

Output: /kaggle/working/results_wadaba.json
"""
import json
import os
import re
import subprocess
import sys
import time
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from glob import glob
from pathlib import Path

SMOKE = False          # True = 1 epoch, 1 fold per protocol (pipeline check only)
EPOCHS = 1 if SMOKE else 30
FOLDS = 5
IMGSZ = 224
MODEL = "yolov8s-cls.pt"
SEED = 0

subprocess.run([sys.executable, "-m", "pip", "install", "-q", "ultralytics"], check=True)

import numpy as np
from PIL import Image
from sklearn.metrics import confusion_matrix, f1_score
from sklearn.model_selection import StratifiedGroupKFold, StratifiedKFold
from ultralytics import YOLO

WORK = Path("/kaggle/working")
TMP = Path("/tmp/pm")
A_TO_CLASS = {"01": "PET", "02": "HDPE", "05": "PP", "06": "PS", "07": "Other"}
CLASSES = sorted(A_TO_CLASS.values())          # Ultralytics orders classes by folder name
NAME_RE = re.compile(r"(\d{4})_a(\d{2})")


def resize_short(src: str, dst: Path, short: int = 256):
    im = Image.open(src).convert("RGB")
    w, h = im.size
    s = short / min(w, h)
    if s < 1:
        im = im.resize((round(w * s), round(h * s)), Image.BILINEAR)
    dst.parent.mkdir(parents=True, exist_ok=True)
    im.save(dst, quality=95)


def load_wadaba():
    files = sorted(glob("/kaggle/input/**/WaDaBa_*/*.jpg", recursive=True))
    items = []
    for f in files:
        m = NAME_RE.search(os.path.basename(f))
        if m and m.group(2) in A_TO_CLASS:
            items.append((f, A_TO_CLASS[m.group(2)], m.group(1)))   # path, class, object id
    print(f"WaDaBa: {len(items)} images, classes {Counter(c for _, c, _ in items)}")
    print(f"objects per class: { {c: len({o for _, cc, o in items if cc == c}) for c in CLASSES} }")
    out = []
    with ThreadPoolExecutor(16) as ex:
        futs = []
        for f, c, o in items:
            dst = TMP / "wadaba256" / c / os.path.basename(f)
            futs.append(ex.submit(resize_short, f, dst))
            out.append((str(dst), c, o))
        for fu in futs:
            fu.result()
    return out


def link_split(root: Path, split: str, items):
    for p, c, *_ in items:
        d = root / split / c
        d.mkdir(parents=True, exist_ok=True)
        dst = d / os.path.basename(p)
        if not dst.exists():
            os.symlink(p, dst)


def predict(weights, items):
    model = YOLO(weights)
    paths = [p for p, *_ in items]
    preds = []
    for i in range(0, len(paths), 128):
        for r in model.predict(paths[i:i + 128], imgsz=IMGSZ, verbose=False):
            preds.append(r.names[r.probs.top1])
    return preds


def run_fold(protocol, k, train, test, val_extra=()):
    name = f"{protocol}_f{k}"
    root = TMP / "folds" / name
    link_split(root, "train", train)
    # val_extra only keeps every class folder present for Ultralytics' per-epoch
    # monitor; our reported metrics use `test` alone.
    link_split(root, "val", list(test) + list(val_extra))
    t0 = time.time()
    model = YOLO(MODEL)
    model.train(data=str(root), epochs=EPOCHS, imgsz=IMGSZ, batch=64, patience=EPOCHS + 1,
                seed=SEED, workers=4, project=str(TMP / "runs"), name=name, exist_ok=True,
                plots=False, verbose=False)
    last = TMP / "runs" / name / "weights" / "last.pt"
    y_true = [c for _, c, _ in test]
    y_pred = predict(str(last), test)
    acc = float(np.mean([a == b for a, b in zip(y_true, y_pred)]))
    res = {
        "fold": k, "n_train": len(train), "n_test": len(test),
        "test_objects": sorted({o for *_, o in test}),
        "acc": acc,
        # score only classes present in this fold ("Other" is absent from object-split test folds)
        "macro_f1": float(f1_score(y_true, y_pred, labels=sorted(set(y_true)), average="macro", zero_division=0)),
        "per_class_recall": {c: (float(np.mean([p == c for t, p in zip(y_true, y_pred) if t == c]))
                                 if c in y_true else None) for c in CLASSES},
        "test_class_counts": dict(Counter(y_true)),
        "confusion": confusion_matrix(y_true, y_pred, labels=CLASSES).tolist(),
        "train_minutes": round((time.time() - t0) / 60, 1),
    }
    print(f"[{name}] acc={acc:.4f} macroF1={res['macro_f1']:.4f} ({res['train_minutes']} min)", flush=True)
    return res


def main():
    TMP.mkdir(parents=True, exist_ok=True)
    data = load_wadaba()
    y = np.array([c for _, c, _ in data])
    groups = np.array([o for *_, o in data])
    X = np.zeros(len(data))

    # WaDaBa's "Other" is ONE physical object, so it cannot be held out by object:
    # in the object protocol it always stays in train and is not scored.
    other = [d for d in data if d[1] == "Other"]
    obj = [d for d in data if d[1] != "Other"]
    yo = np.array([c for _, c, _ in obj])
    go = np.array([o for *_, o in obj])
    splitters = {
        "random": (data, StratifiedKFold(FOLDS, shuffle=True, random_state=SEED).split(X, y), []),
        "object": (obj, StratifiedGroupKFold(FOLDS, shuffle=True, random_state=SEED)
                   .split(np.zeros(len(obj)), yo, go), other),
    }
    results = {"config": {"model": MODEL, "epochs": EPOCHS, "imgsz": IMGSZ, "folds": FOLDS,
                          "classes": CLASSES, "smoke": SMOKE,
                          "base_paper_best": {"ResNeXt": 87.44, "MobileNetV2": 87.35}}}
    for protocol, (pool, split, always_train) in splitters.items():
        folds = []
        for k, (tr, te) in enumerate(split):
            if SMOKE and k > 0:
                break
            folds.append(run_fold(protocol, k, [pool[i] for i in tr] + always_train,
                                  [pool[i] for i in te], val_extra=always_train))
            json.dump(results | {protocol: {"folds": folds}}, open(WORK / "results_wadaba.json", "w"), indent=1)
        accs = [f["acc"] for f in folds]
        f1s = [f["macro_f1"] for f in folds]
        results[protocol] = {
            "folds": folds,
            "mean_acc": float(np.mean(accs)), "std_acc": float(np.std(accs)),
            "mean_macro_f1": float(np.mean(f1s)),
        }
        print(f"== {protocol}: mean acc {np.mean(accs) * 100:.2f}% ± {np.std(accs) * 100:.2f}", flush=True)
        json.dump(results, open(WORK / "results_wadaba.json", "w"), indent=1)

    print(json.dumps({p: {k: v for k, v in r.items() if k != "folds"}
                      for p, r in results.items() if p != "config"}, indent=1))


if __name__ == "__main__":
    main()
