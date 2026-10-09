"""Partition the sea into zones (run after editing the bitmap or the seeds).

Usage: python tools/build_sea_zones.py [map_dir]

Reads data/map/sea_zones.tsv (id, name, x, y = a seed point in bitmap pixels; the other columns
are written by this tool) and provinces.png, coastal.tsv. Every sea pixel joins the nearest seed
by distance through water (so a zone never leaps a peninsula). Writes:

  sea_zones.png       one pixel per ZONE_SCALE x ZONE_SCALE bitmap pixels; red channel = zone id
                      (0 = sea no seed reaches, such as the Caspian); land takes the nearest zone
  sea_zones.tsv       the seeds again, plus cx, cy (a water point near the zone's middle) and area
  sea_adjacency.tsv   id_a, id_b, border (cells) for zones that touch (a < b)
  ports.tsv           id (province), zone, zone2 (0 if none), sea_px: where each coastal province
                      opens on the water; zone2 is a second zone holding >= SECOND_SHARE of it

Fails if a zone is missing or empty or the zone graph is not connected. A coastal province whose
water belongs to no zone (the Arctic and the Caspian) gets no port and is listed; one whose water
is a pocket (an estuary) borrows the nearest zone within FALLBACK_CELLS.
"""
import csv
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ZONE_SCALE = 4
SECOND_SHARE = 0.3
FALLBACK_CELLS = 40

root = Path(__file__).resolve().parent.parent
map_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "data" / "map"

img = np.array(Image.open(map_dir / "provinces.png").convert("RGB"))
H, W = img.shape[:2]
key = img[..., 0].astype(np.int64) | (img[..., 1].astype(np.int64) << 8) | (img[..., 2].astype(np.int64) << 16)
sea = key == 0
del img

seeds = []
with open(map_dir / "sea_zones.tsv", encoding="utf-8") as f:
    for r in csv.DictReader(f, delimiter="\t"):
        seeds.append((int(r["id"]), r["name"], int(r["x"]), int(r["y"])))
assert [s[0] for s in seeds] == list(range(1, len(seeds) + 1)), "zone ids must run 1..N"
assert len(seeds) < 64

# Low-resolution water mask: a cell is water if any of its pixels is sea (keeps straits open).
h, w = -(-H // ZONE_SCALE), -(-W // ZONE_SCALE)
pad = np.zeros((h * ZONE_SCALE, w * ZONE_SCALE), dtype=bool)
pad[:H, :W] = sea
water = pad.reshape(h, ZONE_SCALE, w, ZONE_SCALE).any(axis=(1, 3))
del pad

# Snap each seed to the nearest water cell.
dist, (iy, ix) = ndimage.distance_transform_edt(~water, return_indices=True)
labels = np.zeros((h, w), dtype=np.int16)
for zid, name, x, y in seeds:
    cy, cx = min(y // ZONE_SCALE, h - 1), min(x // ZONE_SCALE, w - 1)
    sy, sx = iy[cy, cx], ix[cy, cx]
    if dist[cy, cx] > 40:
        sys.exit(f"seed {zid} {name} is {dist[cy, cx]:.0f} cells from water")
    labels[sy, sx] = zid

# Geodesic Voronoi: grow every label one step at a time through water, alternating 4 and 8
# neighbourhoods (an octagonal distance) until nothing changes.
cross = ndimage.generate_binary_structure(2, 1)
square = ndimage.generate_binary_structure(2, 2)
step = 0
while True:
    grown = ndimage.grey_dilation(labels, footprint=cross if step % 2 == 0 else square)
    new = (labels == 0) & water & (grown > 0)
    if not new.any() and step % 2 == 1:
        break
    labels[new] = grown[new]
    step += 1

unseeded = water & (labels == 0)
# Land (and unreachable water) takes the nearest zone so lookups near a coast stay valid.
_, (iy, ix) = ndimage.distance_transform_edt(labels == 0, return_indices=True)
filled = labels[iy, ix]
nearest = filled.copy()
filled[unseeded] = 0

Image.fromarray(filled.astype(np.uint8)[..., None].repeat(3, axis=2) * np.array([1, 0, 0], dtype=np.uint8)).save(map_dir / "sea_zones.png")

# Zone of every sea pixel at full resolution.
zone_full = np.repeat(np.repeat(filled.astype(np.uint8), ZONE_SCALE, axis=0), ZONE_SCALE, axis=1)[:H, :W]
zone_full[~sea] = 0
lost = int((sea & (zone_full == 0)).sum())
print(f"{int(sea.sum())} sea pixels, {lost} in no zone ({100.0 * lost / sea.sum():.1f}%)")

# Zone table: area, and a water point near the middle.
areas = np.bincount(zone_full.ravel(), minlength=len(seeds) + 1)
rows = []
for zid, name, x, y in seeds:
    if areas[zid] == 0:
        sys.exit(f"zone {zid} {name} has no water")
    ys, xs = np.nonzero(zone_full[:: ZONE_SCALE, :: ZONE_SCALE] == zid)
    mx, my = xs.mean(), ys.mean()
    j = int(np.argmin((xs - mx) ** 2 + (ys - my) ** 2))
    rows.append((zid, name, x, y, int(xs[j]) * ZONE_SCALE, int(ys[j]) * ZONE_SCALE, int(areas[zid])))
with open(map_dir / "sea_zones.tsv", "w", encoding="utf-8", newline="") as f:
    wr = csv.writer(f, delimiter="\t", lineterminator="\n")
    wr.writerow(["id", "name", "x", "y", "cx", "cy", "area"])
    wr.writerows(rows)

# Adjacency: zones whose water cells touch.
pairs = {}
real = water & (filled > 0)
for a, b in ((filled[:, :-1], filled[:, 1:]), (filled[:-1, :], filled[1:, :])):
    ra, rb = (real[:, :-1], real[:, 1:]) if a.shape[0] == h else (real[:-1, :], real[1:, :])
    m = ra & rb & (a != b) & (a > 0) & (b > 0)
    lo, hi = np.minimum(a[m], b[m]), np.maximum(a[m], b[m])
    for p, n in zip(*np.unique(lo.astype(np.int32) * 64 + hi, return_counts=True)):
        pairs[(int(p) // 64, int(p) % 64)] = pairs.get((int(p) // 64, int(p) % 64), 0) + int(n)
with open(map_dir / "sea_adjacency.tsv", "w", encoding="utf-8", newline="") as f:
    wr = csv.writer(f, delimiter="\t", lineterminator="\n")
    wr.writerow(["id_a", "id_b", "border"])
    for (a, b), n in sorted(pairs.items()):
        wr.writerow([a, b, n])

# Connectivity of the zone graph.
nbr = {z: set() for z in range(1, len(seeds) + 1)}
for a, b in pairs:
    nbr[a].add(b)
    nbr[b].add(a)
seen, todo = {1}, [1]
while todo:
    for n in nbr[todo.pop()]:
        if n not in seen:
            seen.add(n)
            todo.append(n)
if len(seen) != len(seeds):
    sys.exit("zones not connected to zone 1: " + ", ".join(seeds[z - 1][1] for z in sorted(set(nbr) - seen)))

# Ports.
by_key = {}
with open(map_dir / "provinces.tsv", encoding="utf-8") as f:
    for r in csv.DictReader(f, delimiter="\t"):
        by_key[int(r["r"]) | (int(r["g"]) << 8) | (int(r["b"]) << 16)] = int(r["id"])
coastal = []
with open(map_dir / "coastal.tsv", encoding="utf-8") as f:
    coastal = [int(r["id"]) for r in csv.DictReader(f, delimiter="\t")]
counts = {}
for land, zone, wet in ((key[:, :-1], zone_full[:, 1:], sea[:, 1:]), (key[:, 1:], zone_full[:, :-1], sea[:, :-1]),
                        (key[:-1, :], zone_full[1:, :], sea[1:, :]), (key[1:, :], zone_full[:-1, :], sea[:-1, :])):
    m = wet & (land > 0)
    for p, n in zip(*np.unique(land[m] * 64 + zone[m], return_counts=True)):
        k, z = int(p) // 64, int(p) % 64
        if k in by_key:
            counts.setdefault(by_key[k], {})
            counts[by_key[k]][z] = counts[by_key[k]].get(z, 0) + int(n)
centers = {}
with open(map_dir / "provinces.tsv", encoding="utf-8") as f:
    for r in csv.DictReader(f, delimiter="	"):
        centers[int(r["id"])] = (int(r["cx"]), int(r["cy"]))
missing = []
with open(map_dir / "ports.tsv", "w", encoding="utf-8", newline="") as f:
    wr = csv.writer(f, delimiter="\t", lineterminator="\n")
    wr.writerow(["id", "zone", "zone2", "sea_px"])
    for pid in coastal:
        zs = {z: n for z, n in counts.get(pid, {}).items() if z > 0}
        if not zs:
            cx, cy = centers[pid]
            cy, cx = min(cy // ZONE_SCALE, h - 1), min(cx // ZONE_SCALE, w - 1)
            near = nearest[cy, cx]
            ys, xs = np.nonzero(real & (filled == near))
            gap = np.sqrt(((ys - cy) ** 2 + (xs - cx) ** 2).min()) if len(ys) else 1e9
            if gap > FALLBACK_CELLS:
                missing.append(pid)
                continue
            zs = {int(near): 1}
        total = sum(zs.values())
        ranked = sorted(zs, key=lambda z: (-zs[z], z))
        second = ranked[1] if len(ranked) > 1 and zs[ranked[1]] >= SECOND_SHARE * total else 0
        wr.writerow([pid, ranked[0], second, total])
print(len(seeds), "zones,", len(pairs), "links,", len(coastal) - len(missing), "ports")
if missing:
    print("no port (water outside every zone):", ", ".join(map(str, missing)))
