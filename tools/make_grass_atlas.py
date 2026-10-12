#!/usr/bin/env python3
"""v0.15 grass card atlas.

Builds game/assets/textures/foliage/grass_atlas.png (2048x2048 RGBA) out of
Poly Haven CC0 scans (grass_medium_01, grass_medium_02, grass_bermuda_01,
fern_02, dandelion_01; https://polyhaven.com, CC0). Sources live in
tools/grass_src/ (fetch: https://dl.polyhaven.org/file/ph-assets/Models/
{jpg,png}/2k/<id>/<id>_{diff,alpha}_2k.*).

Cells are side views of whole clumps with the roots on the bottom edge, so a
card stands on the ground at v = 1. Colour is bled into the transparent area
so mip-maps do not pick up a dark fringe. tools/grass_atlas.json lists the
cells; world/Foliage.gd's VARIANTS mirror it.
"""
import json, math, os, random, sys
import numpy as np, cv2
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "grass_src")
OUT = os.path.join(HERE, "..", "game", "assets", "textures", "foliage", "grass_atlas.png")
W = H = 2048

def load(name, dry=False):
    d = np.array(Image.open(os.path.join(SRC, f"{name}_{'dry_diff' if dry else 'diff'}_2k.jpg")).convert("RGB")).astype(np.float32) / 255.0
    a = np.array(Image.open(os.path.join(SRC, f"{name}_alpha_2k.png"))).astype(np.float32)
    a /= max(a.max(), 1.0)
    # the scans' alpha carries faint smears from the bake; harden it a little
    a = np.clip((a - 0.22) / 0.56, 0.0, 1.0)
    return d, a

def rgba(d, a, box):
    x0, y0, x1, y1 = box
    return np.dstack([d[y0:y1, x0:x1], a[y0:y1, x0:x1]]).copy()

def keep_main(img, min_area=60):
    """drop little islands (bake debris) that are not part of the clump"""
    m = (img[..., 3] > 0.35).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(m, connectivity=8)
    keep = np.zeros(n, bool)
    for i in range(1, n):
        if st[i, cv2.CC_STAT_AREA] >= min_area: keep[i] = True
    mask = keep[lab]
    soft = cv2.dilate(mask.astype(np.uint8), np.ones((3, 3), np.uint8)).astype(bool)
    img[..., 3] *= soft
    return img

def premul_resize(img, w, h):
    rgb = img[..., :3] * img[..., 3:4]
    t = np.dstack([rgb, img[..., 3]])
    out = cv2.resize(t, (w, h), interpolation=cv2.INTER_AREA if w < img.shape[1] else cv2.INTER_CUBIC)
    out = np.clip(out, 0, 1)
    a = out[..., 3:4]
    rgb = np.where(a > 1e-4, out[..., :3] / np.maximum(a, 1e-4), 0.0)
    return np.dstack([np.clip(rgb, 0, 1), a[..., 0]])

def rotate(img, deg, pivot):
    """rotate RGBA float image about pivot (x, y) on a canvas big enough to keep it"""
    h, w = img.shape[:2]
    pad = int(math.hypot(w, h))
    big = np.zeros((h + 2 * pad, w + 2 * pad, 4), np.float32)
    big[pad:pad + h, pad:pad + w] = img
    px, py = pivot[0] + pad, pivot[1] + pad
    M = cv2.getRotationMatrix2D((px, py), deg, 1.0)
    pm = np.dstack([big[..., :3] * big[..., 3:4], big[..., 3]])
    r = cv2.warpAffine(pm, M, (big.shape[1], big.shape[0]), flags=cv2.INTER_CUBIC, borderValue=(0, 0, 0, 0))
    r = np.clip(r, 0, 1)
    a = r[..., 3:4]
    rgb = np.where(a > 1e-4, r[..., :3] / np.maximum(a, 1e-4), 0.0)
    return np.dstack([np.clip(rgb, 0, 1), a[..., 0]]), (px, py)

def over(dst, src, x, y):
    """composite src (RGBA float) onto dst at integer offset, clipped"""
    h, w = src.shape[:2]
    H2, W2 = dst.shape[:2]
    sx0 = max(0, -x); sy0 = max(0, -y)
    dx0 = max(0, x); dy0 = max(0, y)
    dx1 = min(W2, x + w); dy1 = min(H2, y + h)
    if dx1 <= dx0 or dy1 <= dy0: return
    s = src[sy0:sy0 + (dy1 - dy0), sx0:sx0 + (dx1 - dx0)]
    d = dst[dy0:dy1, dx0:dx1]
    sa = s[..., 3:4]
    da = d[..., 3:4]
    oa = sa + da * (1 - sa)
    orgb = (s[..., :3] * sa + d[..., :3] * da * (1 - sa)) / np.maximum(oa, 1e-5)
    dst[dy0:dy1, dx0:dx1] = np.dstack([orgb, oa[..., 0]])

def bbox(img, thr=0.3):
    ys, xs = np.where(img[..., 3] > thr)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1

def fit_cell(img, cw, ch, pad=10, bottom=4):
    """scale content to the cell, roots on the bottom edge, centred"""
    x0, y0, x1, y1 = bbox(img)
    img = img[y0:y1, x0:x1]
    h, w = img.shape[:2]
    s = min((cw - 2 * pad) / w, (ch - pad - bottom) / h)
    nw, nh = max(1, int(w * s)), max(1, int(h * s))
    r = premul_resize(img, nw, nh)
    cell = np.zeros((ch, cw, 4), np.float32)
    over(cell, r, (cw - nw) // 2, ch - bottom - nh)
    return cell

def grade(img, sat=1.0, gain=1.0, tint=(1, 1, 1)):
    rgb = img[..., :3]
    l = (rgb * np.array([0.2126, 0.7152, 0.0722])).sum(-1, keepdims=True)
    rgb = l + (rgb - l) * sat
    rgb = rgb * gain * np.array(tint, np.float32)
    img[..., :3] = np.clip(rgb, 0, 1)
    return img

def root_shade(cell, depth=0.22, amount=0.45):
    """darken toward the roots: the base of a clump sits in its own shadow"""
    ch = cell.shape[0]
    y = np.linspace(0, 1, ch)[:, None]
    k = 1.0 - amount * np.clip((y - (1 - depth)) / depth, 0, 1) ** 1.3
    cell[..., :3] *= k[..., None]
    return cell

# ---------------------------------------------------------------- sources
m01, m01a = load("grass_medium_01")
m01d, _ = load("grass_medium_01", dry=True)
m02, m02a = load("grass_medium_02")
ber, bera = load("grass_bermuda_01")
fern, ferna = load("fern_02")
dan, dana = load("dandelion_01")

CLUMPS = {   # grass_medium_01's own clump cards (x0, y0, x1, y1), roots at y1
    "A": (395, 1520, 1000, 1801), "B": (1190, 1545, 1685, 1747),
    "D": (480, 1815, 1005, 2011), "E": (1175, 1760, 1625, 2016),
    "C": (35, 1775, 400, 1992),
}

def clump(key, dry=False):
    img = rgba(m01d if dry else m01, m01a, CLUMPS[key])
    return keep_main(img, 120)

def pieces(d, a, thr=0.4, min_area=4000, dil=5):
    m = (a > thr).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(cv2.dilate(m, np.ones((dil, dil), np.uint8)))
    out = []
    for i in range(1, n):
        x, y, w, h, ar = st[i]
        if ar < min_area: continue
        sub = np.dstack([d[y:y + h, x:x + w], a[y:y + h, x:x + w] * (lab[y:y + h, x:x + w] == i)])
        out.append(sub.astype(np.float32))
    return out

def upright(p):
    """blade/frond with its root at the bottom: the root end is the wider one"""
    h, w = p.shape[:2]
    if w > h * 1.3:
        p = np.rot90(p, 1).copy(); h, w = w, h
    al = p[..., 3] > 0.4
    top = al[: max(1, h // 8)].sum(); bot = al[-max(1, h // 8):].sum()
    if top > bot * 1.15: p = p[::-1].copy()
    return p

blades = [upright(p) for p in pieces(m02, m02a, min_area=9000)]
blades = [b for b in blades if b.shape[0] > 500]
def _is_dry(b):
    m = b[..., 3] > 0.5
    r, g, bb = [b[..., i][m].mean() for i in range(3)]
    return r > g * 0.88 or (0.2126 * r + 0.7152 * g + 0.0722 * bb) > 0.42
dry_blades = [b for b in blades if _is_dry(b)]
blades = [b for b in blades if not _is_dry(b)] or blades
def stretch(img, sx, sy):
    h, w = img.shape[:2]
    return premul_resize(img, max(2, int(w * sx)), max(2, int(h * sy)))
sprigs = [upright(p) for p in pieces(ber, bera, min_area=15000, dil=9)]
fronds = [p for p in pieces(fern, ferna, min_area=100000, dil=9)]
heads = [p for p in pieces(dan, dana, thr=0.5, min_area=90000) if p.shape[0] < 520 and p.shape[1] < 520 and p.shape[0] > 380]
leaves = [upright(p) for p in pieces(dan, dana, thr=0.5, min_area=150000) if p.shape[0] > 1000 and p.shape[1] < 600]
print("blades", len(blades), "dry", len(dry_blades), "leaves", len(leaves), "sprigs", len(sprigs),
      "fronds", len(fronds), "heads", len(heads), file=sys.stderr)

def fan(cw, ch, items, n, rng, hmin, hmax, spread_deg, base_w, dark_back=0.72, dry_mix=0.0, wscale=1.0):
    """fan `n` items up from a root zone `base_w` wide; back items darker"""
    S = 2  # work at 2x then downsample
    canvas = np.zeros((ch * S, cw * S, 4), np.float32)
    for k in range(n):
        it = items[rng.randrange(len(items))]
        h = it.shape[0]
        th = rng.uniform(hmin, hmax) * ch * S
        s = th / h
        img = premul_resize(it, max(2, int(it.shape[1] * s * wscale * rng.uniform(0.8, 1.2))), max(2, int(h * s)))
        bx = rng.uniform(-0.5, 0.5)
        ang = rng.gauss(0, spread_deg * 0.45) + bx * spread_deg * 0.9
        img, piv = rotate(img, -ang, (img.shape[1] / 2, img.shape[0] - 1))
        depth = k / max(1, n - 1)           # 0 back .. 1 front
        g = dark_back + (1 - dark_back) * depth
        img[..., :3] *= g
        if dry_mix > 0:
            l = (img[..., :3] * np.array([0.2126, 0.7152, 0.0722])).sum(-1, keepdims=True)
            straw = np.array([0.80, 0.70, 0.45]) * (l / 0.40)
            img[..., :3] = np.clip(img[..., :3] * (1 - dry_mix) + straw * dry_mix, 0, 1)
        rx = cw * S / 2 + bx * base_w * cw * S
        over(canvas, img, int(rx - piv[0]), int(ch * S - 3 - piv[1]))
    return premul_resize(canvas, cw, ch)

def plumes(cell, rng, n, color=(0.86, 0.80, 0.66), stem_h=(0.75, 0.98)):
    """susuki seed heads: a stem and a feather of fine silky spikelets"""
    ch, cw = cell.shape[:2]
    S = 3
    lay = Image.new("RGBA", (cw * S, ch * S), (0, 0, 0, 0))
    dr = ImageDraw.Draw(lay)
    for _ in range(n):
        x0 = cw * S * (0.5 + rng.uniform(-0.28, 0.28))
        top = ch * S * (1.0 - rng.uniform(*stem_h))
        lean = rng.uniform(-0.25, 0.25)
        pts = []
        steps = 18
        for i in range(steps + 1):
            t = i / steps
            y = ch * S - 2 - (ch * S - 2 - top) * t
            x = x0 + lean * (ch * S - y) * 0.35 + math.sin(t * 2.2) * lean * 20
            pts.append((x, y))
        dr.line(pts, fill=(92, 104, 52, 255), width=int(2.2 * S))
        tipx, tipy = pts[-1]
        bend = rng.choice([-1, 1]) * rng.uniform(0.3, 0.9)
        length = (ch * S - top) * rng.uniform(0.26, 0.36)
        c = tuple(int(255 * v * rng.uniform(0.9, 1.05)) for v in color)
        for j in range(140):
            t = j / 140.0
            sx = tipx + bend * length * 0.35 * t * t
            sy = tipy + length * t
            al = rng.uniform(-1.0, 1.0)
            ln = length * rng.uniform(0.18, 0.42) * (1.0 - 0.6 * t)
            ex = sx + math.sin(al) * ln * 0.55 + bend * ln * 0.5
            ey = sy - math.cos(al) * ln * 0.25 + ln * 0.55
            dr.line([(sx, sy), ((sx + ex) / 2 + bend * 3, (sy + ey) / 2), (ex, ey)],
                    fill=c + (int(255 * rng.uniform(0.8, 1.0)),), width=max(1, int(1.6 * S)))
    lay = lay.resize((cw, ch), Image.LANCZOS)
    p = np.array(lay).astype(np.float32) / 255.0
    over(cell, p, 0, 0)
    return cell

def flowers(cell, rng, n, kind):
    ch, cw = cell.shape[:2]
    for _ in range(n):
        hd = heads[rng.randrange(len(heads))].copy()
        if kind == "white":
            l = (hd[..., :3] * np.array([0.2126, 0.7152, 0.0722])).sum(-1, keepdims=True)
            hd[..., :3] = np.clip(0.55 + l * 0.6, 0, 1) * np.array([1.0, 0.98, 0.95])
        elif kind == "purple":
            l = (hd[..., :3] * np.array([0.2126, 0.7152, 0.0722])).sum(-1, keepdims=True)
            hd[..., :3] = np.clip(l * 1.25, 0, 1) * np.array([0.62, 0.48, 0.92])
        sz = int(rng.uniform(0.07, 0.12) * ch)
        hd = premul_resize(hd, sz, sz)
        x = int(cw * (0.5 + rng.uniform(-0.40, 0.40)))
        top = int(ch * (1 - rng.uniform(0.45, 0.85)))
        st = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
        ImageDraw.Draw(st).line([(x + rng.uniform(-6, 6), ch - 2), (x, top + sz // 2)], fill=(70, 96, 40, 255), width=2)
        over(cell, np.array(st).astype(np.float32) / 255.0, 0, 0)
        over(cell, hd, x - sz // 2, top)
    return cell

def bleed(cell):
    """fill transparent texels with nearby colour so mips stay clean"""
    a = cell[..., 3]
    rgb = cell[..., :3] * a[..., None]
    acc = np.zeros_like(rgb); wsum = np.zeros_like(a)
    for k in (3, 9, 27, 81):
        acc += cv2.blur(rgb, (k, k)) * (1.0 / k)
        wsum += cv2.blur(a, (k, k)) * (1.0 / k)
    fill = acc / np.maximum(wsum, 1e-5)[..., None]
    mean = rgb.sum((0, 1)) / max(a.sum(), 1e-5)
    fill = np.where((wsum > 1e-4)[..., None], fill, mean)
    cell[..., :3] = np.where((a > 0.02)[..., None], cell[..., :3], fill)
    return cell

# ---------------------------------------------------------------- layout
rng = random.Random(1515)
atlas = np.zeros((H, W, 4), np.float32)
table = []
def put(name, cell, x, y, h_m, cat):
    cell = bleed(root_shade(cell))
    ch, cw = cell.shape[:2]
    atlas[y:y + ch, x:x + cw] = cell
    table.append({"name": name, "cat": cat, "rect": [x / W, y / H, cw / W, ch / H],
                  "w_m": round(h_m * cw / ch, 3), "h_m": h_m})

CW, CH = 512, 256
# rows 0-1: meadow clumps (scanned)
put("medA", fit_cell(clump("A"), CW, CH), 0, 0, 0.50, "medium")
put("medB", fit_cell(clump("B"), CW, CH), 512, 0, 0.46, "medium")
put("medD", fit_cell(clump("D"), CW, CH), 1024, 0, 0.42, "medium")
put("medE", fit_cell(clump("E"), CW, CH), 1536, 0, 0.55, "medium")
put("dryA", fit_cell(grade(clump("A", True), 0.9, 1.0), CW, CH), 0, 256, 0.50, "dry")
put("dryB", fit_cell(grade(clump("B", True), 0.9, 1.0), CW, CH), 512, 256, 0.46, "dry")
put("dryD", fit_cell(grade(clump("D", True), 0.9, 1.0), CW, CH), 1024, 256, 0.42, "dry")
put("medC", fit_cell(clump("C"), CW, CH), 1536, 256, 0.48, "medium")
# row 2: low ground cover (bermuda sprigs fanned into mats)
for i in range(3):
    c = fan(CW, CH, sprigs, 26, rng, 0.40, 0.95, 50, 0.78, 0.70)
    put("short%d" % i, c, i * 512, 512, 0.22, "short")
c = fan(CW, CH, sprigs, 24, rng, 0.40, 0.95, 50, 0.78, 0.72, dry_mix=0.65)
put("shortdry", c, 1536, 512, 0.22, "dry")
# rows 3-4: tall wild grass. Scanned clumps stretched upward keep their fine
# blades (a stretched clump gets longer, not wider); single blades are thinned
# to a third of their width -- full-width they read as 15 cm ribbons.
TW, TH = 512, 512
c = fit_cell(stretch(clump("A"), 1.0, 2.0), TW, TH)
put("tall0", c, 0, 768, 1.00, "tall")
c = fan(TW, TH, blades, 80, rng, 0.45, 0.98, 40, 0.42, 0.62, wscale=0.30)
c = plumes(c, rng, 6)
put("tall1", c, 512, 768, 1.10, "tall")
c = fit_cell(stretch(clump("E"), 1.0, 2.1), TW, TH)
c = plumes(c, rng, 9, stem_h=(0.85, 1.0))
put("susuki", c, 1024, 768, 1.30, "tall")
c = fit_cell(stretch(clump("B", True), 1.0, 2.0), TW, TH)
if dry_blades:
    c2 = fan(TW, TH, dry_blades, 30, rng, 0.40, 0.90, 46, 0.45, 0.70, wscale=0.30)
    over(c2, c, 0, 0); c = c2
c = plumes(c, rng, 5, color=(0.80, 0.72, 0.56))
put("talldry", c, 1536, 768, 1.05, "dry")
# row 5: flowering meadow + forest herb rosettes
c = fan(CW, CH, sprigs + [clump("C")], 22, rng, 0.45, 0.95, 46, 0.75, 0.72)
put("flowerY", flowers(c, rng, 7, "yellow"), 0, 1280, 0.30, "flower")
c = fan(CW, CH, sprigs, 22, rng, 0.45, 0.95, 46, 0.75, 0.72)
put("flowerW", flowers(c, rng, 8, "white"), 512, 1280, 0.30, "flower")
c = fan(CW, CH, sprigs, 22, rng, 0.45, 0.95, 46, 0.75, 0.72)
put("flowerP", flowers(c, rng, 6, "purple"), 1024, 1280, 0.32, "flower")
c = fan(CW, CH, leaves, 9, rng, 0.55, 1.0, 70, 0.30, 0.62)
put("herb", grade(c, 0.85, 0.85, (0.92, 1.0, 0.92)), 1536, 1280, 0.28, "undergrowth")
# rows 6-7: fern fronds (upright, root at the bottom) + extras
for i, fr in enumerate(fronds[:4]):
    fr = upright(fr)
    put("frond%d" % i, fit_cell(fr, 256, 512, pad=6, bottom=2), i * 256, 1536, 0.80, "frond")
c = fan(CW, CH, sprigs + leaves, 20, rng, 0.40, 0.95, 60, 0.70, 0.62)
put("under0", grade(c, 0.9, 0.85, (0.9, 1.0, 0.92)), 1024, 1536, 0.30, "undergrowth")
put("dryE", fit_cell(grade(clump("E", True), 0.9, 1.0), CW, CH), 1536, 1536, 0.55, "dry")
c = fan(CW, CH, sprigs, 26, rng, 0.40, 0.95, 50, 0.78, 0.70)
put("short3", c, 1024, 1792, 0.24, "short")
put("dryC", fit_cell(grade(clump("C", True), 0.9, 1.0), CW, CH), 1536, 1792, 0.48, "dry")

img = Image.fromarray((np.clip(atlas, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
os.makedirs(os.path.dirname(OUT), exist_ok=True)
img.save(OUT, optimize=True)
json.dump(table, open(os.path.join(HERE, "grass_atlas.json"), "w"), indent=1)
for i, t in enumerate(table): print(i, t["name"], t["cat"], [round(v, 4) for v in t["rect"]], t["w_m"], t["h_m"])
bg = Image.new("RGBA", img.size, (170, 200, 235, 255)); bg.alpha_composite(img)
bg.convert("RGB").resize((1024, 1024), Image.LANCZOS).save("/tmp/grass_atlas_preview.png")
