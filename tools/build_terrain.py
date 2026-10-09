"""Assign a terrain type to every province (curated from real geography).

Usage: python tools/build_terrain.py [map_dir]

Writes terrain.tsv (id, name, terrain). Terrain is one of plains, forest, hills, mountains,
marsh, urban (see "terrain" in data/military.json). There is no elevation dataset in the
repo, so each province's dominant terrain is listed by hand below, keyed by province id
(ids come from provinces.tsv). Anything not listed is plains; very dense small provinces
(big cities) are urban. Re-run after editing the lists; `--check` only validates them.
"""
import csv
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
args = [a for a in sys.argv[1:] if not a.startswith("--")]
map_dir = Path(args[0]) if args else root / "data" / "map"

URBAN_DENSITY = 1000  # people per km2 in a province under URBAN_MAX_KM2
URBAN_MAX_KM2 = 2500
# capitals and big cities that stay urban whatever the modelled population
URBAN_NAMES = {"Moscow", "Saint Petersburg", "Kiev (city)", "Minsk (city)", "Riga", "Constantinople", "Bucuresti", "Belgrade", "Sofia City", "Attica"}

TERRAIN = {
    "mountains": [
        # Austria-Hungary: Alps, Carpathians, Dinaric Alps, Sudetes
        5, 6, 31, 38, 47, 53, 55, 59, 68, 80, 2, 17, 13, 48, 19, 57, 67, 71, 76, 33, 52, 79, 15, 73, 32,
        # France: Alps, Pyrenees, Corsica, Massif Central, Vosges, Isere
        168, 169, 206, 240, 203, 207, 172, 236, 237, 183, 198, 178, 221, 251, 212,
        # UK and Ireland
        297, 298, 299, 300, 256, 333, 271, 293, 303, 353, 275,
        # Spain: Cantabrian, Pyrenees, Sierra Nevada, Gredos, Guadarrama, Iberian
        102, 110, 129, 138, 124, 125, 164, 149, 108, 135, 154,
        # Germany: Sudetes, Beskids, Alps
        386, 419, 367,
        # Italy: Alps, Apennines, Etna, Sardinia
        431, 454, 509, 450, 500, 439, 441, 437, 507, 463, 445, 434, 488, 451, 490, 469, 471, 447, 475, 476,
        # Switzerland
        554, 549, 553, 552, 546,
    ],
    "hills": [
        1, 62, 20, 58, 35, 25, 70, 29, 78, 77, 23, 3, 4, 21, 24, 30, 34, 50, 63, 75, 65, 64, 74,
        87, 89, 514,
        200, 235, 171, 175, 216, 182, 184, 189, 213, 165, 190, 247, 248, 174, 245, 219, 185, 229, 227,
        194, 186, 228, 195, 202,
        286, 344, 254, 255, 320, 334, 266, 272, 264, 332, 319, 260, 270, 274, 273, 281, 327, 279, 336,
        282, 341, 340, 306, 325, 337, 292, 276, 269, 316, 290, 268, 277, 345, 321, 338, 309,
        122, 143, 101, 142, 152, 155, 115, 116, 131, 120, 103, 128, 117, 118, 148, 119, 111, 105, 107,
        123, 163, 134, 137, 144, 146, 133, 126, 112, 106,
        358, 359, 357, 362, 364, 421, 411, 412, 414, 398, 379, 380, 407, 408, 409, 410, 401, 385,
        433, 432, 483, 467, 430, 484, 502, 449, 503, 498, 457, 460, 495, 470, 438, 448, 497, 461, 481,
        492, 480, 455, 444, 428, 499, 477, 496, 506,
        555, 547, 550, 551,
        530, 531, 532, 533, 541, 529, 534, 543, 542,
    ],
    "forest": [
        44, 26, 82,
        170, 188, 214, 197, 215, 218, 242, 231, 232,
        261, 294, 347,
        361, 363, 366, 420, 395, 369, 371, 372, 387, 388, 406, 424, 425, 390,
        518,
    ],
    "marsh": [
        49, 8, 9,
        180, 176,
        262, 329, 351, 335, 265, 288,
        151,
        393, 394, 397, 416, 370,
        422,
        462, 464, 456, 494, 508, 489, 478,
        515, 516, 517, 519, 522, 524, 525, 526,
    ],
}

# Provinces added by tools/extend_map.py, listed by name (ids shift between slices, names do not).
# Anything not listed here or above is plains.
TERRAIN_BY_NAME = {
    "mountains": [
        # Carpathians, Dinaric Alps, Balkan range, Rhodopes, Pindus
        "Carpathian Ruthenia", "Maramures", "Bistrita-Nasaud", "Harghita", "Suceava", "Hunedoara",
        "Caras-Severin", "Covasna", "Brasov", "Stanislau", "Prešov",
        "Dibër", "Kukës", "Shkodër", "Korçë", "Gjirokastër",
        "Berane", "Cetinje", "Nikšic", "Pljevlja", "Podgorica",
        "Zlatiborski", "Raški", "Borski", "Pirotski", "Đakovica", "Struga", "Mavrovo and Rostusa", "Brod",
        "Blagoevgrad", "Smolyan", "Kardzhali", "Sofia", "Pernik", "Kyustendil", "Gabrovo", "Sliven", "Vratsa",
        "Ipeiros", "Dytiki Makedonia", "Thessalia 2", "Stereá Elláda 1", "Peloponnisos 1", "Kriti",
        "Arges", "Prahova", "Gorj", "Vâlcea", "Neamt", "Vrancea",
    ],
    "hills": [
        "Czernowitz", "Alba", "Sibiu", "Mures", "Cluj", "Salaj", "Bihor", "Lemberg", "Tarnopol", "Rzeszow",
        "Krakow", "Košický", "Borsod-Abaúj-Zemplén", "Nógrád", "Heves",
        "Elbasan", "Berat", "Vlorë", "Tiranë",
        "Jablanicki", "Pcinjski", "Zajecarski", "Kolubarski", "Šumadijski", "Moravicki", "Toplicki",
        "Branicevski", "Nišavski", "Skopje", "Kosovska Mitrovica", "Uroševac", "Prilep", "Kumanovo",
        "Kavadartsi", "Kočani", "Radoviš",
        "Pazardzhik", "Lovech", "Veliko Tarnovo", "Montana", "Shumen", "Targovishte", "Burgas", "Haskovo",
        "Kentriki Makedonia 1", "Kentriki Makedonia 2", "Stereá Elláda 2", "Peloponnisos 2", "Dytiki Ellada",
        "Ionioi Nisoi", "Notio Aigaio", "Voreio Aigaio", "Anatoliki Makedonia kai Thraki 1", "Attica",
        "Dâmbovita", "Mehedinti", "Bacau", "Buzau", "Iasi", "Vaslui",
        "Tekirdag", "Gallipoli",
    ],
    "forest": ["Kirklareli", "Warmian-Masurian (2)", "Masuria"],
    "marsh": ["Tulcea", "Braila"],
}
# Russia slice. A trailing * matches every province with that name prefix (split pieces).
for _terrain, _names in {
    "mountains": ["Dagestan", "Chechnya", "North Ossetia", "Kabardin-Balkar", "Karachay-Cherkess", "Adygea"],
    "hills": [
        "Krasnodar", "Crimea", "Sevastopol", "Stavropol", "Murmansk", "Karelia 1", "Bashkortostan*",
        "Yekaterinburg*", "Chelyabinsk", "Perm 3", "Orenburg 2", "Voronezh", "Kursk", "Belgorod", "Oryol",
        "Tula", "Kaluga", "Smolensk", "Penza", "Saratov*", "Simbirsk", "Chuvashia", "Nizhny Novgorod",
        "Podolia", "Vinnytsia", "Cherkasy", "Kiev", "Donetsk", "Luhansk", "Comrat", "Criuleni", "Hîncesti",
        "Rîşcani", "Sîngerei", "Świętokrzyskie", "Võru", "Madona", "Tsaritsyn 1",
    ],
    "forest": [
        "Arkhangelsk*", "Komi*", "Vologda*", "Kostroma", "Vyatka*", "Perm 1", "Perm 2", "Udmurtia", "Mari El",
        "Tver*", "Karelia 2", "Karelia 3", "Yaroslavl", "Ivanovo", "Vladimir", "Moscow Governorate",
        "Petrograd*", "Bryansk", "Zhytomyr", "Podlachian", "Vitebsk", "Minsk", "Mogilev", "Grodno",
        "Central Finland", "Central Ostrobothnia", "Kainuu", "Lapland", "North Karelia", "Northern Ostrobothnia",
        "Northern Savonia", "Southern Savonia", "South Karelia", "Kymenlaakso", "Pirkanmaa", "Päijät-Häme",
        "Satakunta", "Tavastia Proper", "Harju", "Tartu", "Pärnu", "Hiiu", "Saare", "Talsi", "Saldus",
        "Burtnieku", "Gulbene", "Jekabpils", "Ogre", "Rezeknes", "Kauno", "Šiauliai", "Utenos", "Panevezio",
        "Alytaus", "Vilniaus", "Klaipedos", "Konigsberg 1", "Konigsberg 2", "Novgorod", "Sumy",
    ],
    "marsh": ["Nenets", "Brest", "Gomel", "Rivne", "Volyn", "Astrakhan", "Pskov"],
}.items():
    TERRAIN_BY_NAME[_terrain].extend(_names)
by_id = {}
with open(map_dir / "provinces.tsv", encoding="utf-8") as f:
    for r in csv.DictReader(f, delimiter="\t"):
        by_id[int(r["id"])] = r

pop = {}
with open(root / "data" / "scenarios" / "july_1914" / "provinces.tsv", encoding="utf-8") as f:
    for r in csv.DictReader(f, delimiter="\t"):
        pop[int(r["id"])] = int(r["population"])

name_to_id = {r["name"]: i for i, r in by_id.items()}
for terrain, names in TERRAIN_BY_NAME.items():
    expanded = []
    for n in names:
        if n.endswith("*"):
            expanded += [m for m in name_to_id if m.startswith(n[:-1])]
        else:
            expanded.append(n)
    for n in expanded:
        if n not in name_to_id:
            print(f"note: no province named {n!r} (merged or renamed), skipped")
            continue
        TERRAIN.setdefault(terrain, []).append(name_to_id[n])

assigned = {}
for terrain, ids in TERRAIN.items():
    for i in ids:
        if i not in by_id:
            sys.exit(f"unknown province id {i} in {terrain}")
        if i in assigned and assigned[i] != terrain:
            print(f"note: {by_id[i]['name']} ({i}) listed as {assigned[i]} and {terrain}; using {terrain}")
        assigned[i] = terrain

if "--check" in sys.argv:
    print("lists ok")
    sys.exit(0)

counts = {}
with open(map_dir / "terrain.tsv", "w", encoding="utf-8", newline="") as f:
    w = csv.writer(f, delimiter="\t", lineterminator="\n")
    w.writerow(["id", "name", "terrain"])
    for i in sorted(by_id):
        km2 = int(by_id[i]["area"]) * 0.48
        terrain = assigned.get(i, "plains")
        if km2 <= URBAN_MAX_KM2 and pop[i] / max(km2, 1.0) >= URBAN_DENSITY or by_id[i]["name"] in URBAN_NAMES:
            terrain = "urban"
        counts[terrain] = counts.get(terrain, 0) + 1
        w.writerow([i, by_id[i]["name"], terrain])
print(counts)
