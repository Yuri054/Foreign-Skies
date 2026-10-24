#!/usr/bin/env python3
"""Gives a scenario's big cities the factories and railways they already had: writes `buildings`
({province name: {factory, railway}}) into its scenario.json from cities.tsv. Run from the project root:
python3 tools/make_start_buildings.py data/scenarios/july_1914 [more folders]. tools/make_1900.py calls it."""
import csv, json, sys

def levels(pop):
    # (people in the city) -> (factory levels, railway levels)
    for floor, f, r in ((1_400_000, 3, 3), (700_000, 2, 2), (300_000, 1, 2), (150_000, 1, 1), (80_000, 0, 1)):
        if pop >= floor:
            return f, r
    return 0, 0

def main(folder):
    sc_path = folder.rstrip("/") + "/scenario.json"
    sc = json.load(open(sc_path))
    province_name = {}
    for row in csv.DictReader(open(folder.rstrip("/") + "/provinces.tsv"), delimiter="\t"):
        province_name[row["id"]] = row["name"]
    out = {}
    for row in csv.DictReader(open(folder.rstrip("/") + "/cities.tsv"), delimiter="\t"):
        name = province_name.get(row["province"])
        if name is None:
            continue
        f, r = levels(int(float(row["pop"])))
        have = out.setdefault(name, {})
        if f:
            have["factory"] = max(have.get("factory", 0), f)
        if r:
            have["railway"] = max(have.get("railway", 0), r)
    sc["buildings"] = {k: v for k, v in out.items() if v}
    json.dump(sc, open(sc_path, "w"), indent="\t", ensure_ascii=False)
    print(folder, len(sc["buildings"]), "provinces with works")

if __name__ == "__main__":
    for f in sys.argv[1:]:
        main(f)
