"""Find stretched triangles in posed character GLBs.

    blender -b --python tools/stretch.py -- <glb> Clip@sec [Clip@sec ...] [--min=0.30]
    blender -b --python tools/stretch.py -- <glb> --all [--min=0.15]

Imports the shipped GLB, poses it at each clip@seconds, and counts the edges
whose posed length is both over --min metres and more than 3x the rest length.
A sheet of cloth reaching from a shoulder to an ankle shows up as a few very
long edges; the rest height and dominant bones at each end say which part of
which mesh is being dragged, so the culprit is a number instead of a guess from
a render.

--all poses every clip in the file at 25%, 55% and 85% of its length (about
100-180 poses per character) and ends with one STRETCH_TOTAL line. A clean build
prints STRETCH_TOTAL 0; the build before the v0.11 trouser fix printed 7,036 for
Kaito at --min=0.15.
"""
import sys, bpy

argv = sys.argv[sys.argv.index("--") + 1:]
glb = argv[0]
specs = [a for a in argv[1:] if "@" in a]
do_all = "--all" in argv[1:]
min_len = 0.30
for a in argv[1:]:
    if a.startswith("--min="): min_len = float(a.split("=")[1])

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
if arm.animation_data is None:
    arm.animation_data_create()
sc = bpy.context.scene

# The glTF importer puts keys on the scene's frame rate (24 by default), not on
# the clips' authored 30, so seconds are converted with the scene rate.
fps = float(sc.render.fps) / float(sc.render.fps_base)

if do_all:
    for a in sorted(bpy.data.actions, key=lambda a: a.name):
        clip = a.name.split("_Rig")[0]
        length = (a.frame_range[1] - a.frame_range[0]) / fps
        specs += ["%s@%.3f" % (clip, length * f) for f in (0.25, 0.55, 0.85)]

def find_action(clip):
    return next((a for a in bpy.data.actions
                 if a.name == clip or a.name.startswith(clip + "_Rig") or a.name.endswith("|" + clip)), None)

total = 0
for spec in specs:
    clip, secs = spec.split("@")
    act = find_action(clip)
    if act is None:
        print("NO ACTION", clip); continue
    arm.animation_data.action = act
    fr = float(secs) * fps
    sc.frame_set(int(fr), subframe=fr - int(fr))
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    rows = []
    for ob in bpy.data.objects:
        if ob.type != 'MESH':
            continue
        rest = [ob.matrix_world @ v.co for v in ob.data.vertices]
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        pos = [ev.matrix_world @ v.co for v in me.vertices]
        if len(pos) != len(rest):
            print("vertex count differs", ob.name, len(pos), len(rest)); continue
        vg = {g.index: g.name for g in ob.vertex_groups}
        seen = set()
        for p in ob.data.polygons:
            mat = ob.material_slots[p.material_index].name if ob.material_slots else "?"
            vs = list(p.vertices)
            for i in range(len(vs)):
                a, b = vs[i], vs[(i + 1) % len(vs)]
                key = (min(a, b), max(a, b))
                if key in seen: continue
                seen.add(key)
                L = (pos[a] - pos[b]).length
                L0 = (rest[a] - rest[b]).length
                if L > min_len and L > 3.0 * max(L0, 1e-4):
                    def top(i):
                        ws = sorted(((g.weight, vg[g.group]) for g in ob.data.vertices[i].groups), reverse=True)[:2]
                        return ",".join("%s:%.2f" % (n, w) for w, n in ws)
                    rows.append((L, mat, rest[a].z, rest[b].z, top(a), top(b)))
        ev.to_mesh_clear()
    rows.sort(reverse=True)
    total += len(rows)
    line = "%-16s edges=%3d" % (spec, len(rows))
    if rows:
        line += "  longest=%.2f m (%s, rest z %.2f->%.2f, %s | %s)" % (
            rows[0][0], rows[0][1], rows[0][2], rows[0][3], rows[0][4], rows[0][5])
    print("STRETCH " + line)
print("STRETCH_TOTAL %d" % total)
