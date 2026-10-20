"""Adds the 1914 population, resources and terrain of Norway and Sweden to the scenario tables.

Usage: python tools/add_scandinavia.py <path-to-ne_10m_populated_places_simple.geojson>

Run after tools/extend_map.py scandinavia (and the adjacency, coastal, border and sea-zone builders).
It replaces the NOR and SWE rows of data/scenarios/july_1914/provinces.tsv and resources.tsv and of
data/map/terrain.tsv, leaving every other row as it is (the older builders keep their own totals).
Population: a national total split into a rural share (by area, sparser in the north) and an urban
share (by the Natural Earth city populations in each province). Resources: rough 1913 outputs in
thousand tonnes. The frame ends at 67 N, so the iron of Kiruna and Malmberget (just north of it) is
put on the northernmost Norrbotten piece. Terrain is listed by hand.
"""
import csv
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None
root = Path(__file__).resolve().parent.parent
map_dir = root / "data" / "map"
scen = root / "data" / "scenarios" / "july_1914"
LON0, LAT1 = -11.0, 67.0
KY = 160.0
KX = KY * math.cos(math.radians(47.0))

TOTALS = {"NOR": (2_360_000, 0.28), "SWE": (5_450_000, 0.25)}   # 1910 censuses, the part inside the frame
IRON = {"NOR": 250, "SWE": 7000}
COAL = {"NOR": 0, "SWE": 400}
WOOD = {"NOR": 7000, "SWE": 25000}

TERRAIN = {
    "Akershus": "forest", "Østfold": "hills", "Vestfold": "hills", "Christiania": "urban", "Buskerud": "mountains",
    "Hedmark": "forest", "Oppland": "mountains", "Telemark": "mountains", "Aust-Agder": "mountains",
    "Vest-Agder": "hills", "Rogaland": "hills", "Hordaland": "mountains", "Sogn og Fjordane": "mountains",
    "More og Romsdal": "mountains", "Sor-Trondelag": "mountains", "Nord-Trondelag": "mountains",
    "Nordland": "mountains",
    "Blekinge": "forest", "Skane": "plains", "Halland": "plains", "Gotland": "plains", "Kalmar": "forest",
    "Kronoberg": "forest", "Jönköping": "hills", "Ostergotland": "plains", "Sodermanland": "forest",
    "Stockholm City": "urban", "Uppsala": "plains", "Vastmanland": "plains", "Orebro": "forest",
    "Värmland": "forest", "Dalarna": "forest", "Gävleborg": "forest", "Vastra Gotaland": "plains",
    "Vasternorrland": "forest", "Jamtland": "mountains", "Vasterbotten": "forest", "Norrbotten": "forest",
}
# Bergslagen (Grangesberg and the Orebro field) is hilly.
TERRAIN_OVERRIDE = {"Dalarna 2": "hills", "Jamtland 4": "forest", "Norrbotten 4": "mountains", "Norrbotten 5": "mountains"}
# Relative weights for ore and coal (province names).
IRON_W = {"Dalarna 1": 2.0, "Dalarna 2": 3.0, "Orebro": 1.5, "Värmland 1": 0.5}
NORRBOTTEN_ORE_SHARE = 0.83     # of the Swedish total: Kiruna, Malmberget, Svappavaara
COAL_W = {"Skane": 1.0}
FOREST = {"Norrbotten": 1.0, "Vasterbotten": 1.0, "Jamtland": 1.0, "Dalarna": 1.2, "Gävleborg": 1.3,
          "Vasternorrland": 1.3, "Värmland": 1.3, "Kronoberg": 1.5, "Kalmar": 1.2, "Jönköping": 1.2,
          "Hedmark": 1.5, "Oppland": 0.8, "Buskerud": 1.0, "Akershus": 1.0, "Telemark": 0.8, "Østfold": 0.9,
          "Skane": 0.2, "Halland": 0.5, "Gotland": 0.3, "Stockholm City": 0.05, "Christiania": 0.02}


def base(name):
    parts = name.rsplit(" ", 1)
    return parts[0] if len(parts) == 2 and parts[1].isdigit() else name


def main():
    rows = list(csv.DictReader(open(map_dir / "provinces.tsv", encoding="utf-8"), delimiter="\t"))
    mine = [r for r in rows if r["owner"] in TOTALS]
    ids_mine = {int(r["id"]) for r in mine}
    img = np.asarray(Image.open(map_dir / "provinces.png").convert("RGB"))
    key = img[..., 0].astype(np.int64) | (img[..., 1].astype(np.int64) << 8) | (img[..., 2].astype(np.int64) << 16)
    by_key = {int(r["r"]) | (int(r["g"]) << 8) | (int(r["b"]) << 16): int(r["id"]) for r in rows}

    def province_at(lon, lat):
        x, y = int((lon - LON0) * KX), int((LAT1 - lat) * KY)
        for rad in range(0, 30, 3):
            for dy in range(-rad, rad + 1, max(rad, 1)):
                for dx in range(-rad, rad + 1, max(rad, 1)):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < key.shape[0] and 0 <= xx < key.shape[1]:
                        pid = by_key.get(int(key[yy, xx]), 0)
                        if pid in ids_mine:
                            return pid
        return 0

    city = {}
    for f in json.load(open(sys.argv[1], encoding="utf-8"))["features"]:
        p = f["properties"]
        if p["adm0_a3"] not in ("NOR", "SWE"):
            continue
        lon, lat = p["longitude"], p["latitude"]
        pid = province_at(lon, lat)
        if pid:
            city[pid] = city.get(pid, 0) + (p["pop_max"] or 0) ** 0.7
    pop, wood, iron, coal = {}, {}, {}, {}
    for tag, (total, urban) in TOTALS.items():
        group = [r for r in mine if r["owner"] == tag]
        # sparser further north: weight by area / (1 + (lat above 58) / 5)
        rural_w = {}
        for r in group:
            lat = LAT1 - int(r["cy"]) / KY
            rural_w[int(r["id"])] = int(r["area"]) / (1.0 + max(0.0, lat - 58.0) / 4.0)
        rw = sum(rural_w.values())
        cw = sum(city.get(i, 0) for i in rural_w) or 1.0
        for i in rural_w:
            pop[i] = int(round(total * (1 - urban) * rural_w[i] / rw + total * urban * city.get(i, 0) / cw))
        # timber by area and forest weight
        fw = {int(r["id"]): int(r["area"]) * FOREST.get(base(r["name"]), 1.0) for r in group}
        fs = sum(fw.values())
        for i, w in fw.items():
            wood[i] = int(round(WOOD[tag] * w / fs))
    by_id = {int(r["id"]): r for r in mine}
    for i in ids_mine:
        iron[i] = coal[i] = 0
    sw = [i for i in ids_mine if by_id[i]["owner"] == "SWE"]
    ore = {i: IRON_W[by_id[i]["name"]] for i in sw if by_id[i]["name"] in IRON_W}
    norr = [i for i in sw if base(by_id[i]["name"]) == "Norrbotten"]
    north = min(norr, key=lambda i: int(by_id[i]["cy"]))
    sw_total = IRON["SWE"]
    for i, w in ore.items():
        iron[i] = int(round(sw_total * (1 - NORRBOTTEN_ORE_SHARE) * w / sum(ore.values())))
    iron[north] = int(round(sw_total * NORRBOTTEN_ORE_SHARE))
    nor_ore = [i for i in ids_mine if by_id[i]["name"] == "Nordland 2"]
    for i in nor_ore:
        iron[i] = IRON["NOR"]
    for i in sw:
        if by_id[i]["name"] in COAL_W:
            coal[i] = COAL["SWE"]
    print("iron on", by_id[north]["name"], iron[north], "kt;", "population", sum(pop.values()))

    def rewrite(path, header, new_rows, name_col=None):
        with open(path, encoding="utf-8") as f:
            old = list(csv.reader(f, delimiter="\t"))
        keep = [r for r in old[1:] if int(r[0]) not in ids_mine]
        out = sorted(keep + [[str(x) for x in r] for r in new_rows], key=lambda r: int(r[0]))
        with open(path, "w", encoding="utf-8", newline="") as f:
            w = csv.writer(f, delimiter="\t", lineterminator="\n")
            w.writerow(header)
            w.writerows(out)

    rewrite(scen / "provinces.tsv", ["id", "name", "population"], [(i, by_id[i]["name"], pop[i]) for i in sorted(ids_mine)])
    rewrite(scen / "resources.tsv", ["id", "wood", "iron", "coal"], [(i, wood[i], iron[i], coal[i]) for i in sorted(ids_mine)])
    terrain = []
    for i in sorted(ids_mine):
        n = by_id[i]["name"]
        terrain.append((i, n, TERRAIN_OVERRIDE.get(n) or TERRAIN[base(n)]))
    rewrite(map_dir / "terrain.tsv", ["id", "name", "terrain"], terrain)
    print("wrote", len(ids_mine), "provinces")


if __name__ == "__main__":
    main()
