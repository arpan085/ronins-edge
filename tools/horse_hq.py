"""Ronin's Edge: build HorseHQ.glb from the CC0 Quaternius horse.
  blender -b --python tools/horse_hq.py
- Catmull-Clark subdivision (smooth silhouette instead of facets)
- UV unwrap + baked 2k coat (bay: noise, hair streaks, dapples, black points)
  and a tangent-space hair-streak normal map
- hair-card mane, forelock and tail (alpha strands) skinned from the old mane
- actions renamed back to the original clip names"""
import bpy, bmesh, math, random
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
SRC = "/data/ronins_edge/game/assets/horse/Horse.gltf"
OUT = "/data/ronins_edge/game/assets/horse/HorseHQ.glb"
TEX = "/data/ronins_edge/game/assets/horse/"
random.seed(7); np.random.seed(7)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
body = [o for o in bpy.data.objects if o.type == 'MESH'][0]
arm.data.pose_position = 'REST'
for a in bpy.data.actions:
    if a.name.endswith("_AnimalArmature"): a.name = a.name[:-len("_AnimalArmature")]
col = bpy.context.scene.collection
def activate(o):
    bpy.ops.object.mode_set(mode='OBJECT') if bpy.context.object and bpy.context.object.mode != 'OBJECT' else None
    for x in bpy.context.view_layer.objects: x.select_set(False)
    o.select_set(True); bpy.context.view_layer.objects.active = o
# ---- weld the faces. glTF stores a flat-shaded mesh with every face's vertices
# split, so the body arrives as thousands of disconnected faces; Catmull-Clark
# then shrinks each one into a separate rounded tile and the horse renders as a
# net of scales with dark gaps between them (the v0.13 bug). Merge first.
activate(body)
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=0.0005)
bpy.ops.object.mode_set(mode='OBJECT')
print("WELDED verts", len(body.data.vertices), "faces", len(body.data.polygons))
# ---- source copy of the original hair (weights for the cards)
activate(body)
src = body.copy(); src.data = body.data.copy(); col.objects.link(src)
src.modifiers.clear()
hair_idx = [i for i, m in enumerate(src.data.materials) if m.name == "Hair"][0]
bm = bmesh.new(); bm.from_mesh(src.data)
bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index != hair_idx], context='FACES')
bm.to_mesh(src.data); bm.free()
hair_pts = [src.matrix_world @ v.co for v in src.data.vertices]
# ---- subdivide body
activate(body)
sub = body.modifiers.new("Subdivision", 'SUBSURF'); sub.levels = 1; sub.render_levels = 1
bpy.ops.object.modifier_move_to_index(modifier="Subdivision", index=0)
bpy.ops.object.modifier_apply(modifier="Subdivision")
bpy.ops.object.shade_smooth()
# ---- UVs
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004)
bpy.ops.object.mode_set(mode='OBJECT')
# ---- procedural coat materials for baking
BASE = {m.name: tuple(m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value) if m.use_nodes else (0.2,0.1,0.04,1) for m in body.data.materials}
scene = bpy.context.scene
scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'; scene.cycles.samples = 1
scene.render.bake.margin = 24
coat = bpy.data.images.new("horse_coat", 2048, 2048)
nrm = bpy.data.images.new("horse_normal", 2048, 2048, float_buffer=False); nrm.colorspace_settings.name = 'Non-Color'
def build(mat, mode):
    nt = mat.node_tree; nt.nodes.clear(); N = nt.nodes; L = nt.links
    out = N.new('ShaderNodeOutputMaterial')
    tc = N.new('ShaderNodeTexCoord')
    base = N.new('ShaderNodeRGB'); base.outputs[0].default_value = BASE.get(mat.name, (0.2, 0.1, 0.04, 1))
    sep = N.new('ShaderNodeSeparateXYZ'); L.new(tc.outputs['Object'], sep.inputs[0])
    # big soft variation
    n1 = N.new('ShaderNodeTexNoise'); n1.inputs['Scale'].default_value = 1.1; n1.inputs['Detail'].default_value = 3
    L.new(tc.outputs['Object'], n1.inputs['Vector'])
    # hair streaks: long along the body (Y), fine across
    mp = N.new('ShaderNodeMapping'); mp.inputs['Scale'].default_value = (46.0, 3.0, 46.0)
    L.new(tc.outputs['Object'], mp.inputs['Vector'])
    n2 = N.new('ShaderNodeTexNoise'); n2.inputs['Scale'].default_value = 1.0; n2.inputs['Detail'].default_value = 4
    L.new(mp.outputs[0], n2.inputs['Vector'])
    # dapples
    vo = N.new('ShaderNodeTexVoronoi'); vo.inputs['Scale'].default_value = 7.0
    L.new(tc.outputs['Object'], vo.inputs['Vector'])
    if mode == 'EMIT':
        # value = 0.84 + 0.30*n1 ; streak = 0.93 + 0.14*n2 ; dapple lighten
        m1 = N.new('ShaderNodeMapRange'); m1.inputs[3].default_value = 0.80; m1.inputs[4].default_value = 1.16
        L.new(n1.outputs['Fac'], m1.inputs[0])
        m2 = N.new('ShaderNodeMapRange'); m2.inputs[3].default_value = 0.92; m2.inputs[4].default_value = 1.08
        L.new(n2.outputs['Fac'], m2.inputs[0])
        m3 = N.new('ShaderNodeMapRange'); m3.inputs[1].default_value = 0.0; m3.inputs[2].default_value = 0.35
        m3.inputs[3].default_value = 1.10; m3.inputs[4].default_value = 1.0
        L.new(vo.outputs['Distance'], m3.inputs[0])
        mul = N.new('ShaderNodeMath'); mul.operation = 'MULTIPLY'; L.new(m1.outputs[0], mul.inputs[0]); L.new(m2.outputs[0], mul.inputs[1])
        mul2 = N.new('ShaderNodeMath'); mul2.operation = 'MULTIPLY'; L.new(mul.outputs[0], mul2.inputs[0])
        if mat.name == "Main": L.new(m3.outputs[0], mul2.inputs[1])
        else: mul2.inputs[1].default_value = 1.0
        col_mul = N.new('ShaderNodeVectorMath'); col_mul.operation = 'SCALE'
        L.new(base.outputs[0], col_mul.inputs[0]); L.new(mul2.outputs[0], col_mul.inputs['Scale'])
        last = col_mul.outputs[0]
        if mat.name == "Main":
            # bay "points": legs go black below the knee/hock, fading up to the forearm
            pts = N.new('ShaderNodeMapRange'); pts.inputs[1].default_value = 1.95; pts.inputs[2].default_value = 1.05
            L.new(sep.outputs['Z'], pts.inputs[0])
            dark = N.new('ShaderNodeRGB'); dark.outputs[0].default_value = (0.028, 0.02, 0.016, 1)
            mix = N.new('ShaderNodeMix'); mix.data_type = 'RGBA'
            L.new(pts.outputs[0], mix.inputs['Factor']); L.new(last, mix.inputs[6]); L.new(dark.outputs[0], mix.inputs[7])
            last = mix.outputs[2]
            # slightly lighter belly/flank underside
            bel = N.new('ShaderNodeMapRange'); bel.inputs[1].default_value = 2.1; bel.inputs[2].default_value = 2.55
            bel.inputs[3].default_value = 1.12; bel.inputs[4].default_value = 1.0
            L.new(sep.outputs['Z'], bel.inputs[0])
            sc = N.new('ShaderNodeVectorMath'); sc.operation = 'SCALE'; L.new(last, sc.inputs[0]); L.new(bel.outputs[0], sc.inputs['Scale'])
            last = sc.outputs[0]
        em = N.new('ShaderNodeEmission'); L.new(last, em.inputs['Color'])
        L.new(em.outputs[0], out.inputs['Surface'])
    else:
        # fine hair streak bump + soft muscle-scale bump
        mpf = N.new('ShaderNodeMapping'); mpf.inputs['Scale'].default_value = (140.0, 9.0, 140.0)
        L.new(tc.outputs['Object'], mpf.inputs['Vector'])
        n3 = N.new('ShaderNodeTexNoise'); n3.inputs['Scale'].default_value = 1.0; n3.inputs['Detail'].default_value = 3
        L.new(mpf.outputs[0], n3.inputs['Vector'])
        add = N.new('ShaderNodeMath'); add.operation = 'MULTIPLY_ADD'
        L.new(n3.outputs['Fac'], add.inputs[0]); add.inputs[1].default_value = 1.0
        L.new(n1.outputs['Fac'], add.inputs[2])
        bump = N.new('ShaderNodeBump'); bump.inputs['Strength'].default_value = 0.22; bump.inputs['Distance'].default_value = 0.02
        L.new(add.outputs[0], bump.inputs['Height'])
        bs = N.new('ShaderNodeBsdfPrincipled'); L.new(bump.outputs[0], bs.inputs['Normal'])
        L.new(bs.outputs[0], out.inputs['Surface'])
    img = N.new('ShaderNodeTexImage'); img.image = coat if mode == 'EMIT' else nrm
    N.active = img
for m in body.data.materials: m.use_nodes = True; build(m, 'EMIT')
activate(body)
bpy.ops.object.bake(type='EMIT')
coat.filepath_raw = TEX + "horse_coat.png"; coat.file_format = 'PNG'; coat.save()
for m in body.data.materials: build(m, 'NORMAL')
bpy.ops.object.bake(type='NORMAL', normal_space='TANGENT')
nrm.filepath_raw = TEX + "horse_normal.png"; nrm.file_format = 'PNG'; nrm.save()
print("BAKED")
# ---- final body materials: one textured coat, glossy eyes, dark mane core
def pbr(name, rough, tex=True, color=(1, 1, 1, 1)):
    m = bpy.data.materials.new(name); m.use_nodes = True
    N = m.node_tree.nodes; L = m.node_tree.links; bs = N["Principled BSDF"]
    bs.inputs['Roughness'].default_value = rough
    bs.inputs['Base Color'].default_value = color
    if tex:
        t = N.new('ShaderNodeTexImage'); t.image = coat; L.new(t.outputs['Color'], bs.inputs['Base Color'])
        tn = N.new('ShaderNodeTexImage'); tn.image = nrm
        nm = N.new('ShaderNodeNormalMap'); L.new(tn.outputs['Color'], nm.inputs['Color']); L.new(nm.outputs[0], bs.inputs['Normal'])
    return m
coat_m = pbr("Coat", 0.74); hoof_m = pbr("Hoof", 0.48); mane_core = pbr("ManeCore", 0.62, False, (0.022, 0.017, 0.014, 1))
eye_m = pbr("Eye", 0.06, False, (0.012, 0.008, 0.006, 1))
for i, m in enumerate(list(body.data.materials)):
    body.data.materials[i] = {"Hooves": hoof_m, "Hair": mane_core, "Eye_White": eye_m, "Eye_Black": eye_m}.get(m.name, coat_m)
# ---- hair strand texture
W, H = 512, 1024
tex = np.zeros((H, W, 4), np.float32)
ys = np.arange(H) / H
for s in range(260):
    x0 = random.uniform(0, W); ln = random.uniform(0.55, 1.0); w = random.uniform(1.2, 3.2)
    amp = random.uniform(2, 9); fr = random.uniform(0.6, 2.2); ph = random.uniform(0, 6.28)
    val = random.uniform(0.75, 1.3)
    xs = x0 + amp * np.sin(ys * fr * 6.28 + ph) + ys * random.uniform(-14, 14)
    for yi in range(int(H * ln)):
        t = yi / H
        a = 1.0 if t < ln * 0.8 else max(0.0, 1.0 - (t - ln * 0.8) / (ln * 0.2))
        xc = xs[yi]
        for xi in range(int(xc - w - 1), int(xc + w + 2)):
            if 0 <= xi < W:
                d = abs(xi - xc)
                cov = max(0.0, 1.0 - d / w) * a
                if cov > tex[yi, xi, 3]:
                    tex[yi, xi, 3] = cov
                    tex[yi, xi, 0:3] = np.array([0.050, 0.038, 0.030]) * val
img = bpy.data.images.new("mane_strands", W, H, alpha=True)
img.pixels.foreach_set(np.flipud(tex).ravel())
img.filepath_raw = TEX + "mane_strands.png"; img.file_format = 'PNG'; img.save()
hair_m = bpy.data.materials.new("ManeHair"); hair_m.use_nodes = True
N = hair_m.node_tree.nodes; L = hair_m.node_tree.links; bs = N["Principled BSDF"]
t = N.new('ShaderNodeTexImage'); t.image = img
L.new(t.outputs['Color'], bs.inputs['Base Color']); L.new(t.outputs['Alpha'], bs.inputs['Alpha'])
bs.inputs['Roughness'].default_value = 0.55
hair_m.blend_method = 'CLIP'; hair_m.use_backface_culling = False
# ---- hair cards
depsgraph = bpy.context.evaluated_depsgraph_get()
bvh = BVHTree.FromObject(body, depsgraph)
bmh = bmesh.new(); uvl = bmh.loops.layers.uv.new("UVMap")
def lay(p, off):
    loc, nor, _, _ = bvh.find_nearest(p)
    if loc is None: return p
    return loc + nor * off
def card(pts, width, side, rootoff=0.02, follow=True):
    """pts: polyline root->tip; side: unit vector across the card"""
    u0 = random.uniform(0, 0.5); verts = []
    n = len(pts)
    for i, p in enumerate(pts):
        t = i / (n - 1)
        c = lay(p, rootoff + 0.035 * t) if follow else p
        w = width * (1.0 - 0.35 * t)
        verts.append((bmh.verts.new(c - side * w * 0.5), bmh.verts.new(c + side * w * 0.5), t))
    for i in range(n - 1):
        a, b, ta = verts[i]; c2, d, tb = verts[i + 1]
        f = bmh.faces.new((a, b, d, c2))
        for lp, (u, v) in zip(f.loops, ((u0, ta), (u0 + 0.5, ta), (u0 + 0.5, tb), (u0, tb))):
            lp[uvl].uv = (u, 1.0 - v)
# mane crest from the original hair: bins along the neck (y from -2.9 to -1.35)
mane = [p for p in hair_pts if p.y < -1.3]
bins = {}
for p in mane:
    k = int((p.y + 3.0) / 0.075)
    if k not in bins or p.z > bins[k].z: bins[k] = p
crest = [bins[k] for k in sorted(bins)]
for i, top in enumerate(crest):
    for rep in range(3):
        sgn = 1.0 if random.random() < 0.72 else -1.0          # most of the mane falls to one side
        length = random.uniform(0.55, 0.95) * (0.75 if top.y < -2.5 else 1.0)
        down = Vector((sgn * 0.62, 0.18, -1.0)).normalized()
        root = top + Vector((random.uniform(-0.04, 0.04), random.uniform(-0.04, 0.04), 0.02))
        pts = [root + down * length * (j / 5.0) + Vector((sgn * 0.10 * math.sin(j / 5.0 * 1.6), 0, 0)) for j in range(6)]
        card(pts, random.uniform(0.13, 0.19), Vector((0, 1, 0)), 0.025)
# forelock: from the poll between the ears, forward/down over the forehead
poll = max((p for p in mane if p.y < -2.55), key=lambda p: p.z, default=None)
if poll is not None:
    for k in range(7):
        root = poll + Vector((random.uniform(-0.08, 0.08), random.uniform(-0.05, 0.05), 0.0))
        d = Vector((random.uniform(-0.15, 0.15), -0.75, -0.66)).normalized()
        pts = [root + d * 0.42 * (j / 4.0) for j in range(5)]
        card(pts, 0.12, Vector((1, 0, 0)), 0.02)
# tail: follow the tail bone chain, spreading toward the tip
chain = [arm.matrix_world @ arm.data.bones[b].head_local for b in ("Tail2", "Tail3", "Tail4", "Tail5", "Tail6", "Tail7")]
chain.append(chain[-1] + Vector((0.0, 0.06, -0.45)))
for k in range(34):
    ang = random.uniform(0, 6.28); r0 = random.uniform(0.0, 0.07); spread = random.uniform(0.10, 0.26)
    off = Vector((math.cos(ang), 0.0, math.sin(ang) * 0.4)); off.y = math.sin(ang) * 0.6
    pts = []
    for j, c in enumerate(chain):
        t = j / (len(chain) - 1)
        pts.append(c + off * (r0 + spread * t * t) + Vector((0, 0.05 * t, -0.08 * t)))
    side = Vector((-math.sin(ang), math.cos(ang), 0.0)).normalized()
    card(pts, random.uniform(0.14, 0.2), side, 0.0, False)
hm = bpy.data.meshes.new("HorseHair"); bmh.to_mesh(hm); bmh.free()
hair = bpy.data.objects.new("HorseHair", hm); col.objects.link(hair)
hm.materials.append(hair_m)
for p in hm.polygons: p.use_smooth = True
# weights from the original mane/tail
activate(hair)
dt = hair.modifiers.new("DT", 'DATA_TRANSFER'); dt.object = src
dt.use_vert_data = True; dt.data_types_verts = {'VGROUP_WEIGHTS'}; dt.vert_mapping = 'POLYINTERP_NEAREST'
bpy.ops.object.datalayout_transfer(modifier="DT")
bpy.ops.object.modifier_apply(modifier="DT")
bpy.ops.object.vertex_group_limit_total(limit=4)
bpy.ops.object.vertex_group_normalize_all(lock_active=False)
hair.parent = arm
am = hair.modifiers.new("Armature", 'ARMATURE'); am.object = arm
bpy.data.objects.remove(src, do_unlink=True)
arm.data.pose_position = 'POSE'
print("CARDS", len(hm.polygons), "BODY_TRIS", sum(len(p.vertices) - 2 for p in body.data.polygons))
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_animations=True, export_animation_mode='ACTIONS',
                          export_skins=True, export_image_format='AUTO', export_materials='EXPORT', export_apply=False)
print("EXPORTED", OUT)
