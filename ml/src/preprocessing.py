#!/usr/bin/env python3
"""
preprocessing.py — THE canonical preprocessing for PolyMint's on-device models.

This is the single source of truth. The Dart/Flutter side (see
android/preprocessing_spec.md) MUST reproduce these exact steps, or on-device
accuracy will silently drop even though the model is fine. Mismatched
preprocessing is the #1 cause of "works in Python, wrong on phone".

Steps (match Ultralytics YOLOv8-cls default predict transform, crop_fraction=1.0):
  1. Decode image, convert to RGB (drop alpha).
  2. Resize the SHORTER side to `size` (bilinear), preserving aspect ratio.
  3. Center-crop a `size` x `size` square.
  4. Cast to float32 and scale to [0,1]  ->  pixel / 255.0
     (Ultralytics default mean=(0,0,0), std=(1,1,1) => no ImageNet norm.)
  5. Layout NHWC: shape [1, size, size, 3].

If verify_parity.py ever disagrees with Ultralytics on your installed version,
this function — and the Dart port — are what you adjust.
"""
from __future__ import annotations

import numpy as np
from PIL import Image

IMG_SIZE = 224
SCALE = 1.0 / 255.0
# Kept explicit so the Dart side has named constants to mirror.
MEAN = (0.0, 0.0, 0.0)
STD = (1.0, 1.0, 1.0)


def _resize_shorter_then_center_crop(img: Image.Image, size: int) -> Image.Image:
    w, h = img.size
    if w <= h:
        new_w = size
        new_h = max(size, round(h * size / w))
    else:
        new_h = size
        new_w = max(size, round(w * size / h))
    img = img.resize((new_w, new_h), Image.BILINEAR)
    left = (new_w - size) // 2
    top = (new_h - size) // 2
    return img.crop((left, top, left + size, top + size))


def preprocess(img: "Image.Image | str", size: int = IMG_SIZE) -> np.ndarray:
    """Return a float32 NHWC [1,size,size,3] tensor ready for tflite input."""
    if isinstance(img, str):
        img = Image.open(img)
    img = img.convert("RGB")
    img = _resize_shorter_then_center_crop(img, size)
    arr = np.asarray(img, dtype=np.float32) * SCALE           # [H,W,3] in [0,1]
    if MEAN != (0.0, 0.0, 0.0) or STD != (1.0, 1.0, 1.0):     # future-proof
        arr = (arr - np.array(MEAN, np.float32)) / np.array(STD, np.float32)
    return arr[np.newaxis, ...]                               # [1,H,W,3]


def softmax(x: np.ndarray) -> np.ndarray:
    x = x - np.max(x)
    e = np.exp(x)
    return e / e.sum()


if __name__ == "__main__":
    import sys
    t = preprocess(sys.argv[1])
    print(f"tensor {t.shape} {t.dtype}  min={t.min():.3f} max={t.max():.3f}")
