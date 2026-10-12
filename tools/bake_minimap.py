#!/usr/bin/env python3
"""v13: bake the HUD radar map -> game/assets/terrain/minimap.png (1024^2 RGB)

A stylised, readable map rather than a height dump: biome colours, north-west
hillshade, 10 m / 50 m contours, the lake with a pale shore line, the main
river at its real width (river_main.bin) and the old streams as thin lines,
roads with a dark casing, and buildings as small rotated footprints. The HUD
maps it straight onto the world square (UV = world / size), so resolution is
free; 1024 gives ~1.5 m a texel, about 1:1 at the radar's default zoom.
Run after tools/make_river.py.
"""
import json, math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T = os.path.join(ROOT, "game", "assets", "terrain")
W = json.load(open(os.path.join(T, "world.json")))
N, CELL, WL = W["n"], W["cell"], W["water_level"]
SIZE = W["size"]
R = 1024
H = np.fromfile(os.path.join(T, "heightmap.bin"), dtype="<f4").reshape(N, N).astype(np.float64)
raw = open(os.path.join(T, "river_main.bin"), "rb").read()
SURF = np.frombuffer(raw[:N * N * 4], dtype="<f4").reshape(N, N).astype(np.float64)
biome = np.asarray(Image.open(os.path.join(T, "biome.png")).convert("RGBA")).astype(np.float64) / 255.0
river = np.asarray(Image.open(os.path.join(T, "river.png")).convert("RGBA")).astype(np.float64) / 255.0


def up(a, order=1):
    """resample an N x N grid onto the R x R map (bilinear, or nearest)"""
    g = np.linspace(0, a.shape[0] - 1, R)
    if order == 0:
        i = np.clip(np.round(g).astype(int), 0, a.shape[0] - 1)
        return a[np.ix_(i, i)]
    i0 = np.floor(g).astype(int); i1 = np.minimum(i0 + 1, a.shape[0] - 1); f = g - i0
    a0 = a[i0][:, i0] * (1 - f)[None, :] + a[i0][:, i1] * f[None, :]
    a1 = a[i1][:, i0] * (1 - f)[None, :] + a[i1][:, i1] * f[None, :]
    return a0 * (1 - f)[:, None] + a1 * f[:, None]


h = up(H)
px = SIZE / R
PAL = {0: (0.43, 0.49, 0.30), 1: (0.56, 0.54, 0.33), 2: (0.49, 0.50, 0.29), 3: (0.31, 0.42, 0.24),
       4: (0.50, 0.47, 0.40), 5: (0.66, 0.66, 0.63), 6: (0.58, 0.45, 0.47), 7: (0.24, 0.34, 0.21),
       8: (0.54, 0.48, 0.36), 9: (0.60, 0.56, 0.43)}
bid = up(np.round(biome[..., 0] * 255.0), 0).astype(int)
col = np.zeros((R, R, 3))
for k, c in PAL.items(): col[bid == k] = c
# soften the biome borders a little
col = np.stack([np.asarray(Image.fromarray((col[..., i] * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.6)),
                           np.float64) / 255.0 for i in range(3)], -1)
# woods read darker, farmland gets its paddy grid
trees = up(biome[..., 3])
col *= (1.0 - 0.28 * np.clip(trees, 0, 1))[..., None]
yy, xx = np.mgrid[0:R, 0:R]
paddy = ((xx // 7 + yy // 10) % 2) * 0.05 * (bid == 1)
col *= (1.0 - paddy)[..., None]
# elevation: high ground pales toward bare stone
alt = np.clip((h - 60.0) / 80.0, 0, 1) ** 1.2
col = col * (1 - alt[..., None] * 0.45) + np.array([0.74, 0.73, 0.70]) * alt[..., None] * 0.45
# hillshade from the north-west
gy, gx = np.gradient(h, px)
nrm = np.stack([-gx, np.ones_like(h) * 1.0, -gy], -1)
nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
L = np.array([-0.55, 0.70, -0.45]); L /= np.linalg.norm(L)
shade = np.clip(nrm @ L, 0, 1)
flat = L[1]
col *= (0.72 + 0.40 * (shade - flat) / flat * 0.9 + 0.28)[..., None].clip(0.45, 1.35)
# contours
for step, amt in ((10.0, 0.10), (50.0, 0.20)):
    band = np.floor(h / step)
    edge = (band != np.roll(band, 1, 0)) | (band != np.roll(band, 1, 1))
    edge &= h > WL + 0.5
    col[edge] *= 1.0 - amt
# ---- water
lake = h < WL
dep = np.clip((WL - h) / 8.0, 0, 1)
lake_col = np.array([0.25, 0.41, 0.47]) * (1 - dep[..., None]) + np.array([0.12, 0.24, 0.32]) * dep[..., None]
col[lake] = lake_col[lake]
shore = lake & ~(np.roll(lake, 1, 0) & np.roll(lake, -1, 0) & np.roll(lake, 1, 1) & np.roll(lake, -1, 1))
col[shore] = (0.70, 0.74, 0.68)
surf = up(SURF, 0)
rmask = (surf > 0) & (surf > h + 0.02)
col[rmask] = (0.22, 0.40, 0.48)
streams = up(river[..., 0]) > 0.5
col[streams & ~rmask & ~lake] = col[streams & ~rmask & ~lake] * 0.35 + np.array([0.26, 0.44, 0.50]) * 0.65

img = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB")
d = ImageDraw.Draw(img)
s = 1.0 / px
# main river outline: a darker line along its banks reads at radar size
rm = W.get("river_main", {})
# ---- roads (dark casing, then the pale track)
for pts in W["roads"].values():
    q = [(x * s, z * s) for x, z in pts]
    d.line(q, fill=(58, 48, 36), width=5, joint="curve")
for pts in W["roads"].values():
    q = [(x * s, z * s) for x, z in pts]
    d.line(q, fill=(206, 186, 140), width=3, joint="curve")
# fords: a light dash across the water
for x, z in rm.get("fords", []):
    d.ellipse([x * s - 3, z * s - 3, x * s + 3, z * s + 3], fill=(190, 176, 140))
# ---- buildings
FOOT = {"house": (7.0, 5.0), "shrine_hall": (14.0, 10.0), "castle_keep": (16.0, 16.0), "castle_gate": (12.0, 5.0),
        "watchtower": (4.0, 4.0), "stall": (4.0, 3.0), "well": (2.5, 2.5), "wall": (10.0, 1.6), "bridge": (10.0, 3.0)}
for p in W["props"] + W.get("landmarks", []):
    k = p.get("kind")
    if k not in FOOT: continue
    fw, fd = FOOT[k]
    sc = float(p.get("s", 1.0)) * (1.0 if k not in ("shrine_hall", "castle_keep") else 0.6)
    a = math.radians(float(p.get("rot", 0.0)))
    ca, sa = math.cos(a), math.sin(a)
    cx, cz = p["x"] * s, p["z"] * s
    poly = []
    for ox, oz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        lx, lz = ox * fw * 0.5 * sc * s, oz * fd * 0.5 * sc * s
        poly.append((cx + lx * ca - lz * sa, cz + lx * sa + lz * ca))
    if k == "bridge":
        d.polygon(poly, fill=(150, 112, 70), outline=(60, 44, 30))
    elif k == "wall":
        d.polygon(poly, fill=(80, 74, 66))
    else:
        d.polygon(poly, fill=(66, 50, 40), outline=(196, 170, 120))
for p in W.get("landmarks", []) + W["props"]:
    if p.get("kind") == "torii":
        x, z = p["x"] * s, p["z"] * s
        d.rectangle([x - 2.5, z - 1.0, x + 2.5, z + 1.0], fill=(200, 58, 40))
img = img.filter(ImageFilter.UnsharpMask(radius=1.2, percent=40, threshold=2))
out = os.path.join(T, "minimap.png")
img.save(out, optimize=True)
a = np.asarray(img)
print("wrote", out, img.size, "mean", a.reshape(-1, 3).mean(0).round(1), "river px", int(rmask.sum()),
      "lake px", int(lake.sum()))
