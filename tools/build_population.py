"""Distribute 1914 national populations over provinces.

Usage:
    python tools/build_population.py <path-to-ne_10m_populated_places_simple (no extension)>

Each nation's total is split into a rural part (proportional to province area) and an
urban part (proportional to the Natural Earth city populations that fall inside the
province). Totals and urban shares are rough 1910-1914 estimates (see TOTALS) and are
meant to be refined. Writes data/scenarios/july_1914/provinces.tsv.
"""
import csv
import sys
from pathlib import Path

import numpy as np
import shapefile
from PIL import Image
from scipy import ndimage

import build_map as bm
import extend_map  # noqa: F401  sets the (larger) bitmap frame in build_map

root = Path(__file__).resolve().parent.parent
map_dir = root / "data" / "map"
out_path = root / "data" / "scenarios" / "july_1914" / "provinces.tsv"

# population of the part of each nation that lies on the map, and its urban share
GROUPS = [(1, 556, "west"), (557, 717, "balkans"), (718, 878, "russia")]  # province id ranges, one per map slice


def group_of(pid):
    for lo, hi, name in GROUPS:
        if lo <= pid <= hi:
            return name
    raise SystemExit(f"province {pid} is in no group: add its slice to GROUPS")


# Each slice gets its own totals, so adding a region never changes the figures of an older one.
TOTALS = {
    ("GBR", "west"): (45_700_000, 0.78),
    ("FRA", "west"): (39_600_000, 0.44),
    ("GER", "west"): (61_850_000, 0.60),   # east of 19.5 E is added by later slices; Lodz (below) is Russian
    ("RUS", "west"): (2_100_000, 0.45),    # Lodz 1 and 2, cut by the first frame (Russian Poland)
    ("BEL", "west"): (7_500_000, 0.57),
    ("NED", "west"): (6_100_000, 0.55),
    ("LUX", "west"): (260_000, 0.50),
    ("SUI", "west"): (3_800_000, 0.45),
    ("ITA", "west"): (35_400_000, 0.38),
    ("ESP", "west"): (20_400_000, 0.38),
    ("POR", "west"): (6_000_000, 0.30),
    ("DEN", "west"): (2_800_000, 0.40),
    ("AUH", "west"): (33_000_000, 0.40),   # only the part inside the first map frame; rough
    # Balkans slice: 1910-1913 censuses and estimates
    ("AUH", "balkans"): (18_400_000, 0.28),  # Galicia east of Krakow, Bukovina, Ruthenia, Transylvania, Banat, Hungary east
    ("GBR", "balkans"): (25_000, 0.30),      # Shetland
    ("GER", "balkans"): (650_000, 0.15),     # Masuria east of 19.5 E
    ("SRB", "balkans"): (4_500_000, 0.17),   # with Kosovo and Vardar Macedonia (1913)
    ("MNE", "balkans"): (250_000, 0.12),
    ("ALB", "balkans"): (800_000, 0.14),
    ("GRE", "balkans"): (4_800_000, 0.32),   # with Macedonia, Epirus, Crete and the islands (1913)
    ("BUL", "balkans"): (4_750_000, 0.20),
    ("ROM", "balkans"): (7_800_000, 0.18),   # with Southern Dobruja
    ("OTT", "balkans"): (2_000_000, 0.45),   # Thrace and Constantinople
    # Russia slice, by modern country (the "admin" column of provinces.tsv): 1897-1914 estimates
    ("RUS", "russia", "Russia"): (66_000_000, 0.15),     # European Russia, the Urals, the North Caucasus
    ("RUS", "russia", "Finland"): (3_200_000, 0.15),
    ("RUS", "russia", "Estonia"): (1_000_000, 0.18),
    ("RUS", "russia", "Latvia"): (1_900_000, 0.30),
    ("RUS", "russia", "Lithuania"): (2_100_000, 0.15),
    ("RUS", "russia", "Belarus"): (7_000_000, 0.14),
    ("RUS", "russia", "Ukraine"): (27_000_000, 0.17),    # without Galicia and Bukovina (Austrian)
    ("RUS", "russia", "Moldova"): (2_500_000, 0.13),
    ("RUS", "russia", "Poland"): (10_300_000, 0.28),     # Congress Poland without Lodz
    ("GER", "russia", "Russia"): (1_350_000, 0.35),      # Konigsberg and East Prussia
    ("GER", "russia", "Lithuania"): (140_000, 0.30),     # Memel
}

# 1914 populations of cities that the modelled share undersells (their own province)
MIN_POP = {"Saint Petersburg": 2_100_000, "Moscow": 1_800_000}

# modern metro populations overstate the biggest cities relative to 1914, so flatten them
CITY_EXPONENT = 0.7

img = np.array(Image.open(map_dir / "provinces.png").convert("RGB"))
key = img[..., 0].astype(np.int64) | (img[..., 1].astype(np.int64) << 8) | (img[..., 2].astype(np.int64) << 16)
rows, by_key = [], {}
with open(map_dir / "provinces.tsv", encoding="utf-8") as f:
    for r in csv.DictReader(f, delimiter="\t"):
        by_key[int(r["r"]) | (int(r["g"]) << 8) | (int(r["b"]) << 16)] = int(r["id"])
        rows.append(r)
lut_keys = np.array(sorted(by_key))
lut_ids = np.array([by_key[k] for k in lut_keys])
idx = np.minimum(np.searchsorted(lut_keys, key), len(lut_keys) - 1)
ids = np.where(lut_keys[idx] == key, lut_ids[idx], 0)

# nearest land province for every pixel, so coastal cities still land in a province
land_rows, land_cols = np.flatnonzero((ids > 0).any(axis=1)), np.flatnonzero((ids > 0).any(axis=0))
Y0, Y1 = max(land_rows[0] - 40, 0), min(land_rows[-1] + 41, ids.shape[0])
X0, X1 = max(land_cols[0] - 40, 0), min(land_cols[-1] + 41, ids.shape[1])
ids = ids[Y0:Y1, X0:X1]
_, (iy, ix) = ndimage.distance_transform_edt(ids == 0, return_indices=True)

city_pop = np.zeros(len(rows) + 1)
sf = shapefile.Reader(sys.argv[1], encoding="utf-8")
for sr in sf.iterShapeRecords():
    lon, lat = sr.shape.points[0]
    if not (bm.LON0 <= lon < bm.LON1 and bm.LAT0 <= lat < bm.LAT1):
        continue
    x = int((lon - bm.LON0) * bm.KX) - X0
    y = int((bm.LAT1 - lat) * bm.KY) - Y0
    if not (0 <= x < ids.shape[1] and 0 <= y < ids.shape[0]):
        continue
    if np.hypot(ix[y, x] - x, iy[y, x] - y) > 15:  # city in a background country
        continue
    pid = ids[iy[y, x], ix[y, x]]
    if pid:
        city_pop[pid] += max(sr.record["pop_max"], 0) ** CITY_EXPONENT

by_owner = {}
for r in rows:
    by_owner.setdefault((r["owner"], group_of(int(r["id"])), r.get("admin") or ""), []).append(r)

out_path.parent.mkdir(parents=True, exist_ok=True)
with open(out_path, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f, delimiter="\t")
    w.writerow(["id", "name", "population"])
    written = {}
    for (tag, group, admin), plist in sorted(by_owner.items()):
        total, urban = TOTALS.get((tag, group, admin)) or TOTALS[(tag, group)]
        area = np.array([int(r["area"]) for r in plist], dtype=float)
        city = np.array([city_pop[int(r["id"])] for r in plist])
        if city.sum() == 0:
            city = area
        pop = total * (1 - urban) * area / area.sum() + total * urban * city / city.sum()
        for r, p in zip(plist, pop):
            p = max(p, MIN_POP.get(r["name"], 0))
            written[int(r["id"])] = [r["id"], r["name"], int(round(p, -2))]
        top = sorted(zip(pop, (r["name"] for r in plist)), reverse=True)[:3]
        print(tag, group, f"{pop.sum():,.0f}", ", ".join(f"{n} {p:,.0f}" for p, n in top))
    for i in sorted(written):
        w.writerow(written[i])
print("wrote", out_path)
