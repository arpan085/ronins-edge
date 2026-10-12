"""Generate tiling ground/material textures with real surface detail.

The project's existing textures are almost flat (albedo std ~2%, normal maps
with no gradient at all), which is why terrain reads as a smooth plane no
matter how it is lit. This builds seamless albedo + normal + roughness maps
from wrapping value noise, with per-material colour variation, weathering and
edge dirt, then writes them next to the originals.
"""
import numpy as np, os
from PIL import Image

RES = 512
OUT = "/data/ronins_edge/game/assets/textures"
rng_master = np.random.default_rng(4242)

def vnoise(res, seed):
    """Tileable value noise: lattice wraps, so the result tiles seamlessly."""
    g = np.random.default_rng(seed).random((res, res)).astype(np.float32)
    ys = np.linspace(0, res, RES, endpoint=False, dtype=np.float32)
    xs = ys
    y0 = np.floor(ys).astype(int) % res
    x0 = np.floor(xs).astype(int) % res
    y1 = (y0 + 1) % res
    x1 = (x0 + 1) % res
    fy = (ys - np.floor(ys))[:, None]
    fx = (xs - np.floor(xs))[None, :]
    fy = fy * fy * (3 - 2 * fy)
    fx = fx * fx * (3 - 2 * fx)
    a = g[np.ix_(y0, x0)]; b = g[np.ix_(y0, x1)]
    c = g[np.ix_(y1, x0)]; d = g[np.ix_(y1, x1)]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy

def fbm(base, octaves, seed, gain=0.5):
    out = np.zeros((RES, RES), np.float32); amp = 1.0; res = base; tot = 0.0
    for o in range(octaves):
        out += amp * vnoise(max(int(res), 2), seed + o * 131)
        tot += amp; amp *= gain; res *= 2
    return out / tot

def billow(base, octaves, seed):
    n = fbm(base, octaves, seed)
    return np.abs(n * 2 - 1)

SLOPE_PER_STRENGTH = 0.11

def normal_from_height(h, strength=2.4):
    """Sobel-style gradient -> tangent-space normal map.

    `strength` is normalised against the field's own RMS gradient so it means
    an actual surface slope. Scaling the raw difference instead made the
    result depend entirely on how spiky the source height happened to be:
    mud and snow shipped four times flatter than rock for no authored
    reason."""
    slope = strength * SLOPE_PER_STRENGTH
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1))
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0))
    k = slope / max(float(np.sqrt(np.mean(gx * gx + gy * gy))), 1e-9)
    gx = gx * k
    gy = gy * k
    nz = np.ones_like(h)
    ln = np.sqrt(gx ** 2 + gy ** 2 + nz ** 2)
    nx, ny, nz = -gx / ln, -gy / ln, nz / ln
    img = np.stack([(nx * 0.5 + 0.5), (ny * 0.5 + 0.5), (nz * 0.5 + 0.5)], -1)
    return (np.clip(img, 0, 1) * 255).astype(np.uint8)

def ramp(t, c0, c1):
    t = np.clip(t, 0, 1)[..., None]
    return np.array(c0) * (1 - t) + np.array(c1) * t

def save(name, albedo, height, rough=None, nstr=2.4):
    Image.fromarray(np.clip(albedo, 0, 255).astype(np.uint8), "RGB").save(f"{OUT}/{name}_c.png")
    Image.fromarray(normal_from_height(height, nstr), "RGB").save(f"{OUT}/{name}_n.png")
    if rough is not None:
        rr = np.broadcast_to(np.asarray(rough, np.float32), (RES, RES))
        r = (np.clip(rr, 0, 1) * 255).astype(np.uint8)
        Image.fromarray(np.stack([r, r, r], -1), "RGB").save(f"{OUT}/{name}_r.png")
    print(f"  {name:12s} albedo_std={albedo.std():5.1f} height_std={height.std():.3f}")

os.makedirs(OUT, exist_ok=True)
print("generating ground materials")

# ---------------------------------------------------------------- grass
blade = billow(64, 4, 11)                     # fine blade-scale detail
clump = fbm(8, 4, 12)                         # clumping / patchiness
dryness = fbm(5, 3, 13)
h = blade * 0.55 + clump * 0.45
col = ramp(clump * 0.7 + blade * 0.3, (48, 66, 30), (96, 118, 52))
col = col * (0.82 + 0.36 * blade[..., None])
dry = ramp(dryness, (0, 0, 0), (52, 40, -10))
col = col + dry * np.clip(dryness - 0.45, 0, 1)[..., None] * 1.4
save("ground_grass", col, h, 0.80 + 0.18 * clump, 2.0)

# ---------------------------------------------------------------- dirt / road
grit = billow(96, 4, 21)
lumps = fbm(12, 4, 22)
pebble = (vnoise(48, 23) > 0.86).astype(np.float32) * billow(160, 2, 24)
h = grit * 0.4 + lumps * 0.4 + pebble * 0.55
col = ramp(lumps * 0.6 + grit * 0.4, (58, 44, 30), (116, 92, 64))
col = col * (0.86 + 0.28 * grit[..., None])
col = col + pebble[..., None] * 46
save("ground_dirt", col, h, 0.74 + 0.2 * lumps, 2.6)

# ---------------------------------------------------------------- rock / cliff
strata = np.sin(np.linspace(0, 14 * np.pi, RES))[:, None] * 0.5 + 0.5
strata = strata * 0.45 + fbm(6, 3, 31)[..., ] * 0.55
crack = 1.0 - np.clip(billow(24, 5, 32) * 2.2, 0, 1)
face = billow(72, 4, 33)
h = strata * 0.5 + face * 0.35 - crack * 0.5
col = ramp(strata * 0.55 + face * 0.45, (74, 72, 70), (146, 142, 136))
col = col * (0.88 + 0.24 * face[..., None])
col = col - crack[..., None] * 38                     # dark fissures
moss = np.clip(fbm(10, 3, 34) - 0.55, 0, 1) * 2.0
col = col * (1 - moss[..., None] * 0.55) + np.array((48, 68, 34)) * moss[..., None] * 0.55
save("ground_rock", col, h, 0.62 + 0.28 * face, 3.2)

# ---------------------------------------------------------------- mud / wet
sludge = fbm(14, 4, 41)
ripple = billow(40, 3, 42)
h = sludge * 0.6 + ripple * 0.25
col = ramp(sludge, (40, 30, 21), (86, 68, 48))
col = col * (0.9 + 0.2 * ripple[..., None])
save("ground_mud", col, h, 0.34 + 0.3 * sludge, 1.8)

# ---------------------------------------------------------------- bark
fibre = billow(220, 3, 51)
vgrain = np.abs(np.sin(np.linspace(0, 26 * np.pi, RES))[None, :] * 0.5 + 0.5)
vgrain = vgrain * 0.4 + fbm(18, 3, 52) * 0.6
h = fibre * 0.35 + vgrain * 0.6
col = ramp(vgrain * 0.6 + fibre * 0.4, (44, 33, 25), (104, 82, 62))
col = col * (0.85 + 0.3 * fibre[..., None])
save("bark_detail", col, h, 0.85, 2.8)

# ---------------------------------------------------------------- snow
sn = fbm(20, 4, 61)
h = sn * 0.5 + billow(80, 3, 62) * 0.2
col = ramp(sn, (196, 206, 224), (240, 246, 255))
save("ground_snow", col, h, 0.72, 1.4)

print("done")
