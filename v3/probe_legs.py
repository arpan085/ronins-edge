import bpy, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, "/data/ronins_edge/v2")
from mathutils import Vector, Euler, Matrix
from math import radians as D
import rig as RIG, clips as C, anim_core as AC

for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)
bpy.context.scene.render.fps = 30; bpy.context.scene.render.fps_base = 1.0
arm = RIG.make_rig("Probe")
if isinstance(arm, tuple): arm = arm[0]
bpy.context.view_layer.update()
hb = arm.pose.bones["hips"].bone
print("HIPS matrix_local 3x3 (cols = bone X,Y,Z in armature space):")
m = hb.matrix_local.to_3x3()
for r in range(3): print("   %7.4f %7.4f %7.4f" % (m[r][0], m[r][1], m[r][2]))
tb = arm.pose.bones["thigh.L"].bone.matrix_local.to_3x3()
print("THIGH.L:")
for r in range(3): print("   %7.4f %7.4f %7.4f" % (tb[r][0], tb[r][1], tb[r][2]))

def write(arm, name, track):
    if arm.animation_data is None: arm.animation_data_create()
    act = bpy.data.actions.new(name); act.use_fake_user = True
    arm.animation_data.action = act
    for f, p in track:
        for pb in arm.pose.bones:
            r = p.get(pb.name, (0,0,0))
            pb.rotation_euler = Euler([D(r[0]), D(r[1]), D(r[2])], 'XYZ')
            pb.keyframe_insert("rotation_euler", frame=f)
        rb = arm.pose.bones.get("root")
        rb.location = Vector(p.get(AC.ROOT, (0,0,0)))
        rb.keyframe_insert("location", frame=f)
    for fc in act.fcurves:
        for kp in fc.keyframe_points: kp.interpolation = 'LINEAR'
    return act

def probe(label, poser, n=24):
    tr = [(i, poser(i / float(n))) for i in range(n + 1)]
    a = write(arm, "__p_" + label, tr)
    out = {"L": [], "R": []}
    for i in range(n):
        bpy.context.scene.frame_set(i); bpy.context.view_layer.update()
        for s in ("L", "R"):
            w = arm.matrix_world @ arm.pose.bones["foot." + s].head
            out[s].append((w.x, w.y, w.z))
    bpy.data.actions.remove(a)
    print("== %s" % label)
    for s in ("L", "R"):
        zs = [p[2] for p in out[s]]
        thr = min(zs) + max(0.006, (max(zs) - min(zs)) * 0.30)
        idx = [i for i in range(n) if zs[i] <= thr]
        xs = [out[s][i][0] for i in idx]
        print("   %s stance %d frames  ankle.x span %.4f (%.4f..%.4f) target %.3f" % (
            s, len(idx), max(xs) - min(xs), min(xs), max(xs), 0.104 * (1 if s == "R" else -1)))
        steps = [abs(out[s][idx[k+1]][0] - out[s][idx[k]][0]) for k in range(len(idx)-1)
                 if idx[k+1] == idx[k] + 1]
        if steps: print("      max lateral step/frame %.4f m" % max(steps))
        print("      ankle.z %.4f..%.4f (rest 0.098) clearance %.4f" % (
            min(zs), max(zs), max(zs) - 0.098))

g = C.gait_params("jog")
probe("jog", lambda t: C.gait_pose(t, g))
probe("walk", lambda t: C.gait_pose(t, C.gait_params("walk")))
probe("sprint", lambda t: C.gait_pose(t, C.gait_params("sprint")))
probe("back", lambda t: C.back_pose(t, C.gait_params("jog")))
probe("strafeR", lambda t: C.strafe_pose(t, C.gait_params("jog"), 1))
print("PROBE_DONE")
