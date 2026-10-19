"""Turn islands that have no province into provinces, without touching any existing id.

Usage: python tools/add_islands.py [--dry]

The province bitmap paints land that belongs to no province grey (see build_map.BG_RGB). Each
island below is found in that grey: every grey patch that lies inside its box is recoloured with
a new province colour, and the island is appended to provinces.tsv (the next free id), to the
scenario's provinces.tsv (its population) and to resources.tsv (no deposits). Run it once.
Afterwards run, in this order:

    python tools/build_adjacencies.py
    python tools/build_borders.py
    python tools/build_coastal.py
    python tools/build_terrain.py        (the islands' terrain is listed in build_terrain.py)
    python tools/build_sea_zones.py

An island whose name is already in provinces.tsv is skipped, so a second run does nothing.
Boxes are in degrees (lon0, lat0, lon1, lat1) on the map's projection.
"""
import csv
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

Image.MAX_IMAGE_PIXELS = None

ROOT = Path(__file__).resolve().parent.parent
MAP_DIR = ROOT / "data" / "map"
SCENARIO_DIR = ROOT / "data" / "scenarios" / "july_1914"

# The map's projection (the same as build_map.py; the frame has since grown to the north).
LON0, LAT1 = -11.0, 67.0
KY = 160.0
KX = KY * math.cos(math.radians(47.0))
COS47 = math.cos(math.radians(47.0))
BG_RGB = (128, 128, 128)

# name, owner, admin, 1914 population, box. Cyprus was Ottoman in law and British in rule
# (annexed that November); it is given to the power that ran it.
ISLANDS = [
    {"name": "Isle of Man", "owner": "GBR", "admin": "Isle of Man", "pop": 52000, "box": (-4.9, 54.0, -4.2, 54.5)},
    {"name": "Channel Islands", "owner": "GBR", "admin": "Channel Islands", "pop": 93800, "box": (-2.8, 49.1, -2.0, 49.6)},
    {"name": "Malta", "owner": "GBR", "admin": "Malta", "pop": 211600, "box": (14.1, 35.78, 14.65, 36.1)},
    {"name": "Cyprus", "owner": "GBR", "admin": "Cyprus", "pop": 274100, "box": (32.2, 34.5, 34.7, 35.75)},
    {"name": "Faroe Islands", "owner": "DEN", "admin": "Faroe Islands", "pop": 18100, "box": (-7.8, 61.3, -6.2, 62.4)},
    {"name": "Åland", "owner": "RUS", "admin": "Åland", "pop": 21000, "box": (19.4, 59.8, 21.2, 60.5)},
]
# Patches bigger than this are not islands (they are the grey mainland and would swallow it).
MAX_PATCH_PX = 20000


def to_px(lon, lat):
    return (lon - LON0) * KX, (LAT1 - lat) * KY


def eol(path):
    """The line ending a table already uses, so appended rows match it."""
    return "\r\n" if b"\r\n" in path.read_bytes()[:2000] else "\n"


def append_rows(path, rows):
    end = eol(path)
    with open(path, "a", newline="", encoding="utf-8") as f:
        csv.writer(f, delimiter="\t", lineterminator=end).writerows(rows)


def main():
    dry = "--dry" in sys.argv
    img = np.array(Image.open(MAP_DIR / "provinces.png").convert("RGB"))
    grey = (img == BG_RGB).all(axis=2)
    labels, _ = ndimage.label(grey, structure=np.ones((3, 3)))
    with open(MAP_DIR / "provinces.tsv", encoding="utf-8") as f:
        rows = list(csv.reader(f, delimiter="\t"))
    header, body = rows[0], rows[1:]
    names = {r[4] for r in body}
    next_id = max(int(r[0]) for r in body) + 1
    used = {(int(r[1]), int(r[2]), int(r[3])) for r in body}
    added = []
    for isl in ISLANDS:
        if isl["name"] in names:
            print(f"{isl['name']}: already a province, skipped")
            continue
        x0, y1 = to_px(isl["box"][0], isl["box"][1])
        x1, y0 = to_px(isl["box"][2], isl["box"][3])
        x0, x1, y0, y1 = int(x0), int(x1), int(y0), int(y1)
        box = labels[y0:y1 + 1, x0:x1 + 1]
        sizes = np.bincount(labels.ravel())
        patches = [int(l) for l in np.unique(box) if l > 0 and sizes[l] <= MAX_PATCH_PX]
        if not patches:
            print(f"{isl['name']}: no grey land in its box, skipped")
            continue
        mask = np.isin(labels, patches)
        ys, xs = np.nonzero(mask)
        pid = next_id
        next_id += 1
        rgb = (pid & 0xFF, (pid >> 8) & 0xFF, 1 + ((pid * 97) & 0x7F))
        assert rgb not in used, f"colour {rgb} is taken"
        used.add(rgb)
        lat_w = np.cos(np.radians(LAT1 - (ys + 0.5) / KY)) / COS47
        area = int(round(float(lat_w.sum())))
        print(f"{isl['name']}: id {pid}, {len(patches)} patches, {mask.sum()} px, area {area}, centre ({int(xs.mean())}, {int(ys.mean())})")
        added.append((isl, pid, rgb, mask, area, int(xs.mean()), int(ys.mean())))
        if not dry:
            img[mask] = rgb
    if dry or not added:
        return
    Image.fromarray(img, "RGB").save(MAP_DIR / "provinces.png", optimize=False, compress_level=6)
    append_rows(MAP_DIR / "provinces.tsv", [[pid, *rgb, isl["name"], isl["owner"], area, cx, cy, isl["admin"]]
                                            for isl, pid, rgb, _mask, area, cx, cy in added])
    append_rows(SCENARIO_DIR / "provinces.tsv", [[pid, isl["name"], isl["pop"]] for isl, pid, *_ in added])
    append_rows(SCENARIO_DIR / "resources.tsv", [[pid, 0, 0, 0] for _isl, pid, *_ in added])
    print(f"{len(added)} provinces added; now run the builders listed in the docstring.")


if __name__ == "__main__":
    main()
