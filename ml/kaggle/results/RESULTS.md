# PolyMint ML results

## WaDaBa benchmark vs. base paper (Kaggle `polymint-wadaba-benchmark` v2, 2026-10-18)

The base paper is Chazhoor et al. 2022, "Deep transfer learning benchmark for plastic waste classification". It uses WaDaBa with 5 classes (PET, PE-HD, PP, PS, Other), 224 px input, 5-fold CV and an 80/20 split, and reports mean accuracy.

Our setup: YOLOv8s-cls with ImageNet-pretrained weights, 30 epochs, 224 px, Kaggle T4 GPU. Metrics are taken from the **last** epoch, so no checkpoint is picked on the test fold.

| Protocol | Accuracy (mean ± sd, 5 folds) | Macro-F1 | Balanced acc. |
|---|---|---|---|
| Base paper, ResNeXt (best) | 87.44% | n/r | n/r |
| Base paper, MobileNetV2 | 87.35% | n/r | n/r |
| **Ours, random image split (paper protocol)** | **99.67% ± 0.20** | 99.37% ± 0.51 | 99.64% ± 0.20 |
| **Ours, object-disjoint split** | **83.09% ± 6.99** | 76.14% ± 8.25 | 75.95% ± 7.28 |

How to read these:
- WaDaBa shows 100 physical objects about 40 times each. A random image split puts the same object in both train and test, which inflates every random-split number, including the paper's. The object-disjoint split is the honest generalisation estimate.
- In the object split, "Other" is a single object. It always stays in train and is not scored, so only PET, HDPE, PP and PS are evaluated.
- Macro-F1 and balanced accuracy for the object split were recomputed from the confusion matrices over the classes present. The v2 kernel's own `mean_macro_f1` (60.91) wrongly counted the absent "Other" class as 0. The script is now fixed.
- For comparison, a newer paper (arXiv 2412.20232, Dec 2024) reports 98.03% on WaDaBa with YOLO-11m.

Raw data: `benchmark_v2/results_wadaba.json` (per-fold confusion matrices, test object IDs).

## 7-class app model (Kaggle `polymint-7class` v2, 2026-10-18)

Sources: WaDaBa (split by object), harshitkandoi visual-plastic set, piaoya seven_plastics and TACO crops (object labels mapped to resin, so labels are approximate). Near-duplicates were removed with pHash (≤ 4 bits); clusters with conflicting labels were dropped. One fixed train/val/test split is used by all runs. Training: up to 100 epochs, patience 30, 224 px, best checkpoint chosen on val.

| Run | Test, all (n=1352) | Test, resin-labelled only (n=1020) | Macro-F1 (resin) |
|---|---|---|---|
| **v8s_all** (YOLOv8s-cls, all sources) | 71.89% | **76.27%** | **72.99%** |
| v8s_noTACO | 60.21% | 75.00% | 73.91% |
| y11s_all (YOLO11s-cls) | 72.63% | 76.47% | 70.24% |

- Exported model: `models/polymer7_v2_float32.tflite` (v8s_all; NHWC [1,224,224,3] → [1,7]; parity diff 0.0000). Labels, in sorted order: HDPE, LDPE, Other, PET, PP, PS, PVC.
- Weak spots: PVC has only 4 test images, so its recall is unreliable. The web-scraped visual set scores just 54–58%, and its labels are noisy (1,024 of its 2,653 images were dropped as duplicates or label conflicts).
- This is below the 85% plan target. More public data won't close the gap; domain-matched field images will.

## On-device evaluation through the app (2026-10-18)

This runs the bundled `polymer7-v2` through the **real app pipeline** (Dart `ImagePreprocessor` + `tflite_flutter`, Android emulator) on the run's held-out test images. Images come from seven_plastics (all 7 classes) and the visual-plastic set. WaDaBa and TACO are left out.

**How to reproduce:**
1. Run `python ml/kaggle/build_heldout.py --downloads dl --out heldout`. It rebuilds the exact 340 test images (0 class mismatches).
2. Run `flutter build apk --debug -t integration_test/eval_on_device_test.dart` and `adb install -r` the APK.
3. Push the images into the app:
   ```
   tar -cf h.tar -C heldout . && adb push h.tar /data/local/tmp/
   adb shell "run-as com.example.poly_mint sh -c 'mkdir -p files/eval && cd files/eval && tar -xf -' < /data/local/tmp/h.tar"
   ```
4. Launch the app. It writes `files/eval/device_preds.json` and logs per-class counts. Read the file back with `adb shell "run-as com.example.poly_mint cat files/eval/device_preds.json"`.

**App pipeline correctness:** on the 278 real images, the device agrees with the Python reference (same model, same crop and antialiased resize) on **276/278 = 99.3%** of top-1 predictions. Both disagreements are borderline calls below 0.6 confidence. The other **62 held-out images (all from the visual set) are broken scrapes**, such as 3000×32 px strips. On those the two decoders sometimes disagree, which says nothing about the pipeline. Similar images are presumably in the training split too.

**Accuracy per class** (device, 278 clean held-out images, 68.7% overall; seven_plastics 84.0%, visual 60.9%):

| Class | Correct | Main confusion |
|---|---|---|
| PET | 35/55 (64%) | → Other |
| HDPE | 11/12 (92%) | |
| PVC | 2/4 (50%) | → PP (only 4 test images) |
| LDPE | 11/14 (79%) | → HDPE |
| PP | 39/62 (63%) | → PET, Other, PS |
| PS | 18/42 (43%) | → Other, PP |
| Other | 75/89 (84%) | |

All 7 classes are recognised, but PET, PP and PS are weak, mostly confused with Other. This is partly the noisy web-scraped labels.

**The confidence gate is overconfident.** Among records the model calls with ≥ 0.85 confidence (AI_VERIFIED), only **76.4%** are correct. Raising the gate helps little: 81.4% at ≥ 0.95 and 85.0% at ≥ 0.99. Before trusting AI_VERIFIED, do the following:
- remove degenerate images (min side < 64 px or aspect ratio > 4) from training and retrain;
- calibrate the confidence on the validation split (e.g. temperature scaling);
- add field images of real DWCC plastic, which is the proposal's objective O1.

## Confidence calibration (2026-10-18)

The raw model is overconfident, as the on-device evaluation above shows. **Temperature scaling** fixes this: q_i ∝ p_i^(1/T), with T fitted by minimum NLL on the run's **val** split (seven_plastics + visual, broken scrapes removed, n = 279). It is evaluated on the separate **test** split (n = 278). The argmax, and so accuracy, is unchanged.

To reproduce: `python ml/kaggle/build_heldout.py ... --split val` and `python ml/kaggle/calibrate.py ...`.

**T = 4.077**

| Test split (n = 278) | ECE | NLL | Auto-verified (≥ 0.85) | Precision of auto-verified |
|---|---|---|---|---|
| Raw | 23.2 | 1.688 | 80% | 77.0% |
| **Calibrated** | **5.7** | **0.836** | **32%** | **95.5%** |

Confirmed through the app on the device: 89 of 278 batches auto-verified, 85 correct (95.5%), with every class represented. The other 68% go to manual review, which is honest for a model that is weak on PET, PP and PS. Field data (proposal objective O1) should raise both accuracy and the auto-verified share. Re-fit T whenever the model or data changes.

This calibration was fitted on public images only. Recalibrate on field images from the DWCC before relying on it in the field.
