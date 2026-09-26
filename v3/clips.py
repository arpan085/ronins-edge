"""Clip library. Every clip is authored with anticipation, contact poses,
weight transfer, overlap and follow-through. Personality varies per character."""
import sys
sys.path.insert(0, "/data/ronins_edge/v3")
from anim_core import Timeline, Clip, pose, merge, add, lerp_pose, mirror_pose, ROOT
from math import sin, cos, pi, radians, asin, acos, atan2, degrees

# ----------------------------------------------------------- curve helper
def cyc(t, pts):
    """Cyclic Catmull-Rom through (phase, value) control points."""
    t = t % 1.0
    n = len(pts)
    order = sorted(range(n), key=lambda i: pts[i][0] % 1.0)
    ph = [pts[i][0] % 1.0 for i in order]
    vs = [pts[i][1] for i in order]
    i = n - 1
    for j in range(n):
        if ph[j] <= t + 1e-9: i = j
        else: break
    i1 = (i + 1) % n
    span = (ph[i1] - ph[i]) % 1.0
    if span < 1e-9: span = 1.0
    u = ((t - ph[i]) % 1.0) / span
    v0, v1, v2, v3 = vs[(i - 1) % n], vs[i], vs[i1], vs[(i1 + 1) % n]
    return 0.5 * ((2 * v1) + (-v0 + v2) * u + (2 * v0 - 5 * v1 + 4 * v2 - v3) * u * u
                  + (-v0 + 3 * v1 - 3 * v2 + v3) * u * u * u)

# ----------------------------------------------------------- personality
PERSONA = {
    # posture / tempo traits that make each character readable from movement alone
    "kaito":    dict(lean=3, armout=13, stoop=0, chest=4, tempo=1.00, poise=1.00,
                     idlebreath=1.0, headscan=1.0, swagger=0.0),
    "ashigaru": dict(lean=5, armout=10, stoop=4, chest=2, tempo=0.92, poise=0.72,
                     idlebreath=1.35, headscan=0.5, swagger=0.0),   # disciplined, tense
    "archer":   dict(lean=2, armout=11, stoop=1, chest=3, tempo=1.16, poise=0.60,
                     idlebreath=1.6, headscan=2.2, swagger=0.0),    # jittery, alert
    "captain":  dict(lean=1, armout=17, stoop=-2, chest=6, tempo=0.80, poise=1.45,
                     idlebreath=0.6, headscan=0.35, swagger=1.0),   # still, imposing
}

def base_stance(kind, guard=0.0):
    p = PERSONA[kind]
    w = p["armout"]
    return pose(
        hips=(2 + p["stoop"] * 0.3, 0, 0),
        spine=(1.5 + p["stoop"] * 0.4, 0, 0),
        chest=(p["chest"] * 0.5, 0, 0),
        upperchest=(p["chest"] * 0.5 - p["stoop"] * 0.3, 0, 0),
        neck=(-3 - p["stoop"] * 0.4, 0, 0),
        head=(-1.5, 0, 0),
        shoulder__L=(0, 0, -5 - guard * 4), shoulder__R=(0, 0, 5 + guard * 4),
        upperarm__L=(-16 - guard * 16, 0, w), forearm__L=(-52 - guard * 26, 0, 0),
        upperarm__R=(-22 - guard * 20, 0, -w - 3), forearm__R=(-58 - guard * 24, 0, 0),
        hand__L=(0, 0, 0), hand__R=(0, 0, 0),
        thigh__L=(-6, 0, 1.5), thigh__R=(8, 0, -1.5),
        shin__L=(-11, 0, 0), shin__R=(-8, 0, 0),
        foot__L=(5, 0, 0), foot__R=(1, 0, 0),
        toe__L=(0, 0, 0), toe__R=(0, 0, 0),
    )

# =========================================================== LOCOMOTION
# ---- leg solver -----------------------------------------------------------
# Gaits are authored as a *foot path*, then solved with two-link IK. Driving the
# ankle directly is the only way the planted foot can travel at exactly body
# speed: with forward kinematics the knee-absorb curve fights the thigh sweep
# and the contact stalls, which reads as sliding no matter how the clip is
# retimed. Hip height is derived from the same constraint, so the pelvis dips
# through double support instead of over-extending the leg.
THIGH_L = 0.410
SHIN_L = 0.422
REACH = THIGH_L + SHIN_L          # 0.832, ankle at rest height
KMAX = 0.975                      # never fully lock the knee

def leg_ik(dx, dy, zdown):
    """dx: lateral (+ = character's right), dy: fore-aft (+ = forward),
    zdown: hip height above the ankle. Returns (thigh_x, thigh_z, shin_x) deg."""
    d = (dx * dx + dy * dy + zdown * zdown) ** 0.5
    d = min(d, (THIGH_L + SHIN_L) * KMAX)
    d = max(d, abs(THIGH_L - SHIN_L) + 0.02)
    abduct = -degrees(atan2(dx, max(zdown, 0.05)))
    plane = (dx * dx + zdown * zdown) ** 0.5
    psi = degrees(atan2(dy, max(plane, 0.05)))
    ca = (THIGH_L * THIGH_L + d * d - SHIN_L * SHIN_L) / (2.0 * THIGH_L * d)
    alpha = degrees(acos(max(-1.0, min(1.0, ca))))
    ck = (THIGH_L * THIGH_L + SHIN_L * SHIN_L - d * d) / (2.0 * THIGH_L * SHIN_L)
    knee = 180.0 - degrees(acos(max(-1.0, min(1.0, ck))))
    return psi + alpha, abduct, -knee

# The pelvis carries both legs, so its pitch/yaw/roll swings the ankles
# sideways unless the leg solve happens in pelvis space. HIP_PIVOT is where the
# hips bone rotates; HIP_OFF is the thigh root relative to it.
HIP_PIVOT = (0.0, 0.0, 0.95)
HIP_OFF = (0.098, 0.0, -0.020)

def _rx(a):
    from math import sin as _s, cos as _c, radians as _r
    a = _r(a); c, t = _c(a), _s(a)
    return ((1, 0, 0), (0, c, -t), (0, t, c))

def _ry(a):
    from math import sin as _s, cos as _c, radians as _r
    a = _r(a); c, t = _c(a), _s(a)
    return ((c, 0, t), (0, 1, 0), (-t, 0, c))

def _rz(a):
    from math import sin as _s, cos as _c, radians as _r
    a = _r(a); c, t = _c(a), _s(a)
    return ((c, -t, 0), (t, c, 0), (0, 0, 1))

def _mm(a, b):
    return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3))
                 for i in range(3))

# The hips euler is authored in Blender *bone* space, and the hips bone runs
# along its local +Y. Measured rest basis (bone X,Y,Z as armature-space
# columns) is exactly ((1,0,0),(0,0,-1),(0,1,0)): local X = world X, local Y =
# world Z, local Z = world -Y. Conjugating the bone-space euler through that
# basis, and accounting for the solver's mirrored character space, the world
# rotation is Ry(-rz) * Rz(ry) * Rx(rx). Verified by sweeping the sign
# combinations against real FK ankle positions (probe_legs.py): this one
# leaves 0.0042 m of stance lateral travel, the others 0.069-0.222 m.
# Getting it wrong is not cosmetic - the uncorrected pelvis swing drags the
# planted ankle 0.108 m sideways per stance, which was the entire source of
# the 1.1 m/s "foot slide" the QA harness kept reporting.
HIPS_SIGNS = (1.0, 1.0, -1.0)

def _hips_rotmat(rx, ry, rz):
    sx, sy, sz = HIPS_SIGNS
    return _mm(_ry(sz * rz), _mm(_rz(sy * ry), _rx(sx * rx)))

def _mv(m, v):
    return (m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
            m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
            m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2])

def _mtv(m, v):     # transpose (inverse for a rotation)
    return (m[0][0] * v[0] + m[1][0] * v[1] + m[2][0] * v[2],
            m[0][1] * v[0] + m[1][1] * v[1] + m[2][1] * v[2],
            m[0][2] * v[0] + m[1][2] * v[1] + m[2][2] * v[2])

def leg_ik_world(side, ankle, hips_rot, root_z):
    """Solve one leg for a *character-space* ankle target. side is +1 for the
    right leg, -1 for the left.

    The pelvis swing is cancelled here, so the authored ankle path is what the
    ankle actually does in character space."""
    R = _hips_rotmat(*hips_rot)
    pivot = (HIP_PIVOT[0], HIP_PIVOT[1], HIP_PIVOT[2] + root_z)
    off = (HIP_OFF[0] * side, HIP_OFF[1], HIP_OFF[2])
    root = tuple(pivot[i] + _mv(R, off)[i] for i in range(3))
    v = (ankle[0] - root[0], ankle[1] - root[1], ankle[2] - root[2])
    lv = _mtv(R, v)
    th, ab, sh = leg_ik(lv[0] * side, lv[1], max(-lv[2], 0.08))
    return th, ab * side, sh

def _foot_track(ph, duty, stride, rise, clear, fwd=True):
    """Returns (offset along the travel axis, ankle height above rest).
    Stance is strictly linear so the contact cannot creep."""
    if ph < duty:
        u = ph / duty
        off = stride * (0.5 - u)
        if not fwd: off = -off
        # the ankle lifts at both ends of stance: heel strike and toe-off
        h = rise * (2.0 * u - 1.0) ** 2
        return off, h, u, True
    u = (ph - duty) / (1.0 - duty)
    e = u * u * (3 - 2 * u)
    e = e + 0.12 * sin(pi * u) * (1 - u)      # slight overshoot, foot reaches
    off = stride * (-0.5 + e)
    if not fwd: off = -off
    h = clear * sin(pi * min(1.0, u * 1.06)) ** 0.85 + rise * (1.0 - sin(pi * u))
    return off, h, u, False

def gait_pose(t, g):
    """Analytic gait driven by an authored foot path plus two-link IK."""
    duty = g.get("duty", 0.60)
    S = g["stride_m"]
    rise = g["rise"]; clear = g["clear"]
    arm = g["arm"]; lean = g["lean"]
    twist = g["twist"]; hipdrop = g["hipdrop"]
    back = g.get("back", False)

    def track(ph):
        return _foot_track(ph, duty, S, rise, clear, not back)

    oL, hL, uL, stL = track(t)
    oR, hR, uR, stR = track((t + 0.5) % 1.0)
    xL, xR = -0.104, 0.104                      # stance width, in character space
    # hip height: the lowest value either leg can support without locking out
    def need(o, h):
        r = (THIGH_L + SHIN_L) * KMAX
        q = r * r - o * o
        return (q ** 0.5 if q > 0.0 else 0.15) + h
    hipz = min(REACH, need(oL, hL), need(oR, hR))
    rootz = hipz - REACH

    # ankle roll: heel strike -> flat -> toe-off (reversed when backpedalling)
    def ankle(ph, u, stance):
        if back:
            if stance: return -13.0 + 22.0 * (u ** 0.7), -5.0 + 8.0 * u
            return 9.0 - 22.0 * (u ** 0.8), 3.0 - 8.0 * u
        if stance:
            return g["heel"] * (1.0 - min(1.0, u * 3.2)) - g["toeoff"] * max(0.0, u - 0.55) / 0.45, \
                   -g["toe"] * max(0.0, u - 0.6) / 0.4
        return -g["toeoff"] * max(0.0, 1.0 - u * 2.4) + g["heel"] * min(1.0, max(0.0, u - 0.4) / 0.6), \
               -g["toe"] * max(0.0, 1.0 - u * 2.6)
    ftL, toL = ankle(t, uL, stL)
    ftR, toR = ankle((t + 0.5) % 1.0, uR, stR)

    hroll = hipdrop * cyc(t, [(0.00, 0.2), (0.25, 1.0), (0.50, -0.2), (0.75, -1.0)])
    hyaw = twist * cyc(t, [(0.00, 1.0), (0.25, 0.0), (0.50, -1.0), (0.75, 0.0)])
    cyaw = -twist * g["counter"] * cyc(t, [(0.00, 1.0), (0.25, 0.0), (0.50, -1.0), (0.75, 0.0)])
    aL = -arm * cyc(t, [(0.00, 1.0), (0.28, 0.05), (0.50, -1.0), (0.78, -0.05)])
    if back: aL *= -1.0
    aR = -aL
    hips_rot = (2 + lean * 0.25, hyaw, hroll)
    ank_z = 0.098
    thL, abL, shL = leg_ik_world(-1, (xL, oL, ank_z + hL), hips_rot, rootz)
    thR, abR, shR = leg_ik_world(1, (xR, oR, ank_z + hR), hips_rot, rootz)
    return pose(
        hips=hips_rot,
        spine=(lean * 0.35, cyaw * 0.35, -hroll * 0.30),
        chest=(lean * 0.40, cyaw * 0.40, -hroll * 0.25),
        upperchest=(lean * 0.35, cyaw * 0.30, -hroll * 0.20),
        neck=(-lean * 0.55, -cyaw * 0.45, 0),
        head=(-lean * 0.30, -cyaw * 0.35, -hroll * 0.12),
        shoulder__L=(0, 0, -5 - aL * 0.10), shoulder__R=(0, 0, 5 - aR * 0.10),
        upperarm__L=(aL, 0, g["armout"] + abs(aL) * 0.05),
        upperarm__R=(aR, 0, -g["armout"] - abs(aR) * 0.05),
        forearm__L=(-g["elbow"] - 14 * max(0, aL / max(arm, 1)), 0, 0),
        forearm__R=(-g["elbow"] - 14 * max(0, aR / max(arm, 1)), 0, 0),
        thigh__L=(thL, 0, 1.5 + abL), thigh__R=(thR, 0, -1.5 + abR),
        shin__L=(shL, 0, 0), shin__R=(shR, 0, 0),
        foot__L=(ftL, 0, -abL * 0.7), foot__R=(ftR, 0, -abR * 0.7),
        toe__L=(toL, 0, 0), toe__R=(toR, 0, 0),
        _root_loc=(0, 0, rootz),
    )

GAIT = {
    # n is identical for every tier on purpose: a blend space stays phase
    # coherent only when the clips it interpolates share a cycle length. Speed
    # comes from stride plus the runtime time-scale, so cadence rises with
    # speed without desynchronising the contacts.
    "walk":   dict(v=1.15, arm=15, lean=3,  twist=4,  hipdrop=3.5,
                   heel=12, toeoff=18, toe=24, counter=0.8, armout=12, elbow=30,
                   duty=0.60, n=24, rise=0.055, clear=0.10, vside=0.70, backscale=0.74),
    "jog":    dict(v=1.55, arm=28, lean=9,  twist=7,  hipdrop=4.5,
                   heel=9,  toeoff=28, toe=32, counter=0.9, armout=14, elbow=60,
                   duty=0.54, n=24, rise=0.078, clear=0.17, vside=0.90, backscale=0.74),
    "sprint": dict(v=1.90, arm=42, lean=18, twist=10, hipdrop=5.0,
                   heel=5,  toeoff=36, toe=38, counter=1.0, armout=16, elbow=84,
                   duty=0.46, n=24, rise=0.100, clear=0.24, vside=0.90, backscale=0.70),
}

def gait_params(speed, scale=1.0):
    g = dict(GAIT[speed])
    cycle = g["n"] / 30.0
    g["stride_m"] = g["v"] * g["duty"] * cycle * scale
    g["side_m"] = g["vside"] * g["duty"] * cycle * scale
    return g

def back_pose(t, g):
    """Backpedal: the same solver with the travel axis reversed, a guarded
    upper body and a head check over the shoulder."""
    gb = dict(g)
    gb["back"] = True
    gb["stride_m"] = g["stride_m"] * g.get("backscale", 0.74)
    gb["arm"] = g["arm"] * 0.45
    gb["twist"] = g["twist"] * 0.5
    gb["clear"] = g["clear"] * 0.8
    ps = gait_pose(t, gb)
    look = 6.0 * cyc(t, [(0.0, 0.0), (0.35, 1.0), (0.70, -0.6)])
    return merge(ps, pose(
        hips=(ps["hips"][0] - 5, ps["hips"][1], ps["hips"][2]),
        spine=(-3.5, ps["spine"][1], ps["spine"][2]),
        chest=(-4.5, ps["chest"][1], ps["chest"][2]),
        upperchest=(-3.0, ps["upperchest"][1], ps["upperchest"][2]),
        neck=(5.0, ps["neck"][1] + look * 0.5, 0),
        head=(3.0, ps["head"][1] + look, 0)))

def strafe_pose(t, g, s):
    """Side step: the foot path runs along the lateral axis instead, so the
    planted foot slides past the body at exactly the strafe speed."""
    duty = g.get("duty", 0.58)
    A = g["side_m"]
    rise = g["rise"] * 0.8
    clear = g["clear"] * 0.7

    def track(ph):
        o, h, u, st = _foot_track(ph, duty, A, rise, clear, True)
        return s * o, h, u, st

    oL, hL, uL, stL = track(t)
    oR, hR, uR, stR = track((t + 0.5) % 1.0)
    xL = -0.105 + oL
    xR = 0.105 + oR

    def need(x, h):
        r = (THIGH_L + SHIN_L) * KMAX
        q = r * r - x * x
        return (q ** 0.5 if q > 0.0 else 0.15) + h
    hipz = min(REACH, need(xL, hL), need(xR, hR))
    rootz = hipz - REACH
    hroll = g["hipdrop"] * cyc(t, [(0.00, 1.0), (0.50, -1.0)])
    lead = 0.35 * (hR - hL) / max(clear, 0.01)
    hips_rot = (2 + g["lean"] * 0.2, s * 2.0 * lead, hroll - s * 2.0)
    thL, abL, shL = leg_ik_world(-1, (xL, 0.0, 0.098 + hL), hips_rot, rootz)
    thR, abR, shR = leg_ik_world(1, (xR, 0.0, 0.098 + hR), hips_rot, rootz)
    return pose(
        hips=hips_rot,
        spine=(g["lean"] * 0.3, -s * 3.0, -hroll * 0.30),
        chest=(g["lean"] * 0.3, -s * 7.0, -hroll * 0.25),
        upperchest=(g["lean"] * 0.25, -s * 5.0, -hroll * 0.2),
        neck=(-1.0, s * 9.0, 0), head=(-1.0, s * 6.0, -hroll * 0.1),
        shoulder__L=(0, 0, -5), shoulder__R=(0, 0, 5),
        upperarm__L=(-6 - 4 * lead, 0, g["armout"] + 4),
        upperarm__R=(-6 + 4 * lead, 0, -g["armout"] - 4),
        forearm__L=(-g["elbow"] * 0.8, 0, 0),
        forearm__R=(-g["elbow"] * 0.8, 0, 0),
        thigh__L=(thL, 0, 1.5 + abL), thigh__R=(thR, 0, -1.5 + abR),
        shin__L=(shL, 0, 0), shin__R=(shR, 0, 0),
        foot__L=(2.0, 0, -abL * 0.75), foot__R=(2.0, 0, -abR * 0.75),
        toe__L=(-hL * 40.0, 0, 0), toe__R=(-hR * 40.0, 0, 0),
        _root_loc=(0, 0, rootz),
    )

def loco_clip(kind, speed, mode="F", scale=1.0):
    g = gait_params(speed)
    p = PERSONA[kind]
    g["lean"] = g["lean"] * (0.7 + 0.3 * p["poise"]) + p["stoop"] * 0.4
    g["armout"] = g["armout"] + (p["armout"] - 13) * 0.6
    g["stride_m"] *= scale
    g["side_m"] *= scale
    n = g["n"]
    tl = Timeline(loop=True)
    steps = 24
    for i in range(steps + 1):
        t = (i / steps) % 1.0
        if mode == "B":
            ps = back_pose(t, g)
        elif mode == "L":
            ps = strafe_pose(t, g, -1.0)
        elif mode == "R":
            ps = strafe_pose(t, g, 1.0)
        else:
            ps = gait_pose(t, g)
        tl.k(i / steps * n, ps, "linear")
    return tl, n

def idle_loco_clip(kind):
    """Blend-space centre. Shares the locomotion cycle length so interpolating
    it against a gait clip cannot slip out of phase; the feet never leave the
    ground, so it contributes zero stride."""
    p = PERSONA[kind]
    base = base_stance(kind, 0.0)
    n = GAIT["walk"]["n"]
    tl = Timeline(loop=True)
    steps = 24
    br = p["idlebreath"]
    for i in range(steps + 1):
        t = i / steps
        a = 2 * pi * t
        breath = sin(a)
        p2 = dict(base)
        p2["spine"] = (base["spine"][0] + 0.5 * br * breath, base["spine"][1], base["spine"][2])
        p2["chest"] = (base["chest"][0] + 1.0 * br * breath, base["chest"][1], base["chest"][2])
        p2["upperchest"] = (base["upperchest"][0] + 0.8 * br * breath, 0, 0)
        p2["neck"] = (base["neck"][0] - 0.6 * br * breath, 0, 0)
        p2["shoulder.L"] = (0, -0.9 * br * breath, base["shoulder.L"][2])
        p2["shoulder.R"] = (0, 0.9 * br * breath, base["shoulder.R"][2])
        tl.k(t * n, p2, "smooth")
    return tl, n

# =========================================================== IDLES
def idle_clip(kind, variant=0, guard=False):
    p = PERSONA[kind]
    base = base_stance(kind, 1.0 if guard else 0.0)
    n = int(round((150 if variant == 0 else 120) / max(p["tempo"] * 0.8, 0.4)))
    tl = Timeline(loop=True)
    steps = 24
    br = p["idlebreath"]
    for i in range(steps + 1):
        t = i / steps
        a = 2 * pi * t
        breath = sin(a * 2.0)
        p2 = dict(base)
        p2["spine"] = (base["spine"][0] + 0.7 * br * breath, base["spine"][1], base["spine"][2])
        p2["chest"] = (base["chest"][0] + 1.5 * br * breath, base["chest"][1], base["chest"][2])
        p2["upperchest"] = (base["upperchest"][0] + 1.1 * br * breath, 0, 0)
        p2["neck"] = (base["neck"][0] - 0.9 * br * breath, 0, 0)
        p2["shoulder.L"] = (0, -1.2 * br * breath, base["shoulder.L"][2])
        p2["shoulder.R"] = (0, 1.2 * br * breath, base["shoulder.R"][2])
        # slow weight shift between the feet: hips drift and roll
        shift = sin(a * (0.5 if variant == 0 else 1.0) + (1.2 if variant else 0.0))
        p2["hips"] = (base["hips"][0], base["hips"][1] + 1.6 * shift, base["hips"][2] + 2.4 * shift)
        p2["thigh.L"] = (base["thigh.L"][0] - 2.0 * shift, 0, 1.5)
        p2["thigh.R"] = (base["thigh.R"][0] + 2.0 * shift, 0, -1.5)
        p2["shin.L"] = (base["shin.L"][0] + 2.2 * shift, 0, 0)
        p2["shin.R"] = (base["shin.R"][0] - 2.2 * shift, 0, 0)
        p2["foot.L"] = (base["foot.L"][0] + 0.8 * shift, 0, 0)
        p2["ankle_unused"] = (0, 0, 0)
        del p2["ankle_unused"]
        # head life: scan, settle, blink cadence handled by the facial layer
        scan = p["headscan"]
        if variant == 0:
            hy = 5.0 * scan * cyc(t, [(0.0, 0), (0.30, 0.2), (0.45, 1.0), (0.62, 0.9), (0.80, -0.1)])
            hx = 2.0 * scan * cyc(t, [(0.0, 0), (0.40, -0.6), (0.70, 0.3)])
        elif variant == 1:
            hy = 7.0 * scan * cyc(t, [(0.0, 0), (0.18, -1.0), (0.34, -0.8), (0.55, 0.6), (0.78, 0.0)])
            hx = 3.0 * scan * cyc(t, [(0.0, 0), (0.25, 0.8), (0.60, -0.4)])
        else:
            hy = 3.0 * scan * sin(a * 0.5)
            hx = 1.5 * scan * sin(a * 0.75)
        p2["neck"] = (p2["neck"][0] + hx * 0.4, hy * 0.45, 0)
        p2["head"] = (base["head"][0] + hx * 0.6, hy * 0.55, hy * 0.06)
        # eyes lead the head, jaw relaxes
        p2["eye.L"] = (0, hy * 0.9, 0); p2["eye.R"] = (0, hy * 0.9, 0)
        blink = 1.0 if (0.20 < t < 0.225 or (variant == 1 and 0.66 < t < 0.685)) else 0.0
        p2["brow.L"] = (blink * -14 + 1.5 * scan * sin(a * 0.5), 0, 0)
        p2["brow.R"] = (blink * -14 + 1.5 * scan * sin(a * 0.5), 0, 0)
        p2["jaw"] = (1.2 * br * max(0.0, breath), 0, 0)
        p2[ROOT] = (0, 0, 0.004 * breath)
        tl.k(t * n, p2, "linear")
    return tl, n

def breathe_additive(kind):
    """Additive layer: spine/chest/neck only, deltas around zero."""
    n = 96
    tl = Timeline(loop=True)
    for i in range(25):
        t = i / 24.0
        b = sin(2 * pi * t)
        tl.k(t * n, pose(spine=(0.8 * b, 0, 0), chest=(1.7 * b, 0, 0),
                         upperchest=(1.2 * b, 0, 0), neck=(-1.0 * b, 0, 0),
                         shoulder__L=(0, -1.4 * b, 0), shoulder__R=(0, 1.4 * b, 0)), "linear")
    return tl, n

# =========================================================== STARTS / STOPS / TURNS
def start_run(kind):
    p = PERSONA[kind]
    idle = base_stance(kind)
    g = gait_params("jog"); g["lean"] = 10; g["armout"] = 14
    crouch = merge(idle, pose(hips=(10, 0, 0), spine=(7, 0, 0), chest=(5, 0, 0),
                              neck=(-6, 0, 0), head=(-4, 0, 0),
                              thigh__L=(22, 0, 1.5), thigh__R=(16, 0, -1.5),
                              shin__L=(-34, 0, 0), shin__R=(-28, 0, 0),
                              foot__L=(14, 0, 0), foot__R=(11, 0, 0),
                              upperarm__L=(-34, 0, 13), upperarm__R=(14, 0, -16),
                              forearm__L=(-70, 0, 0), forearm__R=(-40, 0, 0),
                              _root_loc=(0, 0, -0.045)))
    drive = merge(gait_pose(0.70, g), pose(hips=(20, 0, 0), spine=(11, 0, 0), chest=(8, 0, 0),
                                           neck=(-10, 0, 0), _root_loc=(0, 0, -0.012)))
    tl = Timeline()
    tl.k(0, idle, "out").k(5, crouch, "sharp").k(11, drive, "out")
    tl.k(20, gait_pose(0.0, g), "linear")
    return tl, 20

def stop_run(kind, hard=True):
    g = gait_params("jog" if hard else "walk")
    run = gait_pose(0.30, g)
    plant = merge(run, pose(hips=(-12, 0, 0), spine=(-9, 0, 0), chest=(-11, 0, 0),
                            neck=(9, 0, 0), head=(6, 0, 0),
                            thigh__L=(34, 0, 1.5), thigh__R=(-14, 0, -1.5),
                            shin__L=(-30, 0, 0), shin__R=(-14, 0, 0),
                            foot__L=(22, 0, 0), foot__R=(-10, 0, 0),
                            upperarm__L=(-46, 0, 26), upperarm__R=(-40, 0, -28),
                            forearm__L=(-64, 0, 0), forearm__R=(-58, 0, 0),
                            _root_loc=(0, 0, -0.06)))
    settle = merge(base_stance(kind), pose(hips=(4, 0, 0), _root_loc=(0, 0, -0.012)))
    tl = Timeline()
    tl.k(0, run, "out").k(6 if hard else 8, plant, "out")
    tl.k(14 if hard else 15, settle, "over").k(24 if hard else 26, base_stance(kind), "smooth")
    return tl, 24 if hard else 26

def turn_clip(kind, deg, right=True):
    """In-place turn: weight shifts onto the pivot foot before the body rotates."""
    p = PERSONA[kind]
    s = 1.0 if right else -1.0
    base = base_stance(kind)
    n = {45: 16, 90: 22, 180: 32}[deg]
    n = int(n / max(p["tempo"] * 0.85, 0.5))
    # 1: anticipation - weight onto the inside foot, shoulders lead
    antic = merge(base, pose(
        hips=(3, -s * deg * 0.06, -s * 4),
        spine=(2, -s * deg * 0.05, 0), chest=(3, -s * deg * 0.09, 0),
        upperchest=(2, -s * deg * 0.10, 0),
        neck=(-3, s * deg * 0.14, 0), head=(-2, s * deg * 0.20, 0),
        thigh__L=(-6 - s * 3, 0, 1.5), thigh__R=(8 + s * 3, 0, -1.5),
        shin__L=(-13, 0, 0), shin__R=(-10, 0, 0),
        _root_loc=(0, 0, -0.018)))
    # 2: step across - hips lead, opposite foot lifts and crosses
    cross = merge(base, pose(
        hips=(5, s * deg * 0.42, s * 5),
        spine=(3, s * deg * 0.16, 0), chest=(2, s * deg * 0.14, 0),
        upperchest=(2, s * deg * 0.12, 0),
        neck=(-4, s * deg * 0.10, 0), head=(-2, s * deg * 0.12, 0),
        thigh__L=(-14 if right else 16, 0, 1.5 + s * 10),
        thigh__R=(16 if right else -14, 0, -1.5 + s * 10),
        shin__L=(-30 if right else -14, 0, 0), shin__R=(-14 if right else -30, 0, 0),
        foot__L=(9, 0, 0), foot__R=(9, 0, 0),
        upperarm__L=(-20 - s * 8, 0, 14), upperarm__R=(-24 + s * 8, 0, -16),
        _root_loc=(0, 0, -0.030)))
    # 3: plant and settle at the new facing (rig yaw returns to 0, code owns facing)
    land = merge(base, pose(hips=(4, s * deg * 0.10, -s * 3), chest=(4, -s * 5, 0),
                            neck=(-4, -s * 4, 0), _root_loc=(0, 0, -0.016)))
    tl = Timeline()
    tl.k(0, base, "out").k(n * 0.22, antic, "sharp").k(n * 0.60, cross, "out")
    tl.k(n * 0.82, land, "over").k(n, base, "smooth")
    return tl, n

# =========================================================== EVASION
def dodge_clip(kind, direction):
    p = PERSONA[kind]
    base = base_stance(kind)
    n = int(round(24 / max(p["tempo"], 0.5)))
    d = direction
    s = 1.0 if d == "R" else -1.0
    compress = merge(base, pose(
        hips=(12, 0, 0), spine=(8, 0, 0), chest=(7, 0, 0), upperchest=(5, 0, 0),
        neck=(-7, 0, 0), head=(-5, 0, 0),
        thigh__L=(26, 0, 1.5), thigh__R=(22, 0, -1.5),
        shin__L=(-44, 0, 0), shin__R=(-40, 0, 0),
        foot__L=(18, 0, 0), foot__R=(16, 0, 0),
        upperarm__L=(-30, 0, 18), upperarm__R=(-34, 0, -20),
        forearm__L=(-72, 0, 0), forearm__R=(-78, 0, 0),
        _root_loc=(0, 0, -0.085)))
    if d == "F":
        burst = merge(base, pose(hips=(26, 0, 0), spine=(14, 0, 0), chest=(10, 0, 0),
                                 neck=(-12, 0, 0), head=(-8, 0, 0),
                                 thigh__L=(-30, 0, 1.5), thigh__R=(38, 0, -1.5),
                                 shin__L=(-14, 0, 0), shin__R=(-58, 0, 0),
                                 foot__L=(-18, 0, 0), foot__R=(22, 0, 0),
                                 upperarm__L=(-52, 0, 24), upperarm__R=(-20, 0, -18),
                                 _root_loc=(0, 0.30, -0.035)))
        recover = merge(base, pose(hips=(8, 0, 0), thigh__L=(-12, 0, 1.5), thigh__R=(18, 0, -1.5),
                                   shin__L=(-20, 0, 0), shin__R=(-26, 0, 0),
                                   _root_loc=(0, 0.42, -0.020)))
        endloc = (0, 0.46, 0)
    elif d == "B":
        burst = merge(base, pose(hips=(-14, 0, 0), spine=(-8, 0, 0), chest=(-10, 0, 0),
                                 neck=(9, 0, 0), head=(6, 0, 0),
                                 thigh__L=(30, 0, 1.5), thigh__R=(-24, 0, -1.5),
                                 shin__L=(-50, 0, 0), shin__R=(-12, 0, 0),
                                 foot__L=(16, 0, 0), foot__R=(-16, 0, 0),
                                 upperarm__L=(-14, 0, 22), upperarm__R=(-18, 0, -24),
                                 _root_loc=(0, -0.28, -0.030)))
        recover = merge(base, pose(hips=(-4, 0, 0), thigh__L=(10, 0, 1.5), thigh__R=(-6, 0, -1.5),
                                   _root_loc=(0, -0.40, -0.016)))
        endloc = (0, -0.44, 0)
    else:
        burst = merge(base, pose(
            hips=(10, -s * 8, -s * 12), spine=(5, -s * 5, -s * 7), chest=(4, s * 8, -s * 5),
            neck=(-5, s * 12, 0), head=(-3, s * 14, 0),
            thigh__L=(4, 0, 1.5 + s * 26), thigh__R=(4, 0, -1.5 + s * 26),
            shin__L=(-34, 0, 0), shin__R=(-30, 0, 0),
            foot__L=(10, 0, s * 6), foot__R=(10, 0, s * 6),
            upperarm__L=(-26, 0, 20 + s * 8), upperarm__R=(-30, 0, -22 + s * 8),
            _root_loc=(s * 0.30, 0.02, -0.045)))
        recover = merge(base, pose(hips=(5, 0, -s * 5), chest=(4, s * 4, 0),
                                   thigh__L=(-4, 0, 1.5 + s * 8), thigh__R=(6, 0, -1.5 + s * 8),
                                   _root_loc=(s * 0.40, 0, -0.018)))
        endloc = (s * 0.44, 0, 0)
    tl = Timeline()
    tl.k(0, base, "out")
    tl.k(n * 0.16, compress, "sharp")          # compress before the explosive move
    tl.k(n * 0.40, burst, "out")               # burst
    tl.k(n * 0.66, recover, "over")            # absorb / overshoot
    tl.k(n, merge(base, pose(_root_loc=endloc)), "smooth")
    return tl, n, endloc

def roll_clip(kind):
    base = base_stance(kind)
    n = 30
    tuck = merge(base, pose(hips=(40, 0, 0), spine=(26, 0, 0), chest=(22, 0, 0),
                            neck=(-14, 0, 0), head=(-18, 0, 0),
                            thigh__L=(72, 0, 1.5), thigh__R=(66, 0, -1.5),
                            shin__L=(-96, 0, 0), shin__R=(-92, 0, 0),
                            upperarm__L=(-70, 0, 26), upperarm__R=(-74, 0, -28),
                            forearm__L=(-100, 0, 0), forearm__R=(-104, 0, 0),
                            _root_loc=(0, 0.20, -0.30)))
    over = merge(tuck, pose(hips=(96, 0, 0), spine=(30, 0, 0), _root_loc=(0, 0.62, -0.38)))
    up = merge(base, pose(hips=(24, 0, 0), spine=(14, 0, 0), thigh__L=(44, 0, 1.5),
                          thigh__R=(10, 0, -1.5), shin__L=(-62, 0, 0), shin__R=(-30, 0, 0),
                          _root_loc=(0, 1.05, -0.12)))
    tl = Timeline()
    tl.k(0, base, "out").k(4, merge(base, pose(hips=(16, 0, 0), thigh__L=(24, 0, 1.5),
                                               shin__L=(-40, 0, 0), _root_loc=(0, 0, -0.07))), "sharp")
    tl.k(10, tuck, "linear").k(18, over, "linear").k(25, up, "over").k(n, base, "smooth")
    return tl, n, (0, 1.25, 0)

def jump_clips(kind):
    base = base_stance(kind)
    crouch = merge(base, pose(hips=(18, 0, 0), spine=(11, 0, 0), chest=(8, 0, 0),
                              thigh__L=(34, 0, 1.5), thigh__R=(32, 0, -1.5),
                              shin__L=(-58, 0, 0), shin__R=(-56, 0, 0),
                              foot__L=(24, 0, 0), foot__R=(22, 0, 0),
                              upperarm__L=(10, 0, 16), upperarm__R=(12, 0, -18),
                              forearm__L=(-30, 0, 0), forearm__R=(-32, 0, 0),
                              _root_loc=(0, 0, -0.14)))
    launch = merge(base, pose(hips=(-4, 0, 0), spine=(-4, 0, 0), chest=(-6, 0, 0),
                              neck=(4, 0, 0),
                              thigh__L=(-14, 0, 1.5), thigh__R=(-12, 0, -1.5),
                              shin__L=(-4, 0, 0), shin__R=(-4, 0, 0),
                              foot__L=(-26, 0, 0), foot__R=(-24, 0, 0), toe__L=(-22, 0, 0),
                              upperarm__L=(-96, 0, 22), upperarm__R=(-94, 0, -24),
                              _root_loc=(0, 0, 0.05)))
    air = merge(base, pose(hips=(8, 0, 0), spine=(4, 0, 0),
                           thigh__L=(30, 0, 1.5), thigh__R=(-16, 0, -1.5),
                           shin__L=(-52, 0, 0), shin__R=(-20, 0, 0),
                           foot__L=(-8, 0, 0), foot__R=(-16, 0, 0),
                           upperarm__L=(-58, 0, 26), upperarm__R=(-44, 0, -28),
                           forearm__L=(-52, 0, 0), forearm__R=(-40, 0, 0)))
    landsoft = merge(base, pose(hips=(20, 0, 0), spine=(12, 0, 0), chest=(9, 0, 0),
                                thigh__L=(38, 0, 1.5), thigh__R=(34, 0, -1.5),
                                shin__L=(-64, 0, 0), shin__R=(-60, 0, 0),
                                foot__L=(20, 0, 0), foot__R=(18, 0, 0),
                                upperarm__L=(-40, 0, 30), upperarm__R=(-42, 0, -32),
                                _root_loc=(0, 0, -0.17)))
    up = Timeline().k(0, base, "out").k(5, crouch, "sharp").k(10, launch, "out").k(14, air, "smooth")
    loop = Timeline(loop=True)
    for i in range(9):
        t = i / 8.0
        loop.k(t * 32, merge(air, pose(
            thigh__L=(30 + 5 * sin(2 * pi * t), 0, 1.5),
            thigh__R=(-16 - 4 * sin(2 * pi * t), 0, -1.5),
            upperarm__L=(-58 + 5 * sin(2 * pi * t + 1), 0, 26),
            upperarm__R=(-44 - 5 * sin(2 * pi * t + 1), 0, -28))), "linear")
    land = Timeline().k(0, air, "out").k(4, landsoft, "snap").k(12, merge(base, pose(hips=(7, 0, 0),
              thigh__L=(6, 0, 1.5), _root_loc=(0, 0, -0.04))), "over").k(20, base, "smooth")
    return (up, 14), (loop, 32), (land, 20)
