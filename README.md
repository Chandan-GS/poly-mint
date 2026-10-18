# ♲ PolyMint

**AI-verified plastic recovery & circular-economy credit minting.**

PolyMint turns recovered plastic into verified impact. You place a batch on the scale and take a
photo. An on-device AI model identifies the polymer (PET, HDPE, PP…), and the
**Proof-of-Physical-Presence** check binds the photo to a live, hashed weight reading. Only then
does the app mint circular-economy credits.

## 🗺️ Project map

| Part | Where | What it is |
|---|---|---|
| **Mobile app** | `lib/`, `assets/`, `test/`, `integration_test/` | Flutter app: scan, PoPP weight check, on-device polymer model, minting, log, ranks |
| **Ledger dashboard** | `dashboard/` | Web dashboard for DWCC operators and auditors over the same Firestore ledger (see `dashboard/README.md`) |
| **ML** | `ml/` | Training, export and evaluation of the polymer model. Kaggle jobs, benchmark against the base paper, calibration (see `ml/README.md` and `ml/kaggle/results/RESULTS.md`) |
| **Backend** | `firestore.rules`, `firebase.json` | Append-only `plastic_transactions` ledger; Hosting serves `dashboard/` |

---

## ✨ Features

| Area | What it does |
|------|--------------|
| **On-device detection** | TFLite model classifies resin type with calibrated soft-max confidence, a ranked **top-3** candidate list, and optional **multi-frame averaging** for stability. |
| **Guided scanning** | Framing reticle, live tips, torch toggle, and an accuracy/speed mode. |
| **Manual correction** | Not sure? Pick from the AI's top suggestions or any resin code. |
| **Credit + CO₂ engine** | Per-resin credit rates and CO₂ factors compute impact live before minting. |
| **Offline-first ledger** | Batches minted offline are queued locally and **auto-sync** when connectivity returns. |
| **Impact dashboard** | Personal & global stats, material breakdown donut, 7-day trend, and real-world equivalences (trees, petrol, CO₂). |
| **History & filters** | Full recovery history, filterable by resin. |
| **Leaderboard** | Ranked contributors across the exchange. |
| **Recycling guide** | Educational reference for every resin code — identify, prep, value. |
| **Onboarding** | First-launch walkthrough of the scan → weigh → mint flow. |
| **Theming** | Material 3 light/dark/system, persisted. |

## 🏗️ Architecture

Feature-first structure on **flutter_bloc**, with `get_it` for dependency
injection and a clean data layer.

```
lib/
├── main.dart                 # bootstrap: Firebase, cameras, DI
├── app/                      # root widget, theme wiring, BlocObserver
├── core/
│   ├── theme/                # Material 3 design system (light/dark)
│   ├── di/                   # get_it service locator
│   ├── utils/                # formatters
│   └── widgets/              # shared UI (stat cards, badges, empty states)
├── data/
│   ├── models/               # PolymerInfo catalog, ClassificationResult,
│   │                         #   WasteTransaction, ImpactStats, Leaderboard
│   └── services/             # MlService, LocationService, ConnectivityService,
│                             #   PreferencesService, TransactionRepository
└── features/                 # onboarding · home · dashboard · scan ·
                              #   result · history · leaderboard · settings · guide
```

Each feature owns a **Cubit/Bloc** (business logic + streams) and a **View**
(pure UI). Services are singletons; blocs are created per-screen and pull
dependencies from the injector.

### State management
- **Cubits** for screen state (dashboard, scan, minting, history, leaderboard, settings).
- `TransactionRepository` exposes **live merged streams** (Firestore + local
  offline queue) so pending records appear instantly.
- `Bloc.observer` logs transitions/errors in development.

### Model detection pipeline (`MlService`)
Bundled model: **`polymer7-v2`**. It is a YOLOv8s-cls with 7 classes (PET, HDPE, PVC, LDPE, PP, PS,
Other), trained by `ml/kaggle/polymint7/` on about 8,400 de-duplicated public images. On held-out
resin-labelled test images it scores **76.3% top-1** (macro-F1 73.0%). PVC has very little data,
so treat PVC calls with care. See `ml/kaggle/results/RESULTS.md`.

1. Reads the input geometry from the model and checks that `labels.txt` matches its outputs.
2. Preprocesses each frame exactly like training (`ImagePreprocessor`): EXIF orientation,
   square center-crop, then a PIL-style **antialiased bilinear** resize to `[0, 1]`. The old
   `[-1, 1]` scaling and nearest-neighbour resize did not match training. Nearest-neighbour alone
   changed about 1 in 6 predictions on full-size photos.
3. Runs inference. The model already outputs probabilities, so softmax is only applied to raw
   logits.
4. Averages across frames (high-accuracy mode) and returns the ranked candidates plus the full
   probability map.

### Verification gate and ledger record
Confidences are **temperature-calibrated** (`ConfidenceCalibration`, T = 4.077, fitted on
validation images with `ml/kaggle/calibrate.py`). The raw model was overconfident: only 77% of its
"≥ 85%" calls were right. After calibration, **95.5%** of them are right on held-out images, with
about a third of batches auto-verified.

A record is **`AI_VERIFIED`** only when the minted resin is the model's own pick at
**≥ 85%** calibrated confidence. Otherwise it is **`MANUAL_REVIEW`**: either the model is below the gate or
the user overrode its pick. The result screen says which before minting, and the log shows
*Review*. Each record also stores:
- the model's own pick (`ai_polymer`, `ai_confidence`) and `model_version`;
- an honest `confidence`, meaning the model's probability for the resin actually recorded;
- the **PoPP proof** (`popp`): settle delta, stable window, capture offset, sample hash chain,
  sample count, simulated flag and verdict. An auditor can then re-check the physical event,
  not just the credit.

## 🚀 Getting started

```bash
flutter pub get
flutter run
```

Requires the Firebase config generated by the FlutterFire CLI
(`lib/firebase_options.dart`) and the model assets in `assets/model/`
(`polymer7_v2_float32.tflite`, `labels.txt`).

`labels.txt` maps output index *i* to a resin code. It must follow the model's class order
(training-folder names, sorted): `2-HDPE, 4-LDPE, 7-Other, 1-PET, 5-PP, 6-PS, 3-PVC`.
`test/model_labels_test.dart` enforces this.

Deploy the hardened Firestore rules (append-only, schema-validated,
immutable ledger):

```bash
firebase deploy --only firestore:rules
```

## 🧪 Quality

```bash
flutter analyze   # static analysis — clean
flutter test      # unit tests: impact aggregation, serialization, PoPP, verification gate,
                  # labels order, preprocessing parity with the training pipeline
flutter test integration_test -d <device-id>   # runs the bundled model on a device
```

## 📦 Tech stack

Flutter · flutter_bloc · get_it · tflite_flutter · camera · geolocator ·
cloud_firestore · connectivity_plus · shared_preferences · fl_chart · intl.
