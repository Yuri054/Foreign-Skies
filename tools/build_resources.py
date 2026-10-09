"""Place 1913-ish coal, iron ore and timber deposits on the provinces.

Usage: python tools/build_resources.py

Writes data/scenarios/july_1914/resources.tsv (id, wood, iron, coal): the potential annual
output of each province in thousand tonnes, at normal extraction.

Coal and iron are listed per province as relative weights, then scaled so each nation's total
matches a rough 1913 national output (only the part inside the map frame; lignite counted at
a third of its tonnage). Timber is spread over each nation's area by forest weight and
sparseness of population. All figures are rough estimates meant to be refined.
"""
import csv
from pathlib import Path

root = Path(__file__).resolve().parent.parent
provinces = list(csv.DictReader(open(root / "data/map/provinces.tsv", encoding="utf-8"), delimiter="\t"))
pops = {int(r["id"]): int(r["population"]) for r in
        csv.DictReader(open(root / "data/scenarios/july_1914/provinces.tsv", encoding="utf-8"), delimiter="\t")}
by_name = {r["name"]: r for r in provinces}


GROUPS = [(1, 556, "west"), (557, 717, "balkans"), (718, 878, "russia")]  # province id ranges, one per map slice (see build_population)


def group_of(i):
    for lo, hi, g in GROUPS:
        if lo <= i <= hi:
            return g
    raise SystemExit(f"province {i} is in no group: add its slice to GROUPS")


def pid(name):
    if name not in by_name:
        raise SystemExit("unknown province: " + name)
    return int(by_name[name]["id"])


# ---- national output targets, thousand tonnes per year
# Each slice of the map has its own totals, so a new region never changes an older one.
COAL_TOTAL = {("GBR", "west"): 292000, ("GER", "west"): 225000, ("FRA", "west"): 40000, ("BEL", "west"): 23000,
              ("NED", "west"): 1900, ("AUH", "west"): 30000, ("ESP", "west"): 4000, ("ITA", "west"): 700,
              ("POR", "west"): 230,
              ("AUH", "balkans"): 7000, ("SRB", "balkans"): 450, ("BUL", "balkans"): 200,
              ("ROM", "balkans"): 100, ("GRE", "balkans"): 50,
              ("RUS", "russia"): 27000}
IRON_TOTAL = {("GER", "west"): 28000, ("LUX", "west"): 7300, ("FRA", "west"): 22000, ("BEL", "west"): 200,
              ("GBR", "west"): 16000, ("ESP", "west"): 9800, ("AUH", "west"): 4500, ("ITA", "west"): 600,
              ("SUI", "west"): 40, ("POR", "west"): 100,
              ("AUH", "balkans"): 550, ("SRB", "balkans"): 30, ("GRE", "balkans"): 100,
              ("RUS", "russia"): 8050}
WOOD_TOTAL = {("GER", "west"): 24000, ("FRA", "west"): 17000, ("AUH", "west"): 20000, ("GBR", "west"): 2000,
              ("ESP", "west"): 4500, ("ITA", "west"): 4000, ("SUI", "west"): 1800, ("BEL", "west"): 700,
              ("NED", "west"): 300, ("LUX", "west"): 130, ("DEN", "west"): 400, ("POR", "west"): 1500,
              ("AUH", "balkans"): 10000, ("GER", "balkans"): 400, ("SRB", "balkans"): 1500,
              ("MNE", "balkans"): 400, ("ALB", "balkans"): 400, ("GRE", "balkans"): 600,
              ("BUL", "balkans"): 1500, ("ROM", "balkans"): 6000, ("OTT", "balkans"): 300,
              # Russia slice, by modern country (provinces.tsv "admin" column)
              ("RUS", "russia", "Russia"): 45000, ("RUS", "russia", "Finland"): 12000,
              ("RUS", "russia", "Estonia"): 1500, ("RUS", "russia", "Latvia"): 2000,
              ("RUS", "russia", "Lithuania"): 1500, ("RUS", "russia", "Belarus"): 4000,
              ("RUS", "russia", "Ukraine"): 3000, ("RUS", "russia", "Moldova"): 100,
              ("RUS", "russia", "Poland"): 2500, ("RUS", "west"): 100,
              ("GER", "russia", "Russia"): 700, ("GER", "russia", "Lithuania"): 50}

# ---- relative weights per province
COAL = {
    # Britain
    "Durham": 41, "Northumberland": 15.6, "Barnsley": 36, "North Yorkshire 2": 22, "Derbyshire": 17,
    "Nottinghamshire": 13, "Lancashire": 24, "Manchester": 4, "Staffordshire": 16, "Warwickshire": 5,
    "Leicestershire": 3, "Cheshire East": 2, "Shropshire": 1.5, "Worcestershire": 1, "Gloucestershire": 1.5,
    "Somerset": 1, "Cumbria": 2.5, "Cardiff": 15, "Bridgend": 12, "Monmouthshire": 9, "Carmarthenshire": 6,
    "Denbighshire": 3, "South Lanarkshire": 17, "Fife": 9, "East Ayrshire": 7, "Edinburgh": 6,
    "Glasgow": 3, "Stirling": 3, "South Ayrshire": 1, "Kilkenny": 0.1,
    # Germany (Ruhr, Aachen, Saar, Silesia, plus lignite at one third)
    "Nordrhein-Westfalen 2": 105, "Nordrhein-Westfalen 4": 20, "Saarland": 13, "Silesian 1": 35,
    "Silesian 2": 10, "Opole": 3, "Lower Silesian 3": 6, "Sachsen 2": 6, "Sachsen 1": 4,
    "Sachsen-Anhalt 3": 8, "Sachsen-Anhalt 2": 2, "Brandenburg 4": 4, "Lubusz 2": 3,
    "Niedersachsen 6": 2, "Hessen 1": 1, "Bayern 3": 1, "Nordrhein-Westfalen 1": 1, "Moselle": 3,
    # France
    "Pas-de-Calais": 20, "Nord": 9, "Loire": 4, "Gard": 2, "Saône-et-Loire": 2, "Tarn": 1.5,
    "Aveyron": 1.5, "Allier": 1, "Isère": 0.5,
    # Belgium and the Netherlands
    "Hainaut": 13, "Liege": 6, "Namur": 1, "Limburg": 0.8, "Limburg (2)": 1,
    # Austria-Hungary
    "Moravskoslezský": 14, "Ústecký": 5, "Plzeňský": 2.5, "Středočeský": 3.5, "Karlovarský": 1.5,
    "Královéhradecký": 1.8, "Steiermark": 0.8, "Oberösterreich": 0.5, "Baranya": 0.8,
    "Komárom-Esztergom": 1.6, "Tuzla": 0.5, "Zenica-Doboj": 0.8, "Istarska": 0.9, "Ljubljana": 0.8,
    # Spain, Italy, Portugal
    "Asturias": 3.0, "León 1": 0.6, "Palencia": 0.4, "Córdoba 1": 1, "Ciudad Real 1": 0.35, "Teruel 1": 0.15,
    "Cagliari": 0.4, "Grosseto": 0.2, "Arezzo": 0.1, "Coimbra": 0.15, "Porto": 0.08,
    # Balkans slice: Galicia, Jiu valley, Hungarian lignite; Serbian, Bulgarian, Romanian, Greek lignite
    "Krakow": 24, "Hunedoara": 23, "Borsod-Abaúj-Zemplén": 7, "Nógrád": 6, "Caras-Severin": 4.5,
    "Kolubarski": 3, "Pomoravski": 2, "Zajecarski": 1.5, "Pirotski": 1, "Borski": 1,
    "Pernik": 5, "Kyustendil": 2, "Burgas": 0.5,
    "Prahova": 2, "Gorj": 1.5, "Bacau": 1, "Arges": 0.5,
    "Stereá Elláda 2": 1,
    # Russia slice: Donbas, Moscow lignite, Kizel, Chelyabinsk lignite
    "Donetsk": 14000, "Luhansk": 8000, "Rostov 1": 4000, "Tula": 500, "Perm 1": 1000, "Chelyabinsk": 500,
}
IRON = {
    "Meurthe-et-Moselle": 19.8, "Meuse": 0.2, "Calvados": 0.9, "Orne": 0.7, "Pyrénées-Orientales": 0.4,
    "Ariège": 0.2, "Moselle": 20.5, "Nordrhein-Westfalen 3": 2.0, "Hessen 2": 1.0, "Niedersachsen 6": 1.6,
    "Rheinland-Pfalz 1": 0.7, "Bayern 3": 0.6, "Lower Silesian 3": 0.2, "Baden-Württemberg 4": 0.4,
    "Luxembourg": 7.3, "Belgian Luxembourg": 0.15,
    "North Yorkshire 1": 5.5, "Northamptonshire": 4.5, "Lincolnshire": 3.5, "Leicestershire": 1.5,
    "Cumbria": 1.4, "Oxfordshire": 0.8, "Staffordshire": 1.0, "Derbyshire": 0.9, "Gloucestershire": 0.3,
    "Shropshire": 0.3, "Warwickshire": 0.3, "Moyle": 0.2,
    "Bizkaia": 5.0, "Cantabria": 0.6, "Asturias": 0.2, "Almería": 1.5, "Murcia": 0.9, "Granada 2": 0.6,
    "Teruel 1": 0.7, "Guadalajara 1": 0.3, "Málaga": 0.3, "León 1": 0.2, "Navarra": 0.2, "Lugo": 0.4,
    "Gipuzkoa": 0.3,
    "Steiermark": 2.0, "Kärnten": 0.3, "Banskobystrický": 0.6, "Zenica-Doboj": 0.3, "Banja Luka": 0.6,
    "Středočeský": 0.3, "Plzeňský": 0.2, "Tirol": 0.1,
    "Grosseto": 0.2, "Aoste": 0.1, "Brescia": 0.1, "Bergamo": 0.1, "Cagliari": 0.05,
    "Sankt Gallen": 0.04, "Bragança": 0.07,
    "Hunedoara": 3.0, "Caras-Severin": 1.0, "Borsod-Abaúj-Zemplén": 1.5,
    "Zlatiborski": 1.0,
    "Notio Aigaio": 1.0,
    # Russia slice: Krivoy Rog, the Urals, Kerch, Tula-Lipetsk
    "Yekaterinoslav": 6000, "Yekaterinburg 1": 450, "Yekaterinburg 2": 250, "Chelyabinsk": 300, "Crimea": 400,
    "Tula": 200, "Lipetsk": 100, "Bashkortostan 2": 100, "Perm 3": 150, "Świętokrzyskie": 100,
}
# Forest weight multipliers (default 1). Applied on top of area and a sparseness factor.
FOREST = {
    "Bayern 3": 3, "Bayern 6": 2, "Bayern 7": 1.5, "Baden-Württemberg 3": 3, "Baden-Württemberg 4": 3,
    "Thüringen 1": 2.5, "Thüringen 2": 2, "Sachsen 1": 2, "Sachsen 2": 2, "Hessen 1": 2, "Hessen 2": 2,
    "Rheinland-Pfalz 1": 2, "Rheinland-Pfalz 2": 2, "Rheinland-Pfalz 3": 2, "Brandenburg 1": 1.5,
    "Brandenburg 2": 1.5, "Brandenburg 3": 1.5, "Brandenburg 4": 1.5, "Niedersachsen 6": 2,
    "Lubusz 1": 2, "Lubusz 2": 2, "Bas-Rhin": 2, "Moselle": 1.5, "Silesian 1": 1.5, "Silesian 2": 2,
    "Lower Silesian 3": 2, "Opole": 1.5, "Berlin": 0.1, "Bremen": 0.1, "Hamburg": 0.1,
    "Vosges": 4, "Landes": 4, "Jura": 3, "Doubs": 2.5, "Haute-Saône": 2, "Ardennes": 3, "Meuse": 2,
    "Gironde": 2, "Haute-Savoie": 2.5, "Savoie": 2.5, "Isère": 2, "Hautes-Alpes": 2, "Var": 2,
    "Corse-du-Sud": 2, "Haute-Corse": 2, "Lozère": 1.5, "Ardèche": 1.5, "Dordogne": 2, "Vendée": 0.5,
    "Paris": 0.05, "Rhône": 0.3, "Nord": 0.3,
    "Jihočeský": 2, "Vysočina": 1.5, "Plzeňský": 2.5, "Karlovarský": 2, "Steiermark": 3.5, "Kärnten": 3,
    "Salzburg": 3, "Oberösterreich": 2, "Tirol": 2.5, "Vorarlberg": 2, "Banskobystrický": 3, "Žilinský": 3,
    "Trenciansky": 2, "Licko-Senjska": 3, "Karlovacka": 2.5, "Primorsko-Goranska": 2.5, "Kocevje": 4,
    "Bohinj": 3, "Bozen": 2.5, "Trento": 2.5, "Bács-Kiskun": 0.3, "Fejér": 0.3, "Tolna": 0.4,
    "Wien": 0.1, "Budapest": 0.05, "Prague": 0.1,
    "Soria": 3, "Segovia": 2, "Cuenca 1": 2, "Cuenca 2": 2, "Guadalajara 1": 1.5, "Navarra": 2,
    "Asturias": 2, "La Coruña": 2, "Lugo": 2, "Orense": 2, "Pontevedra": 2, "Burgos 1": 1.5,
    "Almería": 0.3, "Murcia": 0.4, "Valencia": 0.3, "Sevilla 1": 0.5, "Sevilla 2": 0.5,
    "Sondrio": 3, "Aoste": 3, "Cuneo": 2.5, "Cosenza": 3, "Udine": 2.5, "Pordenone": 1.5,
    "Verbano-Cusio-Ossola": 2.5, "Nuoro": 1.5, "Rieti": 2, "L'Aquila": 2, "Potenza": 1.5, "Genova": 1.5,
    "Belluno": 3, "Padova": 0.3, "Rovigo": 0.3, "Venezia": 0.3,
    "Graubünden": 3, "Valais": 2, "Bern": 1.5, "Ticino": 2,
    "Leiria": 3, "Viseu": 1.5, "Bragança": 1.5,
    "Belgian Luxembourg": 4, "Namur": 2, "Luxembourg": 2,
    "Highland 1": 1.5, "Highland 2": 1.5, "Highland 3": 1.5, "Highland 4": 1.5, "Dumfries and Galloway": 2,
    # Balkans slice
    "Carpathian Ruthenia": 3, "Maramures": 3, "Suceava": 3, "Harghita": 3, "Covasna": 3, "Brasov": 2,
    "Bistrita-Nasaud": 3, "Stanislau": 2.5, "Caras-Severin": 3, "Hunedoara": 2.5, "Gorj": 2, "Vâlcea": 2,
    "Arges": 2, "Neamt": 2.5, "Prahova": 2, "Vrancea": 2.5, "Czernowitz": 2,
    "Zlatiborski": 2.5, "Raški": 2, "Borski": 1.5, "Smolyan": 3, "Blagoevgrad": 2.5, "Kardzhali": 2,
    "Sofia": 2, "Kirklareli": 3, "Bucuresti": 0.05, "Belgrade": 0.1, "Sofia City": 0.1, "Constantinople": 0.1,
    "Attica": 0.3, "Budapest": 0.05,
    "Berane": 2.5, "Pljevlja": 2.5, "Cetinje": 1.5, "Dibër": 2, "Kukës": 2, "Shkodër": 1.5,
    "Masuria": 3,
    "Arkhangelsk 1": 2.5, "Arkhangelsk 2": 2.5, "Arkhangelsk 3": 2.5, "Arkhangelsk 4": 2.5, "Arkhangelsk 5": 2,
    "Komi 1": 3, "Komi 2": 3, "Komi 3": 3, "Komi 4": 3, "Komi 5": 3, "Komi 6": 2.5, "Komi 7": 2.5,
    "Vologda 1": 3, "Vologda 2": 3, "Vologda 3": 3, "Vyatka 1": 3, "Vyatka 2": 3, "Perm 1": 3, "Perm 2": 3,
    "Perm 3": 2.5, "Udmurtia": 2.5, "Kostroma": 3, "Karelia 1": 3, "Karelia 2": 3, "Karelia 3": 3,
    "Tver 1": 1.5, "Tver 2": 1.5, "Novgorod": 2, "Pskov": 1.2, "Petrograd 1": 2, "Petrograd 2": 2,
    "Mari El": 2.5, "Nizhny Novgorod": 1.5, "Murmansk": 0.5, "Nenets": 0.3, "Bashkortostan 1": 1.5,
    "Yekaterinburg 1": 2, "Yekaterinburg 2": 1.5, "Kalmyk": 0.05, "Astrakhan": 0.05, "Stavropol": 0.1,
    "Rostov 1": 0.2, "Rostov 2": 0.1, "Tsaritsyn 1": 0.1, "Tsaritsyn 2": 0.1, "Crimea": 0.2, "Krasnodar": 0.4,
    "Moscow": 0.02, "Saint Petersburg": 0.02, "Sevastopol": 0.05, "Kiev (city)": 0.02, "Minsk (city)": 0.02,
    "Riga": 0.1, "Dagestan": 0.5,
    "Central Finland": 3, "Kainuu": 3, "North Karelia": 3, "Northern Savonia": 3, "Southern Savonia": 3,
    "Lapland": 1.5, "Northern Ostrobothnia": 2, "Pirkanmaa": 2.5, "Satakunta": 1.5, "Päijät-Häme": 2,
    "Podlachian": 2, "Zhytomyr": 1.5, "Volyn": 1.5, "Rivne": 1.5, "Gomel": 1.5, "Brest": 1.5, "Vitebsk": 1.5,
    "Konigsberg 1": 0.8, "Konigsberg 2": 0.8,
}
for r in provinces:  # Bosnia, Herzegovina, Croatia hills default to heavy forest
    if r["owner"] == "AUH" and any(k in r["name"] for k in ("Bosnia", "Banja", "Doboj", "Foča", "Vlasenica", "Zenica", "Una-Sana", "Tuzla", "Sarajevo", "Herzegovina", "Trebinje")):
        FOREST.setdefault(r["name"], 3)


def spread(weights, totals, key):
    """Scale per-province weights so each nation's sum equals its target."""
    out = {}
    sums = {}
    for name, w in weights.items():
        o = (by_name[name]["owner"], group_of(pid(name))) if name in by_name else (_ for _ in ()).throw(SystemExit("unknown province: " + name))
        sums[o] = sums.get(o, 0.0) + w
    for name, w in weights.items():
        o = (by_name[name]["owner"], group_of(pid(name)))
        if o in totals:
            out[pid(name)] = w / sums[o] * totals[o]
        else:
            raise SystemExit(f"{key}: no national total for {o} ({name})")
    return out


coal = spread(COAL, COAL_TOTAL, "coal")
iron = spread(IRON, IRON_TOTAL, "iron")

# timber: area x forest weight x sparseness
raw = {}
for r in provinces:
    i = int(r["id"])
    area_km2 = int(r["area"]) * 0.48
    density = pops[i] / max(area_km2, 1.0)
    sparse = min(1.5, max(0.3, (100.0 / max(density, 1.0)) ** 0.5))
    region = (r["owner"], group_of(i), r.get("admin") or "")
    raw[i] = (region if region in WOOD_TOTAL else region[:2], area_km2 * FOREST.get(r["name"], 1.0) * sparse)
sums = {}
for o, w in raw.values():
    sums[o] = sums.get(o, 0.0) + w
wood = {i: (w / sums[o] * WOOD_TOTAL[o] if o in WOOD_TOTAL else 0.0) for i, (o, w) in raw.items()}

out = root / "data/scenarios/july_1914/resources.tsv"
with open(out, "w", encoding="utf-8", newline="") as f:
    w = csv.writer(f, delimiter="\t", lineterminator="\n")
    w.writerow(["id", "wood", "iron", "coal"])
    for r in provinces:
        i = int(r["id"])
        w.writerow([i, round(wood.get(i, 0.0)), round(iron.get(i, 0.0)), round(coal.get(i, 0.0))])
print("wrote", out)
for label, d in (("coal", coal), ("iron", iron), ("wood", wood)):
    per = {}
    for i, v in d.items():
        o = provinces[i - 1]["owner"] + "/" + group_of(i)
        per[o] = per.get(o, 0) + v
    print(label, {k: round(v) for k, v in sorted(per.items())})
