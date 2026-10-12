"""v0.15: convert the CC0 / CC-BY animal sources to game-ready GLB.

Run with Blender 4.2:
  blender -b <src.blend> --python tools/animals/convert_animals.py -- <name> <out.glb>
  blender -b --python tools/animals/convert_animals.py -- wolf <out.glb> <loup.fbx>

Each source rig drives its legs with IK; the exporter samples the evaluated
pose every frame, so the GLB carries plain FK curves for the deform bones only.
Actions are renamed to the game's clip names (idle / walk / run / eat / look /
attack / hit / die) and pushed onto NLA tracks so each exports as its own
animation. Materials are rebuilt as Principled BSDF with the original
diffuse maps (the 2.7x files still use Blender-Internal texture slots).
"""
import bpy, sys, os

args = sys.argv[sys.argv.index("--") + 1:]
NAME, OUT = args[0], args[1]
SRC_DIR = os.path.dirname(bpy.data.filepath) if bpy.data.filepath else os.path.dirname(args[2])

CFG = {
    "doe": {
        "keep": ["Armature", "Body", "Eyes", "Head"],
        "mats": {"Body": "doe-body", "Head": "doe-head", "Eyes": (0.03, 0.025, 0.02)},
        "actions": {"Idle.000": "idle", "LookAround.000": "look", "Eat.001": "eat", "Run": "run", "Die.000": "die"},
        "def_bones": True,
    },
    "stag": {
        "keep": ["Armature", "Body", "Eyes", "Head", "Horns"],
        "mats": {"Body": "body", "Head": "head", "Horns": "deer-antlers.png", "Eyes": (0.03, 0.025, 0.02)},
        "actions": {"Idle.000": "idle", "LookAround.000": "look", "Eat.001": "eat", "Run": "run", "Die.000": "die"},
        "def_bones": True,
    },
    "fox": {
        "keep": ["Fox_Armature", "Fox"],
        "mats": {"Fox": "file:fox_diffuse.png"},
        "actions": {"IDLE": "idle", "WALK": "walk", "RUN": "run", "BITE": "attack", "DIGGING": "eat", "DEATH": "die"},
        "def_bones": True,
    },
    "boar": {
        "keep": ["boar_armature", "boar_mesh.000"],
        "mats": {"boar_mesh.000": "boar"},
        "actions": {"walk": "walk", "attack": "attack", "default": "idle"},
        "def_bones": False,
    },
    "wolf": {
        "fbx": True,
        "keep": ["Armature", "Forest Wolf"],
        "mats": {},
        "actions": {"Armature|idle|Baked frames": "idle", "Armature|run|Baked frames": "run",
                    "Armature|ATK1|Baked frames": "attack", "Armature|ATK2|Baked frames": "attack2",
                    "Armature|hit|Baked frames": "hit", "Armature|death|Baked frames": "die"},
        "def_bones": False,
    },
}
cfg = CFG[NAME]

if cfg.get("fbx"):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=args[2])

# ---- prune the scene to the rig and its meshes
for o in list(bpy.data.objects):
    if o.name not in cfg["keep"]:
        bpy.data.objects.remove(o, do_unlink=True)
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]

# ---- materials
def image_by_name(n):
    if n.startswith("file:"):
        p = os.path.join(SRC_DIR, n[5:])
        return bpy.data.images.load(p)
    for im in bpy.data.images:
        if im.name == n:
            return im
    raise RuntimeError("no image " + n)

for oname, src in cfg["mats"].items():
    o = bpy.data.objects[oname]
    m = bpy.data.materials.new(NAME + "_" + oname)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.85
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.25
    if isinstance(src, tuple):
        bsdf.inputs["Base Color"].default_value = (src[0], src[1], src[2], 1.0)
        bsdf.inputs["Roughness"].default_value = 0.25
    else:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = image_by_name(src)
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    o.data.materials.clear()
    o.data.materials.append(m)
    for p in o.data.polygons:
        p.material_index = 0

# ---- actions -> NLA tracks, renamed to clip names
ad = arm.animation_data or arm.animation_data_create()
for tr in list(ad.nla_tracks):
    ad.nla_tracks.remove(tr)
ad.action = None
keep_actions = set()
for src_name, dst in cfg["actions"].items():
    a = bpy.data.actions.get(src_name)
    if a is None:
        print("MISSING ACTION", src_name)
        continue
    a.name = dst
    keep_actions.add(dst)
    tr = ad.nla_tracks.new()
    tr.name = dst
    st = tr.strips.new(dst, int(a.frame_range[0]), a)
    tr.mute = True
for a in list(bpy.data.actions):
    if a.name not in keep_actions:
        bpy.data.actions.remove(a)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=OUT, export_format="GLB", use_selection=False, export_apply=True,
    export_animations=True, export_animation_mode="ACTIONS", export_nla_strips=True,
    export_force_sampling=True, export_frame_step=1, export_def_bones=cfg["def_bones"],
    export_yup=True, export_image_format="JPEG", export_jpeg_quality=88,
    export_lights=False, export_cameras=False, export_skins=True, export_morph=False)
print("EXPORTED", OUT, os.path.getsize(OUT))
