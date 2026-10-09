"""Bootstrap the province bitmap from Natural Earth admin-1 boundaries.

Usage:
    python tools/build_map.py <path-to-ne_10m_admin_1_states_provinces (no extension)> [out_dir]

Outputs (default out_dir = data/map):
    provinces.png       flat-color province bitmap (hand-editable; the source of truth afterwards)
    provinces.tsv       id TAB r TAB g TAB b TAB name TAB owner TAB area TAB cx TAB cy
    adjacencies.tsv     id_a TAB id_b TAB border_px
    preview_political.png   quick look at the result (not used by the game)

This is a first pass: 1914 owners are applied through the tables below, but
borders follow modern admin-1 units. Refine by editing provinces.png and
re-running tools/build_adjacencies.py.
"""
import csv
import math
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np
import shapefile
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.cluster.vq import kmeans2
from shapely.geometry import box, shape
from shapely.ops import unary_union

# ---------------------------------------------------------------- projection
LON0, LON1 = -11.0, 19.5
LAT0, LAT1 = 35.8, 59.0
PX_PER_DEG = 160.0
KX = PX_PER_DEG * math.cos(math.radians(47.0))  # px per degree of longitude
KY = PX_PER_DEG                                 # px per degree of latitude
W = int(round((LON1 - LON0) * KX))
H = int(round((LAT1 - LAT0) * KY))

# ---------------------------------------------------------------- 1914 data
# default owner for each Natural Earth country (admin) that becomes provinces
SCOPE = {
    "United Kingdom": "GBR", "Ireland": "GBR",
    "France": "FRA", "Germany": "GER", "Poland": "GER",
    "Belgium": "BEL", "Netherlands": "NED", "Luxembourg": "LUX",
    "Switzerland": "SUI", "Italy": "ITA", "Spain": "ESP", "Portugal": "POR",
    "Denmark": "DEN",
    "Austria": "AUH", "Czech Republic": "AUH", "Slovakia": "AUH", "Hungary": "AUH",
    "Slovenia": "AUH", "Croatia": "AUH", "Bosnia and Herzegovina": "AUH",
}
# (admin, unit name) -> owner in 1914
OVERRIDES = {
    ("France", "Bas-Rhin"): "GER", ("France", "Haut-Rhin"): "GER", ("France", "Moselle"): "GER",
    ("Italy", "Bozen"): "AUH", ("Italy", "Trento"): "AUH",
    ("Italy", "Gorizia"): "AUH", ("Italy", "Trieste"): "AUH",
}
# tiny units that together form one named province (e.g. the Paris urban area)
PARIS = {"Paris", "Hauts-de-Seine", "Seine-Saint-Denis", "Val-de-Marne"}


def group_of(admin, name, region):
    if admin == "France" and name in PARIS:
        return "Paris"
    if admin == "United Kingdom" and region == "Greater London":
        return "London"
    if admin == "Ireland" and region == "Dublin":
        return "Dublin"
    return None


RENAME = {("Belgium", "Luxembourg"): "Belgian Luxembourg"}

# capitals and major cities stay their own province even when smaller than A_MIN
NO_MERGE = {
    "Paris", "London", "Dublin", "Berlin", "Hamburg", "Bremen", "Brussels", "Wien", "Budapest",
    "Prague", "Belfast", "Edinburgh", "Cardiff", "Glasgow", "Liverpool", "Manchester", "Birmingham",
    "Genève", "Basel-Stadt", "Lisboa", "Napoli", "Milano", "Luxembourg",
}

# provinces are merged below A_MIN px and split above A_MAX px (1 px ~ 0.48 km2)
A_MIN = 3000
A_MAX = {"AUH": 90000}
A_MAX_DEFAULT = 22000
SPECK = 40  # drop disconnected fragments smaller than this

BG = 1            # label for out-of-scope land
SEA_RGB = (0, 0, 0)
BG_RGB = (128, 128, 128)


def project(coords):
    a = np.asarray(coords, dtype=np.float64)
    return np.column_stack(((a[:, 0] - LON0) * KX, (LAT1 - a[:, 1]) * KY))


def rasterize(geom):
    """Return (x0, y0, bool mask) for a shapely geometry in pixel space."""
    polys = [geom] if geom.geom_type == "Polygon" else [g for g in geom.geoms if g.geom_type == "Polygon"]
    projected = []
    for p in polys:
        projected.append((project(p.exterior.coords), [project(r.coords) for r in p.interiors]))
    allpts = np.vstack([e for e, _ in projected])
    x0 = max(int(math.floor(allpts[:, 0].min())) - 1, 0)
    y0 = max(int(math.floor(allpts[:, 1].min())) - 1, 0)
    x1 = min(int(math.ceil(allpts[:, 0].max())) + 2, W)
    y1 = min(int(math.ceil(allpts[:, 1].max())) + 2, H)
    img = Image.new("1", (x1 - x0, y1 - y0), 0)
    d = ImageDraw.Draw(img)
    for ext, holes in projected:
        d.polygon([(x - x0, y - y0) for x, y in ext], fill=1)
        for h in holes:
            d.polygon([(x - x0, y - y0) for x, y in h], fill=0)
    return x0, y0, np.array(img, dtype=bool)


def load_units(shp_path):
    sf = shapefile.Reader(shp_path, encoding="utf-8")
    frame = box(LON0, LAT0, LON1, LAT1)
    bg, units = [], []
    grouped = {}
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
        admin, name = rec["admin"], rec["name"] or rec["name_en"] or "Unnamed"
        name = RENAME.get((admin, name), name)
        if admin in SCOPE:
            owner = OVERRIDES.get((admin, name), SCOPE[admin])
            unit = {"name": name, "admin": admin, "owner": owner, "geom": geom}
            group = group_of(admin, name, rec["region"])
            if group:
                grouped.setdefault(group, []).append(unit)
            else:
                units.append(unit)
        else:
            bg.append(geom)
    for name, members in grouped.items():
        units.append({**members[0], "name": name, "geom": unary_union([m["geom"] for m in members])})
    return bg, units


def paint(labels, bg, units):
    for g in bg:
        x0, y0, m = rasterize(g)
        sub = labels[y0:y0 + m.shape[0], x0:x0 + m.shape[1]]
        sub[m & (sub == 0)] = BG
    meta = {}
    for i, u in enumerate(units):
        lab = i + 2
        meta[lab] = {"name": u["name"], "owner": u["owner"], "admin": u["admin"]}
        x0, y0, m = rasterize(u["geom"])
        sub = labels[y0:y0 + m.shape[0], x0:x0 + m.shape[1]]
        sub[m & (sub <= BG)] = lab
    return meta


def clean_specks(labels):
    """Remove tiny disconnected fragments (replaced by the surrounding label)."""
    for lab, sl in enumerate(ndimage.find_objects(labels), start=1):
        if sl is None or lab == BG:
            continue
        sub = labels[sl]
        mask = sub == lab
        comp, n = ndimage.label(mask)
        if n <= 1:
            continue
        sizes = ndimage.sum(mask, comp, range(1, n + 1))
        for c, s in enumerate(sizes, start=1):
            if s >= SPECK:
                continue
            frag = comp == c
            ring = ndimage.binary_dilation(frag) & ~frag
            neigh = sub[ring]
            neigh = neigh[neigh != lab]
            sub[frag] = np.bincount(neigh).argmax() if neigh.size else 0


def border_counts(labels):
    counts = defaultdict(lambda: defaultdict(int))
    for a, b in ((labels[:, :-1], labels[:, 1:]), (labels[:-1, :], labels[1:, :])):
        m = (a != b) & (a > BG) & (b > BG)
        key = a[m].astype(np.int64) * 100000 + b[m]
        u, c = np.unique(key, return_counts=True)
        for k, n in zip(u, c):
            x, y = divmod(int(k), 100000)
            counts[x][y] += int(n)
            counts[y][x] += int(n)
    return counts


def merge_small(labels, meta):
    areas = dict(zip(*np.unique(labels, return_counts=True)))
    counts = border_counts(labels)
    remap = {}
    merged = True
    while merged:
        merged = False
        small = (l for l in meta if l in areas and areas[l] < A_MIN and meta[l]["name"] not in NO_MERGE)
        for lab in sorted(small, key=lambda l: areas[l]):
            cands = {n: c for n, c in counts[lab].items() if meta[n]["owner"] == meta[lab]["owner"]}
            if not cands:
                continue
            # prefer neighbours from the same admin (country), then longest border
            tgt = max(cands, key=lambda n: (meta[n]["admin"] == meta[lab]["admin"], cands[n]))
            remap[lab] = tgt
            areas[tgt] += areas.pop(lab)
            for n, c in counts.pop(lab).items():
                counts[n].pop(lab, None)
                if n != tgt:
                    counts[tgt][n] += c
                    counts[n][tgt] += c
            merged = True
            break  # recompute order after every merge
    lut = np.arange(labels.max() + 1)
    for src in remap:
        t = remap[src]
        while t in remap:
            t = remap[t]
        lut[src] = t
    labels[:] = lut[labels]
    return {l: m for l, m in meta.items() if l not in remap}


def split_large(labels, meta):
    next_lab = labels.max() + 1
    rng = np.random.default_rng(1914)
    slices = ndimage.find_objects(labels)  # bounding boxes stay valid: pieces never leave their parent
    for lab in list(meta):
        if lab > len(slices) or slices[lab - 1] is None:
            continue
        sub = labels[slices[lab - 1]]
        ys, xs = np.nonzero(sub == lab)
        limit = A_MAX.get(meta[lab]["owner"], A_MAX_DEFAULT)
        k = math.ceil(len(xs) / limit)
        if k <= 1:
            continue
        pts = np.column_stack((xs, ys)).astype(np.float64)
        seeds = pts[rng.choice(len(pts), k, replace=False)]
        centers, assign = kmeans2(pts, seeds, minit="matrix", iter=15, seed=rng)
        order = np.argsort(centers[:, 1] * 10000 + centers[:, 0])  # north to south, then west to east
        base = meta[lab]["name"]
        for rank, idx in enumerate(order):
            new = lab if rank == 0 else next_lab
            if rank:
                meta[new] = dict(meta[lab])
                next_lab += 1
            meta[new]["name"] = f"{base} {rank + 1}"
            sel = assign == idx
            sub[ys[sel], xs[sel]] = new
    return meta


def finalize(labels, meta, out):
    """Assign dense ids, unique colors, and write all outputs."""
    present = [l for l in np.unique(labels) if l in meta]
    present.sort(key=lambda l: (meta[l]["owner"], meta[l]["name"]))
    seen = defaultdict(int)
    provinces = []
    for new_id, lab in enumerate(present, start=1):
        name = meta[lab]["name"]
        seen[name] += 1
        if seen[name] > 1:
            name = f"{name} ({seen[name]})"
        provinces.append((new_id, lab, name, meta[lab]["owner"]))

    lut_rgb = np.zeros((labels.max() + 1, 3), dtype=np.uint8)
    lut_rgb[BG] = BG_RGB
    rows = []
    for pid, lab, name, owner in provinces:
        rgb = (pid & 0xFF, (pid >> 8) & 0xFF, 1 + ((pid * 97) & 0x7F))
        lut_rgb[lab] = rgb
        ys, xs = np.nonzero(labels == lab)
        rows.append((pid, *rgb, name, owner, len(xs), int(xs.mean()), int(ys.mean())))
    rgb_img = lut_rgb[labels]
    rgb_img[labels == 0] = SEA_RGB
    Image.fromarray(rgb_img, "RGB").save(out / "provinces.png", optimize=True)

    with open(out / "provinces.tsv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, delimiter="	")
        w.writerow(["id", "r", "g", "b", "name", "owner", "area", "cx", "cy"])
        w.writerows(rows)
    print(f"{len(rows)} provinces, map {W}x{H}")
    return rows


def main():
    shp = sys.argv[1]
    out = Path(sys.argv[2] if len(sys.argv) > 2 else Path(__file__).resolve().parent.parent / "data" / "map")
    out.mkdir(parents=True, exist_ok=True)

    bg, units = load_units(shp)
    print(f"{len(units)} admin-1 units in scope, {len(bg)} background polygons")
    labels = np.zeros((H, W), dtype=np.int32)
    meta = paint(labels, bg, units)
    clean_specks(labels)
    meta = merge_small(labels, meta)
    meta = split_large(labels, meta)
    clean_specks(labels)
    rows = finalize(labels, meta, out)

    by_owner = defaultdict(int)
    for r in rows:
        by_owner[r[5]] += 1
    print(dict(sorted(by_owner.items())))


if __name__ == "__main__":
    main()
