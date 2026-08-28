# PolyMint — ML (Phase 1, phone-only)

The complete ML workstream for PolyMint's Proof-of-Recycling node: a **7-class
polymer classifier** + a **3-class purity grader**, trained with Ultralytics
YOLOv8-cls and exported to **float32 TFLite** to run entirely on the phone via
`tflite_flutter`. Includes the on-device confidence gate and a Dart preprocessing
contract so the app matches training exactly.

> Phase 1 is **phone-only** — so we export **float32** (max accuracy, no int8).
> int8 quantization, ESP32/Pi edge inference, and federated learning are Phase 2
> and are intentionally out of scope here. The ESP32 only streams load-cell
> weight over BLE; **all ML runs in the Flutter app.**

## Current status — trained v0 exists ✅

A real model has been trained end-to-end and exported. Reproducible via the steps
below; artifacts land in `models/` (gitignored — regenerate or share out-of-band).

| | Result |
|---|---|
| Polymer model | `yolov8n-cls`, **6 classes** (PET, HDPE, LDPE, PP, PS, Other) |
| Training data | **1,557 real crops** from TACO (`download_taco.py`) |
| Val top-1 | **~68%** — **below the 85% target** (see why ↓) |
| TFLite export | float32, ~5.5 MB, parity-verified vs PyTorch (max prob diff 0.03) ✅ |
| Purity model | placeholder trained on **synthetic** data — needs real labels |

**Why 68%, not 85%, and how to close it:**
- **TACO labels by object, not resin** — a "bottle" is mapped to PET but may be HDPE, so labels are noisy. Only WaDaBa / self-collected resin-labelled images fix this.
- **No PVC** — TACO has none, so the model is 6-class. PVC needs self-collected data.
- **Class imbalance** — LDPE (660) ≫ PS (107). Balance with more field images.
- The path to 85% is **self-collected scrapyard images + active learning**, exactly as the plan states. The pipeline is proven; it now needs better data, not more code.

## What the ML delivers to the rest of the system

For each armed capture the app gets:

```json
{
  "polymer": "PET",
  "confidence": 0.94,
  "purity": { "grade": "clean", "confidence": 0.88 },
  "status": "AI_VERIFIED"        // or "MANUAL_REVIEW" if confidence < 0.85
}
```

`polymer` + `purity` feed the minting formula
(`creditValue = weightKg × polymerMultiplier[type] × purityFactor[grade]`);
`status = MANUAL_REVIEW` blocks auto-minting — the plan's conservative gate.

## Layout

```
PolyMint_ML/
├── README.md
├── requirements.txt
├── run_all.sh                  # end-to-end smoke test on synthetic data
├── configs/
│   ├── polymer.yaml            # 7-class training config
│   ├── purity.yaml             # 3-class training config
│   └── class_map.yaml          # public-dataset labels -> PolyMint classes
├── src/
│   ├── prepare_dataset.py      # build YOLO-cls dataset (ingest + remap + split)
│   ├── make_synthetic_dataset.py  # fake data to test the plumbing offline
│   ├── train.py                # YOLOv8n-cls training + val vs 85% target
│   ├── export_tflite.py        # -> float32 .tflite + labels + meta sidecars
│   ├── preprocessing.py        # CANONICAL preprocessing (source of truth)
│   ├── infer.py                # phone-identical inference + confidence gate
│   └── verify_parity.py        # asserts tflite == pytorch (ship-gate)
├── android/
│   └── preprocessing_spec.md   # Dart/Flutter preprocessing contract
├── data/                       # datasets (gitignored)
└── models/                     # exported .tflite + labels (gitignored)
```

## Setup

```bash
cd ~/Desktop/PolyMint_ML
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```
Python 3.10/3.11 recommended. On Apple Silicon, training uses the `mps` device
automatically; CPU also works for the nano model (just slower).

## Quickstart — verify the plumbing (no downloads)

```bash
./run_all.sh
```
Generates synthetic data → trains 5 epochs → exports TFLite → runs inference →
parity check. If this completes, every moving part works and you only need to
swap in real images. (Synthetic data teaches the model nothing real — it only
proves the pipeline.)

## Real pipeline

### 1. Datasets

> **Current status: no dataset is downloaded yet.** `data/` is empty. The repo
> knows *how* to ingest the sources below (via `configs/class_map.yaml` +
> `prepare_dataset.py`), but you must download them yourself first. The only
> data that exists out-of-the-box is the **synthetic** set from
> `make_synthetic_dataset.py`, which only tests the plumbing and teaches the
> model nothing real.

Bootstrap from open sources, then dominate with self-collected scrapyard images:

| Source | Format | Fit for our 7-class resin split |
|---|---|---|
| **WaDaBa** | resin-code coded | ⭐ **Best fit** — already organized by resin code (PET/HDPE/PVC…). Make this the primary bootstrap. |
| **TACO** | COCO-JSON | Weak — labels by *object* (bottle/bag/cup); resin must be inferred. Crop annotations → ImageFolder first. |
| **RealWaste** | folder-per-category | Weak — labels by object type, real waste photos. Resin inferred, lossy. |
| **TrashNet** | folder-per-material | Poor — has only **one** generic `plastic` class, not the 7 resins. Marginal value. |
| **Self-collected** | you label | **The real distribution — matters most.** Public data is a warm start; field images are what actually move accuracy. |

**Reality check:** only **WaDaBa** maps cleanly onto PET/HDPE/PVC/LDPE/PP/PS/Other.
The others label by object category, so `configs/class_map.yaml` can only *approximate*
resin from object type (a "bottle" may be PET or HDPE). Expect the public-data model
to be a rough v0 — the accuracy target is reached by adding self-collected scrapyard
images + the active-learning relabels.

**Fastest real dataset — TACO (one command, no auth):** `src/download_taco.py`
downloads TACO images and crops the annotated plastic objects into an
ImageFolder, mapping TACO's object categories → the 7 resin classes via
`configs/taco_map.yaml`. Great for a real v0; note **PVC is absent in TACO** and
classes are imbalanced (LDPE-heavy), so it's a warm start, not the finish line.

```bash
git clone --depth 1 https://github.com/pedropro/TACO.git data/taco_repo
python src/download_taco.py --ann data/taco_repo/data/annotations.json \
    --map configs/taco_map.yaml --out data/taco_crops --pad 0.15 --min-size 40
python src/prepare_dataset.py --source data/taco_crops --identity-map \
    --out data/polymer --classes PET HDPE PVC LDPE PP PS Other
```

**Or bring your own** — put each source as `raw_label/*.jpg` sub-folders, then:

```bash
python src/prepare_dataset.py \
  --source ~/datasets/trashnet ~/datasets/realwaste \
  --class-map configs/class_map.yaml \
  --out data/polymer \
  --classes PET HDPE PVC LDPE PP PS Other
```

**No local GPU?** Use `notebooks/train_polymint_colab.ipynb` — same pipeline on
Colab's free T4, with a download cell for the resulting `.tflite` + labels.
Edit `configs/class_map.yaml` to control how raw labels fold into the 7 classes.
For purity, label your own images into `clean/ mixed/ contaminated/` folders and
ingest with `--identity-map` (see the script header).

### 2. Train
```bash
python src/train.py --config configs/polymer.yaml
python src/train.py --config configs/purity.yaml
```
Prints top-1 vs the plan's **≥85%** target. Tune epochs/augmentation in the
config; bump to `yolov8s-cls.pt` only if accuracy needs it and latency allows.

### 3. Export to float32 TFLite
```bash
python src/export_tflite.py --weights runs/polymer/weights/best.pt --imgsz 224
python src/export_tflite.py --weights runs/purity/weights/best.pt  --imgsz 224
```
Produces `models/<name>_float32.tflite`, `<name>.labels.txt`, `<name>.meta.yaml`.

### 4. Test inference + the gate
```bash
python src/infer.py \
  --tflite models/polymer_float32.tflite --labels models/polymer.labels.txt \
  --purity-tflite models/purity_float32.tflite --purity-labels models/purity.labels.txt \
  --img some_bottle.jpg
```

### 5. Verify parity BEFORE handing to the app  ← don't skip
```bash
python src/verify_parity.py --weights runs/polymer/weights/best.pt \
  --tflite models/polymer_float32.tflite --img some_bottle.jpg
```
Green = the TFLite model + our preprocessing match PyTorch, so
`android/preprocessing_spec.md` is safe to port to Dart. Red = fix
`preprocessing.py` (and the Dart port) before shipping.

## Handoff to the mobile team
Give them: the two `.tflite` files, the two `.labels.txt` files, and
**`android/preprocessing_spec.md`** (has the exact Dart preprocessing code). The
preprocessing contract is as important as the model — mismatched preprocessing
silently wrecks on-device accuracy.

## Targets (from the plan, Phase 1)
- On-device inference **< 1 s** (mid-range Android)
- Classifier **top-1 ≥ 85%** on a field-like val set
- Confidence **< 0.85 → MANUAL_REVIEW** (never auto-mint)

## Active-learning loop
Every MANUAL_REVIEW decision in the app is a new labelled example. Periodically
export those images into `data/polymer/` (or purity), re-run `train.py`, re-export.
The gate's cost shrinks as the model improves — exactly the plan's continuous loop.

## Not in this repo (by design — later phases)
int8 quantization · ESP32/Pi on-device inference · federated learning ·
PoPP / SHA-256 / pHash / crypto (those live on the mobile/edge + backend teams,
not ML).
```
