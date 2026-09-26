"""Production skeleton: 36 bones incl. 3-segment spine, toes, facial, cloth and weapon sockets."""
import bpy, bmesh, math
from mathutils import Vector, Euler, Matrix
from math import radians as D

# name, head, tail, parent            (.L entries are auto-mirrored to .R)
BONES = [
 ("root",       (0, 0, 0),          (0, 0.20, 0),        None),
 ("hips",       (0, 0, 0.95),       (0, 0, 1.06),        "root"),
 ("spine",      (0, 0, 1.06),       (0, 0, 1.19),        "hips"),
 ("chest",      (0, 0, 1.19),       (0, 0, 1.32),        "spine"),
 ("upperchest", (0, 0, 1.32),       (0, 0, 1.45),        "chest"),
 ("neck",       (0, 0, 1.45),       (0, 0, 1.55),        "upperchest"),
 ("head",       (0, 0, 1.55),       (0, 0, 1.74),        "neck"),
 ("jaw",        (0, 0.015, 1.615),  (0, 0.095, 1.575),   "head"),
 ("eye.L",      (0.037, 0.060, 1.655), (0.037, 0.115, 1.655), "head"),
 ("brow.L",     (0.037, 0.062, 1.690), (0.037, 0.112, 1.696), "head"),
 ("shoulder.L", (0.035, 0, 1.415),  (0.165, 0, 1.408),   "upperchest"),
 ("upperarm.L", (0.165, 0, 1.408),  (0.185, 0, 1.150),   "shoulder.L"),
 ("forearm.L",  (0.185, 0, 1.150),  (0.196, 0, 0.910),   "upperarm.L"),
 ("hand.L",     (0.196, 0, 0.910),  (0.200, 0.02, 0.800),"forearm.L"),
 ("sode.L",     (0.238, 0, 1.430),  (0.250, 0, 1.210),   "upperchest"),
 ("thigh.L",    (0.098, 0, 0.930),  (0.102, 0, 0.520),   "hips"),
 ("shin.L",     (0.102, 0, 0.520),  (0.104, 0, 0.098),   "thigh.L"),
 ("foot.L",     (0.104, 0, 0.098),  (0.105, 0.135, 0.032),"shin.L"),
 ("toe.L",      (0.105, 0.135, 0.032),(0.105, 0.215, 0.028),"foot.L"),
 ("kusazuri.F", (0, 0.075, 0.955),  (0, 0.105, 0.770),   "hips"),
 ("kusazuri.B", (0, -0.075, 0.955), (0, -0.105, 0.770),  "hips"),
 ("kusazuri.L", (0.135, 0, 0.955),  (0.170, 0, 0.770),   "hips"),
 ("obi.L",      (0.065, -0.10, 0.985),(0.085, -0.15, 0.790),"hips"),
 ("scabbard",   (0.055, -0.03, 0.975),(-0.085, -0.46, 0.885),"hips"),
 ("weapon.R",   (-0.200, 0.02, 0.800),(-0.200, 0.60, 0.800),"hand.R"),
]

# bones that must never receive automatic envelope weights
NO_AUTO = {"root", "jaw", "eye.L", "eye.R", "brow.L", "brow.R", "weapon.R",
           "scabbard", "sode.L", "sode.R", "kusazuri.F", "kusazuri.B",
           "kusazuri.L", "kusazuri.R", "obi.L", "obi.R"}

FACE_BONES = {"jaw", "eye.L", "eye.R", "brow.L", "brow.R"}
CLOTH_BONES = {"sode.L", "sode.R", "kusazuri.F", "kusazuri.B", "kusazuri.L",
               "kusazuri.R", "obi.L", "obi.R", "scabbard"}

def _m(n): return n[:-2] + ".R" if n.endswith(".L") else n

def full_bone_list(scale=1.0):
    out = []
    for n, h, t, p in BONES:
        out.append((n, h, t, p))
        if n.endswith(".L"):
            out.append((_m(n), (-h[0], h[1], h[2]), (-t[0], t[1], t[2]),
                        _m(p) if p and p.endswith(".L") else p))
    return out

def make_rig(name="Rig", scale=1.0):
    arm = bpy.data.armatures.new(name)
    ob = bpy.data.objects.new(name, arm)
    bpy.context.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.edit_bones
    for n, h, t, p in full_bone_list():
        b = eb.new(n)
        b.head = Vector(h) * scale
        b.tail = Vector(t) * scale
        if p:
            b.parent = eb[p]
            b.use_connect = (Vector(eb[p].tail) - b.head).length < 1e-4
        b.roll = 0
    bpy.ops.object.mode_set(mode='OBJECT')
    for pb in ob.pose.bones:
        pb.rotation_mode = 'XYZ'
    return ob, [n for n, _, _, _ in full_bone_list()]

def _seg_dist(p, a, b):
    ab = b - a; t = 0.0
    if ab.length_squared > 1e-9:
        t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length

def bind(mesh_ob, arm_ob, only=None, falloff=3.4, smooth_iters=2):
    """Nearest-segment weighting with top-3 bones and a smoothing pass.

    only: restrict this mesh part to a specific bone set (e.g. a sode plate).
    """
    bones = []
    for b in arm_ob.data.bones:
        if only is not None:
            if b.name not in only: continue
        elif b.name in NO_AUTO:
            continue
        bones.append((b.name, Vector(b.head_local), Vector(b.tail_local)))
    groups = {}
    for b in arm_ob.data.bones:
        groups[b.name] = mesh_ob.vertex_groups.new(name=b.name)
    mw = mesh_ob.matrix_world
    nv = len(mesh_ob.data.vertices)
    weights = [dict() for _ in range(nv)]
    for v in mesh_ob.data.vertices:
        p = mw @ v.co
        ds = sorted(((_seg_dist(p, h, t), n) for n, h, t in bones))[:3]
        ws = [(n, 1.0 / max(d, 8e-3) ** falloff) for d, n in ds]
        tot = sum(w for _, w in ws)
        for n, w in ws:
            weights[v.index][n] = w / tot
    # smooth weights across edges so joints deform without creasing
    if smooth_iters > 0 and len(mesh_ob.data.edges):
        adj = [[] for _ in range(nv)]
        for e in mesh_ob.data.edges:
            a, b = e.vertices
            adj[a].append(b); adj[b].append(a)
        for _ in range(smooth_iters):
            new = []
            for i in range(nv):
                acc = dict(weights[i])
                for k in acc: acc[k] *= 2.0
                for j in adj[i]:
                    for k, w in weights[j].items():
                        acc[k] = acc.get(k, 0.0) + w
                tot = sum(acc.values()) or 1.0
                acc = {k: w / tot for k, w in acc.items() if w / tot > 0.02}
                tot = sum(acc.values()) or 1.0
                new.append({k: w / tot for k, w in acc.items()})
            weights = new
    for i in range(nv):
        for n, w in weights[i].items():
            groups[n].add([i], w, 'REPLACE')
    mod = mesh_ob.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm_ob
    mesh_ob.parent = arm_ob
    return mesh_ob

def join_parts(parts, name):
    """Join skinned parts into one mesh, preserving vertex groups."""
    bpy.ops.object.select_all(action='DESELECT')
    for p in parts: p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob
