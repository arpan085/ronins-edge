"""Assemble all four characters: mesh parts, rig, baked clips, GLB + anim metadata."""
import bpy, sys, os, json, math
sys.path.insert(0, "/data/ronins_edge/v2")
sys.path.insert(0, "/data/ronins_edge/v3")
from mathutils import Vector, Euler, Matrix
from math import radians as D
from lib_build import reset, uv_project
import rig as RIG
import body as BODY
import anim_core as AC
from anim_core import Timeline, pose, merge, ROOT
import clips as CL
import clips_combat as CC
import clips_enemy as CE

OUT = "/data/ronins_edge/v3/assets/models"
os.makedirs(OUT, exist_ok=True)
FPS = 30

# -------------------------------------------------- overlap / spring configs
OVERLAP = {
    "spine": 0.6, "chest": 1.3, "upperchest": 1.9, "neck": 2.7, "head": 3.5,
    "forearm.L": 0.7, "forearm.R": 0.7, "hand.L": 1.3, "hand.R": 1.3,
    "shoulder.L": 0.9, "shoulder.R": 0.9, "toe.L": 0.5, "toe.R": 0.5,
    "eye.L": 4.2, "eye.R": 4.2, "jaw": 3.8,
}
SPRINGS = {
    "sode.L":      dict(driver="upperarm.L", gain=(1.20, 0.0, 0.55), k=150, c=11, limit=19),
    "sode.R":      dict(driver="upperarm.R", gain=(1.20, 0.0, 0.55), k=150, c=11, limit=19),
    "kusazuri.F":  dict(driver="_root", gain=(16.0, 0.0, 0.0), k=120, c=9.5, limit=24),
    "kusazuri.B":  dict(driver="_root", gain=(-16.0, 0.0, 0.0), k=120, c=9.5, limit=24),
    "kusazuri.L":  dict(driver="thigh.L", gain=(0.55, 0.0, 0.30), k=130, c=10, limit=18),
    "kusazuri.R":  dict(driver="thigh.R", gain=(0.55, 0.0, 0.30), k=130, c=10, limit=18),
    "obi.L":       dict(driver="_root", gain=(20.0, 0.0, 8.0), k=95,  c=7.5, limit=28),
    "obi.R":       dict(driver="_root", gain=(20.0, 0.0, -8.0), k=95, c=7.5, limit=28),
    "scabbard":    dict(driver="hips",  gain=(0.70, 0.35, 0.40), k=170, c=14, limit=13),
}

def springs_for(kind):
    s = dict(SPRINGS)
    if kind == "archer":                 # quiver is strapped tight, barely moves
        s["scabbard"] = dict(driver="hips", gain=(0.35, 0.2, 0.2), k=210, c=17, limit=8)
    if kind == "captain":                # banner pole has a long, slow swing
        s["scabbard"] = dict(driver="_root", gain=(26.0, 0.0, 10.0), k=52, c=5.0, limit=30)
        for b in ("sode.L", "sode.R"):
            s[b] = dict(driver=("upperarm." + b[-1]), gain=(1.45, 0.0, 0.7), k=110, c=9, limit=24)
    if kind == "ashigaru":               # pouch, minimal motion
        s["scabbard"] = dict(driver="hips", gain=(0.45, 0.25, 0.25), k=190, c=15, limit=10)
    return s

# -------------------------------------------------- action writing
def write_action(arm, name, track, bones_only=None, loop=False):
    if arm.animation_data is None:
        arm.animation_data_create()
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data.action = act
    names = set(bones_only) if bones_only else None
    for f, p in track:
        for pb in arm.pose.bones:
            if names is not None and pb.name not in names:
                continue
            r = p.get(pb.name, (0, 0, 0))
            pb.rotation_euler = Euler([D(r[0]), D(r[1]), D(r[2])], 'XYZ')
            pb.keyframe_insert("rotation_euler", frame=f)
        if names is None:
            rb = arm.pose.bones.get("root")
            if rb:
                rb.location = Vector(p.get(ROOT, (0, 0, 0)))
                rb.keyframe_insert("location", frame=f)
    for fc in act.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = 'LINEAR'
    return act

def neutralize_root(track, scale=0.45):
    """Keep the mid-clip weight surge but return horizontal root offset to zero,
    so an action never leaves the model displaced when its layer fades out."""
    n = len(track) - 1
    if n <= 0: return track
    end = track[-1][1].get(ROOT, (0, 0, 0))
    out = []
    for i, (f, p) in enumerate(track):
        t = i / float(n)
        v = p.get(ROOT, (0, 0, 0))
        q = dict(p)
        q[ROOT] = ((v[0] - end[0] * t) * scale, (v[1] - end[1] * t) * scale, v[2])
        out.append((f, q))
    return out

def bake(clip_tl, n, kind, loop=False, overlap=None, springs=None):
    tr = clip_tl.sample(1.0)
    ov = OVERLAP if overlap is None else overlap
    if ov:
        tr = AC.apply_overlap(tr, ov, loop)
    sp = springs_for(kind) if springs is None else springs
    if sp:
        tr = AC.apply_spring(tr, sp, loop)
    return tr

# -------------------------------------------------- stride measurement
def measure_stride(arm, track):
    """Per-leg stance measurement: step length divided by stance duration gives
    the body speed at which the planted foot stays still on the ground."""
    prev = arm.animation_data.action
    tmp = write_action(arm, "__measure", track)
    n = len(track)
    ank = {"L": [], "R": []}
    low = {"L": [], "R": []}
    for i in range(n):
        bpy.context.scene.frame_set(i)
        bpy.context.view_layer.update()
        for s in ("L", "R"):
            fb = arm.pose.bones["foot." + s]
            tb = arm.pose.bones["toe." + s]
            a_w = arm.matrix_world @ fb.head
            t_w = arm.matrix_world @ tb.tail
            ank[s].append(Vector((a_w.x, a_w.y, a_w.z)))
            # stance is detected from the ankle alone: it tracks leg extension,
            # whereas the toe tip dips with ankle roll and would pick the wrong
            # window on toe-first gaits such as the backpedal.
            low[s].append(a_w.z)
    bpy.data.actions.remove(tmp)
    arm.animation_data.action = prev
    vels = []
    windows = []
    for s in ("L", "R"):
        zs = low[s]
        zmin, zmax = min(zs), max(zs)
        thr = zmin + max(0.006, (zmax - zmin) * 0.30)
        best = (0, 0)
        for st in range(n):
            if zs[st] > thr: continue
            L = 0
            while L < n and zs[(st + L) % n] <= thr:
                L += 1
            if L > best[1]:
                best = (st, L)
        st, L = best
        if L < 3:
            continue
        # least-squares slope of foot position over the stance window
        xs = [k / float(FPS) for k in range(L)]
        mx = sum(xs) / L
        den = sum((x - mx) ** 2 for x in xs) or 1e-9
        vv = []
        for axis in (0, 1):
            ps = [ank[s][(st + k) % n][axis] for k in range(L)]
            mp = sum(ps) / L
            vv.append(sum((xs[k] - mx) * (ps[k] - mp) for k in range(L)) / den)
        vels.append(Vector((-vv[0], -vv[1], 0.0)))
        windows.append(L)
    if not vels:
        return dict(foot_vel=[0.0, 0.0], speed_mps=0.0, planted_frames=0, cycle_frames=n - 1)
    v = sum(vels, Vector((0, 0, 0))) / len(vels)
    return dict(foot_vel=[round(v.x, 4), round(v.y, 4)],
                speed_mps=round(v.length, 4),
                planted_frames=int(sum(windows) / len(windows)),
                cycle_frames=n - 1)

# -------------------------------------------------- clip specs
def kaito_clips():
    S = {}
    for sp, key in (("walk", "Walk"), ("jog", "Jog")):
        for mode in ("F", "B", "L", "R"):
            tl, n = CL.loco_clip("kaito", sp, mode)
            S[f"{key}_{mode}"] = dict(tl=tl, n=n, loop=True, loco=(sp in ("walk", "jog")))
    tl, n = CL.loco_clip("kaito", "sprint", "F"); S["Sprint_F"] = dict(tl=tl, n=n, loop=True, loco=True)
    tl, n = CL.idle_loco_clip("kaito"); S["Idle_Loco"] = dict(tl=tl, n=n, loop=True, loco=True)
    for v in (0, 1, 2):
        tl, n = CL.idle_clip("kaito", v); S[f"Idle_{'ABC'[v]}"] = dict(tl=tl, n=n, loop=True)
    tl, n = CL.idle_clip("kaito", 0, guard=True); S["Idle_Combat"] = dict(tl=tl, n=n, loop=True)
    tl, n = CL.breathe_additive("kaito")
    S["Breathe_Add"] = dict(tl=tl, n=n, loop=True, only=["spine", "chest", "upperchest", "neck",
                                                          "shoulder.L", "shoulder.R"], noov=True)
    tl, n = CL.start_run("kaito"); S["Start_Run"] = dict(tl=tl, n=n)
    tl, n = CL.stop_run("kaito", True); S["Stop_Run"] = dict(tl=tl, n=n)
    tl, n = CL.stop_run("kaito", False); S["Stop_Walk"] = dict(tl=tl, n=n)
    for deg in (45, 90, 180):
        for r in (True, False):
            tl, n = CL.turn_clip("kaito", deg, r)
            S[f"Turn_{'R' if r else 'L'}{deg}"] = dict(tl=tl, n=n)
    for d in ("F", "B", "L", "R"):
        tl, n, rm = CL.dodge_clip("kaito", d); S[f"Dodge_{d}"] = dict(tl=tl, n=n, rm=rm)
    tl, n, rm = CL.roll_clip("kaito"); S["Roll_F"] = dict(tl=tl, n=n, rm=rm)
    (u, un), (a, an), (l, ln) = CL.jump_clips("kaito")
    S["Jump_Up"] = dict(tl=u, n=un); S["Jump_Air"] = dict(tl=a, n=an, loop=True)
    S["Jump_Land"] = dict(tl=l, n=ln)
    for fn, nm in ((CC.light1, "Light1"), (CC.light2, "Light2"), (CC.light3, "Light3"),
                   (CC.heavy, "Heavy"), (CC.deflect, "Deflect"), (CC.deathblow, "Deathblow")):
        tl, n, rm = fn("kaito"); S[nm] = dict(tl=tl, n=n, rm=rm)
    (bi, bin_), (bl, bln), (bh, bhn) = CC.block_clips("kaito")
    S["Block_In"] = dict(tl=bi, n=bin_); S["Block_Idle"] = dict(tl=bl, n=bln, loop=True)
    S["Block_Impact"] = dict(tl=bh, n=bhn)
    (pt, ptn), (dr, drn) = CC.sheathe_clips("kaito")
    S["Sheathe"] = dict(tl=pt, n=ptn); S["Unsheathe"] = dict(tl=dr, n=drn)
    for d in ("F", "B", "L", "R"):
        tl, n = CC.hit_clip("kaito", d); S[f"Hit_{d}"] = dict(tl=tl, n=n)
    for d in ("F", "B"):
        tl, n = CC.hit_clip("kaito", d, True); S[f"HitHeavy_{d}"] = dict(tl=tl, n=n)
    for v in (0, 1):
        tl, n = CC.stagger_clip("kaito", v); S[f"Stagger_{'AB'[v]}"] = dict(tl=tl, n=n)
        tl, n = CC.getup_clip("kaito", v); S[f"GetUp_{'AB'[v]}"] = dict(tl=tl, n=n)
        tl, n, rm = CC.death_clip("kaito", v); S[f"Death_{'AB'[v]}"] = dict(tl=tl, n=n, rm=rm)
    for b in (True, False):
        tl, n, rm = CC.knockdown_clip("kaito", b)
        S[f"Knockdown_{'B' if b else 'F'}"] = dict(tl=tl, n=n, rm=rm)
    for k, (tl, n) in CE.cine_clips("kaito").items():
        S[k] = dict(tl=tl, n=n)
    return S

def enemy_clip_specs(kind):
    S = {}
    for sp, key in (("walk", "Walk"), ("jog", "Jog")):
        for mode in (("F", "B") if kind != "archer" else ("F", "B", "L", "R")):
            tl, n = CL.loco_clip(kind, sp, mode)
            S[f"{key}_{mode}"] = dict(tl=tl, n=n, loop=True, loco=True)
    tl, n = CL.idle_loco_clip(kind); S["Idle_Loco"] = dict(tl=tl, n=n, loop=True, loco=True)
    for v in (0, 1):
        tl, n = CL.idle_clip(kind, v); S[f"Idle_{'AB'[v]}"] = dict(tl=tl, n=n, loop=True)
    tl, n = CL.breathe_additive(kind)
    S["Breathe_Add"] = dict(tl=tl, n=n, loop=True, only=["spine", "chest", "upperchest", "neck",
                                                          "shoulder.L", "shoulder.R"], noov=True)
    for deg in (90, 180):
        for r in (True, False):
            tl, n = CL.turn_clip(kind, deg, r)
            S[f"Turn_{'R' if r else 'L'}{deg}"] = dict(tl=tl, n=n)
    tl, n = CE.alert_clip(kind); S["Alert"] = dict(tl=tl, n=n)
    tl, n = CE.investigate_clip(kind); S["Investigate"] = dict(tl=tl, n=n, loop=True)
    for d in ("F", "B", "L", "R"):
        tl, n = CC.hit_clip(kind, d); S[f"Hit_{d}"] = dict(tl=tl, n=n)
    tl, n = CC.hit_clip(kind, "F", True); S["HitHeavy_F"] = dict(tl=tl, n=n)
    tl, n = CC.stagger_clip(kind, 0); S["Stagger_A"] = dict(tl=tl, n=n)
    tl, n = CC.stagger_clip(kind, 1); S["Stagger_B"] = dict(tl=tl, n=n)
    tl, n, rm = CC.knockdown_clip(kind, True); S["Knockdown_B"] = dict(tl=tl, n=n, rm=rm)
    tl, n = CC.getup_clip(kind, 0); S["GetUp_A"] = dict(tl=tl, n=n)
    for v in (0, 1):
        tl, n, rm = CC.death_clip(kind, v); S[f"Death_{'AB'[v]}"] = dict(tl=tl, n=n, rm=rm)
    if kind == "ashigaru":
        sc = CE.spear_clips()
        for nm in ("Attack", "Sweep", "Block"):
            S[nm] = dict(tl=sc[nm][0], n=sc[nm][1])
        S["Shuffle"] = dict(tl=sc["Shuffle"][0], n=sc["Shuffle"][1], loop=True)
    elif kind == "archer":
        bc = CE.bow_clips()
        for nm in ("Nock", "AimIn", "Shoot", "BackStep", "Flinch"):
            S[nm] = dict(tl=bc[nm][0], n=bc[nm][1])
        S["HoldDraw"] = dict(tl=bc["HoldDraw"][0], n=bc["HoldDraw"][1], loop=True)
    else:
        bo = CE.boss_clips()
        S["Idle_Boss"] = dict(tl=bo["Idle"][0], n=bo["Idle"][1], loop=True)
        for nm in ("Intimidate", "EnterCombat", "Attack1", "Attack2", "Attack3",
                   "PhaseTransition", "Defeat"):
            S[nm] = dict(tl=bo[nm][0], n=bo[nm][1])
    return S

# -------------------------------------------------- assembly
def align_to_bone(ob, arm, bone_name, from_dir=Vector((0, 1, 0)), extra_rot=None):
    b = arm.data.bones[bone_name]
    head = Vector(b.head_local); tail = Vector(b.tail_local)
    d = (tail - head).normalized()
    q = from_dir.rotation_difference(d)
    M = Matrix.Translation(head) @ q.to_matrix().to_4x4()
    if extra_rot is not None:
        M = M @ Euler([D(a) for a in extra_rot]).to_matrix().to_4x4()
    ob.matrix_world = M @ ob.matrix_world
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

def build(kind, specs):
    reset()
    M = BODY.kit(kind)
    torso = BODY.build_torso(kind, M); uv_project(torso)
    limbs = BODY.build_limbs(kind, M); uv_project(limbs)
    head = BODY.build_head(kind, M);   uv_project(head)
    sl = BODY.build_sode(kind, M, "L"); uv_project(sl)
    sr = BODY.build_sode(kind, M, "R"); uv_project(sr)
    ku = BODY.build_kusazuri(kind, M);  uv_project(ku)
    ob_ = BODY.build_obi(kind, M);      uv_project(ob_)
    wp = BODY.build_weapon(kind, M);    uv_project(wp)
    sc = BODY.build_scabbard(kind, M);  uv_project(sc)

    arm, bones = RIG.make_rig("Rig_" + kind)
    align_to_bone(wp, arm, "weapon.R", extra_rot=(-24, 0, 0))
    align_to_bone(sc, arm, "scabbard")

    RIG.bind(torso, arm); RIG.bind(limbs, arm); RIG.bind(head, arm, smooth_iters=1)
    RIG.bind(sl, arm, only={"sode.L"}, smooth_iters=0)
    RIG.bind(sr, arm, only={"sode.R"}, smooth_iters=0)
    RIG.bind(ku, arm, only={"kusazuri.F", "kusazuri.B", "kusazuri.L", "kusazuri.R"}, smooth_iters=1)
    RIG.bind(ob_, arm, only={"obi.L", "obi.R"}, smooth_iters=0)
    RIG.bind(wp, arm, only={"weapon.R"}, smooth_iters=0)
    RIG.bind(sc, arm, only={"scabbard"}, smooth_iters=0)
    mesh = RIG.join_parts([torso, limbs, head, sl, sr, ku, ob_, wp, sc], kind.capitalize() + "_Mesh")

    meta = {"bones": len(bones), "clips": {}}
    first = None
    for name, spec in specs.items():
        loop = spec.get("loop", False)
        ov = {} if spec.get("noov") else None
        tr = bake(spec["tl"], spec["n"], kind, loop=loop, overlap=ov,
                  springs={} if spec.get("only") else None)
        if not loop and not spec.get("only"):
            tr = neutralize_root(tr, 0.45)
        write_action(arm, name, tr, bones_only=spec.get("only"), loop=loop)
        if first is None: first = name
        info = {"frames": len(tr) - 1, "fps": FPS, "loop": loop}
        if spec.get("rm"): info["root_motion"] = [round(v, 4) for v in spec["rm"]]
        if spec.get("loco"): info.update(measure_stride(arm, tr))
        meta["clips"][name] = info

    arm.animation_data.action = bpy.data.actions[first]
    # the shared reset() helper leaves the scene at 24 fps; every clip in this
    # pipeline is authored in 30 fps frames, and glTF stores key times in
    # seconds, so exporting at 24 would play the whole game 25% slow
    bpy.context.scene.render.fps = FPS
    bpy.context.scene.render.fps_base = 1.0
    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = 120
    tris = sum(len(p.vertices) - 2 for p in mesh.data.polygons)
    meta["tris"] = tris
    path = os.path.join(OUT, kind.capitalize() + "_Ronin.glb")
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=False,
        export_animations=True, export_animation_mode='ACTIONS', export_nla_strips=False,
        export_skins=True, export_apply=False, export_yup=True,
        export_optimize_animation_size=True, export_image_format='AUTO',
        export_materials='EXPORT')
    print(f"BUILT {kind}: tris={tris} bones={len(bones)} clips={len(specs)} -> {path}")
    return meta

if __name__ == "__main__":
    allmeta = {}
    allmeta["kaito"] = build("kaito", kaito_clips())
    for k in ("ashigaru", "archer", "captain"):
        allmeta[k] = build(k, enemy_clip_specs(k))
    with open(os.path.join(OUT, "anim_meta.json"), "w") as f:
        json.dump(allmeta, f, indent=1)
    for k, v in allmeta.items():
        loco = {n: (c.get("speed_mps"), c.get("cycle_frames")) for n, c in v["clips"].items() if "speed_mps" in c}
        print(k, "tris", v["tris"], "bones", v["bones"], "clips", len(v["clips"]))
        print("   stride:", loco)
    print("ALL_DONE")
