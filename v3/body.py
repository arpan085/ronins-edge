"""Character meshes built as separately-skinned parts for clean deformation."""
import bpy, sys, math
sys.path.insert(0, "/data/ronins_edge/v2")
from lib_build import MeshBuilder, make_mat, uv_project
from math import sin, cos, pi, radians as R

def kit(kind):
    skin  = make_mat("skin", (0.72, 0.56, 0.44), 0.0, 0.58)
    cloth = make_mat("cloth_indigo", (0.085, 0.105, 0.20), 0.0, 0.84,
                     ntex="cloth_n.png", rtex="cloth_r.png", uv_scale=6)
    if kind == "kaito":
        arm  = make_mat("armor_iron", (0.048, 0.050, 0.058), 0.45, 0.40, ntex="metal_n.png", rtex="metal_r.png", uv_scale=4)
        lace = make_mat("lacing_red", (0.36, 0.045, 0.05), 0.0, 0.70, ntex="cloth_n.png", uv_scale=10)
        gold = make_mat("gold_trim", (0.64, 0.46, 0.13), 0.95, 0.24)
        hat  = make_mat("kasa_straw", (0.50, 0.40, 0.23), 0.0, 0.88, ctex="tatami_c.png", ntex="tatami_n.png", uv_scale=5)
        acc  = make_mat("spirit_blue", (0.16, 0.48, 0.80), 0.0, 0.30)
    elif kind == "ashigaru":
        arm  = make_mat("armor_indigo", (0.075, 0.100, 0.23), 0.30, 0.54, ntex="metal_n.png", uv_scale=4)
        lace = make_mat("lacing_black", (0.040, 0.040, 0.046), 0.0, 0.78, ntex="cloth_n.png", uv_scale=10)
        gold = make_mat("brass", (0.46, 0.35, 0.14), 0.85, 0.36)
        hat  = make_mat("jingasa_black", (0.045, 0.045, 0.052), 0.25, 0.48)
        acc  = make_mat("mon_white", (0.80, 0.80, 0.78), 0.0, 0.60)
    elif kind == "archer":
        arm  = make_mat("armor_olive", (0.115, 0.135, 0.090), 0.22, 0.60, ntex="metal_n.png", uv_scale=4)
        lace = make_mat("lacing_tan", (0.36, 0.28, 0.16), 0.0, 0.76, ntex="cloth_n.png", uv_scale=10)
        gold = make_mat("brass", (0.46, 0.35, 0.14), 0.85, 0.36)
        hat  = make_mat("kasa_straw", (0.50, 0.40, 0.23), 0.0, 0.88, ctex="tatami_c.png", ntex="tatami_n.png", uv_scale=5)
        acc  = make_mat("feather", (0.72, 0.68, 0.58), 0.0, 0.66)
    else:
        arm  = make_mat("armor_crimson", (0.28, 0.050, 0.055), 0.36, 0.40, ntex="metal_n.png", rtex="metal_r.png", uv_scale=4)
        lace = make_mat("lacing_gold", (0.56, 0.43, 0.14), 0.6, 0.40, ntex="cloth_n.png", uv_scale=10)
        gold = make_mat("gold_trim", (0.66, 0.48, 0.14), 0.95, 0.22)
        hat  = make_mat("helmet_steel", (0.085, 0.085, 0.10), 0.78, 0.28, ntex="metal_n.png", uv_scale=4)
        acc  = make_mat("banner_crimson", (0.42, 0.055, 0.06), 0.0, 0.72, ntex="cloth_n.png", uv_scale=8)
    return dict(
        skin=skin, cloth=cloth, arm=arm, lace=lace, gold=gold, hat=hat, acc=acc,
        leather=make_mat("leather", (0.19, 0.125, 0.072), 0.05, 0.62, ctex="leather_c.png", ntex="leather_n.png", uv_scale=5),
        steel=make_mat("blade_steel", (0.80, 0.82, 0.86), 1.0, 0.14, ntex="metal_n.png", uv_scale=2),
        wood=make_mat("wood", (0.27, 0.185, 0.105), 0.0, 0.62, ctex="wood_c.png", ntex="wood_n.png", uv_scale=6),
        lacq=make_mat("lacquer_black", (0.022, 0.022, 0.028), 0.28, 0.16))

PROFILE = {           # bulk, shoulder width, height feel
    "kaito":    dict(bulk=1.00, sw=1.00),
    "ashigaru": dict(bulk=0.98, sw=0.94),
    "archer":   dict(bulk=0.92, sw=0.90),
    "captain":  dict(bulk=1.14, sw=1.16),
}

# ------------------------------------------------------------------ torso
def build_torso(kind, M):
    P = PROFILE[kind]; bu = P["bulk"]; sw = P["sw"]
    b = MeshBuilder("Torso")
    # under-layer
    b.cone(0.150 * bu, 0.128 * bu, 0.22, (0, 0, 1.10), seg=10, mat=M["cloth"])
    # do: tapered, wider at chest -> strong silhouette
    b.cone(0.156 * bu, 0.182 * bu * sw, 0.30, (0, 0, 1.30), seg=10, mat=M["arm"])
    b.cone(0.182 * bu * sw, 0.150 * bu, 0.10, (0, 0, 1.475), seg=10, mat=M["cloth"])
    # lacing bands
    for z in (1.20, 1.275, 1.35, 1.42):
        b.cone(0.170 * bu + (z - 1.2) * 0.07, 0.170 * bu + (z - 1.2) * 0.07, 0.020,
               (0, 0, z), seg=10, mat=M["lace"])
    # vertical lacing straps
    for s in (1, -1):
        b.box((0.013, 0.16 * bu, 0.30), (s * 0.168 * bu * sw, 0, 1.30), mat=M["lace"])
    # obi belt
    b.cone(0.162 * bu, 0.158 * bu, 0.062, (0, 0, 1.072), seg=10, mat=M["leather"])
    b.box((0.070, 0.030, 0.070), (0.095, 0.108 * bu, 1.072), mat=M["gold"])
    # hips
    b.cone(0.148 * bu, 0.152 * bu, 0.10, (0, 0, 0.985), seg=10, mat=M["arm"])
    if kind == "kaito":     # spirit-fox emblem
        b.box((0.085, 0.022, 0.085), (0, 0.170 * bu, 1.315), rot=(0, 0, 45), mat=M["acc"])
    if kind == "ashigaru":
        b.cone(0.055, 0.055, 0.016, (0, 0.176 * bu, 1.33), rot=(90, 0, 0), seg=10, mat=M["acc"])
    if kind == "captain":   # back plate for the banner pole
        b.box((0.095, 0.055, 0.17), (0, -0.175 * bu, 1.30), mat=M["lacq"])
    return b.finish()

# ------------------------------------------------------------------ limbs
def build_limbs(kind, M):
    P = PROFILE[kind]; bu = P["bulk"]
    b = MeshBuilder("Limbs")
    for s in (1, -1):
        # arm: tapered upper + fore, kote cuff, hand
        b.cone(0.078 * bu, 0.066 * bu, 0.255, (s * 0.176, 0, 1.278), seg=8, mat=M["arm"])
        b.cone(0.064 * bu, 0.052 * bu, 0.235, (s * 0.191, 0, 1.030), seg=8, mat=M["arm"])
        b.box((0.088, 0.094, 0.052), (s * 0.197, 0, 0.912), mat=M["leather"])
        b.box((0.076, 0.082, 0.098), (s * 0.199, 0.012, 0.848), mat=M["leather"])
        b.box((0.028, 0.030, 0.056), (s * 0.199, -0.044, 0.852), mat=M["skin"])
        # leg: hakama flare, shin wrap, tabi + toe
        b.cone(0.125 * bu, 0.170 * bu, 0.40, (s * 0.100, 0, 0.730), seg=10, mat=M["cloth"])
        b.cone(0.088, 0.078, 0.40, (s * 0.103, 0, 0.300), seg=8, mat=M["cloth"])
        b.box((0.104, 0.145, 0.070), (s * 0.104, 0.012, 0.070), mat=M["leather"])
        b.box((0.096, 0.080, 0.042), (s * 0.104, 0.172, 0.036), mat=M["leather"])   # toe
        b.box((0.050, 0.020, 0.092), (s * 0.104, 0.068, 0.140), mat=M["lace"])
    return b.finish()

# ------------------------------------------------------------------ head
def build_head(kind, M):
    b = MeshBuilder("Head")
    b.cone(0.058, 0.055, 0.105, (0, 0, 1.500), seg=8, mat=M["skin"])
    b.sphere(0.112, (0, 0.004, 1.632), seg=12, rings=8, mat=M["skin"], scale=(1.0, 0.98, 1.14))
    if kind == "kaito":
        b.cone(0.345, 0.020, 0.150, (0, 0, 1.800), seg=16, mat=M["hat"])
        b.cone(0.100, 0.095, 0.030, (0, 0, 1.742), seg=12, mat=M["lace"])
        b.box((0.150, 0.100, 0.058), (0, 0.078, 1.578), mat=M["lacq"])
        b.box((0.162, 0.022, 0.026), (0, 0.112, 1.556), mat=M["lace"])
    elif kind == "ashigaru":
        b.cone(0.285, 0.055, 0.092, (0, 0, 1.752), seg=14, mat=M["hat"])
        b.cone(0.100, 0.096, 0.028, (0, 0, 1.706), seg=12, mat=M["lace"])
        b.box((0.146, 0.098, 0.048), (0, 0.078, 1.578), mat=M["lacq"])
    elif kind == "archer":
        b.cone(0.325, 0.020, 0.140, (0, 0, 1.786), seg=14, mat=M["hat"])
        b.box((0.144, 0.094, 0.046), (0, 0.078, 1.578), mat=M["lacq"])
    else:
        b.sphere(0.140, (0, 0, 1.662), seg=12, rings=8, mat=M["hat"], scale=(1.0, 1.02, 0.86))
        b.cone(0.215, 0.150, 0.042, (0, -0.010, 1.598), seg=14, mat=M["hat"])
        for s in (1, -1):
            b.box((0.048, 0.050, 0.300), (s * 0.112, 0.022, 1.862), rot=(0, s * -22, 0), mat=M["gold"])
        b.box((0.156, 0.118, 0.068), (0, 0.078, 1.578), mat=M["lacq"])
        b.box((0.190, 0.028, 0.032), (0, 0.100, 1.548), mat=M["lace"])
    # facial anchors (deliberately small, driven by jaw/eye/brow bones)
    for s in (1, -1):
        b.box((0.030, 0.014, 0.017), (s * 0.037, 0.098, 1.655), mat=M["lacq"])   # eye
        b.box((0.042, 0.014, 0.011), (s * 0.037, 0.100, 1.692), mat=M["lacq"])   # brow
    b.box((0.078, 0.036, 0.030), (0, 0.086, 1.586), mat=M["skin"])               # jaw
    return b.finish()

# ------------------------------------------------------------------ cloth parts
def build_sode(kind, M, side):
    P = PROFILE[kind]; sw = P["sw"]; s = 1 if side == "L" else -1
    b = MeshBuilder("Sode_" + side)
    n = 4 if kind == "captain" else 3
    for i in range(n):
        z = 1.415 - i * 0.072
        w = (0.205 if kind == "captain" else 0.180) * sw * (1.0 - i * 0.045)
        b.box((w, 0.225, 0.062), (s * (0.245 + i * 0.006), 0, z), rot=(0, s * -8, 0), mat=M["arm"])
        b.box((w * 0.9, 0.012, 0.017), (s * (0.245 + i * 0.006), 0.118, z - 0.021),
              rot=(0, s * -8, 0), mat=M["lace"])
    return b.finish()

def build_kusazuri(kind, M):
    P = PROFILE[kind]; bu = P["bulk"]
    b = MeshBuilder("Kusazuri")
    for a, r in ((0, 0.150), (90, 0.142), (180, 0.150), (270, 0.142)):
        rad = math.radians(a)
        for i in range(2):
            z = 0.895 - i * 0.075
            b.box((0.185 - i * 0.012, 0.042, 0.082), (sin(rad) * r * bu, cos(rad) * r * bu, z),
                  rot=(0, 0, -a), mat=M["arm"])
            b.box((0.165, 0.011, 0.014), (sin(rad) * (r + 0.024) * bu, cos(rad) * (r + 0.024) * bu, z - 0.030),
                  rot=(0, 0, -a), mat=M["lace"])
    return b.finish()

def build_obi(kind, M):
    b = MeshBuilder("ObiTails")
    for s in (1, -1):
        b.box((0.052, 0.030, 0.185), (s * 0.075, -0.125, 0.892), rot=(9 * s, 0, 0), mat=M["leather"])
        b.box((0.044, 0.024, 0.090), (s * 0.080, -0.140, 0.780), rot=(13 * s, 0, 0), mat=M["leather"])
    return b.finish()

# ------------------------------------------------------------------ weapons
def build_weapon(kind, M):
    b = MeshBuilder("Weapon")
    if kind == "kaito":
        b.box((0.028, 0.86, 0.010), (0, 0.50, 0), mat=M["steel"])        # blade
        b.box((0.020, 0.10, 0.012), (0, 0.94, 0), rot=(0, 0, 0), mat=M["steel"])
        b.cone(0.052, 0.052, 0.014, (0, 0.055, 0), rot=(90, 0, 0), seg=10, mat=M["gold"])
        b.box((0.030, 0.115, 0.024), (0, -0.015, 0), mat=M["lace"])      # tsuka
        b.box((0.034, 0.016, 0.028), (0, -0.080, 0), mat=M["gold"])      # kashira
    elif kind == "ashigaru":
        b.cone(0.016, 0.014, 1.95, (0, 0.80, 0), rot=(90, 0, 0), seg=6, mat=M["wood"])
        b.cone(0.030, 0.002, 0.30, (0, 1.90, 0), rot=(-90, 0, 0), seg=6, mat=M["steel"])
        b.cone(0.024, 0.024, 0.05, (0, 1.735, 0), rot=(90, 0, 0), seg=6, mat=M["gold"])
    elif kind == "archer":
        for i in range(7):                                               # yumi limb
            t = (i - 3) / 3.0
            b.box((0.020, 0.26, 0.016), (0, t * 0.80, -abs(t) ** 1.7 * 0.16),
                  rot=(t * 26, 0, 0), mat=M["wood"])
        b.box((0.006, 1.66, 0.006), (0, 0, -0.145), mat=M["leather"])
        b.box((0.030, 0.10, 0.030), (0, 0, 0.004), mat=M["lace"])
    else:
        b.box((0.034, 1.15, 0.012), (0, 0.66, 0), mat=M["steel"])        # nodachi
        b.box((0.024, 0.13, 0.014), (0, 1.27, 0), mat=M["steel"])
        b.cone(0.062, 0.062, 0.016, (0, 0.062, 0), rot=(90, 0, 0), seg=10, mat=M["gold"])
        b.box((0.034, 0.170, 0.028), (0, -0.030, 0), mat=M["lace"])
        b.box((0.038, 0.018, 0.032), (0, -0.122, 0), mat=M["gold"])
    return b.finish()

def build_scabbard(kind, M):
    b = MeshBuilder("Scabbard")
    if kind == "archer":       # quiver of arrows instead
        b.cone(0.045, 0.040, 0.44, (0, 0, 0), rot=(90, 0, 0), seg=8, mat=M["leather"])
        for i in range(4):
            b.box((0.007, 0.36, 0.007), (-0.018 + i * 0.012, 0.22, 0.012), mat=M["wood"])
            b.box((0.014, 0.05, 0.002), (-0.018 + i * 0.012, 0.40, 0.012), mat=M["acc"])
        return b.finish()
    if kind == "ashigaru":     # small side pouch
        b.box((0.075, 0.105, 0.115), (0, 0, 0), mat=M["leather"])
        b.box((0.079, 0.020, 0.030), (0, 0.010, 0.050), mat=M["lace"])
        return b.finish()
    if kind == "captain":      # sashimono banner + saya
        b.cone(0.014, 0.014, 0.50, (0, 0, 0), rot=(90, 0, 0), seg=6, mat=M["lacq"])
        b.box((0.006, 0.42, 0.34), (0, 0.10, 0.0), mat=M["acc"])
        return b.finish()
    ln = 0.80
    b.cone(0.026, 0.023, ln, (0, 0, 0), rot=(90, 0, 0), seg=8, mat=M["lacq"])
    b.cone(0.030, 0.030, 0.020, (0, -ln * 0.42, 0), rot=(90, 0, 0), seg=8, mat=M["gold"])
    b.box((0.030, 0.045, 0.012), (0, -ln * 0.30, 0.024), mat=M["lace"])
    return b.finish()
