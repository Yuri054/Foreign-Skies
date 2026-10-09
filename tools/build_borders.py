"""Trace the borders between provinces (run after editing the bitmap).

Usage: python tools/build_borders.py [map_dir]

Writes borders.tsv (id_a, id_b, points; a < b): one row per stretch of border between two
provinces, as a simplified polyline in bitmap pixels ("x,y;x,y;..."). The game draws fronts along
these lines. Only borders between two provinces are traced, not the coast.
"""
import csv
import sys
from pathlib import Path

import numpy as np
from PIL import Image

TOLERANCE = 2.0  # pixels the simplified line may stray from the traced one

root = Path(__file__).resolve().parent.parent
map_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "data" / "map"

img = np.array(Image.open(map_dir / "provinces.png").convert("RGB"))
key = (img[..., 0].astype(np.int32) | (img[..., 1].astype(np.int32) << 8) | (img[..., 2].astype(np.int32) << 16))
del img
lut = np.zeros(1 << 24, dtype=np.int16)
with open(map_dir / "provinces.tsv", encoding="utf-8") as f:
    for r in csv.DictReader(f, delimiter="\t"):
        lut[int(r["r"]) | (int(r["g"]) << 8) | (int(r["b"]) << 16)] = int(r["id"])
ids = lut[key]
del key

segments = []  # (pair, x1, y1, x2, y2)
# A change of province between two pixels side by side is a vertical edge between them, and
# one between two pixels above each other is a horizontal edge.
a, b = ids[:, :-1], ids[:, 1:]
m = (a != b) & (a > 0) & (b > 0)
ys, xs = np.nonzero(m)
lo, hi = np.minimum(a[m], b[m]).astype(np.int64), np.maximum(a[m], b[m]).astype(np.int64)
segments.append(np.stack([lo * 1024 + hi, xs + 1, ys, xs + 1, ys + 1], axis=1))
a, b = ids[:-1, :], ids[1:, :]
m = (a != b) & (a > 0) & (b > 0)
ys, xs = np.nonzero(m)
lo, hi = np.minimum(a[m], b[m]).astype(np.int64), np.maximum(a[m], b[m]).astype(np.int64)
segments.append(np.stack([lo * 1024 + hi, xs, ys + 1, xs + 1, ys + 1], axis=1))
seg = np.concatenate(segments)
del segments, ids
seg = seg[np.argsort(seg[:, 0], kind="stable")]
print(len(seg), "border edges")


def simplify(points, tol):
    """Douglas-Peucker on a list of (x, y)."""
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        i, j = stack.pop()
        (x1, y1), (x2, y2) = points[i], points[j]
        dx, dy = x2 - x1, y2 - y1
        norm = (dx * dx + dy * dy) ** 0.5
        best, at = -1.0, -1
        for k in range(i + 1, j):
            x, y = points[k]
            d = abs(dy * (x - x1) - dx * (y - y1)) / norm if norm > 0 else ((x - x1) ** 2 + (y - y1) ** 2) ** 0.5
            if d > best:
                best, at = d, k
        if best > tol:
            keep[at] = True
            stack.append((i, at))
            stack.append((at, j))
    return [p for p, k in zip(points, keep) if k]


def chains(rows):
    """Join the unit edges of one border into polylines."""
    at = {}
    for i, (_, x1, y1, x2, y2) in enumerate(rows):
        at.setdefault((x1, y1), []).append(i)
        at.setdefault((x2, y2), []).append(i)
    used = [False] * len(rows)
    out = []
    for start in range(len(rows)):
        if used[start]:
            continue
        used[start] = True
        _, x1, y1, x2, y2 = rows[start]
        line = [(x1, y1), (x2, y2)]
        for end in (1, 0):
            while True:
                tip = line[-1] if end == 1 else line[0]
                nxt = None
                for j in at[tip]:
                    if not used[j]:
                        nxt = j
                        break
                if nxt is None:
                    break
                used[nxt] = True
                _, a1, b1, a2, b2 = rows[nxt]
                other = (a2, b2) if (a1, b1) == tip else (a1, b1)
                if end == 1:
                    line.append(other)
                else:
                    line.insert(0, other)
        out.append(line)
    return out


pairs, starts = np.unique(seg[:, 0], return_index=True)
starts = list(starts) + [len(seg)]
written = 0
points_total = 0
with open(map_dir / "borders.tsv", "w", encoding="utf-8", newline="") as f:
    w = csv.writer(f, delimiter="\t", lineterminator="\n")
    w.writerow(["id_a", "id_b", "points"])
    for n, pair in enumerate(pairs):
        rows = [tuple(int(v) for v in r) for r in seg[starts[n]:starts[n + 1]]]
        for line in chains(rows):
            line = simplify(line, TOLERANCE)
            if len(line) < 2:
                continue
            w.writerow([int(pair) // 1024, int(pair) % 1024, ";".join("%d,%d" % p for p in line)])
            written += 1
            points_total += len(line)
print(written, "stretches of border,", points_total, "points,", len(pairs), "province pairs")
