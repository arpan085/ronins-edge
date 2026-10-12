extends SceneTree
## Retargets CC0 KayKit Character Animations (Rig_Medium, 23 bones, T-pose) onto
## the Ronin skeleton (65 bones, T-pose) and adds them to ronin_anims.res with a
## "K_" prefix.   Run after tools/bake_anims.gd:
##   godot --headless --path game -s tools/bake_kaykit.gd
##
## Method: both rigs face +Z and rest in a T-pose, so every mapped bone copies the
## source bone's *world-space rotation change from rest*:
##     R_t(bone, t) = R_s(src, t) * R_s_rest(src)^-1 * R_t_rest(bone)
## then converts back to parent-local rotations.  Bones the small rig lacks keep
## their rest rotation (spine_02, neck, clavicles) or copy a still hand shape from
## a Universal Animation Library clip (fingers: fist / sword grip / relaxed).
## The pelvis follows the hip-joint midpoint, scaled by the leg-length ratio.

const SRC := "/data/ronins_edge/v4/src/kaykit/Rig_Medium/Rig_Medium_%s.glb"
const LIB := "res://assets/anim/ronin_anims.res"
const FPS := 30.0

# out name: [pack, source clip, loop, left hand, right hand]
const CLIPS := {
	"K_Kick": ["CombatMelee", "Melee_Unarmed_Attack_Kick", false, "fist", "fist"],
	"K_Punch": ["CombatMelee", "Melee_Unarmed_Attack_Punch_A", false, "fist", "fist"],
	"K_Unarmed_Idle": ["CombatMelee", "Melee_Unarmed_Idle", true, "fist", "fist"],
	"K_1H_Chop": ["CombatMelee", "Melee_1H_Attack_Chop", false, "relax", "grip"],
	"K_1H_JumpChop": ["CombatMelee", "Melee_1H_Attack_Jump_Chop", false, "relax", "grip"],
	"K_1H_Diag": ["CombatMelee", "Melee_1H_Attack_Slice_Diagonal", false, "relax", "grip"],
	"K_1H_Horiz": ["CombatMelee", "Melee_1H_Attack_Slice_Horizontal", false, "relax", "grip"],
	"K_1H_Stab": ["CombatMelee", "Melee_1H_Attack_Stab", false, "relax", "grip"],
	"K_2H_Chop": ["CombatMelee", "Melee_2H_Attack_Chop", false, "fist", "grip"],
	"K_2H_Slice": ["CombatMelee", "Melee_2H_Attack_Slice", false, "fist", "grip"],
	"K_2H_Spin": ["CombatMelee", "Melee_2H_Attack_Spin", false, "fist", "grip"],
	"K_2H_Spinning": ["CombatMelee", "Melee_2H_Attack_Spinning", true, "fist", "grip"],
	"K_2H_Stab": ["CombatMelee", "Melee_2H_Attack_Stab", false, "fist", "grip"],
	"K_2H_Idle": ["CombatMelee", "Melee_2H_Idle", true, "fist", "grip"],
	"K_Block": ["CombatMelee", "Melee_Block", false, "relax", "grip"],
	"K_Blocking": ["CombatMelee", "Melee_Blocking", true, "relax", "grip"],
	"K_Block_Hit": ["CombatMelee", "Melee_Block_Hit", false, "relax", "grip"],
	"K_Block_Attack": ["CombatMelee", "Melee_Block_Attack", false, "relax", "grip"],
	"K_Dodge_B": ["MovementAdvanced", "Dodge_Backward", false, "relax", "grip"],
	"K_Dodge_F": ["MovementAdvanced", "Dodge_Forward", false, "relax", "grip"],
	"K_Dodge_L": ["MovementAdvanced", "Dodge_Left", false, "relax", "grip"],
	"K_Dodge_R": ["MovementAdvanced", "Dodge_Right", false, "relax", "grip"],
	"K_Strafe_L": ["MovementAdvanced", "Running_Strafe_Left", true, "relax", "grip"],
	"K_Strafe_R": ["MovementAdvanced", "Running_Strafe_Right", true, "relax", "grip"],
	"K_Walk_Back": ["MovementAdvanced", "Walking_Backwards", true, "relax", "grip"],
	"K_Sneak": ["MovementAdvanced", "Sneaking", true, "relax", "relax"],
	"K_Crouch": ["MovementAdvanced", "Crouching", true, "relax", "relax"],
	"K_Hit_A": ["General", "Hit_A", false, "relax", "grip"],
	"K_Hit_B": ["General", "Hit_B", false, "relax", "grip"],
	"K_Death_A": ["General", "Death_A", false, "relax", "relax"],
	"K_Death_B": ["General", "Death_B", false, "relax", "relax"],
	"K_Interact": ["General", "Interact", false, "relax", "relax"],
	"K_PickUp": ["General", "PickUp", false, "relax", "relax"],
	"K_Throw": ["General", "Throw", false, "relax", "fist"],
	"K_Sit_Chair": ["Simulation", "Sit_Chair_Idle", true, "relax", "relax"],
	"K_Sit_Floor": ["Simulation", "Sit_Floor_Idle", true, "relax", "relax"],
}
## Horizontal hip motion: "osc" removes the net drift (movement comes from code) and
## keeps the sway at 1:1, "inplace" removes it all, "keep" scales it with the legs.
const MODE := {"K_Dodge_B": "inplace", "K_Dodge_F": "inplace", "K_Dodge_L": "inplace",
	"K_Dodge_R": "inplace", "K_Strafe_L": "inplace", "K_Strafe_R": "inplace",
	"K_Walk_Back": "inplace", "K_Sneak": "inplace", "K_Crouch": "inplace",
	"K_Death_A": "keep", "K_Death_B": "keep"}
const MAP := {"hips": "pelvis", "spine": "spine_01", "chest": "spine_03", "head": "Head",
	"upperarm.l": "upperarm_l", "lowerarm.l": "lowerarm_l", "hand.l": "hand_l",
	"upperarm.r": "upperarm_r", "lowerarm.r": "lowerarm_r", "hand.r": "hand_r",
	"upperleg.l": "thigh_l", "lowerleg.l": "calf_l", "foot.l": "foot_l", "toes.l": "ball_l",
	"upperleg.r": "thigh_r", "lowerleg.r": "calf_r", "foot.r": "foot_r", "toes.r": "ball_r"}
const FINGERS := ["index", "middle", "ring", "pinky", "thumb"]

var lib: AnimationLibrary
var tsk: Skeleton3D
var t_order: Array = []
var t_rest: Array = []       # local rest
var t_grest: Array = []      # global rest
var hands := {}              # "fist"/"grip"/"relax" -> {bone_index: Quaternion} for both sides

func _init() -> void:
	lib = load(LIB)
	if lib == null: push_error("no library"); quit(1); return
	var ron := _load_abs("/data/ronins_edge/game/assets/char/Ronin.glb")
	tsk = ron.find_children("*", "Skeleton3D", true, false)[0]
	t_order = _order(tsk)
	for b in tsk.get_bone_count():
		t_rest.append(tsk.get_bone_rest(b)); t_grest.append(tsk.get_bone_global_rest(b))
	_hand_shapes()
	var packs := {}
	var added := 0
	for out in CLIPS:
		var d: Array = CLIPS[out]
		if not packs.has(d[0]):
			var scn := _load_abs(SRC % d[0])
			packs[d[0]] = scn
		var scn: Node = packs[d[0]]
		var ap: AnimationPlayer = scn.find_children("*", "AnimationPlayer", true, false)[0]
		var ssk: Skeleton3D = scn.find_children("*", "Skeleton3D", true, false)[0]
		if not ap.has_animation(d[1]):
			print("MISSING ", d[1], " in ", d[0], ": ", ap.get_animation_list()); continue
		var a := _retarget(ssk, ap.get_animation(d[1]), d[2], d[3], d[4], MODE.get(out, "osc"))
		if lib.has_animation(out): lib.remove_animation(out)
		lib.add_animation(out, a)
		added += 1
		print("%s <- %s  %.2fs" % [out, d[1], a.length])
	var err := ResourceSaver.save(lib, LIB)
	print("added ", added, " clips; library now ", lib.get_animation_list().size(), " saved err=", err)
	for k in packs: packs[k].free()
	ron.free()
	quit()

func _order(sk: Skeleton3D) -> Array:
	var done := {}; var out := []
	while out.size() < sk.get_bone_count():
		for b in sk.get_bone_count():
			if done.has(b): continue
			var p := sk.get_bone_parent(b)
			if p < 0 or done.has(p):
				done[b] = true; out.append(b)
	return out

## Still finger poses sampled from UAL clips on the Ronin rig.
func _hand_shapes() -> void:
	var src := {"fist": ["Punch_Jab", 0.15], "grip": ["Sword_Idle", 0.3], "relax": ["Idle", 0.5]}
	for k in src:
		var a: Animation = lib.get_animation(src[k][0])
		var m := {}
		for b in tsk.get_bone_count():
			var bn := tsk.get_bone_name(b)
			var is_f := false
			for f in FINGERS:
				if bn.begins_with(f + "_"): is_f = true
			if not is_f: continue
			var ti := a.find_track(NodePath("Skeleton3D:" + bn), Animation.TYPE_ROTATION_3D)
			m[b] = a.rotation_track_interpolate(ti, src[k][1]) if ti >= 0 else t_rest[b].basis.get_rotation_quaternion()
		hands[k] = m

func _src_world(sk: Skeleton3D, order: Array, a: Animation, tracks: Dictionary, t: float) -> Array:
	var n := sk.get_bone_count()
	var w := []; w.resize(n)
	for b in order:
		var rest := sk.get_bone_rest(b)
		var p := rest.origin
		var q := rest.basis.get_rotation_quaternion()
		var s := rest.basis.get_scale()
		if a != null and tracks.has(b):
			var tr: Dictionary = tracks[b]
			if tr.has("p"): p = a.position_track_interpolate(tr["p"], t)
			if tr.has("r"): q = a.rotation_track_interpolate(tr["r"], t)
			if tr.has("s"): s = a.scale_track_interpolate(tr["s"], t)
		var l := Transform3D(Basis(q) * Basis.from_scale(s), p)
		var par := sk.get_bone_parent(b)
		w[b] = l if par < 0 else (w[par] as Transform3D) * l
	return w

func _retarget(ssk: Skeleton3D, src: Animation, loop: bool, lh: String, rh: String, mode: String) -> Animation:
	var s_order := _order(ssk)
	var tracks := {}
	for i in src.get_track_count():
		var p := String(src.track_get_path(i))
		var bn := p.substr(p.rfind(":") + 1)
		var b := ssk.find_bone(bn)
		if b < 0: continue
		if not tracks.has(b): tracks[b] = {}
		match src.track_get_type(i):
			Animation.TYPE_POSITION_3D: tracks[b]["p"] = i
			Animation.TYPE_ROTATION_3D: tracks[b]["r"] = i
			Animation.TYPE_SCALE_3D: tracks[b]["s"] = i
	var s_rest := _src_world(ssk, s_order, null, {}, 0.0)
	# mapping target bone -> source bone
	var map := {}
	for sn in MAP:
		var sb := ssk.find_bone(sn); var tb := tsk.find_bone(MAP[sn])
		if sb >= 0 and tb >= 0: map[tb] = sb
	var pel := tsk.find_bone("pelvis")
	var s_ul := ssk.find_bone("upperleg.l"); var s_ur := ssk.find_bone("upperleg.r")
	var t_tl := tsk.find_bone("thigh_l"); var t_tr := tsk.find_bone("thigh_r")
	var s_mid0: Vector3 = ((s_rest[s_ul] as Transform3D).origin + (s_rest[s_ur] as Transform3D).origin) * 0.5
	var t_mid0: Vector3 = ((t_grest[t_tl] as Transform3D).origin + (t_grest[t_tr] as Transform3D).origin) * 0.5
	var ratio := t_mid0.y / maxf(0.01, s_mid0.y)
	var pel_off: Vector3 = (t_grest[pel] as Transform3D).basis.inverse() * (t_mid0 - (t_grest[pel] as Transform3D).origin)
	var w0 := _src_world(ssk, s_order, src, tracks, 0.0)
	var w1 := _src_world(ssk, s_order, src, tracks, src.length)
	var m_a: Vector3 = ((w0[s_ul] as Transform3D).origin + (w0[s_ur] as Transform3D).origin) * 0.5
	var m_b: Vector3 = ((w1[s_ul] as Transform3D).origin + (w1[s_ur] as Transform3D).origin) * 0.5
	var out := Animation.new()
	out.length = src.length
	out.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var rtrack := {}
	for b in tsk.get_bone_count():
		var ti := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(ti, NodePath("Skeleton3D:" + tsk.get_bone_name(b)))
		rtrack[b] = ti
	var ptrack := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(ptrack, NodePath("Skeleton3D:pelvis"))
	var shape := {}
	for b in hands[lh]:
		if tsk.get_bone_name(b).ends_with("_l"): shape[b] = hands[lh][b]
	for b in hands[rh]:
		if tsk.get_bone_name(b).ends_with("_r"): shape[b] = hands[rh][b]
	var nf := int(ceil(src.length * FPS - 0.001))
	for f in nf + 1:
		var t := minf(f / FPS, src.length)
		var sw := _src_world(ssk, s_order, src, tracks, t)
		var tw := []; tw.resize(tsk.get_bone_count())
		for b in t_order:
			var par := tsk.get_bone_parent(b)
			var parw: Transform3D = Transform3D.IDENTITY if par < 0 else tw[par]
			var local: Transform3D = t_rest[b]
			if map.has(b):
				var sb: int = map[b]
				var rw: Basis = ((sw[sb] as Transform3D).basis.orthonormalized() * (s_rest[sb] as Transform3D).basis.orthonormalized().inverse()) * (t_grest[b] as Transform3D).basis.orthonormalized()
				local = Transform3D(parw.basis.orthonormalized().inverse() * rw, local.origin)
			elif shape.has(b):
				local = Transform3D(Basis(shape[b] as Quaternion), local.origin)
			if b == pel:
				var smid: Vector3 = ((sw[s_ul] as Transform3D).origin + (sw[s_ur] as Transform3D).origin) * 0.5
				var dv := smid - s_mid0
				var hz := Vector3(dv.x, 0.0, dv.z)
				match mode:
					"inplace": hz = Vector3.ZERO
					"osc":
						var dr := m_a.lerp(m_b, t / maxf(0.001, src.length)) - s_mid0
						hz -= Vector3(dr.x, 0.0, dr.z)
					_: hz *= ratio
				var tmid := t_mid0 + Vector3(hz.x, dv.y * ratio, hz.z)
				var wb := parw.basis * local.basis
				var wp := tmid - wb * pel_off
				local.origin = parw.affine_inverse() * wp
				out.position_track_insert_key(ptrack, t, local.origin)
			tw[b] = parw * local
			out.rotation_track_insert_key(rtrack[b], t, local.basis.get_rotation_quaternion())
	return out

func _load_abs(path: String) -> Node:
	var st := GLTFState.new(); var doc := GLTFDocument.new()
	var e := doc.append_from_file(path, st)
	if e != OK: push_error("cannot load " + path); quit(1)
	return doc.generate_scene(st)
