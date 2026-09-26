class_name LookAtLayer
extends SkeletonModifier3D
## Additive upper-body look: eyes lead, head follows, chest contributes last.
## Runs on top of whatever the animation tree produced so the body stays alive
## while locomotion continues underneath.

@export var enabled := true
@export var yaw_limit := 74.0
@export var pitch_limit := 34.0
@export var chest_share := 0.22
@export var head_share := 0.62
@export var eye_share := 1.0
@export var smooth := 7.0

var target: Vector3 = Vector3.ZERO
var _looking := false

var _skel: Skeleton3D
var _b := {}
var _yaw := 0.0
var _pitch := 0.0
var _ok := false

func _ready() -> void:
	_skel = get_skeleton()
	if _skel == null: return
	for n in ["chest", "upperchest", "neck", "head", "eye.L", "eye.R"]:
		_b[n] = _skel.find_bone(n)
	_ok = _b.get("head", -1) >= 0

func look_at_point(p: Vector3) -> void:
	target = p
	_looking = true

func clear() -> void:
	_looking = false

func _process_modification() -> void:
	if not _ok or not enabled: return
	var dt := get_process_delta_time()
	if dt <= 0.0: dt = 1.0 / 60.0
	var k: float = clampf(smooth * dt, 0.0, 1.0)
	var wy := 0.0
	var wp := 0.0
	if _looking:
		var owner_node := _skel.get_parent_node_3d()
		var base: Transform3D = owner_node.global_transform if owner_node else _skel.global_transform
		var head_w: Vector3 = _skel.global_transform * _skel.get_bone_global_pose(_b["head"]).origin
		var to: Vector3 = base.affine_inverse().basis * (target - head_w)
		if to.length() > 0.05:
			to = to.normalized()
			wy = rad_to_deg(atan2(-to.x, -to.z))
			wp = rad_to_deg(asin(clampf(to.y, -1.0, 1.0)))
			wy = clampf(wy, -yaw_limit, yaw_limit)
			wp = clampf(wp, -pitch_limit, pitch_limit)
	_yaw = lerpf(_yaw, wy, k)
	_pitch = lerpf(_pitch, wp, k)
	var inf: float = influence
	_add(_b.get("chest", -1), _pitch * chest_share * 0.5 * inf, _yaw * chest_share * inf)
	_add(_b.get("upperchest", -1), _pitch * chest_share * 0.5 * inf, _yaw * chest_share * 0.8 * inf)
	_add(_b.get("neck", -1), _pitch * head_share * 0.45 * inf, _yaw * head_share * 0.45 * inf)
	_add(_b.get("head", -1), _pitch * head_share * 0.55 * inf, _yaw * head_share * 0.55 * inf)
	for e in ["eye.L", "eye.R"]:
		_add(_b.get(e, -1), 0.0, _yaw * eye_share * 0.30 * inf)

func _add(idx: int, pitch_deg: float, yaw_deg: float) -> void:
	if idx < 0: return
	var q: Quaternion = _skel.get_bone_pose_rotation(idx)
	var delta := Quaternion(Vector3.RIGHT, deg_to_rad(-pitch_deg)) * Quaternion(Vector3.UP, deg_to_rad(yaw_deg))
	_skel.set_bone_pose_rotation(idx, (q * delta).normalized())
