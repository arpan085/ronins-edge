#!/usr/bin/env python3
"""Leaf-cluster atlas for tree foliage cards (v0.14).

    python3 tools/make_foliage_atlas.py [--out game/assets/textures/foliage/leaf_atlas.png]
                                        [--petal game/assets/textures/foliage/petal.png]

2048 x 1024 RGBA, 4 x 2 cells of 512 px. Every cell is one *cluster card*: a
branchlet carrying its leaves, drawn with the attachment point at the bottom
centre so MeshLib.tree() can hang the card off the end of a branch.

    0 broadleaf      1 Japanese maple (autumn)   2 sakura blossom   3 black-pine needles
    4 sugi (cedar)   5 bamboo leaves             6 bare twigs       7 maple (summer green)

Everything is drawn at 4x and box-filtered down on premultiplied colour, so
edges are anti-aliased without dark halos. Transparent texels then get the
colour of the nearest leaf (dilation) so mipmapping cannot bleed black into the
silhouette at range. Leaves are drawn back to front with depth shading: the
ones at the back of the cluster are darker, which is most of what makes a
flat card read as a volume of leaves.

Pure procedural drawing (PIL + numpy) - no external art, nothing to credit.
"""
import argparse
import colorsys
import math
import random

import numpy as np
from PIL import Image, ImageDraw

SS = 4                 # supersampling factor
CELL = 512             # output cell size
S = CELL * SS          # drawing canvas per cell

# leaf outline shapes: width profile t^a (1-t)^b (t = 0 at the stalk, 1 at the tip)
SHAPES = {
    "ovate": (0.55, 1.00),
    "elliptic": (0.80, 0.85),
    "lance": (0.38, 1.30),
    "lobe": (0.85, 1.25),
    "obovate": (1.10, 0.50),
    "needle": (0.15, 1.00),
}


def clamp8(x):
    return int(max(0, min(255, round(x))))


def hsv(h, s, v):
    r, g, b = colorsys.hsv_to_rgb((h % 360.0) / 360.0, max(0.0, min(1.0, s)), max(0.0, min(1.0, v)))
    return (r * 255.0, g * 255.0, b * 255.0)


def col(c, f=1.0):
    return (clamp8(c[0] * f), clamp8(c[1] * f), clamp8(c[2] * f), 255)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


MARGIN = S * 0.012


def inb(q, m=MARGIN):
    return m <= q[0] <= S - m and m <= q[1] <= S - m


def clip_pts(pts):
    out = []
    for q in pts:
        if not inb(q):
            break
        out.append(q)
    return out if len(out) >= 2 else pts[:2] if inb(pts[0]) and inb(pts[1]) else []


def heading_vec(a):
    # a = 0 points up the image, positive turns clockwise (to the right)
    return (math.sin(a), -math.cos(a))


def curve_pts(p0, ang, length, bend, n, wiggle=0.0, rng=None):
    pts = [p0]
    x, y = p0
    for i in range(n):
        a = ang + bend * (i + 0.5) / n
        if wiggle and rng is not None:
            a += rng.uniform(-wiggle, wiggle)
        dx, dy = heading_vec(a)
        x += dx * length / n
        y += dy * length / n
        pts.append((x, y))
    return pts


def pt_along(pts, t):
    t = max(0.0, min(1.0, t))
    f = t * (len(pts) - 1)
    i = min(int(f), len(pts) - 2)
    u = f - i
    a, b = pts[i], pts[i + 1]
    ang = math.atan2(b[0] - a[0], -(b[1] - a[1]))
    return (a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u), ang


def seg(dr, p0, p1, w0, w1, c):
    if not (inb(p0, 0) and inb(p1, MARGIN * 0.5)):
        return
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    L = math.hypot(dx, dy) or 1.0
    nx, ny = -dy / L, dx / L
    poly = [(p0[0] + nx * w0 * 0.5, p0[1] + ny * w0 * 0.5), (p1[0] + nx * w1 * 0.5, p1[1] + ny * w1 * 0.5),
            (p1[0] - nx * w1 * 0.5, p1[1] - ny * w1 * 0.5), (p0[0] - nx * w0 * 0.5, p0[1] - ny * w0 * 0.5)]
    dr.polygon(poly, fill=c)
    r = w0 * 0.5
    if r > 1.0:
        dr.ellipse([p0[0] - r, p0[1] - r, p0[0] + r, p0[1] + r], fill=c)


def stem(dr, pts, w0, w1, c, hi=None):
    n = len(pts) - 1
    for i in range(n):
        wa = w0 + (w1 - w0) * i / n
        wb = w0 + (w1 - w0) * (i + 1) / n
        seg(dr, pts[i], pts[i + 1], wa, wb, c)
    if hi is not None and w0 > 6:
        # thin lit edge along one side
        for i in range(n):
            wa = w0 + (w1 - w0) * i / n
            a, b = pts[i], pts[i + 1]
            dx, dy = b[0] - a[0], b[1] - a[1]
            L = math.hypot(dx, dy) or 1.0
            ox, oy = -dy / L * wa * 0.22, dx / L * wa * 0.22
            seg(dr, (a[0] + ox, a[1] + oy), (b[0] + ox, b[1] + oy), wa * 0.35, wa * 0.3, hi)


def leaf_outline(L, W, shape, n=22, curve=0.0, serr=0.0, notch=0.0):
    a, b = SHAPES[shape]
    tm = a / (a + b)
    norm = (tm ** a) * ((1.0 - tm) ** b)
    left, right, mid = [], [], []
    for i in range(n + 1):
        t = i / n
        w = ((t ** a) * ((1.0 - t) ** b)) / norm * W * 0.5
        if serr and 0 < i < n:
            w *= 1.0 + serr * (1.0 if i % 2 else -0.6)
        cx = curve * t * t * L
        cy = -t * L
        left.append((cx - w, cy))
        right.append((cx + w, cy))
        mid.append((cx, cy))
    if notch:
        mid[-1] = (mid[-1][0], mid[-1][1] + notch * L)
    return left, right, mid


def xform(pts, p, ang, sq=None):
    ca, sa = math.cos(ang), math.sin(ang)
    out = []
    for (x, y) in pts:
        X = p[0] + x * ca - y * sa
        Y = p[1] + x * sa + y * ca
        out.append((X, Y))
    if sq is not None:
        cx, cy, axis, k = sq
        ux, uy = math.cos(axis), math.sin(axis)
        res = []
        for (X, Y) in out:
            dx, dy = X - cx, Y - cy
            d = dx * ux + dy * uy
            res.append((X - ux * d * (1.0 - k), Y - uy * d * (1.0 - k)))
        out = res
    return out


def draw_leaf(dr, p, ang, L, W, c, shape="ovate", curve=0.0, serr=0.0, veins=0, fold=0.84,
              rib=1.16, tip_light=1.08, sq=None, notch=0.0, n=22):
    for _try in range(8):
        left, right, mid = leaf_outline(L, W, shape, n=n, curve=curve, serr=serr, notch=notch)
        pts = xform(left + right, p, ang, sq)
        if all(inb(q) for q in pts):
            break
        L *= 0.85
        W *= 0.85
    else:
        return
    # three bands along the blade: darker at the stalk, lighter toward the tip
    bands = [(0, n // 3, 0.90), (n // 3, 2 * n // 3, 1.0), (2 * n // 3, n, tip_light)]
    for (i0, i1, f) in bands:
        lp = left[i0:i1 + 1] + mid[i0:i1 + 1][::-1]
        rp = mid[i0:i1 + 1] + right[i0:i1 + 1][::-1]
        if notch and i1 == n:
            lp = left[i0:i1] + mid[i0:i1 + 1][::-1]
            rp = mid[i0:i1 + 1] + right[i0:i1][::-1]
        dr.polygon(xform(lp, p, ang, sq), fill=col(c, f * fold))
        dr.polygon(xform(rp, p, ang, sq), fill=col(c, f))
    if rib:
        m = xform(mid, p, ang, sq)
        wr = max(W * 0.05, 2.5)
        stem(dr, m[: int(n * 0.92)], wr, wr * 0.25, col(c, rib))
    if veins:
        for k in range(1, veins + 1):
            t = 0.12 + 0.72 * k / (veins + 1)
            i = int(t * n)
            j = min(n, i + max(2, n // 7))
            for side in (left, right):
                a0 = xform([mid[i]], p, ang, sq)[0]
                e = side[j]
                e = (mid[j][0] + (e[0] - mid[j][0]) * 0.82, e[1])
                a1 = xform([e], p, ang, sq)[0]
                seg(dr, a0, a1, max(W * 0.022, 1.6), 1.0, col(c, 1.07))


def run_ops(ops):
    ops.sort(key=lambda o: o[0])
    for _, fn in ops:
        fn()


def depth_f(d, lo=0.60, hi=1.06):
    return lo + (hi - lo) * (max(0.0, min(1.0, d)) ** 0.8)


# ----------------------------------------------------------------- cells
def cell_broadleaf(rng, palette=None, size=1.0):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    ops = []
    twig = hsv(25, 0.45, 0.33)
    base = (S * 0.5, S * 0.985)

    def pal():
        if palette:
            return palette(rng)
        return hsv(rng.uniform(78, 108), rng.uniform(0.55, 0.78), rng.uniform(0.32, 0.55))

    leaves = []
    for m_ in range(3):
        a0 = (-0.55, 0.0, 0.55)[m_] + rng.uniform(-0.1, 0.1)
        main = curve_pts(base, a0, S * rng.uniform(0.70, 0.84) * (1.0 - 0.25 * abs(a0)),
                         rng.uniform(-0.35, 0.35), 14, 0.04, rng)
        ops.append((-2.0, lambda main=main: stem(dr, main, S * 0.014, S * 0.005, col(twig), col(twig, 1.35))))
        n_side = 9
        for k in range(n_side):
            t = 0.16 + 0.80 * k / (n_side - 1)
            p0, h0 = pt_along(main, t)
            side = 1 if (k + m_) % 2 == 0 else -1
            a = h0 + side * rng.uniform(0.55, 1.05)
            ln = S * rng.uniform(0.15, 0.26) * (1.15 - 0.55 * t)
            tw = clip_pts(curve_pts(p0, a, ln, -side * rng.uniform(0.2, 0.6), 6))
            if not tw:
                continue
            ops.append((-1.5, lambda tw=tw: stem(dr, tw, S * 0.0065, S * 0.003, col(twig))))
            nl = rng.randint(4, 6)
            for j in range(nl):
                q, hq = pt_along(tw, 0.2 + 0.8 * j / max(nl - 1, 1))
                leaves.append((q, hq + rng.choice([-1, 1]) * rng.uniform(0.25, 0.9)))
        tip, ht = pt_along(main, 1.0)
        for j in range(4):
            leaves.append((tip, ht + rng.uniform(-0.8, 0.8)))
    for (q, la) in leaves:
        d = rng.random()
        L = S * rng.uniform(0.11, 0.16) * size
        W = L * rng.uniform(0.44, 0.56)
        c2 = tuple(x * depth_f(d) for x in pal())
        pet = S * 0.016
        hx, hy = heading_vec(la)
        p = (q[0] + hx * pet, q[1] + hy * pet)
        sq = (p[0], p[1], rng.uniform(0, math.pi), rng.uniform(0.55, 1.0))
        cv = rng.uniform(-0.12, 0.12)

        def g(p=p, la=la, L=L, W=W, c2=c2, q=q, sq=sq, cv=cv):
            seg(dr, q, p, S * 0.004, S * 0.003, col(twig, 1.1))
            draw_leaf(dr, p, la, L, W, c2, "ovate", curve=cv, serr=0.035, veins=4, fold=0.82, sq=sq)
        ops.append((d, g))
    run_ops(ops)
    return img


def cell_maple(rng):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    ops = []
    twig = hsv(8, 0.45, 0.30)
    base = (S * 0.5, S * 0.985)
    leaves = []
    # a fan of thin layered sprays, the habit of Acer palmatum
    nspray = 8
    for k in range(nspray):
        a = -1.05 + 2.1 * (k + 0.5) / nspray + rng.uniform(-0.12, 0.12)
        ln = S * rng.uniform(0.62, 0.86) * (1.0 - 0.25 * abs(a))
        sp = curve_pts(base, a * 0.85, ln, rng.uniform(-0.4, 0.4), 12, 0.05, rng)
        ops.append((-2.0, lambda sp=sp: stem(dr, sp, S * 0.010, S * 0.003, col(twig), col(twig, 1.4))))
        nl = rng.randint(7, 10)
        for j in range(nl):
            t = 0.22 + 0.78 * j / (nl - 1)
            q, hq = pt_along(sp, t)
            side = 1 if j % 2 else -1
            leaves.append((q, hq + side * rng.uniform(0.3, 1.1)))
    for (q, la) in leaves:
        d = rng.random()
        r = rng.random()
        if r < 0.42:
            c = hsv(rng.uniform(-6, 6), rng.uniform(0.80, 0.92), rng.uniform(0.62, 0.80))
        elif r < 0.78:
            c = hsv(rng.uniform(8, 20), rng.uniform(0.82, 0.94), rng.uniform(0.72, 0.88))
        elif r < 0.95:
            c = hsv(rng.uniform(24, 36), rng.uniform(0.78, 0.92), rng.uniform(0.78, 0.92))
        else:
            c = hsv(rng.uniform(40, 52), rng.uniform(0.70, 0.85), rng.uniform(0.70, 0.85))
        c = tuple(x * depth_f(d, 0.55, 1.0) for x in c)
        R = S * rng.uniform(0.080, 0.112)
        pet = R * 0.75
        hx, hy = heading_vec(la)
        p = (q[0] + hx * pet, q[1] + hy * pet)
        sq = (p[0], p[1], rng.uniform(0, math.pi), rng.uniform(0.55, 1.0))

        def g(p=p, la=la, R=R, c=c, q=q, sq=sq):
            seg(dr, q, p, S * 0.0035, S * 0.0025, col(hsv(355, 0.7, 0.45)))
            lobes = 7
            spread = math.radians(rng.uniform(118, 138))
            for i in range(lobes):
                u = -1.0 + 2.0 * i / (lobes - 1)
                a = la + u * spread
                lr = R * (1.0 - 0.36 * abs(u) ** 1.5)
                draw_leaf(dr, p, a, lr, lr * 0.36, tuple(x * rng.uniform(0.93, 1.06) for x in c), "lobe",
                          serr=0.12, fold=0.86, rib=1.12, tip_light=1.06, sq=sq, n=16)
            rr = R * 0.17
            cc = xform([(0, 0)], p, 0)[0]
            dr.ellipse([cc[0] - rr, cc[1] - rr, cc[0] + rr, cc[1] + rr], fill=col(c, 0.95))
        ops.append((d, g))
    run_ops(ops)
    return img


def petal_poly(R):
    left, right, mid = leaf_outline(R, R * 0.86, "obovate", n=14, notch=0.13)
    # notch: pull the tip in
    tipL = left[-2]
    tipR = right[-2]
    return left[:-1] + [(tipL[0] * 0.5, -R * 0.97), (0, -R * 0.86), (tipR[0] * 0.5, -R * 0.97)] + right[:-1][::-1]


def cell_sakura(rng):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    ops = []
    bark = hsv(12, 0.35, 0.22)
    base = (S * 0.5, S * 0.985)
    flowers = []
    leaves = []
    nb = 6
    for k in range(nb):
        a = -1.05 + 2.1 * (k + 0.5) / nb + rng.uniform(-0.15, 0.15)
        ln = S * rng.uniform(0.60, 0.85) * (1.0 - 0.2 * abs(a))
        br = curve_pts(base, a * 0.8, ln, rng.uniform(-0.5, 0.5), 12, 0.07, rng)
        ops.append((-3.0, lambda br=br: stem(dr, br, S * 0.014, S * 0.004, col(bark), col(bark, 1.5))))
        # spur clusters along the branch
        ncl = rng.randint(5, 7)
        for j in range(ncl):
            t = 0.25 + 0.75 * j / (ncl - 1)
            q, hq = pt_along(br, t)
            nfl = rng.randint(4, 6)
            for m in range(nfl):
                aa = rng.uniform(0, 2 * math.pi)
                rr = S * rng.uniform(0.02, 0.075)
                fp = (q[0] + math.cos(aa) * rr, q[1] + math.sin(aa) * rr * 0.8)
                flowers.append((q, fp))
            if rng.random() < 0.45:
                leaves.append((q, hq + rng.choice([-1, 1]) * rng.uniform(0.5, 1.3)))
    for (q, la) in leaves:
        d = rng.random() * 0.6
        c = hsv(rng.uniform(8, 22), rng.uniform(0.45, 0.65), rng.uniform(0.40, 0.55))
        c = tuple(x * depth_f(d, 0.6, 1.0) for x in c)
        L = S * rng.uniform(0.07, 0.10)

        def g(q=q, la=la, c=c, L=L):
            draw_leaf(dr, q, la, L, L * 0.48, c, "ovate", serr=0.05, veins=3, fold=0.8)
        ops.append((d, g))
    for (q, fp) in flowers:
        d = rng.random()
        R = S * rng.uniform(0.034, 0.047)
        white = (255, 246, 248)
        pink = hsv(rng.uniform(338, 352), rng.uniform(0.22, 0.42), 0.99)
        base_pk = hsv(rng.uniform(335, 348), rng.uniform(0.45, 0.62), 0.92)
        f = depth_f(d, 0.68, 1.0)
        pc = tuple(x * f for x in mix(white, pink, rng.uniform(0.25, 0.75)))
        bc = tuple(x * f for x in base_pk)
        sq = (fp[0], fp[1], rng.uniform(0, math.pi), rng.uniform(0.45, 1.0))
        rot = rng.uniform(0, 2 * math.pi)

        def g(q=q, fp=fp, R=R, pc=pc, bc=bc, sq=sq, rot=rot, f=f):
            seg(dr, q, fp, S * 0.003, S * 0.0022, col(hsv(350, 0.4, 0.45)))
            outer = petal_poly(R)
            inner = petal_poly(R * 0.5)
            for k in range(5):
                a = rot + k * 2 * math.pi / 5 + rng.uniform(-0.12, 0.12)
                dr.polygon(xform(outer, fp, a, sq), fill=col(pc))
                dr.polygon(xform(inner, fp, a, sq), fill=col(mix(pc, bc, 0.6)))
            cr = R * 0.22
            cc = xform([(0, 0)], fp, 0, sq)[0]
            dr.ellipse([cc[0] - cr, cc[1] - cr, cc[0] + cr, cc[1] + cr], fill=col(hsv(345, 0.7, 0.62 * f)))
            for s_ in range(9):
                a = rng.uniform(0, 2 * math.pi)
                l = R * rng.uniform(0.32, 0.52)
                e = xform([(math.cos(a) * l, math.sin(a) * l)], fp, 0, sq)[0]
                seg(dr, cc, e, S * 0.0018, S * 0.0012, col((240, 215, 215), f))
                dr.ellipse([e[0] - S * 0.0025, e[1] - S * 0.0025, e[0] + S * 0.0025, e[1] + S * 0.0025],
                           fill=col((235, 200, 120), f))
        ops.append((d, g))
    run_ops(ops)
    return img


def cell_pine(rng):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    ops = []
    bark = hsv(25, 0.30, 0.30)
    base = (S * 0.5, S * 0.985)
    ntw = 9
    for k in range(ntw):
        a = -1.25 + 2.5 * (k + 0.5) / ntw + rng.uniform(-0.10, 0.10)
        ln = S * rng.uniform(0.55, 0.80) * (1.0 - 0.22 * abs(a))
        tw = curve_pts(base, a * 0.85, ln, rng.uniform(-0.3, 0.3), 10, 0.05, rng)
        ops.append((-3.0, lambda tw=tw: stem(dr, tw, S * 0.013, S * 0.006, col(bark), col(bark, 1.4))))
        steps = 46
        for i in range(steps):
            t = 0.30 + 0.70 * i / (steps - 1)
            q, hq = pt_along(tw, t)
            for m in range(5):
                side = rng.choice([-1, 1])
                na = hq + side * rng.uniform(0.25, 1.15) * (1.0 - 0.45 * t)
                nl = S * rng.uniform(0.085, 0.125)
                d = rng.random()
                c = hsv(rng.uniform(92, 118), rng.uniform(0.50, 0.70), rng.uniform(0.26, 0.42))
                c = tuple(x * depth_f(d, 0.55, 1.05) for x in c)
                bend = rng.uniform(-0.15, 0.15)

                def g(q=q, na=na, nl=nl, c=c, bend=bend):
                    pts = curve_pts(q, na, nl, bend, 3)
                    stem(dr, pts, S * 0.0042, S * 0.0012, col(c))
                    # paler tip third
                    seg(dr, pts[2], pts[3], S * 0.0020, S * 0.0009, col(c, 1.25))
                ops.append((d, g))
        # terminal brush
        tip, ht = pt_along(tw, 1.0)
        for m in range(40):
            na = ht + rng.uniform(-0.75, 0.75)
            nl = S * rng.uniform(0.07, 0.11)
            d = 0.5 + 0.5 * rng.random()
            c = hsv(rng.uniform(88, 110), rng.uniform(0.50, 0.66), rng.uniform(0.34, 0.48))
            c = tuple(x * depth_f(d, 0.55, 1.05) for x in c)

            def g(q=tip, na=na, nl=nl, c=c):
                pts = curve_pts(q, na, nl, rng.uniform(-0.1, 0.1), 3)
                stem(dr, pts, S * 0.0040, S * 0.0012, col(c))
            ops.append((d, g))
    run_ops(ops)
    return img


def cell_cedar(rng):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    ops = []
    base = (S * 0.5, S * 0.985)

    def rope(pts, d, tone):
        c0 = hsv(rng.uniform(105, 128), rng.uniform(0.45, 0.62), tone)
        segs = []
        L = 0.0
        for i in range(len(pts) - 1):
            L += math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
        nstep = max(4, int(L / (S * 0.0085)))
        for i in range(nstep):
            t = i / (nstep - 1)
            q, hq = pt_along(pts, t)
            for side in (-1, 1):
                na = hq + side * rng.uniform(0.45, 0.85)
                nl = S * rng.uniform(0.022, 0.034) * (1.0 - 0.35 * t)
                segs.append((q, na, nl))
        cc = tuple(x * depth_f(d, 0.55, 1.05) for x in c0)

        def g(segs=segs, cc=cc, pts=pts):
            stem(dr, pts, S * 0.010, S * 0.004, col(cc, 0.75))
            for (q, na, nl) in segs:
                hx, hy = heading_vec(na)
                seg(dr, q, (q[0] + hx * nl, q[1] + hy * nl), S * 0.0075, S * 0.0012, col(cc, rng.uniform(0.92, 1.18)))
        ops.append((d, g))

    for f_ in range(3):
        a0 = (-0.50, 0.0, 0.50)[f_] + rng.uniform(-0.08, 0.08)
        main = clip_pts(curve_pts(base, a0, S * rng.uniform(0.74, 0.88) * (1.0 - 0.2 * abs(a0)),
                                  rng.uniform(-0.3, 0.3), 14, 0.03, rng))
        rope(main, 0.30 + 0.1 * f_, 0.36)
        nside = 16
        for k in range(nside):
            t = 0.10 + 0.86 * k / (nside - 1)
            p0, h0 = pt_along(main, t)
            side = 1 if (k + f_) % 2 == 0 else -1
            a = h0 + side * rng.uniform(0.55, 0.95)
            ln = S * rng.uniform(0.14, 0.24) * (1.12 - 0.62 * t)
            br = clip_pts(curve_pts(p0, a, ln, -side * rng.uniform(0.1, 0.5), 7, 0.04, rng))
            if not br:
                continue
            d = rng.random()
            rope(br, d, rng.uniform(0.28, 0.44))
            for m in range(rng.randint(2, 4)):
                tt = rng.uniform(0.25, 0.85)
                q, hq = pt_along(br, tt)
                s2 = rng.choice([-1, 1])
                sb = clip_pts(curve_pts(q, hq + s2 * rng.uniform(0.5, 0.9), ln * rng.uniform(0.35, 0.55), -s2 * 0.3, 5))
                if sb:
                    rope(sb, min(1.0, d + rng.uniform(-0.2, 0.3)), rng.uniform(0.30, 0.50))
    run_ops(ops)
    return img


def cell_bamboo(rng):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    ops = []
    twc = hsv(62, 0.45, 0.48)
    base = (S * 0.5, S * 0.985)
    ntw = 4
    for k in range(ntw):
        a = -0.75 + 1.5 * (k + 0.5) / ntw + rng.uniform(-0.1, 0.1)
        ln = S * rng.uniform(0.55, 0.75)
        tw = curve_pts(base, a, ln, rng.uniform(-0.4, 0.4), 10, 0.03, rng)
        ops.append((-2.0, lambda tw=tw: stem(dr, tw, S * 0.0075, S * 0.004, col(twc), col(twc, 1.3))))
        nn = 4
        for j in range(nn):
            t = 0.35 + 0.65 * j / (nn - 1)
            q, hq = pt_along(tw, t)
            nl = rng.randint(3, 5)
            for m in range(nl):
                side = rng.choice([-1, 1])
                la = hq + side * rng.uniform(0.35, 1.5)
                # bamboo leaves hang: curve the blade toward the ground
                droop = 0.35 * math.sin(la)
                L = S * rng.uniform(0.22, 0.32)
                W = L * rng.uniform(0.11, 0.15)
                d = rng.random()
                c = hsv(rng.uniform(72, 92), rng.uniform(0.55, 0.75), rng.uniform(0.40, 0.60))
                c = tuple(x * depth_f(d, 0.58, 1.05) for x in c)

                def g(q=q, la=la, L=L, W=W, c=c, droop=droop):
                    draw_leaf(dr, q, la, L, W, c, "lance", curve=droop, fold=0.84, rib=1.14, tip_light=1.05)
                ops.append((d, g))
    run_ops(ops)
    return img


def cell_twigs(rng):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    c0 = hsv(28, 0.22, 0.36)

    def branch(p, ang, length, width, depth):
        pts = curve_pts(p, ang, length, rng.uniform(-0.35, 0.35), 6, 0.10, rng)
        f = rng.uniform(0.85, 1.12)
        stem(dr, pts, width, width * 0.62, col(c0, f), col(c0, f * 1.35))
        if depth == 0:
            return
        for k in range(rng.randint(2, 4)):
            t = rng.uniform(0.35, 1.0)
            q, hq = pt_along(pts, t)
            branch(q, hq + rng.choice([-1, 1]) * rng.uniform(0.30, 0.85), length * rng.uniform(0.50, 0.72),
                   width * 0.62, depth - 1)

    for a0 in (-0.35, 0.05, 0.4):
        branch((S * 0.5, S * 0.985), a0 + rng.uniform(-0.1, 0.1), S * 0.33, S * 0.017, 5)
    return img


def cell_bush(rng):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    ops = []
    twig = hsv(25, 0.4, 0.28)
    base = (S * 0.5, S * 0.985)
    for k in range(9):
        a = -1.2 + 2.4 * (k + 0.5) / 9
        tw = curve_pts(base, a * 0.8, S * rng.uniform(0.45, 0.75), rng.uniform(-0.3, 0.3), 8, 0.06, rng)
        ops.append((-2.0, lambda tw=tw: stem(dr, tw, S * 0.008, S * 0.003, col(twig))))
    n = 430
    for i in range(n):
        # dome-shaped scatter over the card
        while True:
            x = rng.uniform(0.06, 0.94)
            y = rng.uniform(0.06, 0.96)
            dx = (x - 0.5) / 0.46
            dy = (y - 0.62) / 0.52
            if dx * dx + dy * dy < 1.0:
                break
        q = (x * S, y * S)
        la = math.atan2(q[0] - base[0], -(q[1] - base[1])) + rng.uniform(-0.9, 0.9)
        d = rng.random()
        c = hsv(rng.uniform(88, 112), rng.uniform(0.55, 0.78), rng.uniform(0.26, 0.46))
        c = tuple(x_ * depth_f(d, 0.55, 1.08) for x_ in c)
        L = S * rng.uniform(0.065, 0.10)

        def g(q=q, la=la, c=c, L=L):
            draw_leaf(dr, q, la, L, L * 0.52, c, "elliptic", veins=2, fold=0.8, tip_light=1.15,
                      sq=(q[0], q[1], rng.uniform(0, math.pi), rng.uniform(0.5, 1.0)))
        ops.append((d, g))
    run_ops(ops)
    return img


# ----------------------------------------------------------------- clump cells (v0.14b)
# A crown is built from many overlapping cards, so a cell must read as a CLUMP
# of foliage - dense in the middle, lacy at the rim, no single obvious stalk.
# The first atlas drew each cell as one fan-shaped spray from the bottom
# centre; repeated over a crown every card showed the same hand-shaped fan.
def blob_sampler(rng, R=0.44, cy=0.52):
    ph = [rng.uniform(0, 6.28) for _ in range(3)]

    def rad(th):
        return R * S * (1.0 + 0.10 * math.sin(3 * th + ph[0]) + 0.07 * math.sin(5 * th + ph[1])
                        + 0.05 * math.sin(7 * th + ph[2]))

    c = (S * 0.5, S * cy)

    def sample(edge_pow=3.0):
        while True:
            th = rng.uniform(0, 2 * math.pi)
            u = math.sqrt(rng.random())
            if rng.random() < 1.0 - u ** edge_pow * 0.85:
                rr = rad(th) * u
                return (c[0] + math.cos(th) * rr, c[1] + math.sin(th) * rr), th, u
    return c, rad, sample


def twigs_to(dr, ops, rng, c, pts, colr, w=0.007):
    # a few hidden twigs from the clump centre out toward the leaves
    for q in pts:
        mid = ((c[0] + q[0]) * 0.5 + rng.uniform(-S * 0.03, S * 0.03), (c[1] + q[1]) * 0.5 + rng.uniform(-S * 0.03, S * 0.03))
        ops.append((-2.0, lambda q=q, mid=mid: stem(dr, [c, mid, q], S * w, S * w * 0.4, col(colr))))


def clump_leaves(rng, n, leaf_fn, twig_col, R=0.44, edge_pow=3.0, ntw=7):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    ops = []
    c, rad, sample = blob_sampler(rng, R)
    tw_pts = []
    for k in range(ntw):
        th = 2 * math.pi * k / ntw + rng.uniform(-0.3, 0.3)
        rr = rad(th) * rng.uniform(0.5, 0.8)
        tw_pts.append((c[0] + math.cos(th) * rr, c[1] + math.sin(th) * rr))
    twigs_to(dr, ops, rng, c, tw_pts, twig_col)
    for i in range(n):
        q, th, u = sample(edge_pow)
        out = math.atan2(q[0] - c[0], -(q[1] - c[1]))   # heading away from centre
        d = rng.random()
        # leaves near the rim are mostly in front; the interior is the back of the clump
        d = min(1.0, d * 0.7 + u * 0.3)
        ops.append((d, (lambda q=q, out=out, d=d, u=u: leaf_fn(dr, q, out, d, u))))
    run_ops(ops)
    return img


def cell_broadleaf2(rng):
    def leaf(dr, q, out, d, u):
        c = hsv(rng.uniform(80, 108), rng.uniform(0.55, 0.78), rng.uniform(0.34, 0.56))
        c = tuple(x * depth_f(d, 0.55, 1.06) for x in c)
        L = S * rng.uniform(0.10, 0.145)
        draw_leaf(dr, q, out + rng.uniform(-1.1, 1.1), L, L * rng.uniform(0.45, 0.56), c, "ovate",
                  curve=rng.uniform(-0.12, 0.12), serr=0.035, veins=4, fold=0.82,
                  sq=(q[0], q[1], rng.uniform(0, math.pi), rng.uniform(0.5, 1.0)))
    return clump_leaves(rng, 125, leaf, hsv(25, 0.45, 0.30))


def maple_leaf(dr, p, la, R, c, rng, sq):
    spread = math.radians(rng.uniform(118, 138))
    for i in range(7):
        u = -1.0 + 2.0 * i / 6
        lr = R * (1.0 - 0.36 * abs(u) ** 1.5)
        draw_leaf(dr, p, la + u * spread, lr, lr * 0.36, tuple(x * rng.uniform(0.93, 1.06) for x in c), "lobe",
                  serr=0.12, fold=0.86, rib=1.12, tip_light=1.06, sq=sq, n=16)
    rr = R * 0.17
    dr.ellipse([p[0] - rr, p[1] - rr, p[0] + rr, p[1] + rr], fill=col(c, 0.95))


def maple_cell(rng, palette):
    def leaf(dr, q, out, d, u):
        c = tuple(x * depth_f(d, 0.52, 1.0) for x in palette(rng))
        R = S * rng.uniform(0.072, 0.098)
        la = out + rng.uniform(-0.9, 0.9)
        sq = (q[0], q[1], rng.uniform(0, math.pi), rng.uniform(0.5, 1.0))
        hx, hy = heading_vec(la + math.pi)
        seg(dr, q, (q[0] + hx * R * 0.7, q[1] + hy * R * 0.7), S * 0.0035, S * 0.0025, col(hsv(355, 0.6, 0.42)))
        maple_leaf(dr, q, la, R, c, rng, sq)
    return clump_leaves(rng, 92, leaf, hsv(8, 0.45, 0.28))


def pal_maple_red(rng):
    # v0.14: a red-leaf cultivar in spring - deep crimson to copper, not the
    # fire-engine red that read as confetti from any distance
    r = rng.random()
    if r < 0.50:
        return hsv(rng.uniform(-4, 6), rng.uniform(0.64, 0.78), rng.uniform(0.42, 0.58))
    if r < 0.80:
        return hsv(rng.uniform(6, 16), rng.uniform(0.66, 0.80), rng.uniform(0.50, 0.64))
    if r < 0.95:
        return hsv(rng.uniform(18, 30), rng.uniform(0.60, 0.76), rng.uniform(0.54, 0.68))
    return hsv(rng.uniform(-22, -12), rng.uniform(0.48, 0.62), rng.uniform(0.34, 0.46))


def pal_maple_green(rng):
    r = rng.random()
    if r < 0.55:
        return hsv(rng.uniform(80, 100), rng.uniform(0.60, 0.80), rng.uniform(0.40, 0.60))
    if r < 0.85:
        return hsv(rng.uniform(58, 76), rng.uniform(0.65, 0.85), rng.uniform(0.55, 0.75))
    # spring flush: pale yellow-green new leaves, not autumn orange
    return hsv(rng.uniform(52, 64), rng.uniform(0.58, 0.76), rng.uniform(0.62, 0.78))


def cell_sakura2(rng):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    ops = []
    c, rad, sample = blob_sampler(rng, 0.44)
    bark = hsv(12, 0.35, 0.22)
    tw = []
    for k in range(8):
        th = 2 * math.pi * k / 8 + rng.uniform(-0.3, 0.3)
        rr = rad(th) * rng.uniform(0.55, 0.85)
        tw.append((c[0] + math.cos(th) * rr, c[1] + math.sin(th) * rr))
    twigs_to(dr, ops, rng, c, tw, bark, 0.007)
    # umbels: 3-5 flowers around a spur
    for i in range(92):
        q, th, u = sample(3.0)
        nfl = rng.randint(3, 5)
        dd = min(1.0, rng.random() * 0.7 + u * 0.3)
        if rng.random() < 0.25:
            lc = hsv(rng.uniform(8, 22), rng.uniform(0.45, 0.65), rng.uniform(0.40, 0.55))
            lc = tuple(x * depth_f(dd * 0.8, 0.6, 1.0) for x in lc)
            L = S * rng.uniform(0.06, 0.085)
            la = math.atan2(q[0] - c[0], -(q[1] - c[1])) + rng.uniform(-1.0, 1.0)
            ops.append((dd * 0.8, lambda q=q, la=la, lc=lc, L=L: draw_leaf(dr, q, la, L, L * 0.48, lc, "ovate",
                                                                          serr=0.05, veins=3, fold=0.8)))
        for m in range(nfl):
            aa = rng.uniform(0, 2 * math.pi)
            rr = S * rng.uniform(0.012, 0.045)
            fp = (q[0] + math.cos(aa) * rr, q[1] + math.sin(aa) * rr * 0.8)
            d = min(1.0, dd + rng.uniform(-0.1, 0.1))
            R = S * rng.uniform(0.030, 0.042)
            white = (255, 246, 248)
            pink = hsv(rng.uniform(338, 352), rng.uniform(0.22, 0.42), 0.99)
            base_pk = hsv(rng.uniform(335, 348), rng.uniform(0.45, 0.62), 0.92)
            f = depth_f(d, 0.66, 1.0)
            pc = tuple(x * f for x in mix(white, pink, rng.uniform(0.25, 0.75)))
            bc = tuple(x * f for x in base_pk)
            sq = (fp[0], fp[1], rng.uniform(0, math.pi), rng.uniform(0.45, 1.0))
            rot = rng.uniform(0, 2 * math.pi)

            def g(q=q, fp=fp, R=R, pc=pc, bc=bc, sq=sq, rot=rot, f=f):
                seg(dr, q, fp, S * 0.003, S * 0.0022, col(hsv(350, 0.4, 0.45)))
                outer = petal_poly(R)
                inner = petal_poly(R * 0.5)
                for k in range(5):
                    a = rot + k * 2 * math.pi / 5 + rng.uniform(-0.12, 0.12)
                    dr.polygon(xform(outer, fp, a, sq), fill=col(pc))
                    dr.polygon(xform(inner, fp, a, sq), fill=col(mix(pc, bc, 0.55)))
                cr = R * 0.20
                cc = xform([(0, 0)], fp, 0, sq)[0]
                dr.ellipse([cc[0] - cr, cc[1] - cr, cc[0] + cr, cc[1] + cr], fill=col(hsv(345, 0.6, 0.66 * f)))
                for s_ in range(8):
                    a = rng.uniform(0, 2 * math.pi)
                    l = R * rng.uniform(0.30, 0.48)
                    e = xform([(math.cos(a) * l, math.sin(a) * l)], fp, 0, sq)[0]
                    seg(dr, cc, e, S * 0.0016, S * 0.0011, col((240, 215, 215), f))
                    rr2 = S * 0.0024
                    dr.ellipse([e[0] - rr2, e[1] - rr2, e[0] + rr2, e[1] + rr2], fill=col((235, 205, 130), f))
            ops.append((d, g))
    run_ops(ops)
    return img


def cell_pine2(rng):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    ops = []
    c, rad, sample = blob_sampler(rng, 0.43)
    bark = hsv(25, 0.30, 0.28)
    tw = []
    for k in range(9):
        th = 2 * math.pi * k / 9 + rng.uniform(-0.3, 0.3)
        rr = rad(th) * rng.uniform(0.45, 0.75)
        tw.append((c[0] + math.cos(th) * rr, c[1] + math.sin(th) * rr))
    twigs_to(dr, ops, rng, c, tw, bark, 0.011)
    # needle tufts: brushes radiating from twig tips all over the pad
    for i in range(135):
        q, th, u = sample(2.5)
        head = math.atan2(q[0] - c[0], -(q[1] - c[1])) + rng.uniform(-0.8, 0.8)
        dd = min(1.0, rng.random() * 0.75 + u * 0.25)
        for m in range(32):
            na = head + rng.uniform(-1.0, 1.0) * rng.choice([0.6, 1.0, 1.5, 2.6])
            nl = S * rng.uniform(0.060, 0.100)
            d = min(1.0, max(0.0, dd + rng.uniform(-0.08, 0.08)))
            cc = hsv(rng.uniform(90, 118), rng.uniform(0.50, 0.70), rng.uniform(0.26, 0.44))
            cc = tuple(x * depth_f(d, 0.50, 1.05) for x in cc)
            bend = rng.uniform(-0.18, 0.18)

            def g(q=q, na=na, nl=nl, cc=cc, bend=bend):
                pts = curve_pts(q, na, nl, bend, 3)
                stem(dr, pts, S * 0.0040, S * 0.0012, col(cc))
                seg(dr, pts[2], pts[3], S * 0.0020, S * 0.0009, col(cc, 1.25))
            ops.append((d, g))
    run_ops(ops)
    return img


def cell_cedar2(rng):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    ops = []
    c, rad, sample = blob_sampler(rng, 0.44)

    def rope(pts, d, tone, w=1.0):
        c0 = hsv(rng.uniform(105, 128), rng.uniform(0.45, 0.62), tone)
        segs = []
        L = 0.0
        for i in range(len(pts) - 1):
            L += math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
        nstep = max(4, int(L / (S * 0.0085)))
        for i in range(nstep):
            t = i / (nstep - 1)
            q, hq = pt_along(pts, t)
            for side in (-1, 1):
                na = hq + side * rng.uniform(0.45, 0.85)
                nl = S * rng.uniform(0.024, 0.036) * (1.0 - 0.35 * t) * w
                segs.append((q, na, nl))
        cc = tuple(x * depth_f(d, 0.52, 1.05) for x in c0)

        def g(segs=segs, cc=cc, pts=pts):
            stem(dr, pts, S * 0.009, S * 0.004, col(cc, 0.75))
            for (q, na, nl) in segs:
                hx, hy = heading_vec(na)
                seg(dr, q, (q[0] + hx * nl, q[1] + hy * nl), S * 0.0072, S * 0.0012, col(cc, rng.uniform(0.92, 1.18)))
        ops.append((d, g))

    for i in range(64):
        q, th, u = sample(2.0)
        q = (c[0] + (q[0] - c[0]) * 0.8, c[1] + (q[1] - c[1]) * 0.8)
        head = math.atan2(q[0] - c[0], -(q[1] - c[1])) + rng.uniform(-0.7, 0.7)
        d = min(1.0, rng.random() * 0.7 + u * 0.3)
        ln = S * rng.uniform(0.13, 0.22)
        # start the frond behind q so it grows out through it
        hx, hy = heading_vec(head)
        st = (q[0] - hx * ln * 0.45, q[1] - hy * ln * 0.45)
        main = clip_pts(curve_pts(st, head, ln, rng.uniform(-0.5, 0.5), 8, 0.04, rng))
        if not main:
            continue
        rope(main, d, rng.uniform(0.30, 0.42))
        for k in range(6):
            t = 0.15 + 0.75 * k / 5
            p0, h0 = pt_along(main, t)
            side = 1 if k % 2 == 0 else -1
            br = clip_pts(curve_pts(p0, h0 + side * rng.uniform(0.5, 0.9), ln * rng.uniform(0.25, 0.42) * (1.1 - 0.5 * t),
                                    -side * 0.3, 5))
            if br:
                rope(br, min(1.0, d + rng.uniform(-0.1, 0.15)), rng.uniform(0.30, 0.48), 0.9)
    run_ops(ops)
    return img


def cell_bamboo2(rng):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    ops = []
    c, rad, sample = blob_sampler(rng, 0.45, 0.50)
    twc = hsv(62, 0.45, 0.45)
    tw = []
    for k in range(6):
        th = 2 * math.pi * k / 6 + rng.uniform(-0.3, 0.3)
        rr = rad(th) * rng.uniform(0.5, 0.8)
        tw.append((c[0] + math.cos(th) * rr, c[1] + math.sin(th) * rr))
    twigs_to(dr, ops, rng, c, tw, twc, 0.006)
    for i in range(36):
        q, th, u = sample(2.0)
        base_h = math.atan2(q[0] - c[0], -(q[1] - c[1]))
        dd = min(1.0, rng.random() * 0.7 + u * 0.3)
        for m in range(rng.randint(3, 5)):
            la = base_h + rng.uniform(-1.2, 1.2)
            # hang: bias toward the ground
            la = la + (math.pi - la % (2 * math.pi)) * 0.25 if math.cos(la) > -0.2 else la
            droop = 0.25 * math.sin(la)
            L = S * rng.uniform(0.17, 0.26)
            W = L * rng.uniform(0.11, 0.15)
            d = min(1.0, max(0.0, dd + rng.uniform(-0.1, 0.1)))
            cc = hsv(rng.uniform(72, 92), rng.uniform(0.55, 0.75), rng.uniform(0.40, 0.60))
            cc = tuple(x * depth_f(d, 0.55, 1.05) for x in cc)
            ops.append((d, lambda q=q, la=la, L=L, W=W, cc=cc, droop=droop: draw_leaf(
                dr, q, la, L, W, cc, "lance", curve=droop, fold=0.84, rib=1.14, tip_light=1.05)))
    run_ops(ops)
    return img


# ----------------------------------------------------------------- post
def box_blur(a, r):
    if r <= 0:
        return a
    k = 2 * r + 1
    pad = np.pad(a, ((r, r), (r, r)) + ((0, 0),) * (a.ndim - 2), mode="edge")
    c = np.cumsum(pad, axis=0)
    c = np.concatenate([np.zeros_like(c[:1]), c], axis=0)
    a1 = (c[k:] - c[:-k])
    c = np.cumsum(a1, axis=1)
    c = np.concatenate([np.zeros_like(c[:, :1]), c], axis=1)
    return (c[:, k:] - c[:, :-k]) / (k * k)


def finish(img):
    a = np.asarray(img).astype(np.float64) / 255.0
    rgb, al = a[..., :3], a[..., 3:4]
    pm = rgb * al
    # 4x box downsample on premultiplied colour
    h, w = al.shape[0] // SS, al.shape[1] // SS
    pm = pm.reshape(h, SS, w, SS, 3).mean(axis=(1, 3))
    al = al.reshape(h, SS, w, SS, 1).mean(axis=(1, 3))
    rgb = np.where(al > 1e-4, pm / np.maximum(al, 1e-4), 0.0)
    # gentle per-texel grain so large leaves are not flat fills
    rng = np.random.default_rng(7)
    grain = 1.0 + (rng.random((h, w, 1)) - 0.5) * 0.06
    rgb = np.clip(rgb * grain, 0, 1)
    # dilation: give empty texels the colour of the nearest foliage
    filled = al[..., 0] > 0.02
    out = rgb.copy()
    w8 = al[..., 0] * filled
    for r in (1, 2, 4, 8, 16, 32, 64):
        num = box_blur(rgb * w8[..., None], r)
        den = box_blur(w8[..., None], r)
        take = (~filled) & (den[..., 0] > 1e-5)
        out[take] = num[take] / den[take]
        filled = filled | take
        w8 = np.where(filled, 1.0, 0.0) * np.maximum(w8, take * 1.0)
        rgb = out
    out[~filled] = rgb[filled].mean(axis=0) if filled.any() else 0.3
    res = np.concatenate([out, al], axis=-1)
    return Image.fromarray(np.clip(res * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGBA")


def make_petal(size=128):
    """One falling sakura petal (obovate, narrow claw, small V notch), for the
    petal particles near sakura trees."""
    W = size * SS
    R = W * 0.86                                # petal length
    Wm = R * 0.36                               # half width at the widest point
    n = 40
    left = []
    for i in range(n + 1):
        t = i / n
        w = Wm * (0.08 + 0.92 * math.sin(math.pi * 0.5 * min(t / 0.72, 1.0)) ** 0.8)
        if t > 0.72:
            w *= 1.0 - 0.42 * ((t - 0.72) / 0.28) ** 2   # round the shoulders
        left.append((-w, -t * R))
    notch = [(-left[-1][0] * 0.0, -R * 0.93)]
    right = [(-x, y) for x, y in left[::-1]]
    poly = left + notch + right
    pts = [(W * 0.5 + x, W * 0.5 + R * 0.5 + y) for x, y in poly]
    m = Image.new("L", (W, W), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    mask = np.asarray(m).astype(np.float64) / 255.0
    yy, xx = np.mgrid[0:W, 0:W].astype(np.float64)
    t = np.clip((W * 0.5 + R * 0.5 - yy) / R, 0, 1)          # 0 at the claw, 1 at the tip
    base = np.array([0.93, 0.62, 0.73])
    tip = np.array([1.00, 0.94, 0.96])
    rgb = base + (tip - base) * (t[..., None] ** 0.45)
    dx = (xx - W * 0.5) / Wm
    crease = np.exp(-(dx / 0.06) ** 2) * (0.3 + 0.7 * t) * 0.07
    veins = (0.5 + 0.5 * np.cos(np.arctan2(dx, t * 2.0 + 0.2) * 11.0)) ** 8 * 0.05 * t
    rgb = rgb * (1.0 - crease - veins)[..., None]
    img = np.concatenate([np.clip(rgb, 0, 1), mask[..., None]], axis=-1)
    return finish(Image.fromarray((img * 255.0 + 0.5).astype(np.uint8), "RGBA"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="game/assets/textures/foliage/leaf_atlas.png")
    ap.add_argument("--preview", default="")
    ap.add_argument("--seed", type=int, default=1414)
    ap.add_argument("--petal", default="game/assets/textures/foliage/petal.png")
    args = ap.parse_args()
    makers = [cell_broadleaf2, lambda r: maple_cell(r, pal_maple_red), cell_sakura2, cell_pine2, cell_cedar2,
              cell_bamboo2, cell_twigs, lambda r: maple_cell(r, pal_maple_green)]
    atlas = Image.new("RGBA", (CELL * 4, CELL * 2), (0, 0, 0, 0))
    for i, mk in enumerate(makers):
        rng = random.Random(args.seed + i * 101)
        im = finish(mk(rng))
        atlas.paste(im, ((i % 4) * CELL, (i // 4) * CELL))
        cov = np.asarray(im)[..., 3].mean() / 255.0
        print(f"cell {i} coverage {cov:.2f}")
    atlas.save(args.out, optimize=True)
    print("wrote", args.out, atlas.size)
    if args.petal:
        make_petal().save(args.petal, optimize=True)
        print("wrote", args.petal)
    if args.preview:
        bg = Image.new("RGBA", atlas.size, (150, 170, 190, 255))
        bg.alpha_composite(atlas)
        bg.convert("RGB").save(args.preview)


if __name__ == "__main__":
    main()
