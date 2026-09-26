"""Production animation core: bezier timing, overlap/follow-through, spring secondary motion."""
import math
from math import sin, cos, pi, radians as D

FPS = 30.0

# ---------------------------------------------------------------- easing
# cubic-bezier(p1x,p1y,p2x,p2y) timing curves, CSS style
EASE = {
    "linear": (0.333, 0.333, 0.667, 0.667),
    "smooth": (0.42, 0.00, 0.58, 1.00),   # ease in-out, generic
    "out":    (0.00, 0.00, 0.45, 1.00),   # fast start -> decelerate (settle)
    "in":     (0.55, 0.00, 1.00, 1.00),   # slow start -> accelerate (release)
    "sharp":  (0.78, 0.00, 0.96, 1.00),   # long build -> explosive
    "snap":   (0.00, 0.00, 0.16, 1.00),   # near-instant then settle (impact)
    "over":   (0.18, 0.00, 0.38, 1.22),   # overshoot then settle
    "under":  (0.30, -0.22, 0.60, 1.00),  # dip back first (anticipation)
    "hold":   (0.95, 0.00, 1.00, 0.02),   # hold then move at the very end
}

def _bez1(t, a, b):
    mt = 1.0 - t
    return 3 * mt * mt * t * a + 3 * mt * t * t * b + t * t * t

def ease_eval(name, x):
    p1x, p1y, p2x, p2y = EASE.get(name, EASE["smooth"])
    if x <= 0.0: return 0.0
    if x >= 1.0: return 1.0
    lo, hi = 0.0, 1.0
    t = x
    for _ in range(24):                       # invert x(t) by bisection
        cx = _bez1(t, p1x, p2x)
        if cx < x: lo = t
        else: hi = t
        t = 0.5 * (lo + hi)
    return _bez1(t, p1y, p2y)

# ---------------------------------------------------------------- poses
ROOT = "_root_loc"

def pose(**kw):
    """pose(hips=(2,0,0), chest=(4,0,0)) -> dict; dots written as __ (thigh__L)."""
    return {k.replace("__", "."): v for k, v in kw.items()}

def merge(*poses):
    o = {}
    for p in poses:
        if p: o.update(p)
    return o

def add(base, delta):
    """component-wise add of a delta pose onto a base pose"""
    o = dict(base)
    for k, v in delta.items():
        b = base.get(k, (0, 0, 0))
        o[k] = (b[0] + v[0], b[1] + v[1], b[2] + v[2])
    return o

def lerp_pose(a, b, k):
    o = {}
    for key in set(a) | set(b):
        va = a.get(key, (0, 0, 0)); vb = b.get(key, (0, 0, 0))
        o[key] = tuple(va[i] + (vb[i] - va[i]) * k for i in range(3))
    return o

def mirror_pose(p):
    """mirror a pose left<->right (for turn/strafe/hit variants)"""
    o = {}
    for k, v in p.items():
        if k == ROOT:
            o[k] = (-v[0], v[1], v[2]); continue
        nk = k
        if k.endswith(".L"): nk = k[:-2] + ".R"
        elif k.endswith(".R"): nk = k[:-2] + ".L"
        o[nk] = (v[0], -v[1], -v[2])
    return o

# ---------------------------------------------------------------- timeline
class Timeline:
    """Keyframes with per-segment bezier timing, sampled densely."""
    def __init__(self, loop=False):
        self.keys = []     # (frame, pose, ease_out_of_this_key)
        self.loop = loop

    def k(self, frame, p, ease="smooth"):
        self.keys.append((float(frame), p, ease))
        return self

    @property
    def length(self):
        return self.keys[-1][0] if self.keys else 0.0

    def sample(self, step=1.0):
        assert len(self.keys) >= 2, "timeline needs >= 2 keys"
        ks = sorted(self.keys, key=lambda x: x[0])
        end = ks[-1][0]
        out = []
        f = 0.0
        i = 0
        n = int(round(end / step))
        for s in range(n + 1):
            f = min(s * step, end)
            while i < len(ks) - 2 and f >= ks[i + 1][0]:
                i += 1
            f0, p0, e0 = ks[i]
            f1, p1, _ = ks[i + 1]
            span = max(f1 - f0, 1e-6)
            x = min(max((f - f0) / span, 0.0), 1.0)
            out.append((f, lerp_pose(p0, p1, ease_eval(e0, x))))
        return out

# ---------------------------------------------------------------- track utils
def _get(track, idx, bone):
    return track[idx][1].get(bone, (0, 0, 0))

def track_at(track, tf, bone, loop):
    """linear read of one bone at fractional frame index tf"""
    n = len(track)
    if loop:
        tf = tf % (n - 1)
    else:
        tf = min(max(tf, 0.0), n - 1)
    i0 = int(math.floor(tf)); i1 = i0 + 1
    if i1 > n - 1: i1 = 0 if loop else n - 1
    a = _get(track, i0, bone); b = _get(track, i1, bone)
    k = tf - i0
    return tuple(a[j] + (b[j] - a[j]) * k for j in range(3))

# ---------------------------------------------------------------- overlap
def apply_overlap(track, delays, loop=False):
    """Delay selected bones so motion cascades up the body (overlap + follow-through)."""
    out = [(f, dict(p)) for f, p in track]
    for bone, d in delays.items():
        if d <= 0: continue
        present = any(bone in p for _, p in track)
        if not present: continue
        for i in range(len(track)):
            out[i][1][bone] = track_at(track, i - d, bone, loop)
    return out

# ---------------------------------------------------------------- springs
def apply_spring(track, specs, loop=False, fps=FPS, passes=3):
    """Spring-damper secondary motion on cloth/accessory bones.

    spec: bone -> dict(driver=<bone or '_root'>, gain=(gx,gy,gz), k=, c=, limit=)
    The bone trails its driver's velocity, then oscillates back to the authored pose.
    """
    n = len(track)
    dt = 1.0 / fps
    out = [(f, dict(p)) for f, p in track]
    for bone, sp in specs.items():
        drv = sp.get("driver", "_root")
        gain = sp.get("gain", (1.0, 0.0, 0.0))
        k = sp.get("k", 90.0); c = sp.get("c", 12.0)
        lim = sp.get("limit", 26.0)
        rest_pose = [track[i][1].get(bone, (0, 0, 0)) for i in range(n)]
        # driver velocity per frame
        vel = []
        for i in range(n):
            if drv == "_root":
                a = track_at(track, i - 1, ROOT, loop); b = track_at(track, i + 1, ROOT, loop)
                # translate root motion into a pseudo angular push
                v = ((b[1] - a[1]) * 900.0, 0.0, (b[0] - a[0]) * 900.0)
            else:
                a = track_at(track, i - 1, drv, loop); b = track_at(track, i + 1, drv, loop)
                v = tuple((b[j] - a[j]) * fps * 0.5 for j in range(3))
            vel.append(v)
        x = [0.0, 0.0, 0.0]; v = [0.0, 0.0, 0.0]
        reps = passes if loop else 1
        for rep in range(reps):
            vals = []
            for i in range(n):
                for j in range(3):
                    target = -gain[j] * vel[i][j] * 0.02
                    target = max(-lim, min(lim, target))
                    acc = -k * (x[j] - target) - c * v[j]
                    v[j] += acc * dt
                    x[j] += v[j] * dt
                    x[j] = max(-lim * 1.6, min(lim * 1.6, x[j]))
                vals.append(tuple(x))
            if rep == reps - 1:
                for i in range(n):
                    r = rest_pose[i]
                    out[i][1][bone] = (r[0] + vals[i][0], r[1] + vals[i][1], r[2] + vals[i][2])
    return out

# ---------------------------------------------------------------- clip object
class Clip:
    def __init__(self, name, timeline, loop=False, overlap=None, springs=None,
                 bones_only=None, additive=False, root_motion=(0, 0, 0)):
        self.name = name
        self.tl = timeline
        self.loop = loop
        self.overlap = overlap
        self.springs = springs
        self.bones_only = bones_only
        self.additive = additive
        self.root_motion = root_motion

    def bake(self, default_overlap=None, default_springs=None):
        tr = self.tl.sample(1.0)
        ov = self.overlap if self.overlap is not None else (default_overlap or {})
        if ov: tr = apply_overlap(tr, ov, self.loop)
        sp = self.springs if self.springs is not None else (default_springs or {})
        if sp: tr = apply_spring(tr, sp, self.loop)
        return tr
