"""Paints the land texture of the map from real elevation and a few rules of climate.

Usage: python tools/build_landtex.py [cache_dir]

Fetches Terrarium elevation tiles (zoom 7; into cache_dir, default /tmp/terrarium; not kept in the
repository), resamples them into the map's frame at half the bitmap's size and paints each pixel as
farmland, forest, steppe, dry scrub, desert, boreal forest, bare rock or snow, from its height, slope,
latitude and longitude, with noise to break up the bands, and a soft hill shading. Writes
data/map/land.jpg. The map shader blends it with the political colours, more the closer you zoom.
"""
import math
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
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
SCALE = 2
ZOOM = 7
URL = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
KM_PER_PX = 0.6928
root = Path(__file__).resolve().parent.parent
rng = np.random.default_rng(1914)


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


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def noise(shape, sigma):
    """Soft random field with unit spread."""
    n = ndimage.gaussian_filter(rng.standard_normal(shape).astype(np.float32), sigma, mode="reflect")
    return n / (n.std() + 1e-6)


def mix(a, b, t):
    return a + (b - a) * t[..., None]


def main():
    cache = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/terrarium")
    cache.mkdir(parents=True, exist_ok=True)
    x0, x1 = int(tile_x(LON0)), int(tile_x(LON1))
    y0, y1 = int(tile_y(LAT1)), int(tile_y(LAT0))
    jobs = [(tx, ty) for ty in range(y0, y1 + 1) for tx in range(x0, x1 + 1)]
    print(f"{len(jobs)} tiles")
    with ThreadPoolExecutor(8) as pool:
        tiles = list(pool.map(lambda j: fetch(cache, *j), jobs))
    mosaic = np.zeros(((y1 - y0 + 1) * 256, (x1 - x0 + 1) * 256), dtype=np.float32)
    for (tx, ty), im in zip(jobs, tiles):
        a = np.asarray(im).astype(np.float32)
        mosaic[(ty - y0) * 256:(ty - y0 + 1) * 256, (tx - x0) * 256:(tx - x0 + 1) * 256] = a[..., 0] * 256.0 + a[..., 1] + a[..., 2] / 256.0 - 32768.0
    del tiles
    ow, oh = W // SCALE, H // SCALE
    lon1d = LON0 + (np.arange(ow) + 0.5) * SCALE / KX
    lat1d = LAT1 - (np.arange(oh) + 0.5) * SCALE / KY
    cols = (np.array([tile_x(v) for v in lon1d]) - x0) * 256.0
    rows = (np.array([tile_y(v) for v in lat1d]) - y0) * 256.0
    yy, xx = np.meshgrid(rows, cols, indexing="ij")
    h = ndimage.map_coordinates(mosaic, [yy, xx], order=1, mode="nearest").astype(np.float32)
    del yy, xx, mosaic
    h = np.maximum(h, 0.0)
    lon = np.broadcast_to(lon1d[None, :], (oh, ow)).astype(np.float32)
    lat = np.broadcast_to(lat1d[:, None], (oh, ow)).astype(np.float32)
    print("terrain fields")
    hs = ndimage.gaussian_filter(h, 1.2)
    gy, gx = np.gradient(hs, SCALE * KM_PER_PX * 1000.0)
    slope = np.hypot(gx, gy)                      # rise over run
    n_fine, n_mid, n_wide = noise(h.shape, 2.0), noise(h.shape, 9.0), noise(h.shape, 45.0)

    # --- climate fields, 0 to 1
    boreal = smooth(lat + 1.2 * n_wide, 57.0, 63.0)
    tundra = smooth(lat + 0.8 * n_wide, 65.5, 67.5) * 0.6 + smooth(h, 900.0, 1400.0) * smooth(lat, 60.0, 66.0)
    desert = smooth(37.2 - lat + 0.6 * n_wide, 0.0, 2.2) * smooth(36.0, 0.0, 1.0) * (lon > -12)
    med_dry = smooth(44.5 - lat + 0.8 * n_wide, 0.0, 6.0) * (1.0 - smooth(h, 900.0, 1800.0))
    meseta = (smooth(lon, -8.5, -6.0) * (1.0 - smooth(lon, 1.0, 3.5)) * smooth(lat, 37.0, 38.5) * (1.0 - smooth(lat, 41.8, 43.0)) * smooth(h, 350.0, 750.0))
    anatolia = smooth(lon, 28.0, 32.0) * (1.0 - smooth(lat, 40.8, 42.0)) * smooth(h, 500.0, 1000.0)
    steppe = smooth(lon + 1.5 * n_wide, 27.0, 35.0) * (1.0 - smooth(lat + 1.0 * n_wide, 49.5, 54.0)) * (1.0 - smooth(h, 300.0, 700.0))
    dry = np.clip(med_dry * 0.7 + meseta * 0.8 + anatolia * 0.9, 0.0, 1.0)
    steppe = np.clip(steppe + 0.4 * anatolia, 0.0, 1.0)

    # --- cover
    hilly = smooth(slope, 0.025, 0.12) * (1.0 - smooth(h, 1700.0, 2300.0))
    forest_bias = -0.15 + 0.4 * boreal + 0.75 * hilly + 0.25 * smooth(h, 150.0, 600.0) * (1.0 - smooth(h, 1500.0, 2000.0)) - 0.7 * dry - 0.8 * steppe - 0.9 * desert
    forest = smooth(0.35 * n_wide + 0.3 * n_mid + 0.12 * n_fine + forest_bias, 0.15, 0.7)
    farm = smooth(-slope, -0.03, -0.006) * (1.0 - boreal) * (1.0 - dry) * smooth(0.55 * n_wide + 0.15 * n_mid + 0.45, 0.3, 0.9) * (1.0 - smooth(h, 500.0, 900.0))
    rock = smooth(slope, 0.06, 0.24) * (1.0 - forest * 0.55) + smooth(h + 150.0 * n_wide, 1500.0, 2400.0) * 0.8
    snowline = 3000.0 - 55.0 * (lat - 36.0) - 120.0 * np.clip(n_wide, -1, 1)
    snow = smooth(h, snowline - 150.0, snowline + 350.0)

    # --- palette (muted, painted)
    field = np.array([0.55, 0.62, 0.38], np.float32)
    farmland = np.array([0.70, 0.69, 0.46], np.float32)
    wood = np.array([0.34, 0.45, 0.30], np.float32)
    taiga = np.array([0.26, 0.38, 0.29], np.float32)
    steppe_c = np.array([0.72, 0.68, 0.45], np.float32)
    scrub = np.array([0.66, 0.60, 0.42], np.float32)
    sand = np.array([0.80, 0.72, 0.52], np.float32)
    stone = np.array([0.57, 0.53, 0.46], np.float32)
    high = np.array([0.66, 0.64, 0.62], np.float32)
    tundra_c = np.array([0.52, 0.55, 0.45], np.float32)
    white = np.array([0.95, 0.96, 0.98], np.float32)
    col = np.broadcast_to(field, h.shape + (3,)).copy()
    col = col * (1.0 + 0.05 * n_wide[..., None]) * (1.0 + 0.025 * n_mid[..., None])
    col = mix(col, farmland + 0.03 * n_fine[..., None], farm)
    col = mix(col, steppe_c, steppe)
    col = mix(col, scrub, dry)
    col = mix(col, sand, desert)
    col = mix(col, wood + 0.025 * n_fine[..., None], forest * (1.0 - steppe * 0.8))
    col = mix(col, taiga + 0.02 * n_fine[..., None], boreal * forest)
    col = mix(col, tundra_c, np.clip(tundra, 0, 1))
    col = mix(col, stone, np.clip(rock, 0, 1) * 0.85)
    col = mix(col, high, smooth(h, 1900.0, 2700.0) * 0.7)
    col = mix(col, white, np.clip(snow, 0, 1))

    # --- hill shading from the north west, and a little grain
    az, alt = math.radians(315.0), math.radians(42.0)
    nx, ny = -gx * 12.0, -gy * 12.0
    norm = np.sqrt(nx * nx + ny * ny + 1.0)
    # image rows run south, so the gradient in y is flipped for the light vector
    lx, ly, lz = math.cos(alt) * math.sin(az), -math.cos(alt) * math.cos(az) * -1.0, math.sin(alt)
    shade = (nx * lx + ny * ly + lz) / norm
    flat = lz
    curve = ndimage.gaussian_filter(h, 3.0) - ndimage.gaussian_filter(h, 8.0)     # valleys are negative
    lit = np.clip(1.0 + (shade - flat) * 2.1 + np.clip(curve / 600.0, -0.25, 0.2), 0.5, 1.55)
    col = col * lit[..., None] * (1.0 + 0.035 * n_fine[..., None])
    out = (np.clip(col, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    Image.fromarray(out, "RGB").save(root / "data/map/land.jpg", quality=90, optimize=True)
    print(f"wrote data/map/land.jpg {ow}x{oh}")


if __name__ == "__main__":
    main()
