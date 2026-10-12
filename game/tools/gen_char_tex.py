# v0.18 procedural costume textures: lacquered lamellar armour + hair strands.
import numpy as np
from PIL import Image
rng = np.random.default_rng(7)
OUT = "/data/ronins_edge/game/assets/char/tex/"

def blur(a, r):
    # separable box blur (wraps, so the tile stays seamless)
    for ax in (0, 1):
        acc = np.zeros_like(a)
        for d in range(-r, r + 1): acc += np.roll(a, d, axis=ax)
        a = acc / (2 * r + 1)
    return a

def noise(n, scale):
    small = rng.random((max(2, n // scale), max(2, n // scale)))
    img = Image.fromarray((small * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)
    return np.asarray(img, dtype=np.float32) / 255.0

def save_normal(h, strength, name):
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    nx, ny = -gx * strength, gy * strength          # OpenGL convention (+Y up)
    nz = np.ones_like(h)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([nx / l, ny / l, nz / l], -1) * 0.5 + 0.5
    Image.fromarray((rgb * 255).astype(np.uint8)).save(OUT + name, quality=92)

# ---------------------------------------------------------------- armour
# One tile = 0.30 m x 0.30 m: five 6 cm lames (kozane rows). Each lame is a
# shallow convex plate; its lower edge overlaps the lame below (dark step).
# Sugake lacing: pairs of silk cords every 5 cm crossing each lame, holes at
# the top and bottom of the lame. Lacquer wears through to brown at edges.
N = 1024
y = (np.arange(N) / N)[:, None] * np.ones((1, N))
x = (np.arange(N) / N)[None, :] * np.ones((N, 1))
rows = 5
ly = (y * rows) % 1.0                      # 0 top of lame .. 1 bottom
h = 0.55 * np.sin(np.pi * np.clip(ly, 0, 1)) ** 0.6   # convex plate
h -= 0.35 * np.clip((ly - 0.90) / 0.10, 0, 1)        # bevel under the overlap
cols = 6                                   # lacing pairs per tile (5 cm)
lx = (x * cols) % 1.0
cord = np.zeros_like(h)
for c0 in (0.35, 0.65):                    # two cords per pair
    cord = np.maximum(cord, np.clip(1.0 - np.abs(lx - c0) / 0.07, 0, 1))
cord_band = ((ly > 0.12) & (ly < 0.86)).astype(np.float32)
cord *= cord_band
cord_h = np.sqrt(np.clip(cord, 0, 1)) * 0.25
# braid ridges along the cord
cord_h *= 0.8 + 0.2 * np.sin(y * N * 0.9)
holes = np.zeros_like(h)
for hy in (0.10, 0.88):
    for c0 in (0.35, 0.65):
        d = np.sqrt(((lx - c0) * 0.30 / cols) ** 2 + ((ly - hy) * 0.30 / rows) ** 2)
        holes = np.maximum(holes, np.clip(1.0 - d / 0.0025, 0, 1))
wear_n = noise(N, 24) * 0.6 + noise(N, 6) * 0.4
edge = np.clip((np.abs(ly - 0.5) - 0.36) / 0.14, 0, 1)        # lame edges
wear = np.clip(edge * (wear_n * 1.6 - 0.45), 0, 1)
scratch = np.zeros_like(h)
for _ in range(140):
    sx, sy = rng.integers(0, N, 2); ln = rng.integers(20, 90); ang = rng.uniform(-0.5, 0.5)
    for t in range(ln):
        px = int(sx + t * np.cos(ang)) % N; py = int(sy + t * np.sin(ang)) % N
        scratch[py, px] = 1.0
scratch = blur(scratch, 1)
height = h + cord_h - holes * 0.4 + noise(N, 3) * 0.015
save_normal(blur(height, 1), 9.0, "armour_lame_nor.jpg")
# albedo: lacquer (lightness ~0.5 so the tint sets colour), worn brown edges,
# silk cords kept separate in a mask stored in the albedo's red channel? no:
# cords get their own colour baked here (crimson), lacquer stays neutral grey.
lac = 1.0 + 0.08 * (noise(N, 40) - 0.5)
alb = np.stack([0.105 * lac, 0.11 * lac, 0.13 * lac], -1)
brown = np.array([0.36, 0.22, 0.14])
alb = alb * (1 - wear[..., None] * 0.8) + brown * (wear[..., None] * 0.8)
alb = alb * (1 - holes[..., None] * 0.9)
alb = alb * (1 - 0.35 * np.clip((ly - 0.88) / 0.12, 0, 1))[..., None]   # overlap shadow
silk = np.array([0.62, 0.10, 0.11]) * (0.85 + 0.15 * np.sin(y * N * 0.9))[..., None]
cm = np.clip(cord * 1.5, 0, 1)[..., None]
alb = alb * (1 - cm) + silk * cm
Image.fromarray((np.clip(alb, 0, 1) * 255).astype(np.uint8)).save(OUT + "armour_lame_diff.jpg", quality=92)
rough = 0.22 + 0.35 * wear + 0.25 * scratch + 0.5 * cm[..., 0] + 0.03 * noise(N, 8)
Image.fromarray((np.clip(rough, 0, 1) * 255).astype(np.uint8)).save(OUT + "armour_lame_rough.jpg", quality=92)

# ---------------------------------------------------------------- hair
# Strands run along V. Tile = 0.06 m wide: fine streaks of varying width and
# brightness, smooth along the strand, a few stray clumps.
M = 512
st = np.zeros((M, M), np.float32)
lane = rng.random(M)
lane = blur(np.tile(lane[None, :], (8, 1)), 1)[0]
st = np.tile(lane[None, :], (M, 1))
st += 0.25 * np.tile(rng.random(M)[None, :], (M, 1))
wav = noise(M, 64)
st = np.stack([np.roll(st[i], int((wav[i, 0] - 0.5) * 6)) for i in range(M)])
st = (st - st.min()) / (st.max() - st.min())
alb = 0.38 + 0.24 * st
Image.fromarray((alb * 255).astype(np.uint8)).save(OUT + "hair_strand_diff.jpg", quality=92)
save_normal(st * 0.6, 6.0, "hair_strand_nor.jpg")
Image.fromarray(((0.42 + 0.18 * (1 - st)) * 255).astype(np.uint8)).save(OUT + "hair_strand_rough.jpg", quality=92)
print("textures written")
