"""Mark which provinces touch the sea (run after editing the bitmap).

Usage: python tools/build_coastal.py [map_dir]

Writes coastal.tsv (id, sea_px): sea_px is how many sea-facing pixel edges the province has.
Provinces with at least MIN_SEA_PX can host ports.
"""
import csv
import sys
from pathlib import Path

import numpy as np
from PIL import Image

MIN_SEA_PX = 8

root = Path(__file__).resolve().parent.parent
map_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "data" / "map"

img = np.array(Image.open(map_dir / "provinces.png").convert("RGB"))
key = img[..., 0].astype(np.int64) | (img[..., 1].astype(np.int64) << 8) | (img[..., 2].astype(np.int64) << 16)
sea = key == 0

by_key = {}
with open(map_dir / "provinces.tsv", encoding="utf-8") as f:
    for r in csv.DictReader(f, delimiter="\t"):
        by_key[int(r["r"]) | (int(r["g"]) << 8) | (int(r["b"]) << 16)] = int(r["id"])

counts = {}
for land, water in ((key[:, :-1], sea[:, 1:]), (key[:, 1:], sea[:, :-1]),
                    (key[:-1, :], sea[1:, :]), (key[1:, :], sea[:-1, :])):
    for k in np.unique(land[water]):
        if k in by_key:
            counts[by_key[k]] = counts.get(by_key[k], 0) + int(((land == k) & water).sum())

with open(map_dir / "coastal.tsv", "w", encoding="utf-8", newline="") as f:
    w = csv.writer(f, delimiter="\t", lineterminator="\n")
    w.writerow(["id", "sea_px"])
    for i in sorted(counts):
        if counts[i] >= MIN_SEA_PX:
            w.writerow([i, counts[i]])
print(sum(1 for c in counts.values() if c >= MIN_SEA_PX), "coastal provinces of", len(by_key))
