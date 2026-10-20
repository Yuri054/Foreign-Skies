"""Extend the province bitmap to the east and south without touching existing province ids.

Usage:
    python tools/extend_map.py <path-to-ne_10m_admin_1_states_provinces (no extension)> <slice> [--dry]

The canvas grows (once) from the original Western Europe frame to the full frame below
(Atlantic to the Urals, Crete to the Arctic coast). The existing bitmap is pasted in
unchanged, so every existing id, colour and name stays valid; new provinces are appended with
the next free ids. Each slice paints one region:

    balkans   Serbia, Montenegro, Albania, Greece, Bulgaria, Romania, Ottoman Thrace and the
              rest of Austria-Hungary (Galicia, Bukovina, Transylvania, Vojvodina, Hungary east
              of 19.5 E). Everything else on the new canvas becomes grey background land.
    russia    European Russia to the Urals, Finland, the Baltics, Poland (Congress), Belarus,
              Ukraine, Moldova.

Run the slices in order. Re-running a slice needs the backup of provinces.png and the tables,
because the output replaces them. Afterwards run tools/build_adjacencies.py,
tools/build_coastal.py and the data builders (terrain, population, resources).

Existing provinces cut by the old frame (East Prussia, Slovakia, Hungary, ...) are extended
into the new area instead of getting a twin; their `area` grows by the new pixels.
"""
import csv
import math
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np
import shapefile
from PIL import Image
from scipy import ndimage
from shapely.geometry import Polygon, box, shape
from shapely.ops import unary_union

import build_map as bm

Image.MAX_IMAGE_PIXELS = None

# ---------------------------------------------------------------- frames
OLD_LON0, OLD_LON1 = -11.0, 19.5
OLD_LAT0, OLD_LAT1 = 35.8, 59.0
LON0, LON1 = -11.0, 61.0
LAT0, LAT1 = 34.8, 67.0
PX_PER_DEG = 160.0
KX = PX_PER_DEG * math.cos(math.radians(47.0))
KY = PX_PER_DEG
W = int(round((LON1 - LON0) * KX))
H = int(round((LAT1 - LAT0) * KY))
OLD_W = int(round((OLD_LON1 - OLD_LON0) * KX))
OLD_H = int(round((OLD_LAT1 - OLD_LAT0) * KY))
DY = int(round((LAT1 - OLD_LAT1) * KY))  # how far the old bitmap moves down

# the shared rasteriser reads these module globals
bm.LON0, bm.LON1, bm.LAT0, bm.LAT1 = LON0, LON1, LAT0, LAT1
bm.KX, bm.KY, bm.W, bm.H = KX, KY, W, H

root = Path(__file__).resolve().parent.parent
MAP_DIR = root / "data" / "map"
SCEN_DIR = root / "data" / "scenarios" / "july_1914"
COS47 = math.cos(math.radians(47.0))

# ---------------------------------------------------------------- slices
# Polygon (lon, lat) of European Turkey: the Bosporus and Dardanelles are the south-east edge.
THRACE = Polygon([
    (24.0, 43.0), (29.4, 43.0), (29.4, 41.35), (29.12, 41.28), (29.04, 41.12), (28.99, 41.0),
    (28.95, 40.88), (27.1, 40.45), (26.9, 40.4), (26.7, 40.4), (26.4, 40.25), (26.35, 40.15),
    (26.15, 40.03), (25.0, 39.8),
])

TRANSYLVANIA = [
    "Satu Mare", "Arad", "Bihor", "Timis", "Caras-Severin", "Suceava", "Maramures", "Cluj",
    "Bistrita-Nasaud", "Salaj", "Hunedoara", "Covasna", "Brasov", "Sibiu", "Mures", "Harghita", "Alba",
]
VOJVODINA = [
    "Severno-Backi", "Zapadno-Backi", "Severno-Banatski", "Sremski", "Južno-Backi",
    "Srednje-Banatski", "Južno-Banatski",
]
GALICIA = ["Transcarpathia", "Chernivtsi", "Ivano-Frankivs'k", "L'viv", "Ternopil'"]

RUSSIA_SKIP = [("Russia", "Chukchi Autonomous Okrug"), ("Russia", "Khanty-Mansiy")]

SLICES = {
    "balkans": {
        "admins": {
            "Albania": "ALB", "Montenegro": "MNE", "Republic of Serbia": "SRB", "Kosovo": "SRB",
            "Macedonia": "SRB", "Bulgaria": "BUL", "Romania": "ROM", "Greece": "GRE", "Turkey": "OTT",
            "Hungary": "AUH", "Slovakia": "AUH", "Croatia": "AUH", "Bosnia and Herzegovina": "AUH",
        },
        "units": {
            **{("Romania", n): "AUH" for n in TRANSYLVANIA},
            **{("Republic of Serbia", n): "AUH" for n in VOJVODINA},
            **{("Ukraine", n): "AUH" for n in GALICIA},
            ("Poland", "Lesser Poland"): "AUH", ("Poland", "Subcarpathian"): "AUH",
            ("Bulgaria", "Dobrich"): "ROM", ("Bulgaria", "Silistra"): "ROM",
        },
        # units of the original scope whose 1914 owner is not on the map yet: left as background
        "skip_old": [("Poland", n) for n in ("Lublin", "Masovian", "Łódź", "Świętokrzyskie", "Podlaskie", "Podlachian")],
        "clip": {"Turkey": THRACE},
        "rename": {
            ("Republic of Serbia", "Grad Beograd"): "Belgrade", ("Bulgaria", "Grad Sofiya"): "Sofia City",
            ("Turkey", "Istanbul"): "Constantinople", ("Turkey", "Çanakkale"): "Gallipoli",
            ("Romania", "Bucharest"): "Bucuresti",
            ("Greece", "Attiki"): "Attica", ("Poland", "Lesser Poland"): "Krakow",
            ("Poland", "Subcarpathian"): "Rzeszow", ("Ukraine", "L'viv"): "Lemberg",
            ("Ukraine", "Chernivtsi"): "Czernowitz", ("Ukraine", "Transcarpathia"): "Carpathian Ruthenia",
            ("Ukraine", "Ivano-Frankivs'k"): "Stanislau", ("Ukraine", "Ternopil'"): "Tarnopol",
        },
        "no_merge": ["Belgrade", "Sofia City", "Constantinople", "Bucuresti", "Attica", "Tiranë", "Podgorica",
                     "Cetinje", "Krakow", "Lemberg"],
        "rename_dup": {"Warmian-Masurian (2)": "Masuria"},
        "a_max": {"AUH": 60000},
        "a_max_default": 22000,
    },
    "scandinavia": {
        "admins": {"Norway": "NOR", "Sweden": "SWE"},
        "units": {},
        "skip_old": [],
        "clip": {},
        "rename": {
            ("Norway", "Oslo"): "Christiania", ("Sweden", "Stockholm"): "Stockholm City",
            ("Norway", "Sør-Trøndelag"): "Sor-Trondelag", ("Norway", "Nord-Trøndelag"): "Nord-Trondelag",
            ("Norway", "Møre og Romsdal"): "More og Romsdal", ("Norway", "Troms"): "Troms",
            ("Sweden", "Västra Götaland"): "Vastra Gotaland", ("Sweden", "Skåne"): "Skane",
            ("Sweden", "Södermanland"): "Sodermanland", ("Sweden", "Örebro"): "Orebro",
            ("Sweden", "Östergötland"): "Ostergotland", ("Sweden", "Jämtland"): "Jamtland",
            ("Sweden", "Västerbotten"): "Vasterbotten", ("Sweden", "Västernorrland"): "Vasternorrland",
            ("Sweden", "Västmanland"): "Vastmanland",
        },
        "rename_dup": {},
        "no_merge": ["Christiania", "Stockholm City"],
        "a_min": 6000,
        "a_max": {"NOR": 60000, "SWE": 50000},
        "a_max_default": 22000,
    },
    "russia": {
        "admins": {
            "Russia": "RUS", "Finland": "RUS", "Estonia": "RUS", "Latvia": "RUS", "Lithuania": "RUS",
            "Belarus": "RUS", "Ukraine": "RUS", "Moldova": "RUS", "Poland": None,
        },
        "units": {
            **{("Poland", n): "RUS" for n in ("Lublin", "Masovian", "Łódź", "Świętokrzyskie", "Podlachian")},
            ("Russia", "Kaliningrad"): "GER", ("Lithuania", "Klaipedos"): "GER",
            **{k: None for k in RUSSIA_SKIP},
            **{("Ukraine", n): "AUH" for n in GALICIA},
        },
        "reown": {"Łódź 1": "RUS", "Łódź 2": "RUS"},
        "skip_old": [],
        "clip": {},
        "rename": {
            ("Russia", "Moskva"): "Moscow", ("Russia", "Moskovskaya"): "Moscow Governorate",
            ("Russia", "City of St. Petersburg"): "Saint Petersburg", ("Russia", "Leningrad"): "Petrograd",
            ("Russia", "Sverdlovsk"): "Yekaterinburg", ("Russia", "Kirov"): "Vyatka",
            ("Russia", "Nizhegorod"): "Nizhny Novgorod", ("Russia", "Ul'yanovsk"): "Simbirsk",
            ("Russia", "Volgograd"): "Tsaritsyn", ("Russia", "Arkhangel'sk"): "Arkhangelsk",
            ("Russia", "Udmurt"): "Udmurtia", ("Russia", "Mariy-El"): "Mari El", ("Russia", "Chuvash"): "Chuvashia",
            ("Russia", "Kaliningrad"): "Konigsberg", ("Russia", "Perm'"): "Perm", ("Russia", "Tver'"): "Tver",
            ("Russia", "Yaroslavl'"): "Yaroslavl", ("Russia", "Ryazan'"): "Ryazan", ("Russia", "Astrakhan'"): "Astrakhan",
            ("Russia", "Stavropol'"): "Stavropol", ("Russia", "Adygey"): "Adygea", ("Russia", "Orel"): "Oryol",
            ("Ukraine", "Dnipropetrovs'k"): "Yekaterinoslav", ("Ukraine", "Kiev City"): "Kiev (city)",
            ("Ukraine", "Khmel'nyts'kyy"): "Podolia", ("Ukraine", "Vinnytsya"): "Vinnytsia",
            ("Ukraine", "Luhans'k"): "Luhansk", ("Ukraine", "Donets'k"): "Donetsk",
            ("Belarus", "City of Minsk"): "Minsk (city)", ("Latvia", "Riga"): "Riga",
        },
        "rename_dup": {},
        "no_merge": ["Moscow", "Saint Petersburg", "Sevastopol", "Kiev (city)", "Minsk (city)", "Riga",
                     "Konigsberg", "Uusimaa", "Harju"],
        "a_min": 12000,
        "a_max": {"RUS": 200000},
        "a_max_default": 22000,
    },
}


# ---------------------------------------------------------------- reading the existing map
def read_rows():
    with open(MAP_DIR / "provinces.tsv", encoding="utf-8") as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    for r in rows:
        r.setdefault("admin", "")
    return rows


def load_ids(rows):
    """int16 array of province ids: 0 sea, -1 background land. Pads an old-size bitmap."""
    img = Image.open(MAP_DIR / "provinces.png").convert("RGB")
    arr = np.asarray(img)
    h, w = arr.shape[:2]
    if (w, h) == (OLD_W, OLD_H):
        full = np.zeros((H, W, 3), dtype=np.uint8)
        full[DY:DY + OLD_H, :OLD_W] = arr
        arr, padded = full, True
    elif (w, h) == (W, H):
        padded = False
    else:
        raise SystemExit(f"unexpected bitmap size {w}x{h}")
    key = arr[..., 0].astype(np.int64) | (arr[..., 1].astype(np.int64) << 8) | (arr[..., 2].astype(np.int64) << 16)
    by_key = {int(r["r"]) | (int(r["g"]) << 8) | (int(r["b"]) << 16): int(r["id"]) for r in rows}
    keys = np.array(sorted(by_key))
    vals = np.array([by_key[k] for k in keys], dtype=np.int16)
    idx = np.searchsorted(keys, key)
    idx[idx >= len(keys)] = 0
    ids = np.where(keys[idx] == key, vals[idx], np.int16(-1))
    ids[key == 0] = 0
    del key, arr
    return ids.astype(np.int16), padded


# ---------------------------------------------------------------- reading the boundaries
def read_units(shp_path, spec):
    """Returns (units, bg, old_units). `units` become new provinces; `old_units` are units of
    the original scope that may extend existing provinces."""
    sf = shapefile.Reader(shp_path, encoding="utf-8")
    frame = box(LON0, LAT0, LON1, LAT1)
    units, bg, old_units = [], [], []
    skip = set(spec["skip_old"])
    for sr in sf.iterShapeRecords():
        b = sr.shape.bbox
        if b[2] < LON0 or b[0] > LON1 or b[3] < LAT0 or b[1] > LAT1:
            continue
        rec = sr.record.as_dict()
        geom = shape(sr.shape.__geo_interface__)
        if not geom.is_valid:
            geom = geom.buffer(0)
        geom = geom.intersection(frame)
        if geom.is_empty or geom.geom_type not in ("Polygon", "MultiPolygon"):
            continue
        admin, raw = rec["admin"], rec["name"] or rec["name_en"] or "Unnamed"
        key = (admin, raw)
        if admin in spec["clip"]:
            inside = geom.intersection(spec["clip"][admin])
            rest = geom.difference(spec["clip"][admin])
            if not rest.is_empty:
                bg.append(rest)
            geom = inside
            if geom.is_empty or geom.geom_type not in ("Polygon", "MultiPolygon"):
                continue
        name = bm.RENAME.get(key, spec["rename"].get(key, raw))
        owner = spec["units"].get(key, spec["admins"].get(admin))
        if key in spec["units"] and owner is None:
            bg.append(geom)
            continue
        if key in skip:
            bg.append(geom)
        elif owner is None:
            # not in this slice: original scope (may extend a province) or plain background
            if admin in bm.SCOPE:
                if b[2] <= OLD_LON1 and b[3] <= OLD_LAT1 and b[1] >= OLD_LAT0:
                    continue  # wholly inside the old frame: already a province
                old_owner = bm.OVERRIDES.get(key, bm.SCOPE[admin])
                group = bm.group_of(admin, raw, rec["region"])
                old_units.append({"name": group or name, "admin": admin, "owner": old_owner, "geom": geom})
            else:
                bg.append(geom)
        elif admin in bm.SCOPE:
            old_units.append({"name": name, "admin": admin, "owner": owner, "geom": geom})
        else:
            units.append({"name": name, "admin": admin, "owner": owner, "geom": geom})
    return units, bg, old_units


def paint_mask(geom):
    x0, y0, m = bm.rasterize(geom)
    return x0, y0, m


# ---------------------------------------------------------------- main
def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry = "--dry" in sys.argv
    shp, slice_name = args[0], args[1]
    spec = SLICES[slice_name]
    bm.A_MIN = spec.get("a_min", 3000)
    bm.A_MAX = spec["a_max"]
    bm.A_MAX_DEFAULT = spec["a_max_default"]
    bm.NO_MERGE = set(bm.NO_MERGE) | set(spec["no_merge"])

    rows = read_rows()
    for r in rows:
        if r["name"] in spec.get("reown", {}):
            r["owner"] = spec["reown"][r["name"]]
    next_id = max(int(r["id"]) for r in rows) + 1
    name_owner = {r["name"]: (int(r["id"]), r["owner"]) for r in rows}

    ids, padded = load_ids(rows)
    print(f"canvas {W}x{H}, existing bitmap {'padded' if padded else 'reused'}, {len(rows)} provinces")
    old_rect = np.zeros((H, W), dtype=bool)
    old_rect[DY:DY + OLD_H, :OLD_W] = True
    # background and new provinces may replace background land anywhere and sea outside the old frame
    paintable = (ids == -1) | ((ids == 0) & ~old_rect)

    units, bg, old_units = read_units(shp, spec)
    print(f"{len(units)} new units, {len(old_units)} units of the original scope, {len(bg)} background polygons")

    # --- 1. extend provinces that the old frame cut
    added_px = defaultdict(float)   # id -> equal-area pixels added
    leftover = []
    rows_by_name = defaultdict(list)
    for r in rows:
        base = r["name"].rsplit(" (", 1)[0]
        base = base.rsplit(" ", 1)[0] if base.rsplit(" ", 1)[-1].isdigit() else base
        rows_by_name[base].append(r)
    lat_w = np.cos(np.radians(LAT1 - (np.arange(H) + 0.5) / KY)) / COS47
    for u in old_units:
        cands = [r for r in rows_by_name.get(u["name"], []) if r["owner"] == u["owner"]]
        x0, y0, m = paint_mask(u["geom"])
        sub = paintable[y0:y0 + m.shape[0], x0:x0 + m.shape[1]]
        new = m & sub
        if not new.any():
            continue
        if not cands:
            leftover.append(u)
            continue
        cand_ids = {int(r["id"]) for r in cands}
        # nearest candidate pixel within a margin around the unit
        pad = 300
        ya, yb = max(y0 - pad, 0), min(y0 + m.shape[0] + pad, H)
        xa, xb = max(x0 - pad, 0), min(x0 + m.shape[1] + pad, W)
        win = ids[ya:yb, xa:xb]
        cmask = np.isin(win, list(cand_ids))
        if not cmask.any():
            leftover.append(u)
            continue
        dist, (iy, ix) = ndimage.distance_transform_edt(~cmask, return_indices=True)
        ny, nx = np.nonzero(new)
        wy, wx = ny + y0 - ya, nx + x0 - xa
        near = dist[wy, wx] <= 200
        for pid in set(win[iy[wy[near], wx[near]], ix[wy[near], wx[near]]].tolist()):
            sel = near & (win[iy[wy, wx], ix[wy, wx]] == pid)
            gy, gx = ny[sel] + y0, nx[sel] + x0
            ids[gy, gx] = pid
            paintable[gy, gx] = False
            added_px[pid] += float(lat_w[gy].sum())
        if (~near).any():
            leftover.append({**u, "geom": u["geom"]})
    print(f"extended {len(added_px)} existing provinces, {len(leftover)} old units become new provinces")
    units.extend(leftover)

    # --- 2. background land, then new units
    labels = np.zeros((H, W), dtype=np.int32)
    paintable_now = paintable & (ids <= 0)
    for g in bg:
        x0, y0, m = paint_mask(g)
        sub = labels[y0:y0 + m.shape[0], x0:x0 + m.shape[1]]
        sub[m & (sub == 0) & paintable_now[y0:y0 + m.shape[0], x0:x0 + m.shape[1]]] = bm.BG
    meta = {}
    for i, u in enumerate(units):
        lab = i + 2
        meta[lab] = {"name": u["name"], "owner": u["owner"], "admin": u["admin"]}
        x0, y0, m = paint_mask(u["geom"])
        sub = labels[y0:y0 + m.shape[0], x0:x0 + m.shape[1]]
        sub[m & (sub <= bm.BG) & paintable_now[y0:y0 + m.shape[0], x0:x0 + m.shape[1]]] = lab
    labels[~paintable_now] = 0
    bm.clean_specks(labels)
    meta = bm.merge_small(labels, meta)
    meta = bm.split_large(labels, meta)
    bm.clean_specks(labels)

    # --- 2b. slivers that only touch existing provinces (city enclaves, border scraps) join the
    # neighbour with the longest shared border, or vanish into the background if tiny
    owner_of_id = {int(r["id"]): r["owner"] for r in rows}
    area_px = dict(zip(*np.unique(labels, return_counts=True)))
    for lab in [l for l in list(meta) if l in area_px and area_px[l] < bm.A_MIN and meta[l]["name"] not in bm.NO_MERGE]:
        sl = ndimage.find_objects((labels == lab).astype(np.uint8))[0]
        if sl is None:
            continue
        ya, yb = max(sl[0].start - 2, 0), min(sl[0].stop + 2, H)
        xa, xb = max(sl[1].start - 2, 0), min(sl[1].stop + 2, W)
        mask = labels[ya:yb, xa:xb] == lab
        ring = ndimage.binary_dilation(mask) & ~mask
        votes = defaultdict(int)
        for v in ids[ya:yb, xa:xb][ring]:
            if v > 0 and owner_of_id.get(int(v)) == meta[lab]["owner"]:
                votes[int(v)] += 1
        if votes:
            tgt = max(votes, key=votes.get)
            ids[ya:yb, xa:xb][mask] = tgt
            added_px[tgt] += float(lat_w[ya:yb][mask.any(axis=1)].sum() * 0 + mask.sum())
            labels[ya:yb, xa:xb][mask] = 0
            del meta[lab]
        elif area_px[lab] < 600:
            labels[ya:yb, xa:xb][mask] = bm.BG
            del meta[lab]

    # --- 3. ids and colours for the new provinces
    present = sorted((l for l in np.unique(labels) if l in meta), key=lambda l: (meta[l]["owner"], meta[l]["name"]))
    seen = defaultdict(int)
    for r in rows:
        seen[r["name"]] += 1
    lut = np.zeros(labels.max() + 1, dtype=np.int32)
    new_rows = []
    for lab in present:
        name = meta[lab]["name"]
        seen[name] += 1
        if seen[name] > 1:
            name = f"{name} ({seen[name]})"
            name = spec.get("rename_dup", {}).get(name, name)
        pid = next_id
        next_id += 1
        lut[lab] = pid
        new_rows.append({"id": pid, "name": name, "owner": meta[lab]["owner"], "admin": meta[lab]["admin"], "lab": lab})
    if next_id > 4000:
        raise SystemExit("too many provinces for the colour scheme")
    new_ids = lut[labels]
    ids = ids.astype(np.int32)
    land_new = (labels >= 2) & (new_ids > 0)
    ids[land_new] = new_ids[land_new]
    ids[(labels == bm.BG) & (ids <= 0) & paintable_now] = -1
    del new_ids, lut

    # --- 4. statistics for new provinces and extended ones
    top = int(ids.max()) + 1
    area = np.zeros(top)
    sx = np.zeros(top)
    sy = np.zeros(top)
    xs = np.arange(W)
    for y in range(H):
        row = ids[y]
        pos = row > 0
        if not pos.any():
            continue
        r = row[pos]
        area += np.bincount(r, minlength=top) * lat_w[y]
        sx += np.bincount(r, weights=xs[pos], minlength=top)
        sy += np.bincount(r, weights=np.full(r.size, y + 0.5), minlength=top)
    px = np.bincount(ids[ids > 0].ravel(), minlength=top).astype(float)
    print(f"{len(new_rows)} new provinces; by owner:",
          dict(sorted(defaultdict(int, {t: sum(1 for n in new_rows if n['owner'] == t) for t in {n['owner'] for n in new_rows}}).items())))
    if dry:
        return

    # --- 5. write everything
    out_rows = []
    for r in rows:
        pid = int(r["id"])
        cy = int(r["cy"]) + (DY if padded else 0)
        if pid in added_px:
            area_new = int(r["area"]) + int(round(added_px[pid]))
            cx, cy2 = int(sx[pid] / px[pid]), int(sy[pid] / px[pid])
            out_rows.append([pid, r["r"], r["g"], r["b"], r["name"], r["owner"], area_new, cx, cy2, r["admin"]])
        else:
            out_rows.append([pid, r["r"], r["g"], r["b"], r["name"], r["owner"], r["area"], r["cx"], cy, r["admin"]])
    for n in new_rows:
        pid = n["id"]
        rgb = (pid & 0xFF, (pid >> 8) & 0xFF, 1 + ((pid * 97) & 0x7F))
        out_rows.append([pid, *rgb, n["name"], n["owner"], int(round(area[pid])),
                         int(sx[pid] / px[pid]), int(sy[pid] / px[pid]), n["admin"]])
    rgb_lut = np.zeros((top + 1, 3), dtype=np.uint8)
    for r in out_rows:
        rgb_lut[int(r[0])] = (int(r[1]), int(r[2]), int(r[3]))
    img = np.zeros((H, W, 3), dtype=np.uint8)
    for y in range(0, H, 512):
        blk = ids[y:y + 512]
        out = rgb_lut[np.clip(blk, 0, top)]
        out[blk == -1] = bm.BG_RGB
        out[blk == 0] = bm.SEA_RGB
        img[y:y + 512] = out
    Image.fromarray(img, "RGB").save(MAP_DIR / "provinces.png", optimize=False, compress_level=6)
    with open(MAP_DIR / "provinces.tsv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, delimiter="\t", lineterminator="\n")
        w.writerow(["id", "r", "g", "b", "name", "owner", "area", "cx", "cy", "admin"])
        w.writerows(out_rows)
    print(f"wrote {len(out_rows)} provinces, map {W}x{H}")


if __name__ == "__main__":
    main()
