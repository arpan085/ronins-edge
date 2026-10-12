#!/usr/bin/env python3
"""v13: pack the Poly Haven CC0 ground sets into two texture arrays.

  game/assets/textures/terrain/ground_albedo.jpg   6 x 1024^2 slices, RGB albedo
  game/assets/textures/terrain/ground_data.png     6 x 512^2 slices:
                                                   R,G normal xy (OpenGL, +Y up)
                                                   B roughness, A height
  game/assets/textures/terrain/ground_macro.jpg    aerial_grass_rock, 512^2, used
                                                   at a 40-160 m repeat to break
                                                   up large areas

Both arrays are imported by Godot's 2d_array_texture importer (slices laid out
horizontally). Slice order must match shaders/terrain.gdshader:
  0 grass (sparse_grass)   1 forest floor (forest_leaves_02)  2 dirt/trail (rocky_trail)
  3 rock (mossy_rock)      4 mud (brown_mud_02)               5 river bed (river_small_rocks)
Source: https://polyhaven.com (CC0). Download with the ids above at 1k:
<id>_diff_1k.jpg, <id>_nor_gl_1k.jpg, <id>_rough_1k.jpg, <id>_disp_1k.png|jpg
"""
import os, sys
import numpy as np
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else "/tmp/ph"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "assets", "textures", "terrain")
LAYERS = ["sparse_grass", "forest_leaves_02", "rocky_trail", "mossy_rock", "brown_mud_02", "river_small_rocks"]
# gentle per-layer grading so the sets sit together under one sun
GRADE = {  # (brightness, saturation)
    "sparse_grass": (1.0, 1.0), "forest_leaves_02": (0.8, 0.85), "rocky_trail": (0.92, 0.9),
    "mossy_rock": (0.95, 0.85), "brown_mud_02": (0.95, 0.95), "river_small_rocks": (0.9, 0.9)}


def load(name, kind, size, mode):
    for ext in ("jpg", "png"):
        p = os.path.join(SRC, "%s_%s.%s" % (name, kind, ext))
        if os.path.exists(p):
            return Image.open(p).convert(mode).resize((size, size), Image.LANCZOS)
    raise SystemExit("missing %s %s" % (name, kind))


def s2l(c): return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


alb = Image.new("RGB", (1024 * len(LAYERS), 1024))
dat = Image.new("RGBA", (512 * len(LAYERS), 512))
for i, n in enumerate(LAYERS):
    a = np.asarray(load(n, "diff", 1024, "RGB")).astype(np.float64) / 255.0
    b, s = GRADE[n]
    lum = a @ np.array([0.299, 0.587, 0.114])
    a = np.clip((lum[..., None] + (a - lum[..., None]) * s) * b, 0, 1)
    alb.paste(Image.fromarray((a * 255 + 0.5).astype(np.uint8)), (1024 * i, 0))
    nor = np.asarray(load(n, "nor", 512, "RGB")).astype(np.float64)
    rough = np.asarray(load(n, "rough", 512, "L")).astype(np.float64)
    disp = np.asarray(load(n, "disp", 512, "L")).astype(np.float64)
    lo, hi = np.percentile(disp, 2), np.percentile(disp, 98)
    disp = np.clip((disp - lo) / max(1.0, hi - lo), 0, 1) * 255.0
    d = np.stack([nor[..., 0], nor[..., 1], rough, disp], -1)
    dat.paste(Image.fromarray((d + 0.5).clip(0, 255).astype(np.uint8), "RGBA"), (512 * i, 0))
    lin = s2l(a).reshape(-1, 3).mean(0)
    print("%-18s avg albedo srgb %s linear %s rough %.2f" % (n, (a.reshape(-1, 3).mean(0)).round(3), lin.round(3), rough.mean() / 255))
alb.save(os.path.join(OUT, "ground_albedo.jpg"), quality=90, subsampling=0)
dat.save(os.path.join(OUT, "ground_data.png"), optimize=True)
m = load("aerial_grass_rock", "diff", 512, "RGB")
m.save(os.path.join(OUT, "ground_macro.jpg"), quality=90)
print("macro avg", (np.asarray(m).reshape(-1, 3).mean(0) / 255).round(3))
for f in ("ground_albedo.jpg", "ground_data.png", "ground_macro.jpg"):
    print(f, os.path.getsize(os.path.join(OUT, f)))
