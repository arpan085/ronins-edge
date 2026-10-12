class_name Anatomy
extends SkeletonModifier3D
## v0.18: joints that move the way a body does. A game skeleton has 65 bones,
## not 206, so this makes the ones it has follow real anatomy:
## * Scapulohumeral rhythm. Past ~30 deg of elevation the shoulder girdle
##   rotates with the arm, about 1 deg for every 2 deg at the shoulder joint
##   (Inman et al. 1944), so a raised arm lifts the shoulder instead of hinging
##   out of a fixed socket. The arm keeps the direction the clip gave it; only
##   the split between clavicle and humerus changes.
## * Breathing. The ribcage lifts the sternum ~14 times a minute at rest; after
##   exertion up to ~40 a minute at three times the depth, with the shoulders
##   joining in, recovering as `exertion` decays. The neck counters the chest so
##   the head stays steady.
## * Hands. A relaxed hand is never flat: flexion increases from the index to
##   the little finger (the "finger cascade"). `grip_l` / `grip_r` close a hand
##   around a scabbard or a hilt.

var exertion := 0.0          ## 0 rested .. 1 out of breath
var grip_l := 0.0            ## 0 relaxed .. 1 closed around something
var grip_r := 0.0
var rhythm := 0.6            ## share of the classic 1:2 scapular rhythm applied
var breath_scale := 1.0
## which way the fingers curl, per hand (+1 / -1 flips the palm side)
var palm_sign := {"l": -1.0, "r": 1.0}

var _phase := 0.0
var exhales := 0             ## v0.21: counts exhales, BreathFX puffs on each one
var _ix := {}
var _ok := false
const FINGERS := ["index", "middle", "ring", "pinky"]
## relaxed flexion per finger (deg) and per joint weight (MCP, PIP, DIP)
const CASCADE := {"index": 6.0, "middle": 10.0, "ring": 14.0, "pinky": 18.0}
const JOINT_W := [0.8, 1.3, 0.7]
const GRIP := [62.0, 88.0, 48.0]

func _cache(sk: Skeleton3D) -> void:
	for n in ["spine_03", "neck_01", "Head", "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
			"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"]:
		_ix[n] = sk.find_bone(n)
	for s in ["l", "r"]:
		for f in FINGERS + ["thumb"]:
			for j in range(1, 5):
				var nm := "%s_%02d_%s" % [f, j, s] if j < 4 else "%s_04_leaf_%s" % [f, s]
				_ix[nm] = sk.find_bone(nm)
	_ok = true
	for k in ["spine_03", "neck_01", "clavicle_l", "upperarm_l", "lowerarm_l", "clavicle_r", "upperarm_r", "lowerarm_r"]:
		if int(_ix[k]) < 0: _ok = false

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null: return
	if _ix.is_empty(): _cache(sk)
	if not _ok: return
	var dt := clampf(get_process_delta_time(), 0.0, 0.1)
	var chest: int = _ix["spine_03"]
	var neck: int = _ix["neck_01"]
	var right := (_gp(sk, _ix["upperarm_r"]).origin - _gp(sk, _ix["upperarm_l"]).origin).normalized()
	var up := (_gp(sk, neck).origin - _gp(sk, chest).origin).normalized()
	# ---- breathing
	var rate := lerpf(14.0, 40.0, exertion) / 60.0
	var pp := _phase
	_phase = fmod(_phase + dt * TAU * rate, TAU)
	if pp < PI and _phase >= PI: exhales += 1
	var inhale := 0.5 - 0.5 * cos(_phase)
	var depth := lerpf(1.0, 3.0, exertion) * breath_scale
	var a := deg_to_rad(1.1) * depth * inhale
	if a > 0.0001:
		_rotate_global(sk, chest, right, a)
		_rotate_global(sk, neck, right, -a * 0.85)
	# ---- shoulders: scapulohumeral rhythm (+ shoulders rising with deep breaths)
	for s in ["l", "r"]:
		var c: int = _ix["clavicle_" + s]
		var u: int = _ix["upperarm_" + s]
		var lo: int = _ix["lowerarm_" + s]
		var sh := _gp(sk, u).origin
		var arm := (_gp(sk, lo).origin - sh).normalized()
		var elev := acos(clampf(arm.dot(-up), -1.0, 1.0))
		var st := maxf(0.0, elev - deg_to_rad(30.0)) / 3.0 * rhythm
		st = minf(st, deg_to_rad(22.0))
		var axis := (-up).cross(arm)
		var bu := _gp(sk, u).basis
		if axis.length() > 0.05 and st > 0.0005:
			_rotate_global(sk, c, axis.normalized(), st)
		# shrug a little on a deep inhale (accessory breathing muscles)
		var shrug := deg_to_rad(1.6) * exertion * inhale
		if shrug > 0.0005:
			var out := (sh - _gp(sk, c).origin).normalized()
			var ax2 := out.cross(up)
			if ax2.length() > 0.05: _rotate_global(sk, c, ax2.normalized(), -shrug)
		# keep the humerus pointing where the clip pointed it
		_set_global_basis(sk, u, bu)
	# ---- hands
	for s in ["l", "r"]:
		var g := grip_l if s == "l" else grip_r
		_hand(sk, s, g)

## relaxed cascade blended toward a closed grip, about each joint's own curl axis
func _hand(sk: Skeleton3D, s: String, g: float) -> void:
	var hand: int = _ix["hand_" + s]
	if hand < 0: return
	var hb := _gp(sk, hand)
	var i1: int = _ix["index_01_" + s]
	var p1: int = _ix["pinky_01_" + s]
	if i1 < 0 or p1 < 0: return
	var palm := ((_gp(sk, i1).origin - hb.origin).cross(_gp(sk, p1).origin - hb.origin)).normalized() * float(palm_sign[s])
	for f in FINGERS:
		for j in 3:
			var b: int = _ix["%s_%02d_%s" % [f, j + 1, s]]
			var nb_name := "%s_%02d_%s" % [f, j + 2, s] if j < 2 else "%s_04_leaf_%s" % [f, s]
			var ch: int = _ix[nb_name]
			if b < 0 or ch < 0: continue
			var d := (_gp(sk, ch).origin - _gp(sk, b).origin).normalized()
			var ax := d.cross(palm)
			if ax.length() < 0.05: continue
			var ang := deg_to_rad(lerpf(float(CASCADE[f]) * JOINT_W[j], GRIP[j], g))
			_rotate_global(sk, b, ax.normalized(), ang)
	if g > 0.01:
		for j in [2, 3]:
			var b: int = _ix["thumb_%02d_%s" % [j, s]]
			var nb_name := "thumb_%02d_%s" % [j + 1, s] if j < 3 else "thumb_04_leaf_%s" % s
			var ch: int = _ix[nb_name]
			if b < 0 or ch < 0: continue
			var d := (_gp(sk, ch).origin - _gp(sk, b).origin).normalized()
			var ax := d.cross(palm)
			if ax.length() < 0.05: continue
			_rotate_global(sk, b, ax.normalized(), deg_to_rad(28.0) * g)

func _gp(sk: Skeleton3D, i: int) -> Transform3D:
	return sk.get_bone_global_pose(i)

## rotate bone i by `ang` about a skeleton-space axis through its own origin
func _rotate_global(sk: Skeleton3D, i: int, axis: Vector3, ang: float) -> void:
	var g := _gp(sk, i)
	_set_global_basis(sk, i, Basis(axis, ang) * g.basis)

func _set_global_basis(sk: Skeleton3D, i: int, gb: Basis) -> void:
	var p := sk.get_bone_parent(i)
	var pb := Basis() if p < 0 else _gp(sk, p).basis
	var local := (pb.inverse() * gb)
	var sc := sk.get_bone_pose_scale(i)
	sk.set_bone_pose_rotation(i, local.orthonormalized().get_rotation_quaternion())
	sk.set_bone_pose_scale(i, sc)
