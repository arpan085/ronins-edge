class_name GroundFix
extends RefCounted
## v0.22: puts the feet back on the ground.
## tools/bake_anims.gd (v0.15) scaled the Universal Animation Library pelvis
## tracks by the ratio of the two rigs' pelvis rest heights, but read that
## height from the bone's local Y. The UBC root bone is turned -90 deg about X,
## so local Y is the pelvis' 4 cm front/back offset, not its height, and the
## ratio came out 0.816 instead of 1.0: every UAL clip (idle, walk, run, sword
## cuts, hits, interactions) held the body 17 cm low with the feet sunk into
## the ground to the ankles, and switching to a KayKit clip (K_*, baked
## separately and correct) popped the body up and down.
## This undoes the error on the vertical axis only, so the horizontal pelvis
## motion (dash and roll distances) is unchanged. Once per loaded library.
const SCALE := 1.226         ## 1 / 0.8157, measured by tests/GroundClips.tscn
const SKIP_PREFIX := ["K_", "Swim_", "A_TPose"]
const SKIP := ["Driving"]    ## the rider's seat on the horse is fitted to this clip
## clips whose lowest contact needs a different factor (deep knee bend)
const CLIP_SCALE := {"Crouch_Idle": 1.174, "Crouch_Fwd": 1.174, "Push": 1.175,
	"Idle_Rail": 1.189, "Idle_Rail_Call": 1.189}

static var enabled := true    ## tests/EnemyLab --nofix 1 shows the old sunk pose

static func apply(lib: AnimationLibrary, sk: Skeleton3D) -> int:
	if not enabled or lib == null or sk == null or lib.has_meta("ground_fix"): return 0
	var pv := sk.find_bone("pelvis")
	if pv < 0: return 0
	lib.set_meta("ground_fix", SCALE)
	var par := sk.get_bone_parent(pv)
	var up := Vector3.UP
	if par >= 0: up = (sk.get_bone_global_rest(par).basis.inverse() * Vector3.UP).normalized()
	var n := 0
	for c in lib.get_animation_list():
		var name := String(c)
		if name in SKIP: continue
		var skip := false
		for p in SKIP_PREFIX:
			if name.begins_with(p): skip = true
		if skip: continue
		var a := lib.get_animation(c)
		var f: float = CLIP_SCALE.get(name, SCALE)
		for i in a.get_track_count():
			if a.track_get_type(i) != Animation.TYPE_POSITION_3D: continue
			if not String(a.track_get_path(i)).ends_with(":pelvis"): continue
			for k in a.track_get_key_count(i):
				var v: Vector3 = a.track_get_key_value(i, k)
				a.track_set_key_value(i, k, v + up * (v.dot(up) * (f - 1.0)))
			n += 1
	return n
