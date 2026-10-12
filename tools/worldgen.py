"""Ronin's Edge world generator.

Builds a large, geographically varied terrain with eroded slopes, a river
network, least-cost roads, biome regions and scattered content, then writes:
  heightmap.bin  float32 [n*n] row-major (z*n + x), metres
  splat.png      R=grass G=dirt B=rock A=mud   (terrain material weights)
  biome.png      R=biome id  G=moisture  B=grass density  A=tree density
  world.json     zones, roads, props, landmarks, water, regions, POIs

Deterministic: same seed -> same world.
"""
import json, math, os, struct
import numpy as np
from PIL import Image

SEED = 20260927
SIZE = 1536.0          # metres across
N = 769                # heightmap resolution (2.0 m cells)
CELL = SIZE / (N - 1)
WATER = 6.0            # water plane height (m)
OUT = "/data/ronins_edge/game/assets/terrain"
rng = np.random.default_rng(SEED)

# ----------------------------------------------------------------- noise
def _smooth_noise(res, oct_seed):
    """Value noise at `res` grid, bilinearly upsampled to N*N."""
    g = np.random.default_rng(oct_seed).random((res + 1, res + 1)).astype(np.float32)
    ys = np.linspace(0, res, N, dtype=np.float32)
    xs = np.linspace(0, res, N, dtype=np.float32)
    y0 = np.floor(ys).astype(int); x0 = np.floor(xs).astype(int)
    y1 = np.minimum(y0 + 1, res);  x1 = np.minimum(x0 + 1, res)
    fy = (ys - y0)[:, None]; fx = (xs - x0)[None, :]
    fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)   # smoothstep
    a = g[np.ix_(y0, x0)]; b = g[np.ix_(y0, x1)]
    c = g[np.ix_(y1, x0)]; d = g[np.ix_(y1, x1)]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy

def fbm(base_res, octaves, seed, gain=0.5, lac=2.0):
    out = np.zeros((N, N), np.float32); amp = 1.0; res = base_res; tot = 0.0
    for o in range(octaves):
        out += amp * _smooth_noise(int(res), seed + o * 977)
        tot += amp; amp *= gain; res *= lac
    return out / tot

def ridged(base_res, octaves, seed):
    out = np.zeros((N, N), np.float32); amp = 1.0; res = base_res; tot = 0.0
    for o in range(octaves):
        n = _smooth_noise(int(res), seed + o * 613)
        out += amp * (1.0 - np.abs(n * 2.0 - 1.0))
        tot += amp; amp *= 0.5; res *= 2.0
    return out / tot

# grid coords in metres
gx = np.linspace(0, SIZE, N, dtype=np.float32)[None, :].repeat(N, 0)   # x varies along axis 1
gz = np.linspace(0, SIZE, N, dtype=np.float32)[:, None].repeat(N, 1)   # z varies along axis 0

_WARP_CACHE = {}

def _warp_field(seed):
    """Cached noise used to break up radial shapes.

    The frequency matters: noise that is too low-frequency barely bends a
    200 m radius and the stamp still reads as a circle. Two harmonics at
    ~150 m and ~60 m give a ragged, natural boundary at region scale.
    """
    if seed not in _WARP_CACHE:
        a = fbm(10, 5, SEED + 700 + seed * 131)
        b = fbm(24, 3, SEED + 1300 + seed * 197)
        _WARP_CACHE[seed] = np.clip(a * 0.68 + b * 0.32, 0.0, 1.0)
    return _WARP_CACHE[seed]

def falloff(cx, cz, r, power=2.0, warp=0.46, seed=0):
    """Radial mask with a noise-warped edge.

    A plain radial falloff stamps a visibly perfect circle into the terrain,
    which reads as obviously procedural. Perturbing the effective radius with
    low-frequency noise gives irregular, natural-looking region boundaries.
    """
    d = np.sqrt((gx - cx) ** 2 + (gz - cz) ** 2)
    rr = r * (1.0 + (_warp_field(seed) - 0.5) * 2.0 * warp)
    return np.clip(1.0 - (d / np.maximum(rr, 1.0)) ** power, 0.0, 1.0)

# ----------------------------------------------------------------- regions
# A deliberate geographic sequence the player can traverse:
# village -> farmland -> tall grass -> bamboo -> rocky slope -> mountain road
# -> shrine -> dense forest -> castle, with a lake and river spine.
POI = {
    "village":   (1180, 1120),
    "farmland":  (980, 1210),
    "grassland": (760, 1180),
    "bamboo":    (520, 1010),
    "slope":     (330, 820),
    "mountain":  (230, 470),
    "shrine":    (620, 560),
    "forest":    (880, 720),
    "castle":    (1210, 420),
    "lake":      (900, 1370),
    "ruins":     (430, 1240),
    "waterfall": (330, 640),
}

# ----------------------------------------------------------------- base terrain
# domain warp for non-repetitive shapes
wx = (fbm(3, 4, SEED + 11) - 0.5) * 140.0
wz = (fbm(3, 4, SEED + 23) - 0.5) * 140.0

cont = fbm(2, 5, SEED + 1)                 # continental mass
hills = fbm(6, 6, SEED + 2)
detail = fbm(18, 5, SEED + 3)
rock = ridged(9, 5, SEED + 4)

h = np.zeros((N, N), np.float32)
h += cont * 34.0
h += hills * 16.0
h += detail * 3.2

# mountain massif in the north-west + ridge along the north edge (distant peaks)
massif = falloff(POI["mountain"][0], POI["mountain"][1], 560, 1.7, 0.40, 1)
h += (ridged(4, 6, SEED + 5) ** 1.5) * massif * 132.0
north_ridge = np.clip(1.0 - (gz / 430.0), 0.0, 1.0) ** 1.6
h += (rock ** 1.4) * north_ridge * 78.0
west_ridge = np.clip(1.0 - (gx / 330.0), 0.0, 1.0) ** 1.8
h += (rock ** 1.3) * west_ridge * 52.0

# broad lowland basin in the south-east (village / farmland / lake)
basin = falloff(1050, 1230, 640, 1.4, 0.38, 2)
h -= basin * 26.0
h += falloff(POI["lake"][0], POI["lake"][1], 210, 1.2, 0.42, 3) * -12.0   # lake bowl

# castle sits on a defensible plateau
cast = falloff(POI["castle"][0], POI["castle"][1], 200, 2.2, 0.40, 4)
cast_top = np.percentile(h, 78) + 24.0 + detail * 5.0 + hills * 3.0
h = h * (1 - cast * 0.62) + cast_top * (cast * 0.62)

# shrine terrace
shr = falloff(POI["shrine"][0], POI["shrine"][1], 130, 2.4, 0.38, 5)
shr_top = h[int(POI["shrine"][1] / CELL), int(POI["shrine"][0] / CELL)] + 4.0 + detail * 2.4
h = h * (1 - shr * 0.66) + shr_top * (shr * 0.66)

h -= h.min()

# ----------------------------------------------------------------- erosion
def thermal(hm, iters=28, talus=0.9):
    """Slope-limited creep: rounds ridges, builds talus at cliff bases."""
    for _ in range(iters):
        d = np.zeros_like(hm)
        for ax, sh in ((0, 1), (0, -1), (1, 1), (1, -1)):
            nb = np.roll(hm, sh, axis=ax)
            diff = hm - nb
            move = np.where(diff > talus, (diff - talus) * 0.22, 0.0)
            d -= move
            d += np.roll(move, -sh, axis=ax)
        hm = hm + d
    return hm

h = thermal(h, 30, 0.85)

def flow_accum(hm):
    """D8 single-flow accumulation, processed high->low."""
    flat = hm.ravel()
    order = np.argsort(-flat)
    acc = np.ones(N * N, np.float32)
    nbr = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
    down = np.full(N * N, -1, np.int64)
    zz, xx = np.divmod(np.arange(N * N), N)
    best = np.zeros(N * N, np.float32)
    for dz, dx in nbr:
        z2 = np.clip(zz + dz, 0, N - 1); x2 = np.clip(xx + dx, 0, N - 1)
        idx2 = z2 * N + x2
        drop = (flat - flat[idx2]) / math.hypot(dz, dx)
        upd = drop > best
        best[upd] = drop[upd]; down[upd] = idx2[upd]
    for i in order:
        d = down[i]
        if d >= 0:
            acc[d] += acc[i]
    return acc.reshape(N, N), down

acc, down = flow_accum(h)
la = np.log1p(acc)
river = la > np.percentile(la, 99.05)          # main channels
stream = la > np.percentile(la, 97.6)          # tributaries

# carve channels, deeper where flow is larger
carve = np.zeros_like(h)
carve[stream] = 1.1
carve[river] = 3.0
# widen with a couple of blur passes
for _ in range(3):
    carve = np.maximum(carve, (np.roll(carve, 1, 0) + np.roll(carve, -1, 0) +
                               np.roll(carve, 1, 1) + np.roll(carve, -1, 1)) * 0.42)
h -= carve
h = thermal(h, 6, 1.1)

# lake basin flattening
lake_mask = falloff(POI["lake"][0], POI["lake"][1], 165, 1.0, 0.44, 3) > 0.30
h[lake_mask] = np.minimum(h[lake_mask], WATER - 1.6)

h -= h.min()
HMAX = float(h.max())

# ----------------------------------------------------------------- slope
def slope_of(hm):
    dzdx = (np.roll(hm, -1, 1) - np.roll(hm, 1, 1)) / (2 * CELL)
    dzdz = (np.roll(hm, -1, 0) - np.roll(hm, 1, 0)) / (2 * CELL)
    return np.sqrt(dzdx ** 2 + dzdz ** 2)

slope = slope_of(h)

# ----------------------------------------------------------------- roads
def road_path(a, b, hm, avoid_water=True):
    """Least-cost path (Dijkstra) preferring gentle gradients."""
    import heapq
    sz, sx = int(a[1] / CELL), int(a[0] / CELL)
    tz, tx = int(b[1] / CELL), int(b[0] / CELL)
    sl = slope_of(hm)
    cost_base = 1.0 + sl * 26.0
    if avoid_water:
        cost_base = cost_base + (hm < WATER + 0.6) * 60.0
    dist = np.full((N, N), np.inf, np.float32)
    prev = np.full((N, N), -1, np.int64)
    dist[sz, sx] = 0.0
    pq = [(0.0, sz * N + sx)]
    step = 3                     # coarse stride keeps it fast
    seen = np.zeros((N, N), bool)
    while pq:
        d, cur = heapq.heappop(pq)
        cz, cx = divmod(cur, N)
        if seen[cz, cx]:
            continue
        seen[cz, cx] = True
        if abs(cz - tz) <= step and abs(cx - tx) <= step:
            tz, tx = cz, cx
            break
        for dz in (-step, 0, step):
            for dx in (-step, 0, step):
                if dz == 0 and dx == 0:
                    continue
                nz, nx = cz + dz, cx + dx
                if not (0 <= nz < N and 0 <= nx < N) or seen[nz, nx]:
                    continue
                w = cost_base[nz, nx] * math.hypot(dz, dx)
                nd = d + w
                if nd < dist[nz, nx]:
                    dist[nz, nx] = nd; prev[nz, nx] = cur
                    heapq.heappush(pq, (nd, nz * N + nx))
    pts = []
    cur = tz * N + tx
    while cur >= 0:
        cz, cx = divmod(cur, N)
        pts.append((cx * CELL, cz * CELL))
        cur = prev[cz, cx]
    return pts[::-1]

ROAD_LINKS = [
    ("village", "farmland"), ("farmland", "grassland"), ("grassland", "bamboo"),
    ("bamboo", "slope"), ("slope", "mountain"), ("mountain", "shrine"),
    ("shrine", "forest"), ("forest", "castle"), ("village", "lake"),
    ("bamboo", "ruins"), ("shrine", "castle"),
]
roads = {}
road_mask = np.zeros((N, N), np.float32)
for a, b in ROAD_LINKS:
    pts = road_path(POI[a], POI[b], h)
    roads["%s-%s" % (a, b)] = [[round(p[0], 1), round(p[1], 1)] for p in pts[::2]]
    for (px, pz) in pts:
        zi, xi = int(pz / CELL), int(px / CELL)
        r = 3
        z0, z1 = max(0, zi - r), min(N, zi + r + 1)
        x0, x1 = max(0, xi - r), min(N, xi + r + 1)
        road_mask[z0:z1, x0:x1] = np.maximum(road_mask[z0:z1, x0:x1], 1.0)

# smooth the road corridor into the terrain (worn, slightly sunken)
rm_blur = road_mask.copy()
for _ in range(4):
    rm_blur = (rm_blur + np.roll(rm_blur, 1, 0) + np.roll(rm_blur, -1, 0) +
               np.roll(rm_blur, 1, 1) + np.roll(rm_blur, -1, 1)) / 5.0
h_sm = h.copy()
for _ in range(6):
    h_sm = (h_sm + np.roll(h_sm, 1, 0) + np.roll(h_sm, -1, 0) +
            np.roll(h_sm, 1, 1) + np.roll(h_sm, -1, 1)) / 5.0
h = h * (1 - rm_blur * 0.85) + (h_sm - 0.22) * (rm_blur * 0.85)

# Final water shaping. This must run AFTER the roads pass, otherwise the road
# smoothing fills the lake basin back in and nothing ends up below the water
# plane. Carve the lake bowl and sink the river bed so channels hold water.
h -= h.min()
lake_bowl = falloff(POI["lake"][0], POI["lake"][1], 185, 1.0, 0.44, 3)
lk = lake_bowl > 0.22
h[lk] = np.minimum(h[lk], WATER - 0.8 - lake_bowl[lk] * 5.0)
# river beds sit just under the surface so the river meshes read as water
h[river] = h[river] - 0.9
h[stream & ~river] = h[stream & ~river] - 0.35
for _ in range(2):      # soften the new banks
    sm = (np.roll(h, 1, 0) + np.roll(h, -1, 0) + np.roll(h, 1, 1) + np.roll(h, -1, 1)) * 0.25
    bank = np.clip(carve, 0, 1)
    h = h * (1 - bank * 0.35) + sm * (bank * 0.35)
h -= h.min()
slope = slope_of(h)
HMAX = float(h.max())

# ----------------------------------------------------------------- biomes
moist = np.clip(fbm(5, 4, SEED + 31) * 0.7 + la / la.max() * 0.7, 0, 1)
hn = h / max(HMAX, 1e-5)

B_GRASS, B_FARM, B_TALL, B_BAMBOO, B_ROCK, B_ALPINE, B_SHRINE, B_FOREST, B_VILLAGE, B_SHORE = range(10)
biome = np.full((N, N), B_GRASS, np.uint8)
biome[moist > 0.55] = B_FOREST
biome[(hn > 0.42) & (slope > 0.35)] = B_ROCK
biome[hn > 0.62] = B_ALPINE
def stamp(name, r, val, power=1.4, seed=0):
    f = falloff(POI[name][0], POI[name][1], r, power, 0.50, 20 + seed)
    m = f > (0.30 + 0.16 * _warp_field(60 + seed))
    biome[m] = val
stamp("forest", 300, B_FOREST, 1.4, 1)
stamp("bamboo", 250, B_BAMBOO, 1.4, 2)
stamp("grassland", 230, B_TALL, 1.4, 3)
stamp("farmland", 190, B_FARM, 1.4, 4)
stamp("village", 165, B_VILLAGE, 1.4, 5)
stamp("shrine", 140, B_SHRINE, 1.4, 6)
stamp("slope", 200, B_ROCK, 1.4, 7)
biome[(h < WATER + 1.5) & (h > WATER - 3.0)] = B_SHORE
biome[(hn > 0.66) & (slope < 0.5)] = B_ALPINE

# ----------------------------------------------------------------- splat
wetness = np.clip((la / la.max()) * 1.6, 0, 1)
grass_w = np.clip(1.0 - slope * 1.5, 0, 1) * (1.0 - np.clip((hn - 0.55) / 0.3, 0, 1))
rock_w = np.clip((slope - 0.30) * 2.2, 0, 1) + np.clip((hn - 0.58) / 0.25, 0, 1) * 0.8
dirt_w = rm_blur * 1.5 + np.clip(fbm(14, 3, SEED + 41) * 1.3 - 0.55, 0, 1)
mud_w = np.clip(wetness * 1.4 - 0.25, 0, 1) * np.clip(1.0 - slope * 2.0, 0, 1)
mud_w = np.maximum(mud_w, (np.abs(h - WATER) < 1.2) * 0.8)
# controlled irregularity so materials never tile perfectly
grass_w *= 0.75 + 0.5 * fbm(22, 3, SEED + 51)
rock_w *= 0.8 + 0.45 * fbm(26, 3, SEED + 52)
stack = np.stack([grass_w, dirt_w, rock_w, mud_w]).astype(np.float32)
stack = np.clip(stack, 0, None)
stack /= np.maximum(stack.sum(0, keepdims=True), 1e-4)
splat = (stack.transpose(1, 2, 0) * 255).astype(np.uint8)

grass_den = np.clip(grass_w * 1.5, 0, 1) * (1.0 - rm_blur * 0.9)
grass_den[biome == B_TALL] *= 1.0
grass_den[biome == B_ROCK] *= 0.25
grass_den[biome == B_ALPINE] *= 0.15
grass_den[biome == B_VILLAGE] *= 0.45
tree_den = np.zeros((N, N), np.float32)
tree_den[biome == B_FOREST] = 0.95
tree_den[biome == B_BAMBOO] = 0.85
tree_den[biome == B_GRASS] = 0.22
tree_den[biome == B_TALL] = 0.12
tree_den[biome == B_SHRINE] = 0.3
tree_den[biome == B_ROCK] = 0.18
tree_den[biome == B_ALPINE] = 0.1
tree_den[biome == B_FARM] = 0.05
tree_den[biome == B_VILLAGE] = 0.1
tree_den *= (1.0 - rm_blur * 0.95) * np.clip(1.0 - slope * 1.1, 0, 1)
tree_den *= 0.65 + 0.7 * fbm(12, 3, SEED + 61)     # clearings and dense pockets

biome_img = np.stack([
    biome.astype(np.uint8),
    (moist * 255).astype(np.uint8),
    (np.clip(grass_den, 0, 1) * 255).astype(np.uint8),
    (np.clip(tree_den, 0, 1) * 255).astype(np.uint8),
], -1)

# ----------------------------------------------------------------- scatter
def hsamp(x, z):
    xi = np.clip(int(x / CELL), 0, N - 1); zi = np.clip(int(z / CELL), 0, N - 1)
    return float(h[zi, xi])

def cell(arr, x, z):
    xi = np.clip(int(x / CELL), 0, N - 1); zi = np.clip(int(z / CELL), 0, N - 1)
    return arr[zi, xi]

TREE_FAMILIES = {
    B_FOREST: [("cedar", .34), ("maple", .26), ("pine", .2), ("dead_tree", .06), ("young_tree", .14)],
    B_BAMBOO: [("bamboo", .82), ("cedar", .08), ("young_tree", .10)],
    B_GRASS:  [("sakura", .3), ("pine", .34), ("maple", .22), ("young_tree", .14)],
    B_TALL:   [("pine", .4), ("sakura", .3), ("young_tree", .3)],
    B_SHRINE: [("sakura", .58), ("cedar", .24), ("maple", .18)],
    B_ROCK:   [("pine", .6), ("dead_tree", .28), ("young_tree", .12)],
    B_ALPINE: [("pine", .52), ("dead_tree", .48)],
    B_FARM:   [("sakura", .5), ("young_tree", .5)],
    B_VILLAGE:[("sakura", .6), ("maple", .4)],
    B_SHORE:  [("maple", .5), ("young_tree", .5)],
}

def pick(fams, r):
    t = 0.0
    for name, wt in fams:
        t += wt
        if r <= t:
            return name
    return fams[0][0]

trees, props, debris = [], [], []
# jittered-grid Poisson-ish scatter for trees
STEP = 7.0
jr = np.random.default_rng(SEED + 99)
nx = int(SIZE / STEP)
for iz in range(nx):
    for ix in range(nx):
        x = (ix + jr.random()) * STEP
        z = (iz + jr.random()) * STEP
        if not (4 < x < SIZE - 4 and 4 < z < SIZE - 4):
            continue
        d = float(cell(tree_den, x, z))
        if jr.random() > d:
            continue
        y = hsamp(x, z)
        if y < WATER + 0.7:
            continue
        b = int(cell(biome, x, z))
        fam = pick(TREE_FAMILIES.get(b, TREE_FAMILIES[B_GRASS]), jr.random())
        base = {"bamboo": 1.0, "cedar": 1.25, "maple": 1.1, "pine": 1.15,
                "sakura": 1.05, "dead_tree": 1.0, "young_tree": 0.6}[fam]
        s = base * (0.75 + jr.random() * 0.6)
        if fam == "cedar" and jr.random() < 0.05:
            s *= 1.9                      # occasional ancient giant
        trees.append({"kind": fam, "x": round(x, 1), "z": round(z, 1), "y": round(y, 2),
                      "rot": round(jr.random() * 360, 1), "s": round(s, 3)})

# ground debris / detail scatter
DEB = [("rock", .3), ("stone_small", .22), ("branch", .16), ("fern", .0), ("stump", .06),
       ("log", .07), ("flower", .12), ("mushroom", .07)]
for _ in range(9000):
    x = jr.random() * SIZE; z = jr.random() * SIZE
    y = hsamp(x, z)
    if y < WATER + 0.4:
        continue
    b = int(cell(biome, x, z))
    if jr.random() > float(cell(grass_den, x, z)) * 0.85 + 0.12:
        continue
    kind = pick([(k, w) for k, w in DEB if w > 0], jr.random())
    if kind == "mushroom" and b not in (B_FOREST, B_BAMBOO):
        continue
    if kind == "flower" and b in (B_ROCK, B_ALPINE):
        continue
    debris.append({"kind": kind, "x": round(x, 1), "z": round(z, 1), "y": round(y, 2),
                   "rot": round(jr.random() * 360, 1), "s": round(0.7 + jr.random() * 0.8, 3)})

# ------------------------------------------------- settlements & structures
def place(kind, x, z, rot=0.0, s=1.0, dy=0.0):
    props.append({"kind": kind, "x": round(x, 1), "z": round(z, 1),
                  "y": round(hsamp(x, z) + dy, 2), "rot": round(rot, 1), "s": round(s, 3)})

def settlement(cx, cz, houses, radius, kind="house", extras=True):
    for i in range(houses):
        a = jr.random() * math.tau
        r = radius * math.sqrt(jr.random())
        x, z = cx + math.cos(a) * r, cz + math.sin(a) * r
        if hsamp(x, z) < WATER + 0.8 or float(cell(slope, x, z)) > 0.35:
            continue
        place(kind, x, z, jr.random() * 360, 0.9 + jr.random() * 0.4)
        if extras and jr.random() < 0.5:
            place(pick([("barrel", .3), ("crate", .3), ("basket", .2), ("stall", .2)], jr.random()),
                  x + jr.uniform(-6, 6), z + jr.uniform(-6, 6), jr.random() * 360, 0.8 + jr.random() * 0.4)
        if extras and jr.random() < 0.35:
            place("fence", x + jr.uniform(-9, 9), z + jr.uniform(-9, 9), jr.random() * 360, 1.0)

settlement(*POI["village"], 34, 95)
settlement(*POI["farmland"], 10, 70)
settlement(*POI["grassland"], 5, 60)
for name, cnt, rad in (("bamboo", 4, 55), ("forest", 4, 60), ("slope", 3, 50)):
    settlement(*POI[name], cnt, rad)          # small outlying settlements

# shrine grounds
sx, sz = POI["shrine"]
place("shrine_hall", sx, sz + 22, 180, 1.7)
for i in range(8):
    a = math.tau * i / 8
    place("lantern", sx + math.cos(a) * 26, sz + math.sin(a) * 26, 0, 1.0)
for i in range(7):
    place("torii", sx, sz - 30 - i * 17, 0, 1.25 - i * 0.03)   # torii corridor

# castle region
cx, cz = POI["castle"]
place("castle_keep", cx, cz, 0, 2.1)
place("castle_gate", cx, cz + 52, 180, 1.6)
for i in range(16):
    a = math.tau * i / 16
    place("wall", cx + math.cos(a) * 74, cz + math.sin(a) * 74, math.degrees(a) + 90, 1.3)
for dx, dz in ((-60, 40), (60, 40), (-60, -40), (60, -40)):
    place("watchtower", cx + dx, cz + dz, jr.random() * 360, 1.35)

# ruins
rx, rz = POI["ruins"]
for i in range(16):
    place(pick([("wall", .5), ("rock", .3), ("lantern", .2)], jr.random()),
          rx + jr.uniform(-50, 50), rz + jr.uniform(-50, 50), jr.random() * 360, 0.8 + jr.random() * 0.7)

# bridges where roads cross water
bridges = []
for key, pts in roads.items():
    for (px, pz) in pts:
        if hsamp(px, pz) < WATER + 0.8:
            if all(math.hypot(px - bx, pz - bz) > 55 for bx, bz, _ in bridges):
                bridges.append((px, pz, key))
for (bx, bz, _) in bridges:
    place("bridge", bx, bz, jr.random() * 180, 1.25, dy=0.6)

# waterfalls: river cells with a large local drop
wf = []
ys, xs = np.nonzero(river)
for i in range(0, len(ys), 37):
    zi, xi = int(ys[i]), int(xs[i])
    if 2 <= zi < N - 2 and 2 <= xi < N - 2:
        loc = h[zi - 2:zi + 3, xi - 2:xi + 3]
        drop = float(loc.max() - loc.min())
        if drop > 7.0:
            x, z = xi * CELL, zi * CELL
            if all(math.hypot(x - a, z - b) > 90 for a, b, _ in wf):
                wf.append((x, z, drop))
waterfalls = [{"x": round(a, 1), "z": round(b, 1), "y": round(hsamp(a, b), 2),
               "drop": round(c, 2)} for a, b, c in wf[:8]]

# cave entrances at the base of steep rock
caves = []
cand = np.nonzero((slope > 0.85) & (h > WATER + 4) & (hn < 0.6))
for i in range(0, len(cand[0]), 401):
    zi, xi = int(cand[0][i]), int(cand[1][i])
    x, z = xi * CELL, zi * CELL
    if all(math.hypot(x - c["x"], z - c["z"]) > 160 for c in caves):
        caves.append({"x": round(x, 1), "z": round(z, 1), "y": round(hsamp(x, z), 2)})
    if len(caves) >= 6:
        break

# landmarks visible from far away
landmarks = [
    {"kind": "torii", "x": sx, "z": sz - 30, "y": round(hsamp(sx, sz - 30), 2), "rot": 0, "s": 3.4},
    {"kind": "castle_keep", "x": cx, "z": cz, "y": round(hsamp(cx, cz), 2), "rot": 0, "s": 2.1},
    {"kind": "shrine_hall", "x": sx, "z": sz + 22, "y": round(hsamp(sx, sz + 22), 2), "rot": 180, "s": 1.7},
]
for i in range(5):     # great ancient cedars as navigation beacons
    a = math.tau * i / 5
    lx = POI["forest"][0] + math.cos(a) * 120
    lz = POI["forest"][1] + math.sin(a) * 120
    landmarks.append({"kind": "cedar", "x": round(lx, 1), "z": round(lz, 1),
                      "y": round(hsamp(lx, lz), 2), "rot": round(jr.random() * 360, 1), "s": 3.1})

hidden = [{"from": "bamboo", "to": "ruins",
           "points": [[round(p[0], 1), round(p[1], 1)] for p in road_path(POI["bamboo"], POI["ruins"], h)[::4]]}]

zones = {
    "village": {"x": POI["village"][0], "z": POI["village"][1], "y": round(hsamp(*POI["village"]), 2)},
    "forest": {"x": POI["forest"][0], "z": POI["forest"][1], "y": round(hsamp(*POI["forest"]), 2)},
    "shrine": {"x": POI["shrine"][0], "z": POI["shrine"][1], "y": round(hsamp(*POI["shrine"]), 2)},
    "castle": {"x": POI["castle"][0], "z": POI["castle"][1], "y": round(hsamp(*POI["castle"]), 2)},
    "mountain": {"x": POI["mountain"][0], "z": POI["mountain"][1], "y": round(hsamp(*POI["mountain"]), 2)},
    "bamboo": {"x": POI["bamboo"][0], "z": POI["bamboo"][1], "y": round(hsamp(*POI["bamboo"]), 2)},
    "grassland": {"x": POI["grassland"][0], "z": POI["grassland"][1], "y": round(hsamp(*POI["grassland"]), 2)},
    "farmland": {"x": POI["farmland"][0], "z": POI["farmland"][1], "y": round(hsamp(*POI["farmland"]), 2)},
    "ruins": {"x": POI["ruins"][0], "z": POI["ruins"][1], "y": round(hsamp(*POI["ruins"]), 2)},
    "lake": {"x": POI["lake"][0], "z": POI["lake"][1], "y": round(hsamp(*POI["lake"]), 2)},
}

# ----------------------------------------------------------------- river map
# R = river strength, G/B = encoded downhill flow direction, A = stream mask.
# Lets the water shader push the surface along the actual channel direction.
zz_i, xx_i = np.divmod(np.arange(N * N), N)
dz_f = np.zeros(N * N, np.float32); dx_f = np.zeros(N * N, np.float32)
valid = down >= 0
dz2, dx2 = np.divmod(down[valid], N)
dz_f[valid] = (dz2 - zz_i[valid]).astype(np.float32)
dx_f[valid] = (dx2 - xx_i[valid]).astype(np.float32)
mag = np.maximum(np.sqrt(dz_f ** 2 + dx_f ** 2), 1e-4)
dz_f /= mag; dx_f /= mag
flow_x = dx_f.reshape(N, N); flow_z = dz_f.reshape(N, N)
river_img = np.stack([
    (river * 255).astype(np.uint8),
    ((flow_x * 0.5 + 0.5) * 255).astype(np.uint8),
    ((flow_z * 0.5 + 0.5) * 255).astype(np.uint8),
    (stream * 255).astype(np.uint8),
], -1)

os.makedirs(OUT, exist_ok=True)
Image.fromarray(river_img, "RGBA").save(os.path.join(OUT, "river.png"))
h.astype(np.float32).tofile(os.path.join(OUT, "heightmap.bin"))
Image.fromarray(splat, "RGBA").save(os.path.join(OUT, "splat.png"))
Image.fromarray(biome_img, "RGBA").save(os.path.join(OUT, "biome.png"))
# 16-bit height png kept as a fallback for the engine loader
h16 = (np.clip(h / max(HMAX, 1e-5), 0, 1) * 65535).astype(np.uint16)
Image.fromarray(np.stack([(h16 >> 8).astype(np.uint8), (h16 & 255).astype(np.uint8),
                          np.zeros_like(h16, np.uint8)], -1), "RGB").save(os.path.join(OUT, "height16.png"))

world = {
    "size": SIZE, "n": N, "cell": CELL, "water_level": WATER, "height_max": round(HMAX, 3),
    "seed": SEED,
    "zones": zones, "roads": roads, "props": props + debris, "trees": trees,
    "landmarks": landmarks, "hidden_paths": hidden,
    "waterfalls": waterfalls, "caves": caves,
    "lake": {"x": POI["lake"][0], "z": POI["lake"][1], "r": 175.0},
    "regions": {str(k): v for k, v in {
        B_GRASS: "grassland", B_FARM: "farmland", B_TALL: "tallgrass", B_BAMBOO: "bamboo",
        B_ROCK: "rocky", B_ALPINE: "alpine", B_SHRINE: "shrine", B_FOREST: "forest",
        B_VILLAGE: "village", B_SHORE: "shore"}.items()},
}
with open(os.path.join(OUT, "world.json"), "w") as f:
    json.dump(world, f, separators=(",", ":"))

print("WORLDGEN size=%.0fm n=%d cell=%.2fm hmax=%.1fm" % (SIZE, N, CELL, HMAX))
print("  trees=%d props=%d debris=%d roads=%d bridges=%d waterfalls=%d caves=%d"
      % (len(trees), len(props), len(debris), len(roads), len(bridges), len(waterfalls), len(caves)))
print("  land above water: %.1f%%   river cells=%d   mean slope=%.3f"
      % (100.0 * (h > WATER).mean(), int(river.sum()), float(slope.mean())))
bc = np.bincount(biome.ravel(), minlength=10)
names = ["grass", "farm", "tall", "bamboo", "rock", "alpine", "shrine", "forest", "village", "shore"]
print("  biome mix: " + "  ".join("%s=%.1f%%" % (names[i], 100.0 * bc[i] / bc.sum()) for i in range(10)))
