"""Derive province adjacencies from data/map/provinces.png (run after editing the bitmap).

Usage: python tools/build_adjacencies.py [map_dir]

Writes adjacencies.tsv (id_a, id_b, border_px, kind = land|strait; a < b) and tools/preview_political.png.
Narrow sea crossings are detected from the bitmap; the rest (e.g. Dover-Calais) go in
data/map/adjacency_overrides.tsv (name_a, name_b, kind).
"""
import csv
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

root = Path(__file__).resolve().parent.parent
map_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "data" / "map"

img = np.array(Image.open(map_dir / "provinces.png").convert("RGB"))
key = img[..., 0].astype(np.int64) | (img[..., 1].astype(np.int64) << 8) | (img[..., 2].astype(np.int64) << 16)

by_key, rows = {}, []
with open(map_dir / "provinces.tsv", encoding="utf-8") as f:
    for r in csv.DictReader(f, delimiter="	"):
        k = int(r["r"]) | (int(r["g"]) << 8) | (int(r["b"]) << 16)
        by_key[k] = int(r["id"])
        rows.append(r)

lut_keys = np.array(sorted(by_key))
lut_ids = np.array([by_key[k] for k in lut_keys])
idx = np.searchsorted(lut_keys, key)
idx[idx >= len(lut_keys)] = 0
ids = np.where(lut_keys[idx] == key, lut_ids[idx], 0)  # 0 = sea / background / unknown color

pairs = {}
for a, b in ((ids[:, :-1], ids[:, 1:]), (ids[:-1, :], ids[1:, :])):
    m = (a != b) & (a > 0) & (b > 0)
    lo, hi = np.minimum(a[m], b[m]), np.maximum(a[m], b[m])
    u, c = np.unique(lo.astype(np.int64) * 100000 + hi, return_counts=True)
    for k, n in zip(u, c):
        pairs[int(k)] = pairs.get(int(k), 0) + int(n)

# ---- sea crossings: narrow water between two different land provinces
STRAIT_PX = 30   # always linked (~21 km)
MAX_GAP_PX = 200  # isolated provinces are linked to their nearest neighbour within this
sea = key == 0
gaps = {}


def scan(ids2d, sea2d):
    for r in range(ids2d.shape[0]):
        row = ids2d[r]
        xs = np.flatnonzero(row > 0)
        if xs.size < 2:
            continue
        d = xs[1:] - xs[:-1]
        for g in np.flatnonzero((d > 1) & (d <= MAX_GAP_PX + 1)):
            a, b = xs[g], xs[g + 1]
            ia, ib = int(row[a]), int(row[b])
            if ia == ib or not sea2d[r, a + 1:b].all():
                continue
            k = (min(ia, ib), max(ia, ib))
            gaps[k] = min(gaps.get(k, 1 << 30), int(b - a - 1))


scan(ids, sea)
scan(ids.T, sea.T)

land = {divmod(k, 100000) for k in pairs}
links = {k: (v, "land") for k, v in ((divmod(k, 100000), n) for k, n in pairs.items())}
for k, dist in gaps.items():
    if k not in land and dist <= STRAIT_PX:
        links[k] = (0, "strait")


def connected():
    return {i for k in links for i in k}


id_by_name = {r["name"]: int(r["id"]) for r in rows}
name_by_id = {v: k for k, v in id_by_name.items()}
for r in rows:  # islands: link to the nearest province across the water
    pid = int(r["id"])
    if pid in connected():
        continue
    cands = [(d, k) for k, d in gaps.items() if pid in k]
    if cands:
        d, k = min(cands)
        links[k] = (0, "strait")
        print(f"island {r['name']}: strait to {name_by_id[k[0] if k[1] == pid else k[1]]} ({d} px)")

overrides = map_dir / "adjacency_overrides.tsv"
if overrides.exists():
    with open(overrides, encoding="utf-8") as f:
        for r in csv.DictReader(f, delimiter="\t"):
            a, b = id_by_name[r["name_a"]], id_by_name[r["name_b"]]
            links[(min(a, b), max(a, b))] = (0, r["kind"])

with open(map_dir / "adjacencies.tsv", "w", newline="") as f:
    w = csv.writer(f, delimiter="\t")
    w.writerow(["id_a", "id_b", "border_px", "kind"])
    for (a, b) in sorted(links):
        w.writerow([a, b, links[(a, b)][0], links[(a, b)][1]])
print(f"{sum(1 for v in links.values() if v[1] == 'land')} land links, "
      f"{sum(1 for v in links.values() if v[1] != 'land')} sea links")

# connectivity report: every playable region should be one component or be linked by a strait
parent = {int(r["id"]): int(r["id"]) for r in rows}


def find(x):
    while parent[x] != x:
        parent[x] = parent[parent[x]]
        x = parent[x]
    return x


for a, b in links:
    parent[find(a)] = find(b)
comps = {}
for pid in parent:
    comps.setdefault(find(pid), []).append(name_by_id[pid])
for members in sorted(comps.values(), key=len, reverse=True):
    print(f"component of {len(members)}: {', '.join(members[:4])}{' ...' if len(members) > 4 else ''}")

# preview
nations = json.loads((root / "data" / "nations.json").read_text(encoding="utf-8"))
owner_by_id = {int(r["id"]): r["owner"] for r in rows}
pal = np.zeros((max(owner_by_id) + 1, 3), dtype=np.uint8)
for pid, tag in owner_by_id.items():
    h = nations[tag]["color"].lstrip("#")
    pal[pid] = [int(h[i:i + 2], 16) for i in (0, 2, 4)]
out = pal[ids]
out[(ids == 0) & (key == 0)] = (30, 50, 80)
out[(ids == 0) & (key != 0)] = (150, 150, 140)
edge = np.zeros(ids.shape, dtype=bool)
edge[:, :-1] |= ids[:, :-1] != ids[:, 1:]
edge[:-1, :] |= ids[:-1, :] != ids[1:, :]
out[edge & (ids > 0)] = (out[edge & (ids > 0)] * 0.55).astype(np.uint8)
Image.fromarray(out).resize((out.shape[1] // 3, out.shape[0] // 3), Image.LANCZOS).save(root / "tools" / "preview_political.png")
