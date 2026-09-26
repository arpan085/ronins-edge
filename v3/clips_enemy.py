"""Enemy and boss animation personalities, plus short cinematic beats."""
import sys
sys.path.insert(0, "/data/ronins_edge/v3")
from anim_core import Timeline, pose, merge, lerp_pose, ROOT
from clips import base_stance, PERSONA, cyc
from math import sin, pi

# --------------------------------------------------------- spear (ashigaru)
def spear_guard():
    return merge(base_stance("ashigaru"), pose(
        hips=(4, 14, -2), spine=(4, 8, 0), chest=(3, 20, 0), upperchest=(2, 14, 0),
        neck=(-4, -16, 0), head=(-3, -12, 0),
        shoulder__L=(0, 0, -10), shoulder__R=(0, 0, 11),
        upperarm__L=(-62, 0, 24), forearm__L=(-52, 0, 0), hand__L=(0, 0, 10),
        upperarm__R=(-40, 0, -30), forearm__R=(-96, 0, 0), hand__R=(0, 0, -12),
        thigh__L=(-18, 0, 4), thigh__R=(18, 0, -4),
        shin__L=(-26, 0, 0), shin__R=(-20, 0, 0),
        foot__L=(10, 0, 0), _root_loc=(0, 0, -0.055)))

def spear_clips():
    g = spear_guard()
    # disciplined telegraph: short, economical, weight settles onto the back foot
    tele = merge(g, pose(
        hips=(2, 4, -3), spine=(2, 2, 0), chest=(-4, 8, 0), upperchest=(-2, 6, 0),
        neck=(0, -6, 0), head=(0, -4, 0),
        upperarm__R=(-52, 0, -38), forearm__R=(-116, 0, 0),
        upperarm__L=(-70, 0, 18), forearm__L=(-40, 0, 0),
        thigh__R=(26, 0, -4), shin__R=(-34, 0, 0), thigh__L=(-16, 0, 4),
        brow__L=(-10, 0, 0), brow__R=(-10, 0, 0),
        _root_loc=(0, -0.09, -0.075)))
    thrust = merge(g, pose(
        hips=(12, 22, 3), spine=(9, 12, 0), chest=(16, 28, 0), upperchest=(12, 20, 0),
        neck=(-10, -22, 0), head=(-8, -18, 0),
        upperarm__R=(24, 0, -10), forearm__R=(-16, 0, 0), hand__R=(0, 0, -4),
        upperarm__L=(-26, 0, 16), forearm__L=(-20, 0, 0),
        thigh__L=(26, 0, 4), thigh__R=(-20, 0, -4), shin__L=(-30, 0, 0),
        foot__L=(16, 0, 0), toe__R=(-26, 0, 0), jaw=(10, 0, 0),
        _root_loc=(0, 0.46, -0.06)))
    sweep_a = merge(g, pose(
        hips=(4, -26, -4), chest=(-6, -32, 0), neck=(2, 28, 0), head=(1, 22, 0),
        upperarm__R=(-70, 0, -54), forearm__R=(-80, 0, 0),
        upperarm__L=(-84, 0, 40), forearm__L=(-36, 0, 0),
        thigh__R=(20, 0, -4), shin__R=(-28, 0, 0), _root_loc=(0, -0.05, -0.07)))
    sweep_b = merge(g, pose(
        hips=(6, 34, 5), chest=(10, 42, 0), neck=(-6, -32, 0), head=(-4, -26, 0),
        upperarm__R=(-30, 0, 44), forearm__R=(-30, 0, 0),
        upperarm__L=(-40, 0, 6), forearm__L=(-70, 0, 0),
        thigh__L=(18, 0, 4), thigh__R=(-14, 0, -4), jaw=(8, 0, 0),
        _root_loc=(0, 0.16, -0.055)))
    attack = Timeline().k(0, g, "out").k(9, tele, "sharp").k(13, thrust, "snap")
    attack.k(18, merge(thrust, pose(_root_loc=(0, 0.50, -0.065))), "out")
    attack.k(28, lerp_pose(thrust, g, 0.6), "smooth").k(40, g, "smooth")
    sweep = Timeline().k(0, g, "out").k(10, sweep_a, "sharp").k(15, sweep_b, "snap")
    sweep.k(20, merge(sweep_b, pose(chest=(12, 50, 0))), "out")
    sweep.k(30, lerp_pose(sweep_b, g, 0.6), "smooth").k(42, g, "smooth")
    # cautious spacing shuffle used while circling the player
    shuffle = Timeline(loop=True)
    for i in range(13):
        t = i / 12.0
        s = sin(2 * pi * t)
        shuffle.k(t * 40, merge(g, pose(
            hips=(4 + 1.2 * s, 14 + 3 * s, -2 - 2 * s),
            chest=(3 + 1.4 * s, 20 + 4 * s, 0), neck=(-4 - 1.0 * s, -16 - 3 * s, 0),
            thigh__L=(-18 - 5 * s, 0, 4), thigh__R=(18 + 5 * s, 0, -4),
            shin__L=(-26 - 4 * s, 0, 0), shin__R=(-20 + 4 * s, 0, 0),
            foot__L=(10 + 3 * s, 0, 0), foot__R=(1 - 3 * s, 0, 0),
            upperarm__R=(-40 - 1.6 * s, 0, -30), forearm__R=(-96 - 2 * s, 0, 0),
            _root_loc=(0, 0.018 * s, -0.055 + 0.006 * abs(s)))), "linear")
    block = Timeline().k(0, g, "out").k(3, merge(g, pose(
        hips=(-4, 6, 0), chest=(-10, 10, 0), neck=(8, -8, 0), head=(6, -6, 0),
        upperarm__L=(-86, 0, 34), forearm__L=(-56, 0, 0),
        upperarm__R=(-70, 0, -24), forearm__R=(-86, 0, 0),
        thigh__R=(24, 0, -4), shin__R=(-32, 0, 0), _root_loc=(0, -0.10, -0.08))), "snap")
    block.k(10, merge(g, pose(chest=(-2, 16, 0), _root_loc=(0, -0.03, -0.06))), "out").k(20, g, "smooth")
    return dict(Attack=(attack, 40), Sweep=(sweep, 42), Shuffle=(shuffle, 40), Block=(block, 20),
                Guard=g)

# --------------------------------------------------------- bow (archer)
def bow_ready():
    return merge(base_stance("archer"), pose(
        hips=(2, 20, -2), spine=(2, 12, 0), chest=(2, 26, 0), upperchest=(1, 18, 0),
        neck=(-3, -22, 0), head=(-2, -18, 0),
        shoulder__L=(0, 0, -12), shoulder__R=(0, 0, 10),
        upperarm__L=(-78, 0, 22), forearm__L=(-16, 0, 0), hand__L=(0, 0, 6),
        upperarm__R=(-58, 0, -34), forearm__R=(-104, 0, 0),
        thigh__L=(-12, 0, 4), thigh__R=(12, 0, -4),
        shin__L=(-18, 0, 0), shin__R=(-14, 0, 0), _root_loc=(0, 0, -0.03)))

def bow_clips():
    r = bow_ready()
    aim = merge(r, pose(
        upperarm__L=(-88, 0, 26), forearm__L=(-8, 0, 0),
        upperarm__R=(-74, 0, -44), forearm__R=(-118, 0, 0),
        chest=(0, 30, 0), neck=(-2, -26, 0), head=(-1, -22, 0),
        eye__L=(0, -12, 0), eye__R=(0, -12, 0),
        brow__L=(-8, 0, 0), brow__R=(-8, 0, 0), _root_loc=(0, 0, -0.035)))
    draw = merge(aim, pose(
        upperarm__R=(-80, 0, -60), forearm__R=(-134, 0, 0),
        chest=(0, 36, 0), upperchest=(0, 26, 0), shoulder__R=(0, -6, 16),
        jaw=(4, 0, 0), brow__L=(-14, 0, 0), brow__R=(-14, 0, 0),
        _root_loc=(0, -0.01, -0.04)))
    rel = merge(aim, pose(
        upperarm__R=(-62, 0, -18), forearm__R=(-40, 0, 0), hand__R=(0, 0, 14),
        chest=(0, 20, 0), shoulder__R=(0, 4, 4), jaw=(7, 0, 0),
        _root_loc=(0, -0.05, -0.03)))
    # hold the draw: readable telegraph with visible strain tremor
    hold = Timeline(loop=True)
    for i in range(13):
        t = i / 12.0
        s = sin(2 * pi * t * 3.0)
        hold.k(t * 24, merge(draw, pose(
            upperarm__R=(draw["upperarm.R"][0] - 1.0 * s, 0, draw["upperarm.R"][2] - 1.4 * s),
            forearm__R=(draw["forearm.R"][0] - 1.2 * s, 0, 0),
            upperarm__L=(draw["upperarm.L"][0] + 0.6 * s, 0, draw["upperarm.L"][2]),
            head=(draw["head"][0], draw["head"][1] - 0.8 * s, 0))), "linear")
    nock = Timeline().k(0, r, "out")
    nock.k(7, merge(r, pose(upperarm__R=(-16, 0, -60), forearm__R=(-96, 0, 0),
                            chest=(2, 10, 0), neck=(-2, -6, 0), head=(-2, -10, 0))), "smooth")
    nock.k(14, merge(r, pose(upperarm__R=(-40, 0, -46), forearm__R=(-112, 0, 0))), "out")
    nock.k(22, aim, "smooth")
    aim_in = Timeline().k(0, r, "out").k(6, aim, "out").k(12, draw, "sharp").k(18, draw, "smooth")
    shoot = Timeline().k(0, draw, "out").k(2, rel, "snap")
    shoot.k(8, merge(rel, pose(chest=(0, 16, 0), upperarm__R=(-54, 0, -12))), "out")
    shoot.k(16, aim, "smooth").k(24, r, "smooth")
    # nervous: quick backpedal with the bow raised defensively
    backstep = Timeline().k(0, r, "out")
    backstep.k(4, merge(r, pose(hips=(-8, 18, 0), chest=(-8, 24, 0), neck=(8, -20, 0),
                                head=(7, -16, 0), upperarm__L=(-96, 0, 30),
                                upperarm__R=(-30, 0, -28), forearm__R=(-80, 0, 0),
                                thigh__L=(26, 0, 4), thigh__R=(-16, 0, -4),
                                shin__L=(-44, 0, 0), brow__L=(-18, 0, 0), brow__R=(-18, 0, 0),
                                _root_loc=(0, -0.26, -0.05))), "snap")
    backstep.k(12, merge(r, pose(hips=(-3, 20, 0), _root_loc=(0, -0.48, -0.03))), "out")
    backstep.k(22, merge(r, pose(_root_loc=(0, -0.52, 0))), "smooth")
    flinch = Timeline().k(0, r, "out")
    flinch.k(2, merge(r, pose(hips=(-4, 24, 0), spine=(-6, 14, 0), chest=(-16, 30, 0),
                              neck=(14, -24, 0), head=(13, -20, 0),
                              upperarm__L=(-40, 0, 40), upperarm__R=(-20, 0, -40),
                              forearm__L=(-70, 0, 0), forearm__R=(-74, 0, 0),
                              thigh__R=(20, 0, -4), shin__R=(-28, 0, 0),
                              jaw=(12, 0, 0), brow__L=(-24, 0, 0), brow__R=(-24, 0, 0),
                              _root_loc=(0, -0.13, -0.06))), "snap")
    flinch.k(9, merge(r, pose(chest=(-6, 26, 0), neck=(6, -22, 0), brow__L=(-10, 0, 0),
                              brow__R=(-10, 0, 0), _root_loc=(0, -0.05, -0.03))), "out")
    flinch.k(18, r, "smooth")
    return dict(Nock=(nock, 22), AimIn=(aim_in, 18), HoldDraw=(hold, 24), Shoot=(shoot, 24),
                BackStep=(backstep, 22), Flinch=(flinch, 18), Ready=r)

# --------------------------------------------------------- boss (captain)
def boss_stance():
    return merge(base_stance("captain"), pose(
        hips=(1, 8, -1), spine=(0, 5, 0), chest=(5, 12, 0), upperchest=(4, 9, 0),
        neck=(-3, -10, 0), head=(-1, -8, 0),
        shoulder__L=(0, 0, -12), shoulder__R=(0, 0, 13),
        upperarm__L=(-30, 0, 26), forearm__L=(-62, 0, 0),
        upperarm__R=(-38, 0, -30), forearm__R=(-70, 0, 0), hand__R=(0, 0, -6),
        thigh__L=(-12, 0, 5), thigh__R=(12, 0, -5),
        shin__L=(-16, 0, 0), shin__R=(-12, 0, 0), _root_loc=(0, 0, -0.025)))

def boss_clips():
    g = boss_stance()
    # unique idle: almost motionless, deep slow breath, occasional blade adjustment
    idle = Timeline(loop=True)
    N = 210
    for i in range(29):
        t = i / 28.0
        b = sin(2 * pi * t * 1.0)
        adj = cyc(t, [(0.0, 0.0), (0.52, 0.0), (0.60, 1.0), (0.70, 0.35), (0.84, 0.0)])
        idle.k(t * N, merge(g, pose(
            spine=(0.6 * b, 5, 0), chest=(5 + 1.9 * b, 12, 0), upperchest=(4 + 1.4 * b, 9, 0),
            neck=(-3 - 1.1 * b, -10, 0), head=(-1 - 0.5 * b, -8 + 2.5 * adj, 0),
            shoulder__L=(0, -1.8 * b, -12), shoulder__R=(0, 1.8 * b, 13),
            upperarm__R=(-38 - 2.0 * b - 7 * adj, 0, -30 - 3 * adj),
            forearm__R=(-70 - 2.2 * b - 9 * adj, 0, 0), hand__R=(0, 0, -6 - 5 * adj),
            upperarm__L=(-30 + 1.2 * b, 0, 26),
            jaw=(0.9 * max(0.0, b), 0, 0),
            brow__L=(-4 - 3 * adj, 0, 0), brow__R=(-4 - 3 * adj, 0, 0),
            eye__L=(0, 4 * adj, 0), eye__R=(0, 4 * adj, 0),
            _root_loc=(0, 0, -0.025 + 0.003 * b))), "linear")
    # intimidation: plants feet, rolls shoulders, levels the blade at the player
    intim = Timeline()
    intim.k(0, g, "out")
    intim.k(10, merge(g, pose(hips=(4, -6, 0), spine=(3, -4, 0), chest=(-4, -10, 0),
                              neck=(6, 8, 0), head=(5, 8, 0),
                              shoulder__L=(0, -12, -18), shoulder__R=(0, 12, 19),
                              upperarm__L=(-18, 0, 34), upperarm__R=(-26, 0, -38),
                              thigh__L=(-16, 0, 5), thigh__R=(16, 0, -5),
                              brow__L=(-12, 0, 0), brow__R=(-12, 0, 0),
                              _root_loc=(0, -0.03, -0.055))), "sharp")
    intim.k(20, merge(g, pose(hips=(-2, 14, 2), spine=(-2, 8, 0), chest=(10, 20, 0),
                              upperchest=(8, 15, 0), neck=(-8, -16, 0), head=(-6, -14, 0),
                              upperarm__R=(-6, 0, -20), forearm__R=(-26, 0, 0),
                              upperarm__L=(-40, 0, 20), jaw=(14, 0, 0),
                              brow__L=(-18, 0, 0), brow__R=(-18, 0, 0),
                              _root_loc=(0, 0.10, -0.03))), "snap")
    intim.k(34, merge(g, pose(chest=(8, 18, 0), upperarm__R=(-14, 0, -24),
                              forearm__R=(-40, 0, 0), jaw=(6, 0, 0))), "hold")
    intim.k(48, g, "smooth")
    # entering combat: deliberate step forward, blade comes up, no wasted motion
    enter = Timeline().k(0, base_stance("captain"), "out")
    enter.k(12, merge(g, pose(hips=(6, 2, 0), thigh__L=(-20, 0, 5), thigh__R=(22, 0, -5),
                              shin__R=(-30, 0, 0), foot__R=(14, 0, 0),
                              upperarm__R=(-30, 0, -34), forearm__R=(-86, 0, 0),
                              _root_loc=(0, 0.18, -0.05))), "out")
    enter.k(24, merge(g, pose(chest=(7, 16, 0), upperarm__R=(-44, 0, -28),
                              _root_loc=(0, 0.34, -0.03))), "over")
    enter.k(36, g, "smooth")
    # attacks: overhead, wide horizontal, and an unblockable lunge
    over_a = merge(g, pose(hips=(-4, -18, -3), spine=(-2, -10, 0), chest=(-14, -24, 0),
                           upperchest=(-10, -18, 0), neck=(12, 22, 0), head=(10, 18, 0),
                           upperarm__R=(-158, 0, -22), forearm__R=(-44, 0, 0), hand__R=(0, 0, 14),
                           upperarm__L=(-116, 0, 30), forearm__L=(-52, 0, 0),
                           thigh__R=(16, 0, -5), shin__R=(-22, 0, 0),
                           brow__L=(-14, 0, 0), brow__R=(-14, 0, 0),
                           _root_loc=(0, -0.06, 0.03)))
    over_b = merge(g, pose(hips=(20, 18, 4), spine=(14, 10, 0), chest=(26, 22, 0),
                           upperchest=(19, 17, 0), neck=(-16, -18, 0), head=(-14, -15, 0),
                           upperarm__R=(44, 0, -12), forearm__R=(-12, 0, 0), hand__R=(0, 0, -14),
                           upperarm__L=(10, 0, 20), forearm__L=(-30, 0, 0),
                           thigh__L=(30, 0, 5), thigh__R=(-24, 0, -5), shin__L=(-36, 0, 0),
                           foot__L=(20, 0, 0), toe__R=(-30, 0, 0), jaw=(13, 0, 0),
                           _root_loc=(0, 0.42, -0.10)))
    a1 = Timeline().k(0, g, "out").k(8, merge(g, pose(hips=(2, -8, 0),
                                                      _root_loc=(0, -0.02, -0.04))), "smooth")
    a1.k(20, over_a, "sharp").k(25, over_b, "snap")
    a1.k(30, merge(over_b, pose(chest=(28, 26, 0), upperarm__R=(58, 0, -6),
                                _root_loc=(0, 0.48, -0.12))), "out")
    a1.k(44, lerp_pose(over_b, g, 0.55), "smooth").k(58, g, "smooth")
    wide_a = merge(g, pose(hips=(2, -44, -5), spine=(1, -24, 0), chest=(-6, -50, 0),
                           upperchest=(-4, -36, 0), neck=(4, 44, 0), head=(3, 38, 0),
                           upperarm__R=(-96, 0, -62), forearm__R=(-58, 0, 0),
                           upperarm__L=(-104, 0, 44), forearm__L=(-40, 0, 0),
                           thigh__R=(20, 0, -5), shin__R=(-26, 0, 0),
                           _root_loc=(0, -0.05, -0.065)))
    wide_b = merge(g, pose(hips=(8, 48, 6), spine=(6, 26, 0), chest=(16, 54, 0),
                           upperchest=(12, 40, 0), neck=(-10, -42, 0), head=(-8, -36, 0),
                           upperarm__R=(-26, 0, 50), forearm__R=(-22, 0, 0),
                           upperarm__L=(-34, 0, 4), forearm__L=(-64, 0, 0),
                           thigh__L=(22, 0, 5), thigh__R=(-18, 0, -5), jaw=(11, 0, 0),
                           _root_loc=(0, 0.24, -0.075)))
    a2 = Timeline().k(0, g, "out").k(14, wide_a, "sharp").k(19, wide_b, "snap")
    a2.k(25, merge(wide_b, pose(chest=(18, 62, 0), upperarm__R=(-18, 0, 62))), "out")
    a2.k(38, lerp_pose(wide_b, g, 0.55), "smooth").k(50, g, "smooth")
    lunge_a = merge(g, pose(hips=(10, 6, 0), spine=(7, 4, 0), chest=(-6, 10, 0),
                            neck=(6, -8, 0), head=(5, -6, 0),
                            upperarm__R=(-58, 0, -40), forearm__R=(-124, 0, 0),
                            upperarm__L=(-46, 0, 30), forearm__L=(-96, 0, 0),
                            thigh__L=(-22, 0, 5), thigh__R=(30, 0, -5),
                            shin__L=(-28, 0, 0), shin__R=(-42, 0, 0), foot__R=(20, 0, 0),
                            brow__L=(-20, 0, 0), brow__R=(-20, 0, 0), jaw=(6, 0, 0),
                            _root_loc=(0, -0.13, -0.13)))
    lunge_b = merge(g, pose(hips=(22, 14, 3), spine=(15, 8, 0), chest=(24, 18, 0),
                            upperchest=(17, 14, 0), neck=(-16, -14, 0), head=(-14, -12, 0),
                            upperarm__R=(52, 0, -10), forearm__R=(-6, 0, 0),
                            upperarm__L=(14, 0, 18), forearm__L=(-26, 0, 0),
                            thigh__L=(36, 0, 5), thigh__R=(-30, 0, -5), shin__L=(-40, 0, 0),
                            foot__L=(24, 0, 0), toe__R=(-34, 0, 0), jaw=(15, 0, 0),
                            _root_loc=(0, 0.86, -0.08)))
    a3 = Timeline().k(0, g, "out").k(12, merge(g, pose(chest=(2, 4, 0),
                                                       _root_loc=(0, -0.04, -0.05))), "smooth")
    a3.k(26, lunge_a, "sharp").k(31, lunge_b, "snap")
    a3.k(37, merge(lunge_b, pose(_root_loc=(0, 0.94, -0.09))), "out")
    a3.k(52, lerp_pose(lunge_b, g, 0.5), "smooth").k(66, g, "smooth")
    # phase transition: staggers, drives the blade down, rises with a new stance
    phase = Timeline().k(0, g, "out")
    phase.k(8, merge(g, pose(hips=(-10, 0, 0), chest=(-20, 0, 0), neck=(16, 0, 0),
                             head=(14, 0, 0), upperarm__L=(-6, 0, 40), upperarm__R=(-10, 0, -42),
                             jaw=(16, 0, 0), brow__L=(-24, 0, 0), brow__R=(-24, 0, 0),
                             thigh__R=(26, 0, -5), shin__R=(-36, 0, 0),
                             _root_loc=(0, -0.20, -0.12))), "snap")
    phase.k(26, merge(g, pose(hips=(34, 0, 0), spine=(20, 0, 0), chest=(18, 0, 0),
                              neck=(-10, 0, 0), head=(-14, 0, 0),
                              thigh__L=(64, 0, 5), thigh__R=(18, 0, -5),
                              shin__L=(-108, 0, 0), shin__R=(-30, 0, 0), foot__L=(32, 0, 0),
                              upperarm__R=(24, 0, -18), forearm__R=(-16, 0, 0),
                              upperarm__L=(-20, 0, 24), jaw=(10, 0, 0),
                              _root_loc=(0, 0.12, -0.44))), "out")
    phase.k(48, merge(g, pose(hips=(30, 0, 0), chest=(14, 0, 0), head=(-10, 0, 0),
                              jaw=(4, 0, 0), _root_loc=(0, 0.12, -0.42))), "hold")
    phase.k(64, merge(g, pose(hips=(-6, 0, 0), spine=(-4, 0, 0), chest=(-12, 0, 0),
                              upperchest=(-8, 0, 0), neck=(8, 0, 0), head=(6, 0, 0),
                              shoulder__L=(0, -14, -20), shoulder__R=(0, 14, 21),
                              upperarm__R=(-20, 0, -40), forearm__R=(-48, 0, 0),
                              upperarm__L=(-14, 0, 36), jaw=(18, 0, 0),
                              brow__L=(-20, 0, 0), brow__R=(-20, 0, 0),
                              _root_loc=(0, 0, 0.02))), "snap")
    phase.k(78, merge(g, pose(chest=(8, 14, 0), jaw=(8, 0, 0))), "out").k(92, g, "smooth")
    # defeat: knees buckle, blade used as a crutch, final collapse
    defeat = Timeline().k(0, g, "out")
    defeat.k(8, merge(g, pose(hips=(8, 0, 0), chest=(14, 0, 0), neck=(-8, 0, 0),
                              head=(-10, 0, 0), jaw=(15, 0, 0), brow__L=(-22, 0, 0),
                              brow__R=(-22, 0, 0), _root_loc=(0, 0, -0.07))), "snap")
    defeat.k(28, merge(g, pose(hips=(26, 4, 0), spine=(18, 0, 0), chest=(22, 0, 0),
                               neck=(-14, 0, 0), head=(-18, 0, 0),
                               thigh__L=(70, 0, 5), thigh__R=(26, 0, -5),
                               shin__L=(-114, 0, 0), shin__R=(-40, 0, 0), foot__L=(34, 0, 0),
                               upperarm__R=(20, 0, -16), forearm__R=(-12, 0, 0),
                               upperarm__L=(6, 0, 22), jaw=(10, 0, 0),
                               _root_loc=(0, 0.08, -0.50))), "out")
    defeat.k(52, merge(g, pose(hips=(24, 4, 0), chest=(18, 0, 0), head=(-16, 0, 0),
                               thigh__L=(70, 0, 5), shin__L=(-114, 0, 0),
                               upperarm__R=(18, 0, -14), jaw=(5, 0, 0),
                               _root_loc=(0, 0.08, -0.52))), "hold")
    defeat.k(74, merge(g, pose(hips=(62, 10, -6), spine=(20, 0, 0), chest=(12, 0, 0),
                               neck=(-4, 0, 0), head=(-6, 0, 0),
                               thigh__L=(64, 0, 5), thigh__R=(40, 0, -5),
                               shin__L=(-100, 0, 0), shin__R=(-70, 0, 0),
                               upperarm__L=(26, 0, 46), upperarm__R=(22, 0, -48),
                               jaw=(2, 0, 0), brow__L=(-4, 0, 0), brow__R=(-4, 0, 0),
                               _root_loc=(0, 0.26, -0.84))), "in")
    defeat.k(86, merge(g, pose(hips=(64, 10, -6), chest=(8, 0, 0),
                               thigh__L=(64, 0, 5), shin__L=(-100, 0, 0),
                               upperarm__L=(26, 0, 46), upperarm__R=(22, 0, -48),
                               _root_loc=(0, 0.28, -0.86))), "out")
    defeat.k(104, merge(g, pose(hips=(64, 10, -6), thigh__L=(64, 0, 5), shin__L=(-100, 0, 0),
                                upperarm__L=(26, 0, 46), upperarm__R=(22, 0, -48),
                                _root_loc=(0, 0.28, -0.86))), "smooth")
    return dict(Idle=(idle, N), Intimidate=(intim, 48), EnterCombat=(enter, 36),
                Attack1=(a1, 58), Attack2=(a2, 50), Attack3=(a3, 66),
                PhaseTransition=(phase, 92), Defeat=(defeat, 104), Stance=g)

# --------------------------------------------------------- shared enemy beats
def alert_clip(kind):
    """Detect the player: head snaps, body follows, weapon comes up."""
    p = PERSONA[kind]
    base = base_stance(kind)
    n = int(round(30 / max(p["tempo"], 0.5)))
    snap = merge(base, pose(
        neck=(-6, 26, 0), head=(-4, 30, 0), eye__L=(0, 22, 0), eye__R=(0, 22, 0),
        brow__L=(-20, 0, 0), brow__R=(-20, 0, 0), jaw=(8, 0, 0),
        chest=(base["chest"][0] + 2, 6, 0), _root_loc=(0, 0, -0.012)))
    turn = merge(base, pose(
        hips=(3, 12, -2), spine=(2, 8, 0), chest=(4, 18, 0), upperchest=(3, 13, 0),
        neck=(-5, 10, 0), head=(-3, 12, 0), eye__L=(0, 8, 0), eye__R=(0, 8, 0),
        brow__L=(-14, 0, 0), brow__R=(-14, 0, 0),
        upperarm__L=(-40, 0, 22), upperarm__R=(-46, 0, -26),
        forearm__L=(-76, 0, 0), forearm__R=(-84, 0, 0),
        thigh__L=(-14, 0, 4), thigh__R=(14, 0, -4),
        shin__L=(-20, 0, 0), shin__R=(-16, 0, 0), _root_loc=(0, 0, -0.03)))
    tl = Timeline()
    tl.k(0, base, "out").k(3, snap, "snap").k(int(n * 0.30), snap, "hold")
    tl.k(int(n * 0.66), turn, "out").k(n, turn, "smooth")
    return tl, n

def investigate_clip(kind):
    """Suspicious: slow scan, weapon half-raised, cautious lean."""
    p = PERSONA[kind]
    base = base_stance(kind)
    n = int(round(110 / max(p["tempo"] * 0.9, 0.4)))
    tl = Timeline(loop=True)
    for i in range(17):
        t = i / 16.0
        look = cyc(t, [(0.0, 0.0), (0.18, -1.0), (0.36, -0.7), (0.56, 1.0), (0.74, 0.6), (0.9, 0.0)])
        lean = cyc(t, [(0.0, 0.0), (0.30, 0.7), (0.62, 0.2), (0.85, 0.5)])
        tl.k(t * n, merge(base, pose(
            hips=(base["hips"][0] + 2 * lean, look * 6, 0),
            spine=(base["spine"][0] + 1.5 * lean, look * 4, 0),
            chest=(base["chest"][0] + 2 * lean, look * 9, 0),
            upperchest=(base["upperchest"][0] + 1.4 * lean, look * 7, 0),
            neck=(-4 - 2 * lean, look * 16, 0), head=(-2 - 1.5 * lean, look * 20, look * 3),
            eye__L=(0, look * 16, 0), eye__R=(0, look * 16, 0),
            brow__L=(-8, 0, 0), brow__R=(-8, 0, 0),
            upperarm__L=(-30, 0, 18), upperarm__R=(-36, 0, -22),
            forearm__L=(-66, 0, 0), forearm__R=(-72, 0, 0),
            _root_loc=(0, 0, -0.018))), "linear")
    return tl, n

def cine_clips(kind):
    """Short, skippable cinematic beats for Kaito."""
    base = base_stance(kind)
    # arriving in a new area: stops, looks up and across the vista
    arrive = Timeline().k(0, base, "out")
    arrive.k(14, merge(base, pose(hips=(0, 0, 0), spine=(-2, 0, 0), chest=(-4, -12, 0),
                                  upperchest=(-3, -9, 0), neck=(-8, -18, 0), head=(-12, -22, 0),
                                  eye__L=(0, -14, 0), eye__R=(0, -14, 0),
                                  upperarm__L=(-10, 0, 16), upperarm__R=(-14, 0, -18),
                                  forearm__L=(-34, 0, 0), forearm__R=(-38, 0, 0),
                                  _root_loc=(0, 0, 0.012))), "out")
    arrive.k(38, merge(base, pose(chest=(-2, 20, 0), neck=(-9, 26, 0), head=(-13, 30, 0),
                                  eye__L=(0, 20, 0), eye__R=(0, 20, 0),
                                  _root_loc=(0, 0, 0.014))), "smooth")
    arrive.k(58, merge(base, pose(chest=(2, 4, 0), neck=(-4, 4, 0), head=(-2, 4, 0))), "smooth")
    arrive.k(72, base, "smooth")
    # discovery: crouches to inspect something on the ground
    disc = Timeline().k(0, base, "out")
    disc.k(18, merge(base, pose(hips=(30, 6, 0), spine=(18, 2, 0), chest=(16, 4, 0),
                                neck=(-10, 0, 0), head=(-16, 0, 0),
                                thigh__L=(72, 0, 4), thigh__R=(34, 0, -4),
                                shin__L=(-108, 0, 0), shin__R=(-58, 0, 0),
                                foot__L=(32, 0, 0), foot__R=(20, 0, 0),
                                upperarm__L=(24, 0, 16), forearm__L=(-52, 0, 0),
                                upperarm__R=(-26, 0, -24), forearm__R=(-72, 0, 0),
                                _root_loc=(0, 0.08, -0.40))), "out")
    disc.k(44, merge(base, pose(hips=(32, 8, 0), spine=(19, 3, 0), chest=(17, 6, 0),
                                neck=(-11, 2, 0), head=(-18, 3, 0),
                                thigh__L=(72, 0, 4), thigh__R=(34, 0, -4),
                                shin__L=(-108, 0, 0), shin__R=(-58, 0, 0),
                                foot__L=(32, 0, 0), foot__R=(20, 0, 0),
                                upperarm__L=(40, 0, 14), forearm__L=(-30, 0, 0),
                                upperarm__R=(-26, 0, -24), forearm__R=(-72, 0, 0),
                                _root_loc=(0, 0.12, -0.42))), "smooth")
    disc.k(66, merge(base, pose(hips=(14, 4, 0), thigh__L=(30, 0, 4),
                                shin__L=(-48, 0, 0), _root_loc=(0, 0.04, -0.18))), "out")
    disc.k(84, base, "smooth")
    # quest complete / victory: sheathes, settles, bows
    bow = Timeline().k(0, base, "out")
    bow.k(12, merge(base, pose(chest=(3, 0, 0), upperarm__L=(-8, 0, 10),
                               upperarm__R=(-12, 0, -12), forearm__L=(-24, 0, 0),
                               forearm__R=(-28, 0, 0))), "smooth")
    bow.k(30, merge(base, pose(hips=(24, 0, 0), spine=(14, 0, 0), chest=(10, 0, 0),
                               upperchest=(7, 0, 0), neck=(-4, 0, 0), head=(-6, 0, 0),
                               upperarm__L=(-4, 0, 8), upperarm__R=(-8, 0, -10),
                               forearm__L=(-18, 0, 0), forearm__R=(-22, 0, 0),
                               thigh__L=(-8, 0, 4), thigh__R=(-6, 0, -4),
                               _root_loc=(0, 0.02, -0.02))), "out")
    bow.k(48, merge(base, pose(hips=(26, 0, 0), spine=(15, 0, 0), chest=(11, 0, 0),
                               neck=(-4, 0, 0), head=(-6, 0, 0),
                               upperarm__L=(-4, 0, 8), upperarm__R=(-8, 0, -10),
                               forearm__L=(-18, 0, 0), forearm__R=(-22, 0, 0),
                               thigh__L=(-8, 0, 4), thigh__R=(-6, 0, -4),
                               _root_loc=(0, 0.02, -0.02))), "hold")
    bow.k(64, base, "out").k(76, base, "smooth")
    return dict(Cine_Arrive=(arrive, 72), Cine_Discover=(disc, 84), Cine_Bow=(bow, 76))
