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
