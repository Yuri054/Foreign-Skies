"""Builds the coast map the 3D map's water reads: how far each place is from the shore.

Usage: python tools/build_coast.py

Reads data/map/provinces.png (black is the sea) and writes data/map/coast.png at a quarter of its size, the same frame
as data/map/relief.png. Red is the signed distance to the shoreline near it: 128 on the shore, 8 steps a texel, more
out to sea and less inland (up to 16 texels either way), so a linearly filtered read finds the shore to well under a
texel. Green is the distance out to sea, farther: 255 * sqrt(texels / FAR) up to FAR texels, 0 on land; the 3D map
uses it for the depth of the water (a stand-in for the sea floor: near the coast is shallow).
"""
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

Image.MAX_IMAGE_PIXELS = None
ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "data" / "map" / "provinces.png"
OUT = ROOT / "data" / "map" / "coast.png"
SCALE = 4
NEAR_STEPS = 8.0      # red steps a texel
FAR = 120.0           # texels at which green reaches 255 (about 330 km)


def main() -> None:
    rgb = np.asarray(Image.open(SRC).convert("RGB"))
    sea = np.all(rgb == 0, axis=2)
    h, w = sea.shape
    qh, qw = h // SCALE, w // SCALE
    share = sea[: qh * SCALE, : qw * SCALE].reshape(qh, SCALE, qw, SCALE).mean(axis=(1, 3))
    water = share >= 0.5
    to_land = ndimage.distance_transform_edt(water)       # in the sea: texels to the nearest land
    to_sea = ndimage.distance_transform_edt(~water)       # on land: texels to the nearest sea
    signed = np.where(water, to_land - 0.5, -(to_sea - 0.5))
    # The share of sea in each texel moves the shore within it, for a finer line than the threshold alone.
    signed = signed + (share - 0.5) * 0.9
    red = np.clip(128.0 + signed * NEAR_STEPS, 0, 255)
    green = np.where(water, 255.0 * np.sqrt(np.clip(to_land / FAR, 0.0, 1.0)), 0.0)
    out = np.stack([red, green, np.zeros_like(red)], axis=2).round().astype(np.uint8)
    Image.fromarray(out, "RGB").save(OUT, optimize=True)
    print("wrote %s (%dx%d), %.0f%% sea" % (OUT.relative_to(ROOT), qw, qh, water.mean() * 100.0))


if __name__ == "__main__":
    main()
