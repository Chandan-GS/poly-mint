# PolyMint — ML (Phase 1, phone-only)

The ML workstream for PolyMint's Proof-of-Recycling node: a **7-class polymer
classifier** (PET, HDPE, PVC, LDPE, PP, PS, Other) + a **3-class purity grader**
(clean/mixed/contaminated), trained with Ultralytics YOLOv8-cls and exported to
**float32 TFLite** to run entirely on the phone via `tflite_flutter`. Includes the
on-device confidence gate and a Dart preprocessing contract so the app matches
training exactly.

> Phase 1 is **phone-only** → we export **float32** (max accuracy, no int8).
> int8 quantization, ESP32/Pi edge inference, and federated learning are Phase 2
> and out of scope here. The ESP32 only streams load-cell weight over BLE;
> **all ML runs in the Flutter app.**

---

## TL;DR for a new dev

```bash
# 0. setup (Python 3.12 recommended — see note below)
/opt/homebrew/bin/python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# 1. smoke-test the whole pipeline on fake data (no downloads, ~2 min)
./run_all.sh

# 2. build a REAL dataset (auto-downloads, no auth) and train the 7-class model
git clone --depth 1 https://github.com/pedropro/TACO.git data/taco_repo
python src/download_taco.py --ann data/taco_repo/data/annotations.json \
    --map configs/taco_map.yaml --out data/taco_crops --pad 0.15 --min-size 40
python src/download_hf_resin.py --out data/hf_crops
python src/prepare_dataset.py --source data/taco_crops data/hf_crops --identity-map \
    --out data/polymer7 --classes PET HDPE PVC LDPE PP PS Other --cap 350
python src/train.py --config configs/polymer7.yaml           # trains to convergence
python src/export_tflite.py --weights runs/polymer7/weights/best.pt --imgsz 224
python src/verify_parity.py --weights runs/polymer7/weights/best.pt \
    --tflite models/polymer7_float32.tflite --img $(find data/polymer7/test -name '*.jpg' | head -1)
```

---

## Current status (what's actually trained & shipped)

| Artifact | State |
|---|---|
| `models/polymer_float32.tflite` | **Shipped v0.** `yolov8n-cls`, 6 classes (no PVC), TACO-only. **Val top-1 ≈ 68%**, parity-verified (max prob diff 0.03). |
| `models/purity_float32.tflite` | **Placeholder** — trained on *synthetic* data. Runs, but means nothing until trained on real clean/mixed/contaminated images. |
| 7-class model (`configs/polymer7.yaml`) | **Pipeline ready, not fully trained.** A partial 14-epoch run scored 64% (undertrained). Run `train.py` to convergence to finish it — this is the recommended next step. |

**Why v0 is ~68%, not the 85% target — and how to close the gap:**
- **TACO labels by *object*, not resin** — a "bottle" → PET even if it's HDPE, so labels are noisy.
- **PVC is scarce** — TACO has none; the HF resin set adds only 24 PVC images. This class stays weak until more PVC data exists.
- **Class imbalance** — handled with `prepare_dataset.py --cap`, but small classes still hurt.
- **Biggest lever = more resin-labelled data.** The two auto-downloadable sources here get you a real v0; **WaDaBa** (4k resin-labelled images, incl. lots of PVC) is the clean win but is **license-gated** — see [Datasets](#datasets).

---

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

---

## Layout

```
ml/
├── README.md
├── requirements.txt
├── run_all.sh                     # end-to-end smoke test on synthetic data
├── configs/
│   ├── polymer.yaml               # 6/7-class nano config (TACO-only path)
│   ├── polymer7.yaml              # 7-class, yolov8s-cls + augmentation (best path)
│   ├── purity.yaml                # 3-class purity grader config
│   ├── taco_map.yaml              # TACO object categories -> 7 resin classes
│   └── class_map.yaml             # generic public-dataset labels -> classes
├── src/
│   ├── download_taco.py           # fetch TACO + crop annotations -> ImageFolder
│   ├── download_hf_resin.py       # fetch HF resin dataset (incl. PVC), no auth
│   ├── prepare_wadaba.py          # ingest WaDaBa zips (if you obtain the password)
│   ├── prepare_dataset.py         # ingest + remap + stratified split (+ --cap rebalance)
│   ├── make_synthetic_dataset.py  # fake data to test the plumbing offline
│   ├── train.py                   # YOLOv8-cls training + augmentation + val vs 85%
│   ├── export_tflite.py           # -> float32 .tflite + labels + meta (onnx2tf fallback)
│   ├── preprocessing.py           # CANONICAL preprocessing (source of truth)
│   ├── infer.py                   # phone-identical inference + confidence gate
│   └── verify_parity.py           # asserts tflite == pytorch (ship-gate)
├── notebooks/train_polymint_colab.ipynb   # same pipeline on Colab's free GPU
├── android/preprocessing_spec.md  # Dart/Flutter preprocessing contract
├── data/                          # datasets (gitignored)
└── models/                        # exported .tflite + labels (committed for the app)
```

---

## Setup

```bash
/opt/homebrew/bin/python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```
**Use Python 3.12.** 3.13 lacks some wheels; 3.9 (macOS system Python) is too old for
the export toolchain. On Apple Silicon, training auto-uses the `mps` GPU. First
`pip install` is heavy (~2–3 GB: torch + tensorflow + onnx2tf).

**Known install gotcha:** `onnxsim` can fail to build if pip backtracks to an old
version. `requirements.txt` avoids the bad pin; if you hit it, install onnxsim
unpinned first (`pip install onnxsim`) so it grabs the prebuilt wheel.

---

## Datasets

| Source | Auth? | Maps to resin? | How |
|---|---|---|---|
| **HF `plastic-recycling-codes`** | ✅ none | ✅ real resin labels, **incl. PVC** | `src/download_hf_resin.py` (~606 imgs) |
| **TACO** | ✅ none | ⚠️ by object (approximated) | `src/download_taco.py` (~1,557 crops, no PVC) |
| **WaDaBa** | ❌ license form + emailed password | ✅✅ 4,000 resin-labelled, lots of PVC | see below |
| **Synthetic** | ✅ none | ❌ fake (plumbing only) | `src/make_synthetic_dataset.py` |
| **Self-collected** | — | ✅ ground truth | label into class folders, ingest with `--identity-map` |

**WaDaBa (the clean win, but gated):** images are free but the download ZIPs are
**password-protected** — you must fill the contract form at http://wadaba.pcz.pl
and wait for an email with the password. If you get it:
```bash
# (download the 20 WaDaBa_*.zip archives into data/wadaba_zips first)
cd data/wadaba_zips && for z in *.zip; do unzip -P "<PASSWORD>" -o "$z" -d ../wadaba_extracted; done
python src/prepare_wadaba.py --zips data/wadaba_zips --out data/wadaba_crops   # if unencrypted
# then add data/wadaba_crops as another --source to prepare_dataset.py
```
`prepare_wadaba.py` maps WaDaBa's filename `aNN` code (`a01=PET … a06=PS`) to classes.

**Combine sources + rebalance:**
```bash
python src/prepare_dataset.py --source data/taco_crops data/hf_crops --identity-map \
    --out data/polymer7 --classes PET HDPE PVC LDPE PP PS Other --cap 350
```
`--cap N` randomly caps each class to N images (tames majority classes). Drop
`--cap` to use everything. For your own images, name folders exactly as the classes
and pass `--identity-map`; for object-labelled sources use `--class-map`.

---

## Train

```bash
# best path: 7-class, larger backbone + augmentation
python src/train.py --config configs/polymer7.yaml

# quick path: nano, whatever classes exist in data/polymer
python src/train.py --config configs/polymer.yaml

# purity grader (needs real clean/mixed/contaminated folders; synthetic = placeholder)
python src/train.py --config configs/purity.yaml
```
Prints val top-1 vs the **≥85%** target. Override on the CLI:
`--epochs 100 --batch 32 --model yolov8s-cls.pt --device cpu`. Augmentation
(HSV/rotation/flip/erasing/RandAugment) is set in the config.

**No local GPU?** Open `notebooks/train_polymint_colab.ipynb` (free T4, same steps,
downloads the `.tflite` at the end).

---

## Export → Test → Verify

```bash
# 1. export to float32 tflite (+ labels + meta sidecars)
python src/export_tflite.py --weights runs/polymer7/weights/best.pt --imgsz 224

# 2. run it exactly like the phone will (incl. the <0.85 gate)
python src/infer.py \
  --tflite models/polymer7_float32.tflite --labels models/polymer7.labels.txt \
  --purity-tflite models/purity_float32.tflite --purity-labels models/purity.labels.txt \
  --img some_bottle.jpg

# 3. ALWAYS verify parity before handing to the app  ← don't skip
python src/verify_parity.py --weights runs/polymer7/weights/best.pt \
  --tflite models/polymer7_float32.tflite --img some_bottle.jpg
```
Parity green = the TFLite + our preprocessing match PyTorch, so
`android/preprocessing_spec.md` is safe to port to Dart. Red = fix
`preprocessing.py` (and the Dart port) before shipping.

**Export note:** Ultralytics' native TFLite export crashes on Python 3.12 (dead
`tflite_support` dep). `export_tflite.py` auto-falls back to driving `onnx2tf`
directly — no action needed.

---

## Handoff to the mobile team
Ship: the `.tflite` file(s), the matching `.labels.txt`, and
**`android/preprocessing_spec.md`** (exact Dart preprocessing code). The
preprocessing contract matters as much as the model — mismatched preprocessing
silently wrecks on-device accuracy. Load class order from `.labels.txt`, never
hard-code it.

## Targets (plan, Phase 1)
- On-device inference **< 1 s** (mid-range Android) · float32 nano/s-cls both qualify
- Classifier **top-1 ≥ 85%** on a field-like val set
- Confidence **< 0.85 → MANUAL_REVIEW** (never auto-mint)

## Active-learning loop
Every MANUAL_REVIEW image in the app is a new labelled example. Periodically drop
those into `data/…/<class>/`, re-run `prepare_dataset.py` → `train.py` → export.
The gate's cost shrinks as the model improves — the plan's continuous loop.

## Not in this repo (by design — later phases)
int8 quantization · ESP32/Pi on-device inference · federated learning ·
PoPP / SHA-256 / pHash / crypto (mobile/edge + backend teams, not ML).
```
