"""After tools/redraw_split_provinces.py: re-files each city under the province it now stands in, and re-splits the
population of every redrawn group between its pieces (60% by how the piece's area changed, 40% by how its city
population changed), keeping each group's total. Reads the old areas from git (HEAD) and writes both scenarios.
Run once, from the project root: python3 tools/fix_after_redraw.py"""
import csv
import re
import subprocess
from collections import defaultdict

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None
RURAL = 0.6
SCENARIOS = ["data/scenarios/july_1914", "data/scenarios/jan_1900"]


def table(text):
    r = list(csv.reader(text.splitlines(), delimiter="\t"))
    return r[0], r[1:]


head, new_rows = table(open("data/map/provinces.tsv", encoding="utf-8").read())
_, old_rows = table(subprocess.check_output(["git", "show", "HEAD:data/map/provinces.tsv"]).decode("utf-8"))
old_area = {int(r[0]): float(r[6]) for r in old_rows}
new_area = {int(r[0]): float(r[6]) for r in new_rows}
names = {int(r[0]): r[4] for r in new_rows}
groups = defaultdict(list)
for r in new_rows:
    m = re.match(r"^(.*) (\d+)$", r[4])
    if m and r[5] == "GER" and old_area[int(r[0])] != new_area[int(r[0])]:
        groups[m.group(1)].append(int(r[0]))

img = np.array(Image.open("data/map/provinces.png").convert("RGB"))
ids = img[:, :, 0].astype(np.int32) + (img[:, :, 1].astype(np.int32) << 8)

for folder in SCENARIOS:
    ch, cities = table(open(folder + "/cities.tsv", encoding="utf-8").read())
    old_city = defaultdict(float)
    new_city = defaultdict(float)
    for c in cities:
        old_p, x, y, pop = int(c[2]), int(c[3]), int(c[4]), float(c[5])
        old_city[old_p] += pop
        now = int(ids[y, x]) if 0 <= y < ids.shape[0] and 0 <= x < ids.shape[1] else 0
        if now in names and now != old_p:
            if pop >= 300000:
                print("  %s: %s moves %s -> %s" % (folder.split("/")[-1], c[1], names.get(old_p), names[now]))
            c[2] = str(now)
        new_city[int(c[2])] += pop
    with open(folder + "/cities.tsv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, delimiter="\t", lineterminator="\n")
        w.writerow(ch)
        w.writerows(cities)
    ph, prov = table(open(folder + "/provinces.tsv", encoding="utf-8").read())
    pop = {int(r[0]): float(r[2]) for r in prov}
    eps = 50000.0
    for name, pieces in groups.items():
        total = sum(pop[p] for p in pieces)
        raw = {p: pop[p] * (RURAL * new_area[p] / old_area[p] + (1 - RURAL) * (new_city[p] + eps) / (old_city[p] + eps)) for p in pieces}
        k = total / sum(raw.values())
        for p in pieces:
            pop[p] = round(raw[p] * k / 100.0) * 100.0
    for r in prov:
        r[2] = str(int(pop[int(r[0])]))
    with open(folder + "/provinces.tsv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, delimiter="\t", lineterminator="\n")
        w.writerow(ph)
        w.writerows(prov)
print("done:", len(groups), "groups re-split")

# ---- resources that stood on a piece the redraw moved (deposits found by their towns' places on the new map)
moves = [
    # (from piece, to piece, resource, share moved)
    ("Nordrhein-Westfalen 2", "Nordrhein-Westfalen 3", "coal", 0.5),  # the Ruhr now falls in two pieces (Essen, Bochum)
    ("Niedersachsen 6", "Niedersachsen 4", "iron", 1.0),              # Peine
    ("Niedersachsen 6", "Niedersachsen 4", "coal", 1.0),              # the Deister
    ("Lower Silesian 3", "Lower Silesian 2", "coal", 1.0),            # Waldenburg
    ("Lower Silesian 3", "Lower Silesian 2", "iron", 1.0),
]
for folder in SCENARIOS:
    rh, res = table(open(folder + "/resources.tsv", encoding="utf-8").read())
    row = {names[int(r[0])]: r for r in res}
    col = {k: i for i, k in enumerate(rh)}
    for src, dst, what, share in moves:
        amount = int(row[src][col[what]])
        part = round(amount * share)
        row[src][col[what]] = str(amount - part)
        row[dst][col[what]] = str(int(row[dst][col[what]]) + part)
    with open(folder + "/resources.tsv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, delimiter="\t", lineterminator="\n")
        w.writerow(rh)
        w.writerows(res)
print("resources moved")
