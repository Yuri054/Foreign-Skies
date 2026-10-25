#!/usr/bin/env python3
"""Builds data/scenarios/jan_1900 from july_1914: the same land with the 1900 map, people, wealth, armies and
treaties. Run from the project root; the output is committed, so this is only for re-tuning the numbers."""
import csv, json, os

SRC = "data/scenarios/july_1914/"
DST = "data/scenarios/jan_1900/"
os.makedirs(DST, exist_ok=True)
sc = json.load(open(SRC + "scenario.json"))

# ---- the 1900 map: land the Balkan Wars and 1913 settlement moved
owner_changes = {}
def give(tag, names):
    for n in names:
        owner_changes[n] = tag
give("OTT", ["Berat", "Dibër", "Elbasan", "Fier", "Gjirokastër", "Korçë", "Kukës", "Shkodër", "Tiranë", "Vlorë"])
give("OTT", ["Gevgelija", "Kavadartsi", "Kočani", "Kumanovo", "Mavrovo and Rostusa", "Prilep", "Struga",
             "Kosovska Mitrovica", "Priština", "Uroševac", "Đakovica", "Raški"])
give("OTT", ["Berane", "Pljevlja"])
give("OTT", ["Anatoliki Makedonia kai Thraki 1", "Anatoliki Makedonia kai Thraki 2", "Dytiki Makedonia",
             "Kentriki Makedonia 1", "Kentriki Makedonia 2", "Ipeiros", "Kriti", "Voreio Aigaio"])
give("OTT", ["Blagoevgrad", "Smolyan", "Kardzhali"])
give("BUL", ["Dobrich", "Silistra"])

map_rows = {r["name"]: r for r in csv.DictReader(open("data/map/provinces.tsv"), delimiter="\t")}
for n in owner_changes:
    assert n in map_rows, n

# ---- people: fewer of them, and the great powers less than later
pop = {"GBR": .90, "FRA": .94, "GER": .82, "AUH": .86, "RUS": .80, "ITA": .88, "ESP": .92, "POR": .90, "BEL": .88,
       "NED": .86, "SUI": .90, "DEN": .88, "SWE": .93, "NOR": .90, "ROM": .82, "SRB": .80, "BUL": .80, "GRE": .80,
       "OTT": .85, "MNE": .85, "LUX": .88, "ALB": .85}
def owner_of(row):
    return owner_changes.get(row["name"], map_rows[row["name"]]["owner"])
by_id = {r["id"]: r for r in map_rows.values()}
with open(SRC + "provinces.tsv") as f, open(DST + "provinces.tsv", "w") as g:
    g.write("id\tname\tpopulation\n")
    for row in csv.DictReader(f, delimiter="\t"):
        o = owner_of(by_id[row["id"]])
        g.write("%s\t%s\t%d\n" % (row["id"], row["name"], round(int(row["population"]) * pop.get(o, .88), -2)))

def copy_scaled_cities():
    with open(SRC + "cities.tsv") as f, open(DST + "cities.tsv", "w") as g:
        rd = csv.DictReader(f, delimiter="\t")
        g.write("\t".join(rd.fieldnames) + "\n")
        for row in rd:
            prov = by_id.get(row["province"])
            o = owner_of(prov) if prov else "X"
            row["pop"] = str(int(round(int(row["pop"]) * pop.get(o, .88) * .97, -3)))
            g.write("\t".join(row[k] for k in rd.fieldnames) + "\n")
copy_scaled_cities()
open(DST + "resources.tsv", "w").write(open(SRC + "resources.tsv").read())

# ---- fleets: no submarines yet, battle squadrons thinner, a smaller German navy
navy_cut = {"GER": {"dreadnought": 1}, "AUH": {"dreadnought": 1}, "ITA": {"dreadnought": 1}, "RUS": {"dreadnought": 1}}
with open(SRC + "navy.tsv") as f, open(DST + "navy.tsv", "w") as g:
    rd = csv.DictReader(f, delimiter="\t")
    g.write("\t".join(rd.fieldnames) + "\n")
    for row in rd:
        if row["type"] == "submarine":
            continue
        cap = navy_cut.get(row["tag"], {}).get(row["type"])
        if cap is not None:
            row["count"] = str(min(int(row["count"]), cap))
        if row["tag"] == "GER" and row["type"] == "destroyer":
            row["count"] = str(max(1, int(row["count"]) // 2))
        if row["tag"] == "FRA" and row["type"] == "dreadnought":
            row["count"] = str(max(1, int(row["count"]) - 1))
        g.write("\t".join(row[k] for k in rd.fieldnames) + "\n")

# ---- nations
dev = {"GER": .78, "RUS": .80, "AUH": .82, "ITA": .82, "FRA": .88, "GBR": .88}
army = {"GER": .72, "FRA": .85, "RUS": .80, "AUH": .80, "ITA": .85, "GBR": .85, "OTT": .8}
navy = {"GER": .40, "GBR": .72, "FRA": .80, "RUS": .60, "ITA": .70, "AUH": .55}
nations = {}
for tag, v in sc["nations"].items():
    w = dict(v)
    w["development"] = round(v["development"] * dev.get(tag, .85), 3)
    w["peacetime_army"] = int(round(v["peacetime_army"] * army.get(tag, .85), -3))
    w["naval_budget"] = round(v["naval_budget"] * navy.get(tag, .7), 2)
    w["treasury"] = round(v["treasury"] * .7, 1)
    w["pop_growth"] = v["pop_growth"]
    if tag == "RUS":
        w["government"] = "constitutional_monarchy"
    nations[tag] = w
nations["ALB"] = {"pop_growth": 0.0}

out = {
    "name": "January 1900",
    "description": "A new century. Europe's great powers are at peace, rich and sure of themselves, and the alliances that will carry them into a great war are not yet signed. Whether it comes is up to you.",
    "start_date": [1900, 1, 1],
    "default_player": "GER",
    "playable": True,
    "pressure_ai": True,
    "owner_changes": owner_changes,
    "nations": nations,
    "_deployment_note": sc["_deployment_note"],
    "deployment": {k: v for k, v in sc["deployment"].items() if k != "ALB"},
    "blocs": {"Triple Alliance": ["GER", "AUH", "ITA"], "Dual Alliance": ["FRA", "RUS"]},
    "neutral_pacts": {},
    "guarantees": [{"guarantor": "GBR", "guaranteed": "BEL", "note": "1839 Treaty of London"},
                   {"guarantor": "GER", "guaranteed": "BEL", "note": "1839 Treaty of London"},
                   {"guarantor": "FRA", "guaranteed": "BEL", "note": "1839 Treaty of London"}],
    "alliances": [
        {"a": "FRA", "b": "RUS", "note": "Franco-Russian Alliance, 1894"},
        {"a": "GER", "b": "AUH", "note": "Dual Alliance, 1879"},
        {"a": "SWE", "b": "NOR", "note": "Union under one king"},
        {"a": "ITA", "b": "GER", "terms": {"defensive_only": True}, "note": "Triple Alliance, 1882"},
        {"a": "ITA", "b": "AUH", "terms": {"defensive_only": True}, "note": "Triple Alliance, 1882"},
        {"a": "GBR", "b": "POR", "terms": {"defensive_only": True}, "note": "Anglo-Portuguese Alliance, 1373"},
    ],
    "passage": [], "nap": [],
    "ai_traits": {}, "ai_plans": [],
    "relations": [
        {"a": "GER", "b": "FRA", "value": -40}, {"a": "GBR", "b": "FRA", "value": -15, "note": "Fashoda, 1898"},
        {"a": "GBR", "b": "RUS", "value": -30, "note": "The Great Game"}, {"a": "GBR", "b": "GER", "value": 5},
        {"a": "RUS", "b": "AUH", "value": -35, "note": "Rivals in the Balkans"}, {"a": "RUS", "b": "GER", "value": -5},
        {"a": "ITA", "b": "AUH", "value": -20, "note": "Italia irredenta"}, {"a": "ITA", "b": "FRA", "value": 5},
        {"a": "GBR", "b": "OTT", "value": -5}, {"a": "OTT", "b": "RUS", "value": -45}, {"a": "OTT", "b": "GER", "value": 20},
        {"a": "GRE", "b": "OTT", "value": -40}, {"a": "SRB", "b": "AUH", "value": -25}, {"a": "SRB", "b": "OTT", "value": -25},
        {"a": "BUL", "b": "OTT", "value": -30}, {"a": "BUL", "b": "SRB", "value": -20},
        {"a": "NOR", "b": "SWE", "value": 25, "note": "Joined in a union under one king"},
        {"a": "SWE", "b": "RUS", "value": -30}, {"a": "DEN", "b": "GER", "value": -20, "note": "Schleswig"},
        {"a": "BEL", "b": "GBR", "value": 25}, {"a": "BEL", "b": "FRA", "value": 15},
        {"a": "NED", "b": "GBR", "value": 10, "note": "The Boer War"}, {"a": "ESP", "b": "FRA", "value": 5},
    ],
    "claims": [c for c in sc["claims"] if c["holder"] not in ("SRB", "AUH", "ROM")] + [
        {"holder": "SRB", "kind": "border_claim", "provinces": ["Sarajevo-romanija", "Central Bosnia", "Južno-Backi"], "note": "Bosnia and Vojvodina"}],
}
dep = out["deployment"]
def retarget(tag, old, name, at):
    for e in dep[tag]:
        if e["at"] == old:
            e["at"], e["name"] = at, name
retarget("SRB", "Kumanovo", "Southern Corps (Vranje)", "Pcinjski")
retarget("SRB", "Priština", "Toplica Corps", "Toplicki")
retarget("GRE", "Kentriki Makedonia 1", "Army of Thessaly (Larissa)", "Thessalia 2")
retarget("GRE", "Ipeiros", "Army of the Isthmus", "Stereá Elláda 1")
dep["OTT"] += [{"name": "Army of Macedonia (Salonika)", "at": "Kentriki Makedonia 1", "weight": 3},
               {"name": "Scutari Corps", "at": "Shkodër", "weight": 1},
               {"name": "Kosovo Corps", "at": "Priština", "weight": 1}]
json.dump(out, open(DST + "scenario.json", "w"), indent="\t", ensure_ascii=False)
import subprocess
subprocess.run(["python3", "tools/make_start_buildings.py", DST], check=True)
print("owner changes:", len(owner_changes))
