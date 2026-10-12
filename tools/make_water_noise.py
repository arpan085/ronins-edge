#!/usr/bin/env python3
"""v13: tileable noise for the water shaders -> game/assets/textures/water_noise.png

R  foam web: Worley F2-F1 (bright cell borders = the lace pattern of
   aerated water), wrapped so it tiles
G  fbm, low frequency (streaks when stretched along the flow)
B  fbm, higher frequency (breakup / waterfall streak detail)
A  255 (kept opaque: Godot's fix_alpha_border would rewrite RGB under A=0)
"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "assets", "textures", "water_noise.png")
S = 512
rng = np.random.default_rng(1313)


def fbm(lo, hi, slope=1.2):
    """band-limited periodic noise via FFT filtering of white noise"""
    f = np.fft.fftfreq(S) * S
    fx, fy = np.meshgrid(f, f)
    r = np.hypot(fx, fy)
    amp = np.where((r >= lo) & (r <= hi), 1.0 / np.maximum(r, 1.0) ** slope, 0.0)
    ph = np.fft.fft2(rng.standard_normal((S, S)))
    n = np.real(np.fft.ifft2(ph * amp))
    n = (n - n.mean()) / (n.std() + 1e-9)
    return np.clip(0.5 + n * 0.18, 0, 1)


def worley(count):
    pts = rng.random((count, 2)) * S
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    f1 = np.full((S, S), 1e9, np.float32); f2 = np.full((S, S), 1e9, np.float32)
    for px, py in pts:
        dx = np.abs(xx - px); dx = np.minimum(dx, S - dx)
        dy = np.abs(yy - py); dy = np.minimum(dy, S - dy)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < f1
        f2 = np.where(closer, f1, np.minimum(f2, d))
        f1 = np.where(closer, d, f1)
    e = f2 - f1
    cell = S / np.sqrt(count)
    web = np.clip(1.0 - e / (cell * 0.22), 0, 1) ** 1.6
    return web


web = worley(140) * 0.65 + worley(520) * 0.35
web = np.clip(web * (0.6 + 0.8 * fbm(2, 10)), 0, 1)
g = fbm(3, 40, 1.0)
b = fbm(8, 120, 0.9)
img = np.stack([web, g, b, np.ones_like(g)], -1)
Image.fromarray((img * 255).astype(np.uint8), "RGBA").save(OUT)
print("wrote", OUT, [round(float(c.mean()), 3) for c in (web, g, b)])
