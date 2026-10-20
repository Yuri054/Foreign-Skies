"""Builds the terrain relief heightmap of the 3D map from open elevation tiles.

Usage: python tools/build_relief.py [cache_dir]

Fetches Mapzen/AWS "Terrarium" elevation tiles (zoom 6, covering the map frame; elevation in metres
is R * 256 + G + B / 256 - 32768) into cache_dir (default /tmp/terrarium; not kept in the repository),
stitches them, and resamples them into the map's own frame (equirectangular, see extend_map.py) at
a quarter of the bitmap's size. Writes data/map/relief.png: 8-bit grey, 0 for the sea and for sea
level, rising as the square root of the height to 255 at TOP_M metres (so lowlands keep their detail; higher ground is clipped): metres = TOP_M * (grey / 255) ** 2. The 3D map reads it.
"""
import io
import math
import sys
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

LON0, LON1 = -11.0, 61.0
LAT0, LAT1 = 34.8, 67.0
PX_PER_DEG = 160.0
KX = PX_PER_DEG * math.cos(math.radians(47.0))
KY = PX_PER_DEG
W = int(round((LON1 - LON0) * KX))
H = int(round((LAT1 - LAT0) * KY))
SCALE = 4
ZOOM = 6
TOP_M = 3000.0
URL = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"

root = Path(__file__).resolve().parent.parent


def tile_x(lon):
    return (lon + 180.0) / 360.0 * (1 << ZOOM)


def tile_y(lat):
    r = math.radians(lat)
    return (1.0 - math.log(math.tan(r) + 1.0 / math.cos(r)) / math.pi) / 2.0 * (1 << ZOOM)


def fetch(cache, x, y):
    path = cache / f"{ZOOM}_{x}_{y}.png"
    if not path.exists():
        with urllib.request.urlopen(URL.format(z=ZOOM, x=x, y=y), timeout=60) as r:
            path.write_bytes(r.read())
    return Image.open(path).convert("RGB")


def main():
    cache = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/terrarium")
    cache.mkdir(parents=True, exist_ok=True)
    x0, x1 = int(tile_x(LON0)), int(tile_x(LON1))
    y0, y1 = int(tile_y(LAT1)), int(tile_y(LAT0))
    print(f"tiles x {x0}..{x1}, y {y0}..{y1}")
    mosaic = np.zeros(((y1 - y0 + 1) * 256, (x1 - x0 + 1) * 256), dtype=np.float32)
    for ty in range(y0, y1 + 1):
        for tx in range(x0, x1 + 1):
            a = np.asarray(fetch(cache, tx, ty)).astype(np.float32)
            elev = a[..., 0] * 256.0 + a[..., 1] + a[..., 2] / 256.0 - 32768.0
            mosaic[(ty - y0) * 256:(ty - y0 + 1) * 256, (tx - x0) * 256:(tx - x0 + 1) * 256] = elev
    ow, oh = W // SCALE, H // SCALE
    lon = LON0 + (np.arange(ow) + 0.5) * SCALE / KX
    lat = LAT1 - (np.arange(oh) + 0.5) * SCALE / KY
    cols = (np.array([tile_x(v) for v in lon]) - x0) * 256.0
    rows = (np.array([tile_y(v) for v in lat]) - y0) * 256.0
    yy, xx = np.meshgrid(rows, cols, indexing="ij")
    out = ndimage.map_coordinates(mosaic, [yy, xx], order=1, mode="nearest")
    grey = np.sqrt(np.clip(out / TOP_M, 0.0, 1.0)) * 255.0
    Image.fromarray(grey.round().astype(np.uint8), "L").save(root / "data/map/relief.png", optimize=True)
    print(f"wrote data/map/relief.png {ow}x{oh}, highest {out.max():.0f} m")


if __name__ == "__main__":
    main()
