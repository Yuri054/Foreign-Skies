"""Lists the major cities of 1914 and where they stand on the map.

Usage:
    python tools/build_cities.py <path-to-ne_10m_populated_places_simple.geojson>

Natural Earth gives the places and their positions (modern names and populations). The cities that
mattered in 1914 get their name and rough 1910-1914 population from CITIES below; the rest are
kept when a share of today's city population (EST_SHARE) comes to MIN_POP or more, and are marked
as estimates. Each city is put in the province it stands in (the nearest one for a coastal city).
Rank 1 is a nation's capital, 2 a city of RANK2_POP or more, 3 any other. Writes
data/scenarios/july_1914/cities.tsv: id, name, province, x, y (pixels of the map), pop, rank, est.
"""
import csv
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

root = Path(__file__).resolve().parent.parent
map_dir = root / "data" / "map"
scenario_dir = root / "data" / "scenarios" / "july_1914"

# the frame of the map bitmap (see tools/extend_map.py)
LON0, LON1 = -11.0, 61.0
LAT0, LAT1 = 34.8, 67.0
PX_PER_DEG = 160.0
KX = PX_PER_DEG * math.cos(math.radians(47.0))
KY = PX_PER_DEG

MIN_POP = 150_000
EST_SHARE = 0.30
EST_SHARE_EAST = 0.10
RANK2_POP = 500_000
SEARCH = 22  # pixels to look for the nearest province when a coastal city falls in the sea

# 1914 name and rough population (thousands) of the cities that mattered, by Natural Earth name.
CITIES = {
    "London": ("London", 7250), "Paris": ("Paris", 2880), "Berlin": ("Berlin", 2070), "Vienna": ("Vienna", 2030),
    "Saint Petersburg": ("Saint Petersburg", 2100), "St. Petersburg": ("Saint Petersburg", 2100), "Moscow": ("Moscow", 1760), "Istanbul": ("Constantinople", 1100),
    "Budapest": ("Budapest", 880), "Hamburg": ("Hamburg", 1000), "Warsaw": ("Warsaw", 880), "Lodz": ("Lodz", 500),
    "Odessa": ("Odessa", 630), "Kiev": ("Kiev", 520), "Kyiv": ("Kiev", 520), "Tirana": ("Tirana", 10), "Bern": ("Bern", 90), "Luxembourg": ("Luxembourg", 20), "Kobenhavn": ("Copenhagen", 560), "Sankt-Peterburg": ("Saint Petersburg", 2100), "Moskva": ("Moscow", 1760), "Kharkiv": ("Kharkov", 250), "Riga": ("Riga", 520),
    "Naples": ("Naples", 720), "Milan": ("Milan", 600), "Rome": ("Rome", 590), "Turin": ("Turin", 430), "Genoa": ("Genoa", 270),
    "Palermo": ("Palermo", 340), "Florence": ("Florence", 230), "Venice": ("Venice", 160), "Bologna": ("Bologna", 170),
    "Marseille": ("Marseille", 550), "Lyon": ("Lyon", 523), "Bordeaux": ("Bordeaux", 261), "Lille": ("Lille", 217),
    "Toulouse": ("Toulouse", 150), "Nantes": ("Nantes", 170), "Nice": ("Nice", 150), "Le Havre": ("Le Havre", 130),
    "Brussels": ("Brussels", 720), "Antwerp": ("Antwerp", 330), "Amsterdam": ("Amsterdam", 570), "Rotterdam": ("Rotterdam", 510),
    "The Hague": ("The Hague", 280), "Copenhagen": ("Copenhagen", 560), "Stockholm": ("Stockholm", 360), "Gothenburg": ("Gothenburg", 170), "Goteborg": ("Gothenburg", 170), "Malmo": ("Malmo", 95), "Bergen": ("Bergen", 78), "Trondheim": ("Trondheim", 45),
    "Oslo": ("Christiania", 250), "Helsinki": ("Helsinki", 190), "Madrid": ("Madrid", 600), "Barcelona": ("Barcelona", 600),
    "Valencia": ("Valencia", 230), "Seville": ("Seville", 150), "Bilbao": ("Bilbao", 100), "Lisbon": ("Lisbon", 435),
    "Porto": ("Porto", 195), "Athens": ("Athens", 170), "Belgrade": ("Belgrade", 90), "Sofia": ("Sofia", 100),
    "Bucharest": ("Bucharest", 340), "Munich": ("Munich", 640), "Cologne": ("Cologne", 600), "Leipzig": ("Leipzig", 590),
    "Dresden": ("Dresden", 550), "Wroclaw": ("Breslau", 510), "Frankfurt": ("Frankfurt", 440), "Dusseldorf": ("Dusseldorf", 360),
    "Düsseldorf": ("Dusseldorf", 360), "Nuremberg": ("Nuremberg", 360), "Nürnberg": ("Nuremberg", 360), "Stuttgart": ("Stuttgart", 290),
    "Hanover": ("Hanover", 310), "Hannover": ("Hanover", 310), "Gdansk": ("Danzig", 170), "Kaliningrad": ("Konigsberg", 250),
    "Essen": ("Essen", 440), "Duisburg": ("Duisburg", 230), "Dortmund": ("Dortmund", 215), "Bremen": ("Bremen", 250),
    "Magdeburg": ("Magdeburg", 280), "Chemnitz": ("Chemnitz", 290), "Szczecin": ("Stettin", 240), "Poznan": ("Posen", 160),
    "Prague": ("Prague", 640), "Brno": ("Brunn", 125), "Trieste": ("Trieste", 230), "Lviv": ("Lemberg", 210), "Krakow": ("Krakow", 180),
    "Zagreb": ("Agram", 80), "Bratislava": ("Pressburg", 78), "Graz": ("Graz", 152), "Cluj-Napoca": ("Klausenburg", 60),
    "Manchester": ("Manchester", 715), "Birmingham": ("Birmingham", 840), "Glasgow": ("Glasgow", 1000), "Liverpool": ("Liverpool", 750),
    "Leeds": ("Leeds", 450), "Sheffield": ("Sheffield", 450), "Edinburgh": ("Edinburgh", 400), "Bristol": ("Bristol", 370),
    "Newcastle upon Tyne": ("Newcastle", 270), "Belfast": ("Belfast", 390), "Dublin": ("Dublin", 400), "Cardiff": ("Cardiff", 180),
    "Nottingham": ("Nottingham", 260), "Bradford": ("Bradford", 290), "Hull": ("Hull", 280), "Portsmouth": ("Portsmouth", 235),
    "Thessaloniki": ("Salonika", 160), "Izmir": ("Smyrna", 200), "Chisinau": ("Kishinev", 125), "Tallinn": ("Reval", 120),
    "Vilnius": ("Vilna", 190), "Minsk": ("Minsk", 110), "Rijeka": ("Fiume", 50), "Ljubljana": ("Laibach", 45), "Sarajevo": ("Sarajevo", 52),
    "Saratov": ("Saratov", 235), "Kazan": ("Kazan", 200), "Nizhny Novgorod": ("Nizhny Novgorod", 100), "Samara": ("Samara", 150),
    "Rostov-na-Donu": ("Rostov", 120), "Yekaterinoslav": ("Yekaterinoslav", 210), "Dnipro": ("Yekaterinoslav", 210), "Donetsk": ("Yuzovka", 70),
    "Tbilisi": ("Tiflis", 330), "Baku": ("Baku", 215), "Sevastopol": ("Sevastopol", 70), "Voronezh": ("Voronezh", 100),
    "Tula": ("Tula", 120), "Yaroslavl": ("Yaroslavl", 110), "Astrakhan": ("Astrakhan", 150), "Tver": ("Tver", 60), "Smolensk": ("Smolensk", 100),
    "Archangel": ("Arkhangelsk", 50), "Arkhangelsk": ("Arkhangelsk", 50), "Tampere": ("Tammerfors", 40),
}


# Capitals that Natural Earth does not put in the capital province of 1914 (or names another city).
CAPITAL_FIX = {"BUL": ("Sofia", 100_000), "MNE": ("Cetinje", 5_000)}
SKIP = {"Vatican City"}


def main() -> None:
    places = json.load(open(sys.argv[1], encoding="utf-8"))["features"]
    img = np.array(Image.open(map_dir / "provinces.png").convert("RGB"))
    key = img[..., 0].astype(np.int64) | (img[..., 1].astype(np.int64) << 8) | (img[..., 2].astype(np.int64) << 16)
    by_key = {}
    with open(map_dir / "provinces.tsv", encoding="utf-8") as f:
        for r in csv.DictReader(f, delimiter="\t"):
            by_key[int(r["r"]) | (int(r["g"]) << 8) | (int(r["b"]) << 16)] = int(r["id"])
    rows_by_id = {}
    with open(map_dir / "provinces.tsv", encoding="utf-8") as f:
        for r in csv.DictReader(f, delimiter="\t"):
            rows_by_id[int(r["id"])] = r
    scenario = json.load(open(scenario_dir / "scenario.json", encoding="utf-8"))
    capitals = {n["capital"]: tag for tag, n in scenario["nations"].items() if "capital" in n}
    height, width = key.shape

    def province_at(x: int, y: int) -> tuple[int, int, int]:
        """The province of a pixel, or of the nearest land pixel within SEARCH pixels."""
        for radius in range(0, SEARCH + 1):
            best = None
            for dy in range(-radius, radius + 1):
                for dx in range(-radius, radius + 1):
                    if max(abs(dx), abs(dy)) != radius:
                        continue
                    px, py = x + dx, y + dy
                    if 0 <= px < width and 0 <= py < height:
                        pid = by_key.get(int(key[py, px]), 0)
                        if pid and (best is None or dx * dx + dy * dy < best[3]):
                            best = (pid, px, py, dx * dx + dy * dy)
            if best:
                return best[0], best[1], best[2]
        return 0, x, y

    found = {}
    for feature in places:
        p = feature["properties"]
        lon, lat = p["longitude"], p["latitude"]
        if not (LON0 <= lon < LON1 and LAT0 <= lat < LAT1):
            continue
        if p["nameascii"] in SKIP:
            continue
        name = next((n for n in (p["name"], p["nameascii"]) if n in CITIES), None)
        if name:
            hist, pop, est = CITIES[name][0], CITIES[name][1] * 1000, 0
        else:
            # Cities in the east grew several times over by today: take a smaller share of them.
            share = EST_SHARE if lon < 25.0 else EST_SHARE_EAST
            pop = int(round(max(p["pop_min"], 0) * share, -4))
            hist, est = p["nameascii"], 1
        x = int((lon - LON0) * KX)
        y = int((LAT1 - lat) * KY)
        pid, cx, cy = province_at(x, y)
        if not pid:
            continue
        if pop < MIN_POP and not (pid in capitals and p["adm0cap"] == 1):
            continue  # too small, unless it is a nation's capital
        pop = max(pop, 5000)
        # one entry for a name (Natural Earth lists some places twice)
        if hist in found and found[hist]["pop"] >= pop:
            continue
        found[hist] = {"name": hist, "province": pid, "x": cx, "y": cy, "pop": pop, "est": est}

    for tag, (city, pop) in CAPITAL_FIX.items():
        cap = scenario["nations"][tag].get("capital")
        have = any(c["province"] == cap for c in found.values())
        if cap and not have:
            r = rows_by_id[cap]
            found[city] = {"name": city, "province": cap, "x": int(r["cx"]), "y": int(r["cy"]), "pop": pop, "est": 0}
    rows = sorted(found.values(), key=lambda c: -c["pop"])
    biggest = {}
    for c in rows:
        biggest.setdefault(c["province"], c["name"])
    for c in rows:
        if c["province"] in capitals and biggest[c["province"]] == c["name"]:
            c["rank"] = 1
        else:
            c["rank"] = 2 if c["pop"] >= RANK2_POP else 3
    out = scenario_dir / "cities.tsv"
    with open(out, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, delimiter="\t", lineterminator="\n")
        w.writerow(["id", "name", "province", "x", "y", "pop", "rank", "est"])
        for i, c in enumerate(rows, 1):
            w.writerow([i, c["name"], c["province"], c["x"], c["y"], c["pop"], c["rank"], c["est"]])
    caps = [c for c in rows if c["rank"] == 1]
    print("%d cities (%d capitals, %d of rank 2, %d estimated)" % (len(rows), len(caps), sum(c["rank"] == 2 for c in rows), sum(c["est"] for c in rows)))
    missing = [t for pid, t in capitals.items() if pid not in {c["province"] for c in caps}]
    print("capitals without a city:", missing)
    for t in missing:
        pid = [k for k, v in capitals.items() if v == t][0]
        near = sorted((math.hypot(c["x"] - float(rows_by_id[pid]["cx"]), c["y"] - float(rows_by_id[pid]["cy"])), c["name"]) for c in rows)[:1]
        print("  ", t, "capital province", pid, rows_by_id[pid]["name"], "nearest listed city", near)
    print("estimated:", ", ".join("%s %dk" % (c["name"], c["pop"] // 1000) for c in rows if c["est"]))


if __name__ == "__main__":
    main()
