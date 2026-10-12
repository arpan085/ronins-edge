#!/usr/bin/env python3
"""v13: carve the main river into the terrain and describe it for the game.

The river rises at the mountain waterfall by the pass (278, 580), follows the
real drainage (priority-flood + flow accumulation on the heightmap) and is
routed with A* to keep >= ~65 m from zone centres, crossing roads as few times
as possible, down to the lake. Along the route the water surface is a
monotone (isotonic) fit of the smoothed valley floor; steep drops become
waterfalls, road crossings become shallow fords.

Reads pristine inputs from tools/terrain_src/ (so it can be re-run) and writes
into game/assets/terrain/:
  heightmap.bin   carved channel, banks and fords
  splat.png       gravel/mud bed and wet banks painted in
  river.png       old stream network cleared inside the new channel
  river_main.bin  float32[n*n] water surface height (0 = dry) + uint8[n*n]
                  bank proximity (shader wetness, 255 at the centre line)
  world.json      "river_main": points [x, surface_y, z, width, depth, flow],
                  falls, fords; trees/props in the channel removed, the
                  rest re-seated on the new ground
"""
import json, heapq, math, os, sys
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "terrain_src")
DST = os.path.join(ROOT, "game", "assets", "terrain")
W = json.load(open(os.path.join(SRC, "world.json")))
N, CELL, WL = W["n"], W["cell"], W["water_level"]
H0 = np.fromfile(os.path.join(SRC, "heightmap.bin"), dtype="<f4").reshape(N, N).astype(np.float64)
VERBOSE = "-v" in sys.argv


def hs(x, z, H=H0):
    """bilinear height at world (x, z)"""
    gx = np.clip(np.asarray(x) / CELL, 0, N - 1.001); gz = np.clip(np.asarray(z) / CELL, 0, N - 1.001)
    x0 = gx.astype(int); z0 = gz.astype(int); fx = gx - x0; fz = gz - z0
    return (H[z0, x0] * (1 - fx) * (1 - fz) + H[z0, x0 + 1] * fx * (1 - fz)
            + H[z0 + 1, x0] * (1 - fx) * fz + H[z0 + 1, x0 + 1] * fx * fz)


# ------------------------------------------------------------------ route
def route():
    h = H0[::2, ::2]; n = h.shape[0]; C = CELL * 2
    lake_def = W["lake"]
    ii, jj = np.meshgrid(np.arange(n), np.arange(n)); X = ii * C; Z = jj * C
    lake = (h < WL) & (np.hypot(X - lake_def["x"], Z - lake_def["z"]) < lake_def["r"] + 40)
    # priority flood (depression filling) towards the lake + flow accumulation
    F = h.copy(); done = lake.copy(); pq = [(h[j, i], j, i) for j, i in zip(*np.nonzero(lake))]
    heapq.heapify(pq); rec = np.full((n, n, 2), -1, np.int32)
    nb8 = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)]
    while pq:
        v, j, i = heapq.heappop(pq)
        for dj, di in nb8:
            a, b = j + dj, i + di
            if 0 <= a < n and 0 <= b < n and not done[a, b]:
                done[a, b] = True; F[a, b] = max(h[a, b], v + 1e-4); rec[a, b] = (j, i)
                heapq.heappush(pq, (F[a, b], a, b))
    acc = np.ones((n, n))
    for idx in np.argsort(-F, axis=None):
        j, i = divmod(int(idx), n); r = rec[j, i]
        if r[0] >= 0: acc[r[0], r[1]] += acc[j, i]
    cost = 1.0 + 2.5 * np.clip(1.0 - np.log(acc) / np.log(6000.0), 0, 1)
    for k, v in W["zones"].items():
        if k == "lake": continue
        d = np.hypot(X - v["x"], Z - v["z"]); cost += np.where(d < 85, 60.0 * (1 - d / 85) ** 2, 0)
    R = {"house": 10, "stall": 7, "wall": 9, "fence": 6, "watchtower": 9, "castle_gate": 16, "castle_keep": 25,
         "shrine_hall": 16, "torii": 6, "bridge": 10, "well": 6, "lantern": 3}
    block = np.zeros((n, n), bool)
    for p in W["props"] + W["landmarks"]:
        r = R.get(p["kind"])
        if r: block |= np.hypot(X - p["x"], Z - p["z"]) < r + 4
    road = np.zeros((n, n), bool)
    for pts in W["roads"].values():
        for a, b in zip(pts[:-1], pts[1:]):
            m = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) / 2))
            for t in range(m + 1):
                x = a[0] + (b[0] - a[0]) * t / m; z = a[1] + (b[1] - a[1]) * t / m
                road |= np.hypot(X - x, Z - z) < 5
    gy, gx = np.gradient(h, C); cost *= 1.0 + 2.0 * np.clip(np.hypot(gx, gy) - 0.35, 0, 2)
    start = (int(584 / C), int(278 / C))
    g = np.full((n, n), np.inf); g[start] = 0; prev = {}; pq = [(0.0, start)]; found = None
    steps = [(-1, 0, 1), (1, 0, 1), (0, -1, 1), (0, 1, 1), (-1, -1, 1.4142), (-1, 1, 1.4142), (1, -1, 1.4142), (1, 1, 1.4142)]
    while pq:
        c, (j, i) = heapq.heappop(pq)
        if c > g[j, i]: continue
        if lake[j, i]: found = (j, i); break
        for dj, di, dl in steps:
            a, b = j + dj, i + di
            if not (0 <= a < n and 0 <= b < n) or block[a, b]: continue
            nc = c + dl * C * 0.5 * (cost[j, i] + cost[a, b]) + max(0.0, F[a, b] - F[j, i]) * 45.0 \
                + (35.0 if (road[a, b] and not road[j, i]) else 0.0)
            if nc < g[a, b]:
                g[a, b] = nc; prev[(a, b)] = (j, i); heapq.heappush(pq, (nc, (a, b)))
    path = [found]
    while path[-1] != start: path.append(prev[path[-1]])
    path.reverse()
    # two cells into the lake so the ribbon meets open water
    return np.array([(i * C, j * C) for j, i in path], dtype=np.float64)


def chaikin(P, it=3):
    for _ in range(it):
        Q = [P[0]]
        for a, b in zip(P[:-1], P[1:]):
            Q.append(0.75 * a + 0.25 * b); Q.append(0.25 * a + 0.75 * b)
        Q.append(P[-1]); P = np.array(Q)
    return P


def resample(P, step):
    d = np.r_[0, np.cumsum(np.hypot(*np.diff(P, axis=0).T))]
    s = np.arange(0, d[-1], step)
    return np.c_[np.interp(s, d, P[:, 0]), np.interp(s, d, P[:, 1])], s


def isotonic_decreasing(y, w=None):
    """least-squares non-increasing fit (pool adjacent violators)"""
    y = list(y); w = [1.0] * len(y) if w is None else list(w)
    blocks = []  # [value, weight, count]
    for v, ww in zip(y, w):
        blocks.append([v, ww, 1])
        while len(blocks) > 1 and blocks[-2][0] < blocks[-1][0]:
            v2, w2, c2 = blocks.pop(); v1, w1, c1 = blocks.pop()
            blocks.append([(v1 * w1 + v2 * w2) / (w1 + w2), w1 + w2, c1 + c2])
    out = []
    for v, _, c in blocks: out += [v] * c
    return np.array(out)


def smooth(a, k):
    k = max(1, k | 1); pad = k // 2
    ap = np.r_[np.full(pad, a[0]), a, np.full(pad, a[-1])]
    return np.convolve(ap, np.ones(k) / k, mode="valid")


def median(a, k):
    pad = k // 2; ap = np.r_[np.full(pad, a[0]), a, np.full(pad, a[-1])]
    return np.array([np.median(ap[i:i + k]) for i in range(len(a))])


def road_mask():
    road = np.zeros((N, N), bool)
    ii, jj = np.meshgrid(np.arange(N), np.arange(N))
    for pts in W["roads"].values():
        for a, b in zip(pts[:-1], pts[1:]):
            m = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) / 1.5))
            for t in range(m + 1):
                x = a[0] + (b[0] - a[0]) * t / m; z = a[1] + (b[1] - a[1]) * t / m
                i0, i1 = max(0, int((x - 6) / CELL)), min(N, int((x + 6) / CELL) + 2)
                j0, j1 = max(0, int((z - 6) / CELL)), min(N, int((z + 6) / CELL) + 2)
                sub = np.hypot(ii[j0:j1, i0:i1] * CELL - x, jj[j0:j1, i0:i1] * CELL - z) < 3.5
                road[j0:j1, i0:i1] |= sub
    return road


def profile():
    raw = route()
    P, S = resample(chaikin(raw, 3), 2.0)
    # settle the line into the valley floor: A* on a 4 m grid happily runs
    # along a hillside, which leaves one bank below the water. Move each point
    # (smoothly, at most ~12 m) toward the lowest ground across the channel.
    offs = np.arange(-14.0, 14.5, 1.0)
    for _ in range(3):
        tan = np.gradient(P, axis=0); tan /= np.linalg.norm(tan, axis=1)[:, None]
        nrm = np.c_[-tan[:, 1], tan[:, 0]]
        sh = np.zeros(len(P))
        for k in range(len(P)):
            hh = hs(P[k, 0] + nrm[k, 0] * offs, P[k, 1] + nrm[k, 1] * offs)
            hh = np.convolve(np.r_[hh[0], hh[0], hh, hh[-1], hh[-1]], np.ones(5) / 5, mode="valid")
            sh[k] = offs[int(np.argmin(hh + 0.012 * offs ** 2))]
        sh = smooth(sh, 21) * 0.7
        sh[:4] = 0; sh[-4:] = 0
        P = P + nrm * sh[:, None]
        P, S = resample(P, 2.0)
    L = S[-1]
    tan = np.gradient(P, axis=0); tan /= np.linalg.norm(tan, axis=1)[:, None]
    nrm = np.c_[-tan[:, 1], tan[:, 0]]
    u = S / L
    width = 4.5 + 7.0 * u ** 0.8
    depth = 0.75 + 0.45 * u
    floor = np.minimum.reduce([hs(P[:, 0] + nrm[:, 0] * o * (width + 6.0), P[:, 1] + nrm[:, 1] * o * (width + 6.0))
                               for o in (-0.5, -0.25, 0.0, 0.25, 0.5)])
    # the mouth: stop where the ground falls to the lake; the last stretch is a fall into it
    # (v13b: at the channel OR either bank -- the path can run along the
    # shore hillside with the lake just below one bank, and water there
    # would hang in the air on the open side)
    mouth = len(S) - 1
    for k in range(len(S)):
        if S[k] <= L * 0.8: continue
        wk = width[k] * 0.5 + 2.0
        gl = hs(P[k, 0] + nrm[k, 0] * wk, P[k, 1] + nrm[k, 1] * wk)
        gr = hs(P[k, 0] - nrm[k, 0] * wk, P[k, 1] - nrm[k, 1] * wk)
        if min(hs(P[k, 0], P[k, 1]), gl, gr) < WL + 0.8: mouth = k; break
    target = smooth(median(floor, 9), 9) - 0.45
    # asymmetric monotone fit: water standing above the ground needs levees,
    # so over-filling is weighted 6x against cutting a little deeper
    surf = isotonic_decreasing(target)
    for _ in range(6):
        surf = isotonic_decreasing(target, np.where(surf > target, 6.0, 1.0))
    # the last stretch before the lake: the lip is where the shore starts to plunge
    lip = mouth
    while lip > 0 and S[mouth] - S[lip] < 40:
        a, b = lip - 3, min(mouth, lip + 3)
        if (floor[a] - floor[b]) / max(1e-3, S[b] - S[a]) < 0.22 and floor[lip] > WL + 3.0: break
        lip -= 1
    # Only a real cliff gets one big fall into the lake. A shore that slopes
    # down over tens of metres (v13 first pass: 12 m over 38 m) left the fall
    # sheet landing on dry hillside; there the river runs on down as rapids
    # and tiered falls and meets the lake at its own level.
    cliff = S[mouth] - S[lip] <= 10.0
    if cliff:
        surf[lip + 1:] = WL
    else:
        lip = mouth
        surf = np.maximum(surf, WL)
        surf[mouth:] = WL
    # steep stretches -> tiered waterfalls: each lip sits at the top of its
    # tier and the pool below is cut down to the next tier's level (max ~5 m)
    falls = []
    sl = np.zeros(len(S))
    for k in range(len(S)):
        a, b = max(0, k - 4), min(len(S) - 1, k + 4)
        sl[k] = (surf[a] - surf[b]) / max(1e-3, S[b] - S[a])
    k = 6
    while k < lip - 4:
        if sl[k] > 0.30:
            a = k
            while k < lip - 4 and sl[k] > 0.16: k += 1
            b = k
            if surf[a] - surf[b] >= 2.5:
                tiers = max(1, int(math.ceil((surf[a] - surf[b]) / 5.0)))
                levels = np.linspace(surf[a], surf[b], tiers + 1)
                lips = [a]
                for t in range(1, tiers):
                    lips.append(int(np.argmin(np.abs(surf[a:b + 1] - levels[t]))) + a)
                lips.append(b)
                for t in range(tiers):
                    la, lb = lips[t], lips[t + 1]
                    top, bot = float(surf[la]), float(surf[lb])
                    surf[la + 1:lb + 1] = bot
                    falls.append({"k": int(la), "top": top, "bottom": bot, "drop": top - bot})
        k += 1
    if cliff:
        falls.append({"k": int(lip), "top": float(surf[lip]), "bottom": float(WL), "drop": float(surf[lip] - WL), "lake": True})
        mouth = lip + 1
    elif surf[mouth - 1] - WL > 1.2:
        # the last step down into the lake is too tall for rapids
        falls.append({"k": int(mouth - 1), "top": float(surf[mouth - 1]), "bottom": float(WL),
                      "drop": float(surf[mouth - 1] - WL), "lake": True})
    # rapids: shallower and a little narrower where it runs fast
    fast = np.clip((sl - 0.04) / 0.14, 0, 1)
    fast[[f["k"] for f in falls]] = 0
    depth *= 1.0 - 0.45 * fast
    width *= 1.0 - 0.18 * fast
    n_keep = min(len(S), mouth + 1)
    return P[:n_keep], S[:n_keep], surf[:n_keep], width[:n_keep], depth[:n_keep], fast[:n_keep], falls, nrm[:n_keep], tan[:n_keep]


def carve(P, S, surf, width, depth, fast, falls, fords, ford_w, tan):
    n = len(S)
    H = H0.copy()
    best = np.full((N, N), np.inf); bk = np.full((N, N), -1, np.int32); bt = np.zeros((N, N))
    ii, jj = np.meshgrid(np.arange(N), np.arange(N))
    R = width.max() * 0.5 + 16.0
    for k in range(n - 1):
        a, b = P[k], P[k + 1]
        i0 = max(0, int((min(a[0], b[0]) - R) / CELL)); i1 = min(N, int((max(a[0], b[0]) + R) / CELL) + 2)
        j0 = max(0, int((min(a[1], b[1]) - R) / CELL)); j1 = min(N, int((max(a[1], b[1]) + R) / CELL) + 2)
        X = ii[j0:j1, i0:i1] * CELL; Z = jj[j0:j1, i0:i1] * CELL
        ab = b - a; L2 = max(1e-9, ab @ ab)
        t = np.clip(((X - a[0]) * ab[0] + (Z - a[1]) * ab[1]) / L2, 0, 1)
        d = np.hypot(X - (a[0] + ab[0] * t), Z - (a[1] + ab[1] * t))
        sub = best[j0:j1, i0:i1]; upd = d < sub
        sub[upd] = d[upd]; bk[j0:j1, i0:i1][upd] = k; bt[j0:j1, i0:i1][upd] = t[upd]
    m = np.isfinite(best) & (best < R)
    # nothing past the two ends of the line (the spring and the lake lip)
    m &= ~((bk == 0) & (bt <= 0.0)) & ~((bk == n - 2) & (bt >= 1.0))
    k = bk[m]; t = bt[m]; d = best[m]
    lerp = lambda arr: arr[k] * (1 - t) + arr[k + 1] * t
    ys = lerp(surf); w = lerp(width); D = lerp(depth); fw = lerp(ford_w)
    # the lake lip: no interpolation onto the lake level past the lip
    last = n - 2
    ys = np.where(k >= last, surf[last], ys)
    half = w * 0.5
    orig = H[m]
    cut = orig - ys
    bank_slope = 0.55 + 0.6 * np.clip((cut - 2.0) / 4.0, 0, 1)
    bank_slope = bank_slope * (1 - fw) + 0.2 * fw
    uu = np.clip(d / half, 0, 1)
    bed = ys - D * (1 - uu ** 2) + 0.06 * uu ** 2
    e = np.maximum(0.0, d - half)
    bank = ys + 0.06 + e * bank_slope
    new = np.where(d <= half, np.minimum(orig, bed), np.minimum(orig, bank))
    # low ground beside the water: a soft levee so the surface never hangs in the air
    lev = ys + 0.3 - np.maximum(0.0, e - 2.5) * 0.25
    lev = np.minimum(lev, orig + 2.4)   # v13b: +1.0 left 12 spots perched up to 1.25 m
    new = np.where((d > half) & (lev > new) & (k < n - 4), lev, new)
    H[m] = new
    # ---- outputs: water surface + bank proximity
    surf_map = np.zeros((N, N), np.float32)
    wet = d <= half + 1.0
    sm = surf_map[m]; sm[wet] = ys[wet]; surf_map[m] = sm
    prox = np.zeros((N, N), np.uint8)
    prox[m] = (255 * np.clip(1.0 - e / 12.0, 0, 1)).astype(np.uint8)
    with open(os.path.join(DST, "river_main.bin"), "wb") as f:
        f.write(surf_map.astype("<f4").tobytes()); f.write(prox.tobytes())
    H.astype("<f4").tofile(os.path.join(DST, "heightmap.bin"))
    dh = H - H0
    print("carved %d vertices: lowered max %.1f m, raised max %.1f m" % ((np.abs(dh) > 0.01).sum(), -dh.min(), dh.max()))
    # ---- splat: gravel/mud bed, wet banks, rock on the cut walls
    sp = np.asarray(Image.open(os.path.join(SRC, "splat.png")).convert("RGBA")).astype(np.float64) / 255.0
    gy, gx = np.gradient(H, CELL); slope = np.hypot(gx, gy)
    tgt_bed = np.array([0.04, 0.22, 0.46, 0.28]); tgt_bank = np.array([0.12, 0.28, 0.14, 0.46])
    tgt_ford = np.array([0.05, 0.62, 0.18, 0.15])
    cur = sp[m]
    ub = np.clip(d / half, 0, 3)
    wbed = np.clip((1.0 - ub) / 0.15 + 0.0, 0, 1)
    wbank = np.clip(1.0 - np.maximum(0, e - 1.0) / 4.0, 0, 1)
    tb = tgt_bed[None, :] * (1 - fw[:, None]) + tgt_ford[None, :] * fw[:, None]
    tk = tgt_bank[None, :] * (1 - fw[:, None]) + tgt_ford[None, :] * fw[:, None]
    mix_bank = cur * (1 - wbank[:, None]) + tk * wbank[:, None]
    out = mix_bank * (1 - wbed[:, None]) + tb * wbed[:, None]
    walls = np.clip((slope[m] - 0.55) / 0.4, 0, 1) * (np.abs(dh[m]) > 0.3)
    out = out * (1 - walls[:, None]) + np.array([0.05, 0.15, 0.75, 0.05])[None, :] * walls[:, None]
    out /= np.maximum(1e-6, out.sum(axis=1, keepdims=True))
    sp[m] = out
    Image.fromarray((np.clip(sp, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(DST, "splat.png"))
    # ---- old stream network: clear it inside the new channel
    rv = np.asarray(Image.open(os.path.join(SRC, "river.png")).convert("RGBA")).copy()
    clr = np.zeros((N, N), bool); clr[m] = e < 4.0
    rv[clr, 0] = 0; rv[clr, 3] = 0
    Image.fromarray(rv, "RGBA").save(os.path.join(DST, "river.png"))
    # ---- world.json
    Wn = json.load(open(os.path.join(SRC, "world.json")))
    def local(x, z):
        i = int(round(x / CELL)); j = int(round(z / CELL))
        if not (0 <= i < N and 0 <= j < N): return None
        return best[j, i], i, j
    removed = {"trees": 0, "props": 0}; reseated = 0
    keep_t = []
    for tr in Wn["trees"]:
        r = local(tr["x"], tr["z"])
        if r is None or not np.isfinite(r[0]) or r[0] >= R: keep_t.append(tr); continue
        dd, i, j = r
        hw = width[bk[j, i]] * 0.5
        change = H[j, i] - H0[j, i]
        if dd < hw + 2.0 or change < -0.6: removed["trees"] += 1; continue
        if abs(change) > 0.02: tr["y"] = round(float(hs(tr["x"], tr["z"], H)) - 0.05, 2); reseated += 1
        keep_t.append(tr)
    Wn["trees"] = keep_t
    small = {"rock", "stone_small"}
    keep_p = []
    for pr in Wn["props"]:
        r = local(pr["x"], pr["z"])
        if r is None or not np.isfinite(r[0]) or r[0] >= R: keep_p.append(pr); continue
        dd, i, j = r
        kk = bk[j, i]; hw = width[kk] * 0.5
        change = H[j, i] - H0[j, i]
        if pr["kind"] in small:
            if ford_w[kk] > 0.05 and dd < hw + 6: removed["props"] += 1; continue
        elif dd < hw + 1.5 or change < -0.8:
            if pr["kind"] not in ("flower", "mushroom", "branch", "log", "stump"):
                print("  WARNING removing", pr["kind"], pr["x"], pr["z"])
            removed["props"] += 1; continue
        if abs(change) > 0.02:
            pr["y"] = round(float(hs(pr["x"], pr["z"], H)) - (0.25 if pr["kind"] in small else 0.03), 2); reseated += 1
        keep_p.append(pr)
    Wn["props"] = keep_p
    # the old mountain fall sat where the new river rises
    Wn["waterfalls"] = [f for f in Wn["waterfalls"] if math.hypot(f["x"] - P[0, 0], f["z"] - P[0, 1]) > 25]
    # river rocks around the spring
    rng = np.random.default_rng(13)
    for a in np.linspace(0, 2 * math.pi, 7, endpoint=False):
        x = P[0, 0] - tan[0, 0] * 2.5 + math.cos(a) * rng.uniform(2.6, 3.6)
        z = P[0, 1] - tan[0, 1] * 2.5 + math.sin(a) * rng.uniform(2.6, 3.6)
        Wn["props"].append({"kind": "rock", "x": round(x, 1), "z": round(z, 1), "y": round(float(hs(x, z, H)) - 0.3, 2),
                            "rot": round(float(rng.uniform(0, 360)), 1), "s": round(float(rng.uniform(0.7, 1.3)), 2)})
    pts = [[round(float(P[k, 0]), 2), round(float(surf[k]), 3), round(float(P[k, 1]), 2), round(float(width[k]), 2),
            round(float(depth[k]), 2), round(float(fast[k]), 2)] for k in range(n)]
    def fall_dir(f):
        """the lip's heading; a fall into the lake also leans toward the
        steepest way down, so it spills over the open side"""
        t = tan[f["k"]].copy()
        if f.get("lake", False):
            x, z = P[f["k"], 0], P[f["k"], 1]
            g = np.array([hs(x + 4, z) - hs(x - 4, z), hs(x, z + 4) - hs(x, z - 4)])
            if np.linalg.norm(g) > 0.2: t = t - 1.5 * g / np.linalg.norm(g)
        return t / max(1e-6, np.linalg.norm(t))
    Wn["river_main"] = {
        "points": pts,
        "falls": [{"k": f["k"], "x": round(float(P[f["k"], 0]), 2), "z": round(float(P[f["k"], 1]), 2),
                   "top": round(f["top"], 2), "bottom": round(f["bottom"], 2), "width": round(float(width[f["k"]]), 2),
                   "dx": round(float(fall_dir(f)[0]), 4), "dz": round(float(fall_dir(f)[1]), 4), "lake": bool(f.get("lake", False))}
                  for f in falls],
        "fords": [[round(float(P[f, 0]), 1), round(float(P[f, 1]), 1)] for f in fords],
    }
    json.dump(Wn, open(os.path.join(DST, "world.json"), "w"), separators=(",", ":"))
    print("removed %d trees, %d props; re-seated %d" % (removed["trees"], removed["props"], reseated))
    for hp in Wn.get("hidden_paths", []):
        for q in hp.get("points", []):
            r = local(q[0], q[1])
            if r and np.isfinite(r[0]) and r[0] < 8: print("  WARNING hidden reward near the river", q)


if __name__ == "__main__":
    P, S, surf, width, depth, fast, falls, nrm, tan = profile()
    road = road_mask()
    # fords where the river meets a road
    on_road = np.array([road[int(round(z / CELL)), int(round(x / CELL))] for x, z in P])
    fords = []
    k = 0
    while k < len(S):
        if on_road[k]:
            a = k
            while k < len(S) and on_road[k]: k += 1
            fords.append((a + k) // 2)
        k += 1
    ford_w = np.zeros(len(S))
    for f in fords:
        ford_w = np.maximum(ford_w, np.clip(1.0 - np.abs(S - S[f]) / 14.0, 0, 1))
    ford_w = np.clip(ford_w * 1.6, 0, 1)
    depth = depth * (1 - ford_w) + 0.3 * ford_w
    cutc = hs(P[:, 0], P[:, 1]) - surf
    print("length %.0f m, %d pts, surface %.1f -> %.1f; cut max %.1f fill max %.1f" % (S[-1], len(S), surf[0], surf[-1], cutc.max(), -cutc.min()))
    for f in falls: print("fall at s=%.0f (%.0f, %.0f) drop %.1f%s" % (S[f["k"]], P[f["k"], 0], P[f["k"], 1], f["drop"], " into the lake" if f.get("lake") else ""))
    for f in fords: print("ford at s=%.0f (%.0f, %.0f) bank cut %.1f" % (S[f], P[f, 0], P[f, 1], cutc[f]))
    np.savez("/tmp/river/profile.npz", P=P, S=S, surf=surf, width=width, depth=depth, fast=fast, nrm=nrm, tan=tan, ford=ford_w)
    carve(P, S, surf, width, depth, fast, falls, fords, ford_w, tan)
