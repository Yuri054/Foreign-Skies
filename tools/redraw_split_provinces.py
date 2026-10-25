"""Redraws the German pieces of data/map/provinces.png along real district borders.

Usage:
    python tools/redraw_split_provinces.py <kreise.geojson> <powiaty.geojson> [--dry]

build_map.py cut every large admin-1 unit into numbered pieces ("Bayern 1" ... "Bayern 7") with k-means, so
Germany (and the Polish land it held) came out as straight-edged cells beside France's departments. This
keeps every id, colour and name, and only moves the borders between the pieces of one group: each group's
pixels are re-cut from district polygons (German Landkreise and Polish powiats; modern, but their edges are
real), grown outward from the old pieces' centres into contiguous parts of about equal area.

Afterwards run tools/build_adjacencies.py, build_borders.py, build_coastal.py and build_sea_zones.py, and
tools/fix_after_redraw.py for the city and population tables.
"""
import csv
import json
import math
import re
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from shapely.geometry import shape

Image.MAX_IMAGE_PIXELS = None
root = Path(__file__).resolve().parent.parent
map_dir = root / "data" / "map"

LON0, LAT1 = -11.0, 67.0
KY = 160.0
KX = KY * math.cos(math.radians(47.0))

dry = "--dry" in sys.argv
paths = [a for a in sys.argv[1:] if not a.startswith("--")]


def px(coords):
    return [((lon - LON0) * KX, (LAT1 - lat) * KY) for lon, lat in coords]


def load_units(*files):
    out = []
    for f in files:
        for feat in json.load(open(f, encoding="utf-8"))["features"]:
            g = shape(feat["geometry"])
            if not g.is_valid:
                g = g.buffer(0)
            polys = [g] if g.geom_type == "Polygon" else [p for p in g.geoms if p.geom_type == "Polygon"]
            rp = g.representative_point()
            out.append({"polys": polys, "pt": ((rp.x - LON0) * KX, (LAT1 - rp.y) * KY), "bounds": g.bounds})
    return out


rows = list(csv.reader(open(map_dir / "provinces.tsv", encoding="utf-8"), delimiter="\t"))
head, body = rows[0], rows[1:]
by_id = {int(r[0]): r for r in body}
img = np.array(Image.open(map_dir / "provinces.png").convert("RGB"))
ids = img[:, :, 0].astype(np.int32) + (img[:, :, 1].astype(np.int32) << 8)
H, W = ids.shape

groups = defaultdict(list)
for r in body:
    m = re.match(r"^(.*) (\d+)$", r[4])
    if m and r[5] == "GER":
        groups[m.group(1)].append(int(r[0]))
groups = {k: sorted(v) for k, v in groups.items() if len(v) > 1}
print(len(groups), "groups:", {k: len(v) for k, v in groups.items()})

units = load_units(*paths[:2])
print(len(units), "district polygons")

changed = {}
for name, pieces in groups.items():
    mask = np.isin(ids, pieces)
    ys, xs = np.nonzero(mask)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    sub = mask[y0:y1, x0:x1]
    sub_ids = ids[y0:y1, x0:x1]
    # district polygons whose representative point lies in the group
    chosen = []
    for u in units:
        ux, uy = int(u["pt"][0]), int(u["pt"][1])
        if x0 <= ux < x1 and y0 <= uy < y1 and sub[uy - y0, ux - x0]:
            chosen.append(u)
    if len(chosen) < len(pieces):
        print("  skip", name, "(only", len(chosen), "districts)")
        continue
    lab_img = Image.new("I", (x1 - x0, y1 - y0), 0)
    d = ImageDraw.Draw(lab_img)
    for i, u in enumerate(chosen, start=1):
        for p in u["polys"]:
            d.polygon([(x - x0, y - y0) for x, y in px(p.exterior.coords)], fill=i)
    lab = np.array(lab_img, dtype=np.int32)
    lab[~sub] = 0
    # pixels of the group no district reached take the nearest district
    gap = sub & (lab == 0)
    if gap.any():
        _, (iy, ix) = ndimage.distance_transform_edt(lab == 0, return_indices=True)
        lab[gap] = lab[iy[gap], ix[gap]]
    n = len(chosen)
    area = np.bincount(lab[sub], minlength=n + 1).astype(float)
    # who touches whom, and along how much border
    nb = defaultdict(lambda: defaultdict(int))
    for a, b in ((lab[:, :-1], lab[:, 1:]), (lab[:-1, :], lab[1:, :])):
        m = (a != b) & (a > 0) & (b > 0)
        for p, q in zip(a[m], b[m]):
            nb[int(p)][int(q)] += 1
            nb[int(q)][int(p)] += 1
    # seeds: the district under the pixel of each old piece nearest its centre
    owner_of = {}
    seeds = {}
    for pid in pieces:
        py, px_ = np.nonzero(sub_ids == pid)
        cy, cx = py.mean(), px_.mean()
        order = np.argsort((py - cy) ** 2 + (px_ - cx) ** 2)
        for k in order[:2000]:
            u = int(lab[py[k], px_[k]])
            if u > 0 and u not in owner_of:
                owner_of[u] = pid
                seeds[pid] = u
                break
        else:
            u = int(np.argmax(np.bincount(lab[sub_ids == pid], minlength=n + 1)[1:])) + 1
            owner_of[u] = pid
            seeds[pid] = u
    got = defaultdict(float)
    for u, pid in owner_of.items():
        got[pid] += area[u]
    frontier_dead = set()
    while len(owner_of) < n and len(frontier_dead) < len(pieces):
        pid = min((p for p in pieces if p not in frontier_dead), key=lambda p: got[p])
        best, best_score = None, -1
        for u, p in list(owner_of.items()):
            if p != pid:
                continue
            for v, shared in nb[u].items():
                if v not in owner_of and shared > best_score:
                    best, best_score = v, shared
        if best is None:
            frontier_dead.add(pid)
            continue
        owner_of[best] = pid
        got[pid] += area[best]
    cent = {}
    for pid in pieces:
        members = [u for u, p in owner_of.items() if p == pid]
        w = np.array([area[u] for u in members])
        cent[pid] = (np.array([np.mean(np.nonzero(lab == u), axis=1) for u in members]) * w[:, None]).sum(0) / w.sum()
    for u in range(1, n + 1):  # districts nothing reached (cut off by water) join the nearest part
        if u not in owner_of:
            c = np.mean(np.nonzero(lab == u), axis=1)
            owner_of[u] = min(pieces, key=lambda p: float(((cent[p] - c) ** 2).sum()))
    lut = np.zeros(n + 1, dtype=np.int32)
    for u, pid in owner_of.items():
        lut[u] = pid
    new_sub = np.where(sub, lut[lab], sub_ids)
    changed[name] = (int(((new_sub != sub_ids) & sub).sum()), len(pieces), n)
    sub_ids[:] = new_sub
    print("  %-26s %d pieces from %d districts, %d px moved" % (name, len(pieces), n, changed[name][0]))

# East Prussia and the Kaliningrad pieces have no district data here; their straight edges are bent with smooth
# noise instead (run once: running it again would bend the borders twice).
WIGGLE = ["Warmian-Masurian", "Masuria", "Klaipedos", "Konigsberg 1", "Konigsberg 2"]
wig_ids = [int(r[0]) for r in body if r[4] in WIGGLE]
wmask = np.isin(ids, wig_ids)
wy, wx = np.nonzero(wmask)
m = 40
y0, y1 = max(wy.min() - m, 0), min(wy.max() + m, H)
x0, x1 = max(wx.min() - m, 0), min(wx.max() + m, W)
rng = np.random.default_rng(1914)
sub = ids[y0:y1, x0:x1]
inside = wmask[y0:y1, x0:x1]
dx = ndimage.gaussian_filter(rng.normal(size=sub.shape), 22) * 700
dy = ndimage.gaussian_filter(rng.normal(size=sub.shape), 22) * 700
gy, gx = np.mgrid[0:sub.shape[0], 0:sub.shape[1]]
sy = np.clip((gy + dy).round().astype(int), 0, sub.shape[0] - 1)
sx = np.clip((gx + dx).round().astype(int), 0, sub.shape[1] - 1)
cand = sub[sy, sx]
take = inside & np.isin(cand, wig_ids)
sub[take] = cand[take]
print("bent the East Prussian borders:", int(take.sum()), "px sampled")
touched_extra = wig_ids

if dry:
    sys.exit(0)

# write the bitmap back with the same colours
col = {int(r[0]): (int(r[1]), int(r[2]), int(r[3])) for r in body}
touched = [p for ps in groups.values() for p in ps] + touched_extra
for pid in touched:
    img[ids == pid] = col[pid]
Image.fromarray(img, "RGB").save(map_dir / "provinces.png", optimize=True)
for pid in touched:
    yy, xx = np.nonzero(ids == pid)
    r = by_id[pid]
    r[6], r[7], r[8] = str(len(xx)), str(int(xx.mean())), str(int(yy.mean()))
with open(map_dir / "provinces.tsv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f, delimiter="\t", lineterminator="\n")
    w.writerow(head)
    w.writerows(body)
print("wrote provinces.png and provinces.tsv")
