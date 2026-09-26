class_name FootIK
extends SkeletonModifier3D
## Two-link leg IK with ground raycasts and pelvis compensation so feet stay
## planted on slopes and steps instead of floating or sinking.

@export var enabled := true
@export var ray_up := 0.55
@export var ray_down := 0.85
@export var max_pelvis_drop := 0.32
@export var max_foot_lift := 0.40
@export var ankle_height := 0.10          ## ankle joint height above the sole
@export var normal_limit_deg := 26.0
@export var smooth := 26.0
@export var collision_mask := 1

var _skel: Skeleton3D
var _b := {}
var _len := {}
var _pelvis_off := 0.0
var _lift := {"L": 0.0, "R": 0.0}
var _norm := {"L": Vector3.UP, "R": Vector3.UP}
var _hips_rest := Vector3.ZERO
var _ok := false
var _grounded := true

func _ready() -> void:
	_skel = get_skeleton()
	if _skel == null: return
	for n in ["hips", "thigh.L", "shin.L", "foot.L", "toe.L", "thigh.R", "shin.R", "foot.R", "toe.R"]:
		_b[n] = _skel.find_bone(n)
		if _b[n] < 0:
			return
	for s in ["L", "R"]:
		_len["thigh." + s] = _skel.get_bone_rest(_b["shin." + s]).origin.length()
		_len["shin." + s] = _skel.get_bone_rest(_b["foot." + s]).origin.length()
	_hips_rest = _skel.get_bone_rest(_b["hips"]).origin
	_ok = true

func set_grounded(g: bool) -> void:
	_grounded = g

func _process_modification() -> void:
	if not _ok or not enabled or influence <= 0.001:
		return
	var dt := get_process_delta_time()
	if dt <= 0.0: dt = 1.0 / 60.0
	var k: float = clampf(smooth * dt, 0.0, 1.0)
	var xf := _skel.global_transform
	var inv := xf.affine_inverse()
	var space := _skel.get_world_3d().direct_space_state
	var want := {"L": 0.0, "R": 0.0}
	# Ground height under the character itself. Foot targets are expressed as a
	# *delta* from this plane, never as an absolute pin: pinning the ankle to
	# the ground every frame also drags the swing foot down, which flattened the
	# authored step arc to 3.3 cm and made the walk look like a shuffle.
	var base_y: float = xf.origin.y
	var rq := PhysicsRayQueryParameters3D.create(
		xf.origin + Vector3.UP * ray_up, xf.origin + Vector3.DOWN * (ray_down + 0.5))
	rq.collision_mask = collision_mask
	var rhit := space.intersect_ray(rq)
	if not rhit.is_empty(): base_y = rhit.position.y
	if _grounded:
		for s in ["L", "R"]:
			var ankle_w: Vector3 = xf * _skel.get_bone_global_pose(_b["foot." + s]).origin
			var q := PhysicsRayQueryParameters3D.create(
				ankle_w + Vector3.UP * ray_up, ankle_w + Vector3.DOWN * ray_down)
			q.collision_mask = collision_mask
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				want[s] = 0.0
				_norm[s] = _norm[s].lerp(Vector3.UP, k)
				continue
			# terrain offset relative to the plane the character stands on, so
			# slopes and steps move the foot while the swing arc survives
			var terrain: float = hit.position.y - base_y
			# ...but never let the sole sink through the ground under it
			var pen: float = (hit.position.y + ankle_height) - ankle_w.y
			want[s] = clampf(maxf(terrain, pen), -max_foot_lift, max_foot_lift)
			var n: Vector3 = hit.normal
			if n.angle_to(Vector3.UP) > deg_to_rad(normal_limit_deg):
				n = Vector3.UP.slerp(n, deg_to_rad(normal_limit_deg) / max(n.angle_to(Vector3.UP), 0.001))
			_norm[s] = _norm[s].lerp(n.normalized(), k)
	else:
		_norm["L"] = _norm["L"].lerp(Vector3.UP, k)
		_norm["R"] = _norm["R"].lerp(Vector3.UP, k)
	for s in ["L", "R"]:
		# Asymmetric response: a step-up moves the body 0.28 m in a single
		# physics tick, and symmetric smoothing left both feet hanging 0.29 m
		# above the ground for several frames. Chase large corrections fast,
		# release them slowly so slopes stay smooth.
		var kk: float = k
		if absf(want[s] - _lift[s]) > 0.10:
			kk = clampf(k * 3.2, 0.0, 1.0)
		_lift[s] = lerpf(_lift[s], want[s], kk)
	# pelvis follows the lower foot so the higher one can still reach
	var target_off: float = minf(minf(_lift["L"], _lift["R"]), 0.0)
	target_off = maxf(target_off, -max_pelvis_drop)
	var kp: float = k
	if absf(target_off - _pelvis_off) > 0.10:
		kp = clampf(k * 3.2, 0.0, 1.0)
	_pelvis_off = lerpf(_pelvis_off, target_off, kp)
	var off_local: Vector3 = inv.basis * Vector3(0.0, _pelvis_off * influence, 0.0)
	_skel.set_bone_pose_position(_b["hips"], _skel.get_bone_pose_position(_b["hips"]) + off_local)
	for s in ["L", "R"]:
		var lift: float = (_lift[s] - _pelvis_off) * influence
		_solve_leg(s, lift, xf, inv)

func _solve_leg(s: String, lift: float, xf: Transform3D, inv: Transform3D) -> void:
	var ti: int = _b["thigh." + s]
	var si: int = _b["shin." + s]
	var fi: int = _b["foot." + s]
	var L1: float = _len["thigh." + s]
	var L2: float = _len["shin." + s]
	var t_thigh: Transform3D = _skel.get_bone_global_pose(ti)
	var t_shin: Transform3D = _skel.get_bone_global_pose(si)
	var t_foot: Transform3D = _skel.get_bone_global_pose(fi)
	var hip: Vector3 = t_thigh.origin
	var knee_now: Vector3 = t_shin.origin
	var target: Vector3 = t_foot.origin + inv.basis * Vector3(0.0, lift, 0.0)
	var v: Vector3 = target - hip
	var d: float = clampf(v.length(), absf(L1 - L2) + 0.012, L1 + L2 - 0.012)
	if d < 0.02: return
	var vd: Vector3 = v.normalized()
	# hinge axis: the knee's current bend axis, falling back to the body's right
	var hinge: Vector3 = (knee_now - hip).cross(target - knee_now)
	if hinge.length() < 1e-4:
		hinge = t_thigh.basis.x
	hinge = hinge.normalized()
	if absf(vd.dot(hinge)) > 0.99: return
	var cos_a: float = clampf((L1 * L1 + d * d - L2 * L2) / (2.0 * L1 * d), -1.0, 1.0)
	var a1: float = acos(cos_a)
	var c1: Vector3 = vd.rotated(hinge, a1)
	var c2: Vector3 = vd.rotated(hinge, -a1)
	var ref: Vector3 = (knee_now - hip).normalized()
	var dir: Vector3 = c1 if c1.dot(ref) >= c2.dot(ref) else c2
	# thigh
	var axis_t: Vector3 = _skel.get_bone_rest(si).origin.normalized()
	var cur_t: Vector3 = (t_thigh.basis * axis_t).normalized()
	var q_t := Quaternion(cur_t, dir)
	var nb_t: Basis = Basis(q_t) * t_thigh.basis
	_skel.set_bone_global_pose(ti, Transform3D(nb_t, hip))
	# shin
	var knee: Vector3 = hip + dir * L1
	var t_shin2: Transform3D = _skel.get_bone_global_pose(si)
	var want_s: Vector3 = (target - knee)
	if want_s.length() < 1e-4: return
	want_s = want_s.normalized()
	var axis_s: Vector3 = _skel.get_bone_rest(fi).origin.normalized()
	var cur_s: Vector3 = (t_shin2.basis * axis_s).normalized()
	var q_s := Quaternion(cur_s, want_s)
	var nb_s: Basis = Basis(q_s) * t_shin2.basis
	_skel.set_bone_global_pose(si, Transform3D(nb_s, t_shin2.origin))
	# foot: roll the sole onto the ground normal
	var t_foot2: Transform3D = _skel.get_bone_global_pose(fi)
	var n_local: Vector3 = (inv.basis * _norm[s]).normalized()
	var q_f := Quaternion(Vector3.UP, Vector3.UP.slerp(n_local, influence)).normalized()
	_skel.set_bone_global_pose(fi, Transform3D(Basis(q_f) * t_foot2.basis, t_foot2.origin))

## Distance from each ankle to the ground; used by the animation QA harness.
func debug_ankle_gap() -> Dictionary:
	if not _ok: return {}
	var xf := _skel.global_transform
	var space := _skel.get_world_3d().direct_space_state
	var out := {}
	for s in ["L", "R"]:
		var w: Vector3 = xf * _skel.get_bone_global_pose(_b["foot." + s]).origin
		var q := PhysicsRayQueryParameters3D.create(w + Vector3.UP * ray_up, w + Vector3.DOWN * 2.0)
		q.collision_mask = collision_mask
		var hit := space.intersect_ray(q)
		out[s] = 999.0 if hit.is_empty() else (w.y - ankle_height) - hit.position.y
	return out

func foot_world(s: String) -> Vector3:
	if not _ok: return Vector3.ZERO
	return _skel.global_transform * _skel.get_bone_global_pose(_b["toe." + s]).origin

func ankle_world(s: String) -> Vector3:
	if not _ok: return Vector3.ZERO
	return _skel.global_transform * _skel.get_bone_global_pose(_b["foot." + s]).origin
