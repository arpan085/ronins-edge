"""Combat, reaction, boss and cinematic clips. Timing is deliberately uneven:
light attacks are quick and loose, heavies have long builds, deathblows breathe."""
import sys
sys.path.insert(0, "/data/ronins_edge/v3")
from anim_core import Timeline, pose, merge, lerp_pose, mirror_pose, ROOT
from clips import base_stance, PERSONA, cyc
from math import sin, pi

def guard_stance(kind):
    """Combat-ready: sword up, hips coiled, weight on the back foot."""
    p = PERSONA[kind]
    return merge(base_stance(kind), pose(
        hips=(3, -10, -2), spine=(2, -5, 0), chest=(4, -12, 0), upperchest=(3, -8, 0),
        neck=(-4, 12, 0), head=(-2, 10, 0),
        shoulder__L=(0, 0, -8), shoulder__R=(0, 0, 9),
        upperarm__L=(-44, 0, 22), forearm__L=(-84, 0, 0),
        upperarm__R=(-52, 0, -26), forearm__R=(-92, 0, 0),
        hand__R=(0, 0, -8), hand__L=(0, 0, 6),
        thigh__L=(-14, 0, 4), thigh__R=(14, 0, -4),
        shin__L=(-20, 0, 0), shin__R=(-16, 0, 0),
        foot__L=(8, 0, 0), foot__R=(2, 0, 0),
        _root_loc=(0, 0, -0.035)))

# --------------------------------------------------------------- Kaito attacks
def light1(kind):
    g = guard_stance(kind)
    n = 22
    antic = merge(g, pose(
        hips=(2, -22, -3), spine=(0, -12, 0), chest=(-8, -30, 0), upperchest=(-6, -22, 0),
        neck=(2, 26, 0), head=(0, 22, 0),
        shoulder__R=(0, -6, 16), upperarm__R=(-118, 0, -34), forearm__R=(-86, 0, 0),
        upperarm__L=(-60, 0, 30), forearm__L=(-104, 0, 0),
        thigh__R=(18, 0, -4), shin__R=(-24, 0, 0), thigh__L=(-16, 0, 4),
        _root_loc=(0, -0.045, -0.02)))
    contact = merge(g, pose(
        hips=(8, 26, 4), spine=(6, 14, 0), chest=(14, 30, 0), upperchest=(10, 24, 0),
        neck=(-6, -22, 0), head=(-4, -18, 0),
        shoulder__R=(0, 4, -4), upperarm__R=(2, 0, -14), forearm__R=(-24, 0, 0),
        hand__R=(0, 0, -16),
        upperarm__L=(-30, 0, 18), forearm__L=(-70, 0, 0),
        thigh__R=(-18, 0, -4), thigh__L=(20, 0, 4), shin__L=(-26, 0, 0),
        foot__L=(12, 0, 0), toe__R=(-16, 0, 0),
        _root_loc=(0, 0.20, -0.045)))
    follow = merge(contact, pose(
        chest=(16, 38, 0), upperarm__R=(24, 0, -6), forearm__R=(-16, 0, 0),
        neck=(-4, -28, 0), _root_loc=(0, 0.26, -0.05)))
    tl = Timeline()
    tl.k(0, g, "out").k(4, antic, "sharp").k(7, contact, "snap")
    tl.k(10, follow, "out").k(16, lerp_pose(follow, g, 0.7), "smooth").k(n, g, "smooth")
    return tl, n, (0, 0.30, 0)

def light2(kind):
    g = guard_stance(kind)
    n = 20
    antic = merge(g, pose(
        hips=(3, 20, 3), chest=(6, 34, 0), upperchest=(4, 26, 0),
        neck=(-2, -26, 0), head=(-1, -20, 0),
        upperarm__R=(-24, 0, -78), forearm__R=(-66, 0, 0), hand__R=(0, 0, 20),
        upperarm__L=(-36, 0, 46), forearm__L=(-76, 0, 0),
        thigh__L=(-10, 0, 4), thigh__R=(12, 0, -4),
        _root_loc=(0, -0.02, -0.03)))
    contact = merge(g, pose(
        hips=(6, -30, -5), spine=(4, -16, 0), chest=(10, -36, 0), upperchest=(8, -28, 0),
        neck=(-4, 30, 0), head=(-2, 24, 0),
        upperarm__R=(-16, 0, 54), forearm__R=(-30, 0, 0), hand__R=(0, 0, -10),
        upperarm__L=(-48, 0, 14), forearm__L=(-92, 0, 0),
        thigh__L=(14, 0, 4), thigh__R=(-12, 0, -4), shin__L=(-22, 0, 0),
        _root_loc=(0, 0.14, -0.04)))
    tl = Timeline()
    tl.k(0, g, "out").k(3, antic, "sharp").k(6, contact, "snap")
    tl.k(9, merge(contact, pose(chest=(12, -44, 0), upperarm__R=(-10, 0, 66))), "out")
    tl.k(14, lerp_pose(contact, g, 0.65), "smooth").k(n, g, "smooth")
    return tl, n, (0, 0.20, 0)

def light3(kind):
    """Finisher: rising cut with a full step through. Slower, heavier rhythm."""
    g = guard_stance(kind)
    n = 32
    load = merge(g, pose(
        hips=(14, -18, -4), spine=(9, -10, 0), chest=(4, -26, 0), upperchest=(4, -18, 0),
        neck=(-4, 22, 0), head=(-4, 18, 0),
        upperarm__R=(-6, 0, -46), forearm__R=(-96, 0, 0), hand__R=(0, 0, 18),
        upperarm__L=(-30, 0, 34), forearm__L=(-98, 0, 0),
        thigh__L=(-18, 0, 4), thigh__R=(24, 0, -4), shin__L=(-26, 0, 0), shin__R=(-34, 0, 0),
        foot__L=(12, 0, 0), _root_loc=(0, -0.08, -0.095)))
    rise = merge(g, pose(
        hips=(-14, 24, 6), spine=(-9, 14, 0), chest=(-16, 30, 0), upperchest=(-12, 24, 0),
        neck=(10, -24, 0), head=(8, -18, 0),
        upperarm__R=(-142, 0, -18), forearm__R=(-30, 0, 0), hand__R=(0, 0, -8),
        upperarm__L=(-84, 0, 26), forearm__L=(-56, 0, 0),
        thigh__L=(22, 0, 4), thigh__R=(-20, 0, -4), shin__L=(-28, 0, 0),
        foot__L=(10, 0, 0), toe__R=(-24, 0, 0),
        _root_loc=(0, 0.34, 0.02)))
    tl = Timeline()
    tl.k(0, g, "out").k(8, load, "sharp").k(13, rise, "snap")
    tl.k(17, merge(rise, pose(chest=(-20, 36, 0), upperarm__R=(-156, 0, -10),
                              _root_loc=(0, 0.40, 0.03))), "out")
    tl.k(24, lerp_pose(rise, g, 0.55), "smooth").k(n, g, "smooth")
    return tl, n, (0, 0.46, 0)

def heavy(kind):
    """Long, readable build then a committed sweep with a heavy recovery."""
    g = guard_stance(kind)
    n = 46
    coil = merge(g, pose(
        hips=(6, -40, -6), spine=(4, -22, 0), chest=(-4, -46, 0), upperchest=(-2, -34, 0),
        neck=(0, 40, 0), head=(0, 34, 0),
        shoulder__R=(0, -10, 20), upperarm__R=(-148, 0, -38), forearm__R=(-68, 0, 0),
        upperarm__L=(-96, 0, 34), forearm__L=(-92, 0, 0),
        thigh__R=(22, 0, -4), shin__R=(-30, 0, 0), thigh__L=(-20, 0, 4),
        foot__R=(14, 0, 0), _root_loc=(0, -0.09, -0.08)))
    contact = merge(g, pose(
        hips=(10, 40, 7), spine=(8, 22, 0), chest=(18, 46, 0), upperchest=(14, 36, 0),
        neck=(-8, -34, 0), head=(-6, -28, 0),
        shoulder__R=(0, 6, -8), upperarm__R=(14, 0, -10), forearm__R=(-18, 0, 0),
        hand__R=(0, 0, -20),
        upperarm__L=(-26, 0, 16), forearm__L=(-58, 0, 0),
        thigh__L=(26, 0, 4), thigh__R=(-22, 0, -4), shin__L=(-32, 0, 0),
        foot__L=(16, 0, 0), toe__R=(-28, 0, 0),
        _root_loc=(0, 0.34, -0.075)))
    through = merge(contact, pose(
        hips=(14, 56, 8), chest=(22, 62, 0), upperarm__R=(40, 0, 4), forearm__R=(-10, 0, 0),
        neck=(-6, -44, 0), _root_loc=(0, 0.42, -0.10)))
    tl = Timeline()
    tl.k(0, g, "out").k(6, merge(g, pose(hips=(4, -16, -3), _root_loc=(0, -0.03, -0.05))), "smooth")
    tl.k(16, coil, "sharp")                      # long readable telegraph
    tl.k(21, contact, "snap")                    # explosive
    tl.k(25, through, "out")                     # follow-through past the target
    tl.k(34, lerp_pose(through, g, 0.5), "smooth").k(n, g, "smooth")
    return tl, n, (0, 0.50, 0)

def deflect(kind):
    """Perfect parry: minimal anticipation, hard stop, ringing recoil."""
    g = guard_stance(kind)
    n = 20
    meet = merge(g, pose(
        hips=(4, 6, 0), spine=(3, 4, 0), chest=(2, 10, 0), upperchest=(2, 8, 0),
        neck=(-2, -6, 0), head=(-1, -4, 0),
        shoulder__L=(0, -4, -14), shoulder__R=(0, 4, 15),
        upperarm__L=(-72, 0, 30), forearm__L=(-72, 0, 0),
        upperarm__R=(-78, 0, -22), forearm__R=(-70, 0, 0), hand__R=(0, 0, -34),
        thigh__L=(-12, 0, 4), thigh__R=(12, 0, -4),
        _root_loc=(0, 0.035, -0.03)))
    ring = merge(meet, pose(
        hips=(-2, -8, -2), spine=(-3, -5, 0), chest=(-8, -12, 0), upperchest=(-6, -9, 0),
        neck=(6, 8, 0), head=(5, 6, 0),
        upperarm__L=(-58, 0, 38), upperarm__R=(-64, 0, -34), forearm__R=(-92, 0, 0),
        hand__R=(0, 0, -16),
        _root_loc=(0, -0.075, -0.02)))
    tl = Timeline()
    tl.k(0, g, "out").k(2, meet, "snap")          # blade arrives almost instantly
    tl.k(5, ring, "out")                          # recoil from the impact
    tl.k(9, lerp_pose(ring, meet, 0.6), "over")
    tl.k(14, lerp_pose(g, meet, 0.25), "smooth").k(n, g, "smooth")
    return tl, n, (0, -0.05, 0)

def block_clips(kind):
    g = guard_stance(kind)
    hold = merge(g, pose(
        hips=(4, 12, 0), spine=(3, 6, 0), chest=(6, 16, 0), upperchest=(4, 12, 0),
        neck=(-3, -10, 0), head=(-2, -8, 0),
        shoulder__L=(0, 0, -16), shoulder__R=(0, 0, 17),
        upperarm__L=(-80, 0, 26), forearm__L=(-78, 0, 0),
        upperarm__R=(-86, 0, -20), forearm__R=(-76, 0, 0), hand__R=(0, 0, -30),
        thigh__L=(-16, 0, 4), thigh__R=(16, 0, -4),
        shin__L=(-24, 0, 0), shin__R=(-20, 0, 0),
        _root_loc=(0, 0, -0.055)))
    into = Timeline().k(0, g, "out").k(4, merge(hold, pose(chest=(8, 20, 0))), "over").k(8, hold, "smooth")
    loop = Timeline(loop=True)
    for i in range(13):
        t = i / 12.0
        b = sin(2 * pi * t)
        loop.k(t * 60, merge(hold, pose(
            chest=(hold["chest"][0] + 1.1 * b, hold["chest"][1], 0),
            upperchest=(hold["upperchest"][0] + 0.8 * b, hold["upperchest"][1], 0),
            neck=(hold["neck"][0] - 0.7 * b, hold["neck"][1], 0),
            upperarm__R=(hold["upperarm.R"][0] - 1.2 * b, 0, hold["upperarm.R"][2]),
            forearm__R=(hold["forearm.R"][0] - 1.0 * b, 0, 0),
            _root_loc=(0, 0, -0.055 + 0.004 * b))), "linear")
    impact = merge(hold, pose(
        hips=(-6, -6, 0), spine=(-6, -4, 0), chest=(-14, -10, 0), upperchest=(-10, -7, 0),
        neck=(10, 6, 0), head=(8, 5, 0),
        upperarm__L=(-62, 0, 36), upperarm__R=(-68, 0, -30), forearm__R=(-96, 0, 0),
        thigh__L=(-8, 0, 4), thigh__R=(22, 0, -4), shin__R=(-30, 0, 0),
        _root_loc=(0, -0.13, -0.075)))
    hit = Timeline().k(0, hold, "out").k(2, impact, "snap").k(7, lerp_pose(impact, hold, 0.55), "out")
    hit.k(14, hold, "smooth")
    return (into, 8), (loop, 60), (hit, 14)

def deathblow(kind):
    """Slow, weighted execution: stab, hold, withdraw, flourish, settle."""
    g = guard_stance(kind)
    n = 64
    raise_ = merge(g, pose(
        hips=(-6, -14, -3), spine=(-4, -8, 0), chest=(-12, -20, 0), upperchest=(-8, -14, 0),
        neck=(8, 18, 0), head=(6, 14, 0),
        upperarm__R=(-152, 0, -20), forearm__R=(-40, 0, 0), hand__R=(0, 0, 14),
        upperarm__L=(-100, 0, 30), forearm__L=(-70, 0, 0),
        thigh__L=(-10, 0, 4), thigh__R=(10, 0, -4),
        _root_loc=(0, -0.04, 0.025)))
    thrust = merge(g, pose(
        hips=(18, 20, 4), spine=(12, 12, 0), chest=(22, 26, 0), upperchest=(16, 20, 0),
        neck=(-12, -20, 0), head=(-10, -16, 0),
        upperarm__R=(46, 0, -14), forearm__R=(-8, 0, 0), hand__R=(0, 0, -6),
        upperarm__L=(6, 0, 22), forearm__L=(-34, 0, 0),
        thigh__L=(28, 0, 4), thigh__R=(-24, 0, -4), shin__L=(-34, 0, 0),
        foot__L=(18, 0, 0), toe__R=(-30, 0, 0),
        _root_loc=(0, 0.60, -0.09)))
    hold = merge(thrust, pose(chest=(24, 28, 0), neck=(-14, -22, 0), _root_loc=(0, 0.62, -0.10)))
    pull = merge(g, pose(
        hips=(2, -8, 0), chest=(-4, -12, 0), neck=(2, 10, 0),
        upperarm__R=(-46, 0, -30), forearm__R=(-96, 0, 0),
        thigh__L=(-6, 0, 4), thigh__R=(6, 0, -4),
        _root_loc=(0, 0.12, -0.04)))
    flick = merge(g, pose(
        hips=(3, 22, 3), chest=(8, 30, 0), neck=(-4, -24, 0),
        upperarm__R=(-10, 0, 52), forearm__R=(-24, 0, 0), hand__R=(0, 0, -22),
        _root_loc=(0, 0.06, -0.03)))
    tl = Timeline()
    tl.k(0, g, "out").k(8, raise_, "sharp").k(13, thrust, "snap")
    tl.k(22, hold, "hold").k(30, hold, "out")
    tl.k(40, pull, "smooth").k(46, flick, "snap").k(54, lerp_pose(flick, g, 0.6), "out")
    tl.k(n, g, "smooth")
    return tl, n, (0, 0.72, 0)

def sheathe_clips(kind):
    g = guard_stance(kind)
    rest = base_stance(kind)
    put = Timeline()
    put.k(0, g, "out")
    put.k(8, merge(g, pose(upperarm__R=(-36, 0, -46), forearm__R=(-102, 0, 0),
                           upperarm__L=(-30, 0, 44), forearm__L=(-96, 0, 0),
                           chest=(2, -16, 0), neck=(-2, 16, 0))), "smooth")
    put.k(18, merge(rest, pose(upperarm__R=(-24, 0, -22), forearm__R=(-70, 0, 0),
                               chest=(3, -6, 0))), "out")
    put.k(26, rest, "smooth")
    draw = Timeline()
    draw.k(0, rest, "out")
    draw.k(5, merge(rest, pose(hips=(4, -18, 0), chest=(2, -24, 0), neck=(-2, 22, 0),
                               upperarm__R=(-30, 0, -34), forearm__R=(-96, 0, 0),
                               thigh__R=(14, 0, -4), _root_loc=(0, 0, -0.04))), "sharp")
    draw.k(9, merge(g, pose(hips=(8, 30, 4), chest=(14, 36, 0), neck=(-8, -28, 0),
                            upperarm__R=(-4, 0, 34), forearm__R=(-22, 0, 0),
                            _root_loc=(0, 0.14, -0.05))), "snap")
    draw.k(14, merge(g, pose(chest=(10, 22, 0))), "out")
    draw.k(22, g, "smooth")
    return (put, 26), (draw, 22)

# --------------------------------------------------------------- reactions
def hit_clip(kind, direction, heavy_hit=False):
    """Directional reaction. Torso, shoulders, head and hips each react differently."""
    g = guard_stance(kind)
    m = 1.9 if heavy_hit else 1.0
    n = int((30 if heavy_hit else 18))
    if direction == "F":       # struck from the front, pushed back
        peak = pose(
            hips=(-9 * m, 0, 0), spine=(-8 * m, 0, 0), chest=(-15 * m, 4 * m, 0),
            upperchest=(-11 * m, 3 * m, 0), neck=(13 * m, -3 * m, 0), head=(11 * m, -4 * m, 0),
            shoulder__L=(0, -6 * m, -10), shoulder__R=(0, 6 * m, 12),
            upperarm__L=(-30, 0, 24 + 6 * m), upperarm__R=(-34, 0, -26 - 6 * m),
            forearm__L=(-62, 0, 0), forearm__R=(-68, 0, 0),
            thigh__L=(-6, 0, 4), thigh__R=(18 * m, 0, -4), shin__R=(-22 * m, 0, 0),
            foot__R=(10, 0, 0), jaw=(7 * m, 0, 0),
            brow__L=(-16, 0, 0), brow__R=(-16, 0, 0),
            _root_loc=(0, -0.10 * m, -0.03 * m))
    elif direction == "B":     # struck from behind, arches forward
        peak = pose(
            hips=(11 * m, 0, 0), spine=(9 * m, 0, 0), chest=(16 * m, -3 * m, 0),
            upperchest=(12 * m, -2 * m, 0), neck=(-14 * m, 2 * m, 0), head=(-12 * m, 3 * m, 0),
            shoulder__L=(0, 8 * m, -16), shoulder__R=(0, -8 * m, 18),
            upperarm__L=(-8, 0, 30), upperarm__R=(-12, 0, -32),
            thigh__L=(-16 * m, 0, 4), thigh__R=(-10 * m, 0, -4),
            shin__L=(-14, 0, 0), jaw=(9 * m, 0, 0),
            brow__L=(-18, 0, 0), brow__R=(-18, 0, 0),
            _root_loc=(0, 0.10 * m, -0.025 * m))
    else:
        s = 1.0 if direction == "R" else -1.0
        peak = pose(
            hips=(2, -s * 8 * m, -s * 11 * m), spine=(-2, -s * 5 * m, -s * 8 * m),
            chest=(-6 * m, -s * 12 * m, -s * 14 * m), upperchest=(-4 * m, -s * 9 * m, -s * 10 * m),
            neck=(7 * m, s * 12 * m, s * 9 * m), head=(6 * m, s * 14 * m, s * 11 * m),
            shoulder__L=(0, -s * 7 * m, -10 - s * 6), shoulder__R=(0, -s * 7 * m, 12 - s * 6),
            upperarm__L=(-28, 0, 22 + s * 10), upperarm__R=(-32, 0, -24 + s * 10),
            thigh__L=(-6, 0, 4 - s * 10 * m), thigh__R=(8, 0, -4 - s * 10 * m),
            shin__L=(-16, 0, 0), shin__R=(-14, 0, 0),
            jaw=(6 * m, s * 3, 0), brow__L=(-15, 0, 0), brow__R=(-15, 0, 0),
            _root_loc=(-s * 0.09 * m, -0.02, -0.02 * m))
    peak = merge(g, peak)
    tl = Timeline()
    tl.k(0, g, "out")
    tl.k(2 if not heavy_hit else 3, peak, "snap")
    tl.k(int(n * 0.40), lerp_pose(peak, g, 0.45), "out")
    if heavy_hit:
        tl.k(int(n * 0.62), lerp_pose(peak, g, 0.80), "over")
    tl.k(n, g, "smooth")
    return tl, n

def stagger_clip(kind, variant=0):
    """Posture break: unstable footing, torso and shoulders lag behind the hips."""
    g = guard_stance(kind)
    n = 46 if variant == 0 else 52
    s = 1.0 if variant == 0 else -1.0
    a = merge(g, pose(
        hips=(-10, -s * 6, -s * 8), spine=(-9, 0, -s * 6), chest=(-18, -s * 10, -s * 10),
        upperchest=(-13, -s * 7, -s * 7), neck=(16, s * 8, s * 6), head=(14, s * 10, s * 8),
        shoulder__L=(0, -10, -6), shoulder__R=(0, 10, 8),
        upperarm__L=(-14, 0, 34), upperarm__R=(-18, 0, -36),
        forearm__L=(-44, 0, 0), forearm__R=(-50, 0, 0),
        thigh__L=(-10, 0, 4 - s * 6), thigh__R=(24, 0, -4 - s * 6), shin__R=(-34, 0, 0),
        foot__R=(14, 0, 0), jaw=(12, 0, 0), brow__L=(-20, 0, 0), brow__R=(-20, 0, 0),
        _root_loc=(-s * 0.06, -0.22, -0.10)))
    b = merge(g, pose(
        hips=(4, s * 14, s * 10), spine=(2, s * 8, s * 7), chest=(-8, s * 18, s * 9),
        upperchest=(-6, s * 13, s * 6), neck=(9, -s * 14, -s * 5), head=(8, -s * 16, -s * 7),
        upperarm__L=(-26, 0, 28), upperarm__R=(-30, 0, -30),
        thigh__L=(16, 0, 4 + s * 8), thigh__R=(-12, 0, -4 + s * 8),
        shin__L=(-28, 0, 0), foot__L=(12, 0, 0),
        jaw=(9, 0, 0), _root_loc=(s * 0.10, -0.30, -0.13)))
    c = merge(g, pose(
        hips=(-4, 0, 0), chest=(-10, 0, 0), neck=(9, 0, 0), head=(8, 0, 0),
        upperarm__L=(-34, 0, 26), upperarm__R=(-38, 0, -28),
        thigh__L=(-8, 0, 4), thigh__R=(14, 0, -4), shin__R=(-24, 0, 0),
        jaw=(6, 0, 0), _root_loc=(0, -0.34, -0.09)))
    tl = Timeline()
    tl.k(0, g, "out").k(3, a, "snap").k(int(n * 0.30), b, "out")
    tl.k(int(n * 0.52), c, "over").k(int(n * 0.74), lerp_pose(c, g, 0.5), "smooth").k(n, g, "smooth")
    return tl, n

def knockdown_clip(kind, back=True):
    g = guard_stance(kind)
    n = 54
    s = 1.0 if back else -1.0
    hitp = merge(g, pose(
        hips=(-18 * s, 0, 0), spine=(-14 * s, 0, 0), chest=(-24 * s, 0, 0),
        neck=(20 * s, 0, 0), head=(18 * s, 0, 0),
        upperarm__L=(-4, 0, 40), upperarm__R=(-8, 0, -42),
        thigh__L=(-20 * s, 0, 4), thigh__R=(-14 * s, 0, -4),
        jaw=(14, 0, 0), brow__L=(-22, 0, 0), brow__R=(-22, 0, 0),
        _root_loc=(0, -0.16 * s, -0.05)))
    air = merge(g, pose(
        hips=(-34 * s, 0, 0), spine=(-20 * s, 0, 0), chest=(-30 * s, 0, 0),
        neck=(24 * s, 0, 0), head=(22 * s, 0, 0),
        upperarm__L=(20, 0, 52), upperarm__R=(16, 0, -54),
        forearm__L=(-30, 0, 0), forearm__R=(-34, 0, 0),
        thigh__L=(-46 * s, 0, 4), thigh__R=(-38 * s, 0, -4),
        shin__L=(-30, 0, 0), shin__R=(-26, 0, 0),
        _root_loc=(0, -0.42 * s, -0.34)))
    down = merge(g, pose(
        hips=(-78 * s, 0, 0), spine=(-10 * s, 0, 0), chest=(-12 * s, 0, 0),
        neck=(16 * s, 0, 0), head=(14 * s, 0, 0),
        upperarm__L=(30, 0, 66), upperarm__R=(26, 0, -68),
        forearm__L=(-20, 0, 0), forearm__R=(-24, 0, 0),
        thigh__L=(-70 * s, 0, 4), thigh__R=(-62 * s, 0, -4),
        shin__L=(-20, 0, 0), shin__R=(-16, 0, 0),
        jaw=(10, 0, 0), _root_loc=(0, -0.62 * s, -0.80)))
    tl = Timeline()
    tl.k(0, g, "out").k(3, hitp, "snap").k(12, air, "in")
    tl.k(20, down, "snap").k(26, merge(down, pose(chest=(-6 * s, 0, 0),
                                                  _root_loc=(0, -0.64 * s, -0.78))), "out")
    tl.k(n, down, "smooth")
    return tl, n, (0, -0.66 * s, 0)

def getup_clip(kind, variant=0):
    g = guard_stance(kind)
    down = pose(hips=(-78, 0, 0), spine=(-10, 0, 0), chest=(-12, 0, 0), neck=(16, 0, 0),
                head=(14, 0, 0), upperarm__L=(30, 0, 66), upperarm__R=(26, 0, -68),
                forearm__L=(-20, 0, 0), forearm__R=(-24, 0, 0),
                thigh__L=(-70, 0, 4), thigh__R=(-62, 0, -4), shin__L=(-20, 0, 0),
                shin__R=(-16, 0, 0), _root_loc=(0, 0, -0.80))
    down = merge(g, down)
    if variant == 0:      # roll onto a knee, push up with the sword hand
        mid = merge(g, pose(hips=(-34, 14, 8), spine=(-8, 8, 0), chest=(2, 16, 0),
                            neck=(4, -12, 0), head=(2, -10, 0),
                            upperarm__R=(-40, 0, -34), forearm__R=(-94, 0, 0),
                            upperarm__L=(-10, 0, 48), forearm__L=(-60, 0, 0),
                            thigh__L=(-56, 0, 4), thigh__R=(38, 0, -4),
                            shin__L=(-26, 0, 0), shin__R=(-88, 0, 0),
                            _root_loc=(0, 0.10, -0.50)))
        knee = merge(g, pose(hips=(10, 8, 3), spine=(8, 4, 0), chest=(6, 10, 0),
                             neck=(-6, -8, 0), head=(-4, -6, 0),
                             thigh__L=(-18, 0, 4), thigh__R=(58, 0, -4),
                             shin__L=(-14, 0, 0), shin__R=(-104, 0, 0), foot__R=(28, 0, 0),
                             _root_loc=(0, 0.16, -0.30)))
        n = 52
    else:                 # kip up onto both feet, faster and showier
        mid = merge(g, pose(hips=(-50, 0, 0), spine=(-16, 0, 0), chest=(-8, 0, 0),
                            thigh__L=(-96, 0, 4), thigh__R=(-92, 0, -4),
                            shin__L=(-54, 0, 0), shin__R=(-50, 0, 0),
                            upperarm__L=(60, 0, 52), upperarm__R=(56, 0, -54),
                            _root_loc=(0, -0.06, -0.70)))
        knee = merge(g, pose(hips=(26, 0, 0), spine=(14, 0, 0), chest=(8, 0, 0),
                             thigh__L=(46, 0, 4), thigh__R=(40, 0, -4),
                             shin__L=(-72, 0, 0), shin__R=(-68, 0, 0),
                             foot__L=(26, 0, 0), foot__R=(24, 0, 0),
                             _root_loc=(0, 0.22, -0.22)))
        n = 40
    tl = Timeline()
    tl.k(0, down, "out").k(int(n * 0.16), merge(down, pose(chest=(-4, 6, 0), jaw=(8, 0, 0))), "smooth")
    tl.k(int(n * 0.42), mid, "out").k(int(n * 0.68), knee, "out")
    tl.k(int(n * 0.86), lerp_pose(knee, g, 0.75), "over").k(n, g, "smooth")
    return tl, n

def death_clip(kind, variant=0):
    g = guard_stance(kind)
    n = 66 if variant == 0 else 58
    if variant == 0:      # sink to the knees, then fall forward
        a = merge(g, pose(hips=(6, 0, 0), spine=(8, 0, 0), chest=(14, 0, 0), neck=(-8, 0, 0),
                          head=(-10, 0, 0), upperarm__L=(-10, 0, 30), upperarm__R=(-14, 0, -32),
                          forearm__L=(-40, 0, 0), forearm__R=(-44, 0, 0),
                          jaw=(13, 0, 0), brow__L=(-20, 0, 0), brow__R=(-20, 0, 0),
                          _root_loc=(0, 0, -0.06)))
        b = merge(g, pose(hips=(20, 0, 0), spine=(16, 0, 0), chest=(22, 0, 0), neck=(-14, 0, 0),
                          head=(-18, 0, 0), thigh__L=(72, 0, 4), thigh__R=(68, 0, -4),
                          shin__L=(-116, 0, 0), shin__R=(-112, 0, 0),
                          foot__L=(34, 0, 0), foot__R=(32, 0, 0),
                          upperarm__L=(4, 0, 22), upperarm__R=(0, 0, -24),
                          jaw=(8, 0, 0), _root_loc=(0, 0.04, -0.48)))
        c = merge(b, pose(hips=(56, 0, 0), spine=(22, 0, 0), chest=(16, 0, 0),
                          neck=(-6, 0, 0), head=(-8, 0, 0),
                          upperarm__L=(24, 0, 44), upperarm__R=(20, 0, -46),
                          jaw=(3, 0, 0), brow__L=(-6, 0, 0), brow__R=(-6, 0, 0),
                          _root_loc=(0, 0.34, -0.80)))
        tl = Timeline().k(0, g, "out").k(6, a, "snap").k(20, b, "out")
        tl.k(34, merge(b, pose(chest=(24, 0, 0), _root_loc=(0, 0.06, -0.50))), "hold")
        tl.k(48, c, "in").k(56, merge(c, pose(chest=(14, 0, 0))), "out").k(n, c, "smooth")
        end = (0, 0.36, 0)
    else:                 # spin and fall backwards
        a = merge(g, pose(hips=(-8, 16, -6), spine=(-6, 10, 0), chest=(-14, 22, 0),
                          neck=(12, -18, 0), head=(10, -20, 0),
                          upperarm__L=(2, 0, 44), upperarm__R=(-2, 0, -46),
                          jaw=(14, 0, 0), brow__L=(-22, 0, 0), brow__R=(-22, 0, 0),
                          _root_loc=(0, -0.10, -0.04)))
        b = merge(g, pose(hips=(-30, 26, -10), spine=(-16, 14, 0), chest=(-24, 30, 0),
                          neck=(20, -24, 0), head=(18, -26, 0),
                          thigh__L=(-30, 0, 4), thigh__R=(-22, 0, -4),
                          upperarm__L=(28, 0, 58), upperarm__R=(24, 0, -60),
                          _root_loc=(0, -0.40, -0.40)))
        c = merge(b, pose(hips=(-80, 20, -6), spine=(-6, 6, 0), chest=(-8, 10, 0),
                          neck=(14, -8, 0), head=(12, -10, 0),
                          thigh__L=(-64, 0, 4), thigh__R=(-56, 0, -4),
                          shin__L=(-22, 0, 0), shin__R=(-18, 0, 0),
                          upperarm__L=(34, 0, 70), upperarm__R=(30, 0, -72),
                          jaw=(4, 0, 0), brow__L=(-5, 0, 0), brow__R=(-5, 0, 0),
                          _root_loc=(0, -0.62, -0.82)))
        tl = Timeline().k(0, g, "out").k(5, a, "snap").k(18, b, "in").k(28, c, "snap")
        tl.k(36, merge(c, pose(chest=(-2, 8, 0), _root_loc=(0, -0.60, -0.80))), "out").k(n, c, "smooth")
        end = (0, -0.64, 0)
    return tl, n, end
