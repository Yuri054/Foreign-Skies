#!/usr/bin/env python3
"""Gives each nation of a scenario its starting buildings in the gold economy (docs/REWORK.md, R3): civilian factories
sized so that its income at the start is about its target, and construction sectors (about one for every four
factories), placed where the old economy had its factories (the capital if none). Railways are kept. Writes
`buildings` ({province name: {type: level}}) into the scenario's scenario.json. Run from the project root:
python3 tools/make_start_economy.py data/scenarios/july_1914 data/scenarios/jan_1900

Targets, gold a month in 1914: the great powers' from docs/REWORK.md; every other nation's is its revenue a month in
the old economy (0.17.0, the first number of OLD_REVENUE) times SCALE. A 1900 target is the 1914 one times the old
revenue in 1900 over the old revenue in 1914. Base income is economy.json's income.per_million gold a month for each
million people to the power income.exponent, per province."""
import csv, json, sys

TARGETS_1914 = {"GER": 25.0, "GBR": 28.0, "FRA": 20.0, "RUS": 18.0, "AUH": 14.0, "ITA": 10.0}
SCALE = 1.12
# Old revenue a month (GBP millions) in 1914 and 1900, from the 0.17.0 economy.
OLD_REVENUE = {
    "GBR": (16.6, 13.2), "FRA": (16.0, 13.3), "GER": (22.4, 14.1), "BEL": (2.4, 1.7), "NED": (2.1, 1.5),
    "LUX": (0.2, 0.1), "SUI": (1.0, 0.7), "ITA": (8.0, 5.7), "ESP": (3.1, 2.4), "POR": (1.2, 0.9), "DEN": (1.2, 0.9),
    "AUH": (12.0, 8.3), "SRB": (0.6, 0.2), "MNE": (0.0, 0.0), "ALB": (0.1, 0.1), "GRE": (0.9, 0.4), "BUL": (0.8, 0.5),
    "ROM": (1.4, 0.9), "OTT": (0.4, 0.7), "RUS": (20.4, 12.9), "NOR": (0.7, 0.5), "SWE": (1.5, 1.2),
}
PORT_START = 0.3   # every nation with a fleet gets one port level at its main base (Navy.deploy_starting)


def read_tsv(path):
    return list(csv.DictReader(open(path, encoding="utf-8"), delimiter="\t"))


def target(tag, year_1900):
    now, then = OLD_REVENUE.get(tag, (0.0, 0.0))
    t = TARGETS_1914.get(tag, now * SCALE)
    if year_1900:
        t *= then / now if now > 0 else 1.0
    return t


def spread(total, weights):
    """`total` levels over the keys of `weights` by largest remainder, at most 10 each."""
    out = {k: 0 for k in weights}
    s = sum(weights.values())
    if s <= 0 or total <= 0:
        return out
    exact = {k: total * w / s for k, w in weights.items()}
    for k in out:
        out[k] = min(10, int(exact[k]))
    left = total - sum(out.values())
    for k in sorted(weights, key=lambda k: exact[k] - int(exact[k]), reverse=True):
        if left <= 0:
            break
        if out[k] < 10:
            out[k] += 1
            left -= 1
    return out


def main(folder):
    folder = folder.rstrip("/")
    sc_path = folder + "/scenario.json"
    text = open(sc_path, encoding="utf-8").read()
    sc = json.loads(text)
    eco = json.load(open("data/economy.json"))
    per_million, exponent = eco["income"]["per_million"], eco["income"]["exponent"]
    civ_income = eco["buildings"]["civilian_factory"]["income"]
    year_1900 = sc["start_date"][0] < 1910
    names, owner = {}, {}
    for row in read_tsv("data/map/provinces.tsv"):
        names[row["id"]] = row["name"]
        owner[row["name"]] = row["owner"]
    for name, tag in sc.get("owner_changes", {}).items():
        owner[name] = tag
    pop = {names[r["id"]]: int(r["population"]) for r in read_tsv(folder + "/provinces.tsv") if r["id"] in names}
    old = sc.get("buildings", {})
    by_nation = {}
    for name, tag in owner.items():
        by_nation.setdefault(tag, []).append(name)
    out = {name: {"railway": v["railway"]} for name, v in old.items() if v.get("railway")}
    for tag, provinces in sorted(by_nation.items()):
        if tag not in sc["nations"]:
            continue
        base = sum(per_million * (pop.get(p, 0) / 1e6) ** exponent for p in provinces)
        civ = max(1, round((target(tag, year_1900) - base - PORT_START) / civ_income))
        sectors = max(1, round(civ / 4))
        capital = names.get(str(sc["nations"][tag].get("capital", 0)), max(provinces, key=lambda p: pop.get(p, 0)))
        weights = {p: old.get(p, {}).get("factory", 0) for p in provinces}
        if sum(weights.values()) == 0:
            weights = {capital: 1}
        for p, n in spread(civ, weights).items():
            if n:
                out.setdefault(p, {})["civilian_factory"] = n
        ranked = sorted(weights, key=lambda p: (-weights[p], p != capital, p))
        for p in ranked[:sectors]:
            out.setdefault(p, {})["construction_sector"] = 1
        if sectors > len(ranked):
            out.setdefault(ranked[0], {})["construction_sector"] = sectors - len(ranked) + 1
        print("%s %s: base %.1f, %d civilian factories, %d construction sectors, about %.1f gold a month" % (
            folder.split("/")[-1], tag, base, civ, sectors, base + civ * civ_income + PORT_START))
    block = json.dumps({"buildings": {k: dict(sorted(v.items())) for k, v in out.items()}}, indent="\t", ensure_ascii=False)
    block = block[2:-2]   # the key and its value, one level in
    i = text.index('\t"buildings": {')
    open(sc_path, "w", encoding="utf-8").write(text[:i] + block + "\n}")


if __name__ == "__main__":
    for f in sys.argv[1:]:
        main(f)
