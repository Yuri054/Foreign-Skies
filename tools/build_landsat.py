"""Cuts the satellite-style land texture of the map from Natural Earth II.

Usage: python tools/build_landsat.py <NE2_HR_LC_SR_W_DR.tif> [cache_dir]

Natural Earth II with shaded relief, water and drainages (naturalearthdata.com, public domain; in the
natural-earth-raster repository on GitHub as 10m_rasters/NE2_HR_LC_SR_W_DR; NE1_HR_LC_SR_W_DR is the paler cousin) is a 21600 by 10800 picture
of the world, 60 pixels to the degree, in plain latitude and longitude. This crops the map's frame from
it and resamples it to half the bitmap's size (3928 by 2576). The map's coast is not Natural Earth's, so
the big bluish water (the sea) takes the colour of the nearest land, so no blue shows along a shore;
small lakes and rivers stay. A touch of fine hill detail from the elevation is added.
Writes data/map/land_satellite.jpg.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

import build_landtex as lt

Image.MAX_IMAGE_PIXELS = None
root = Path(__file__).resolve().parent.parent
PX_PER_DEG_SRC = 60.0


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def main():
    src = Image.open(sys.argv[1]).convert("RGB")
    cache = Path(sys.argv[2] if len(sys.argv) > 2 else "/tmp/terrarium")
    x0 = int(round((lt.LON0 + 180.0) * PX_PER_DEG_SRC))
    x1 = int(round((lt.LON1 + 180.0) * PX_PER_DEG_SRC))
    y0 = int(round((90.0 - lt.LAT1) * PX_PER_DEG_SRC))
    y1 = int(round((90.0 - lt.LAT0) * PX_PER_DEG_SRC))
    crop = src.crop((x0, y0, x1, y1))
    del src
    ow, oh = lt.W // lt.SCALE, lt.H // lt.SCALE
    img = np.asarray(crop.resize((ow, oh), Image.LANCZOS)).astype(np.float32) / 255.0
    del crop
    h, _, _ = lt.elevation_grid(cache)
    # The sea is the big bluish water (small lakes and the rivers stay): its pixels, and a hair of
    # shore, take the colour of the nearest land, so no blue shows along a coast the map draws differently.
    blue = img[..., 2] - np.maximum(img[..., 0], img[..., 1])
    water = blue > 0.03
    sea = ndimage.binary_opening(water, structure=np.ones((3, 3)), iterations=3)
    labels, count = ndimage.label(sea)
    sizes = ndimage.sum(sea, labels, index=np.arange(1, count + 1))
    big = np.isin(labels, 1 + np.flatnonzero(sizes > 4000))
    big = ndimage.binary_dilation(big, iterations=4) & (water | big)
    big = ndimage.binary_dilation(big, iterations=2)
    _, (fy, fx) = ndimage.distance_transform_edt(big, return_indices=True)
    # Natural Earth's tints are those of an atlas, pale and blue-green. Its greens and tans say how
    # green the ground is, so they pick a colour from a richer, more photographic palette, and its
    # shaded relief carries over as light and dark.
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    luma = 0.299 * r + 0.587 * g + 0.114 * b
    sat = img.max(axis=2) - img.min(axis=2)
    green = smooth((g - r) + 0.01, 0.03, 0.2)             # 0 tan, 1 green
    dry = smooth(r - b, 0.18, 0.4) * (1.0 - green)         # bright tan: dry ground
    desert = smooth(luma, 0.80, 0.9) * dry
    forest = np.array([0.15, 0.27, 0.12], np.float32)
    field = np.array([0.33, 0.43, 0.19], np.float32)
    steppe = np.array([0.52, 0.52, 0.28], np.float32)
    sand = np.array([0.74, 0.65, 0.45], np.float32)
    lush = smooth(green, 0.45, 0.95)
    base = np.where(green[..., None] > 0.0, field + (forest - field) * lush[..., None], field)
    base = base + (steppe - base) * (1.0 - green)[..., None] * 0.85
    base = base + (sand - base) * desert[..., None]
    # the relief's light and dark (a ratio to its own surroundings), and a grain of fields and woods
    rel = luma / (ndimage.gaussian_filter(luma, 12.0) + 0.02)
    rel = np.clip(rel, 0.45, 1.7)
    rng = np.random.default_rng(1914)
    grain = ndimage.gaussian_filter(rng.standard_normal(luma.shape).astype(np.float32), 1.2)
    grain2 = ndimage.gaussian_filter(rng.standard_normal(luma.shape).astype(np.float32), 5.0)
    grain = grain / grain.std() * 0.05 + grain2 / grain2.std() * 0.07
    img_land = base * rel[..., None] * (1.0 + grain[..., None])
    # snow and bare rock are pale and grey in the picture: keep them
    pale = smooth(luma, 0.72, 0.9) * (1.0 - smooth(sat, 0.14, 0.3)) * (1.0 - desert)
    img_land = img_land + (np.clip(img, 0.0, 1.0) * 1.05 - img_land) * pale[..., None]
    # rivers and lakes stay, a little deeper
    water_px = (blue > 0.03)
    img_land = np.where(water_px[..., None], img * np.array([0.8, 0.9, 1.0], np.float32), img_land)
    img = img_land
    # Fine hill detail: only what the picture's own shading is too coarse to show.
    lit, _, _ = lt.hill_light(np.maximum(h, 0.0))
    detail = lit - ndimage.gaussian_filter(lit, 6.0)
    img = img * (1.0 + 0.9 * np.clip(detail, -0.3, 0.3))[..., None]
    img = img[fy, fx]   # the sea takes the colour of the nearest graded land
    out = (np.clip(img, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    Image.fromarray(out, "RGB").save(root / "data/map/land_satellite.jpg", quality=90, optimize=True)
    print(f"wrote data/map/land_satellite.jpg {ow}x{oh}")


if __name__ == "__main__":
    main()
