class_name HorseTail
extends SkeletonModifier3D
## v0.23 the horse's tail moves on its own, on top of the animation: it
## streams up and back at the gallop and bounces with the stride, swings out
## on turns, lags like a whip when the horse sets off or reins in, and swishes
## at flies now and then when the horse stands or walks.
## A chain of damped springs, one per tail bone (Tail1..Tail7), each chasing
## the one above it, so the tip lags the dock.

var horse: Node3D                     ## the Horse (speed and heading)
var _bones := PackedInt32Array()
var _lat := PackedFloat32Array()      ## side swing per bone (rad)
var _lat_v := PackedFloat32Array()
var _up := PackedFloat32Array()       ## lift (up and back) per bone (rad)
var _up_v := PackedFloat32Array()
var _swish_t := 4.0
var _swish := 0.0
var _swish_dir := 1.0
var _prev_yaw := 0.0
var _prev_speed := 0.0
var _yaw_rate := 0.0
var _accel := 0.0
var _t := 0.0
var _primed := false

## skeleton space of HorseHQ.glb: +Z is the head end, +X the horse's left
const AX_SIDE := Vector3(0, 0, 1)     ## swings the hanging tail sideways
const AX_LIFT := Vector3(1, 0, 0)     ## positive lifts it up and back

func setup(sk: Skeleton3D) -> bool:
	for i in range(1, 8):
		var b := sk.find_bone("Tail%d" % i)
		if b < 0: return false
		_bones.append(b)
	_lat.resize(7)
	_lat_v.resize(7)
	_up.resize(7)
	_up_v.resize(7)
	return true

## for the tests: [lift at the dock, side at the dock, lift at the tip, side at the tip]
func state() -> Array:
	return [_up[0], _lat[0], _up[6], _lat[6]] if _up.size() == 7 else [0.0, 0.0, 0.0, 0.0]

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or _bones.size() != 7: return
	var dt := clampf(get_process_delta_time(), 0.0, 0.05)
	if dt <= 0.0: return
	_t += dt
	var spd := 0.0
	var yaw := 0.0
	if horse != null and is_instance_valid(horse):
		spd = absf(float(horse.get("_speed")))
		yaw = horse.global_rotation.y
	if not _primed:
		_primed = true
		_prev_yaw = yaw
		_prev_speed = spd
	var yr := wrapf(yaw - _prev_yaw, -PI, PI) / dt
	_prev_yaw = yaw
	_yaw_rate = lerpf(_yaw_rate, yr, clampf(dt * 6.0, 0.0, 1.0))
	var acc := (spd - _prev_speed) / dt
	_prev_speed = spd
	_accel = lerpf(_accel, acc, clampf(dt * 5.0, 0.0, 1.0))
	var g := clampf((spd - 3.0) / 9.5, 0.0, 1.0)          # 0 at a trot .. 1 at a full gallop
	# lift: carried higher the faster it goes, bouncing with the stride; it
	# flicks back when the horse surges forward and drops when it reins in
	var up := 0.06 + 0.45 * g + 0.08 * g * sin(_t * TAU * 2.1) + clampf(_accel * 0.03, -0.2, 0.3)
	# side: out of the turn, a slow sway at rest
	var side := clampf(-_yaw_rate * (0.22 + 0.35 * g), -0.65, 0.65) + 0.05 * sin(_t * 1.3) * (1.0 - g)
	_swish_t -= dt
	if _swish_t <= 0.0:
		_swish_t = randf_range(3.5, 9.0)
		if spd < 2.0:
			_swish = 1.0
			_swish_dir = -_swish_dir
	if _swish > 0.0:
		_swish = maxf(0.0, _swish - dt * 1.7)
		side += _swish_dir * sin(_swish * PI) * 0.55
	# the chain: the dock chases the drive, every bone chases the one above
	for i in 7:
		var tl: float = side if i == 0 else _lat[i - 1]
		var tu: float = up if i == 0 else _up[i - 1]
		var k := 140.0 - 14.0 * float(i)
		var c := 2.0 * sqrt(k) * 0.6
		_lat_v[i] += (k * (tl - _lat[i]) - c * _lat_v[i]) * dt
		_lat[i] += _lat_v[i] * dt
		_up_v[i] += (k * (tu - _up[i]) - c * _up_v[i]) * dt
		_up[i] += _up_v[i] * dt
	# each bone adds its step of the bend, about skeleton-space axes
	for i in 7:
		var b := _bones[i]
		var dl: float = _lat[i] - (_lat[i - 1] if i > 0 else 0.0)
		var du: float = _up[i] - (_up[i - 1] if i > 0 else 0.0)
		if absf(dl) < 0.0001 and absf(du) < 0.0001: continue
		var gb := sk.get_bone_global_pose(b).basis.orthonormalized()
		var inv := gb.inverse()
		var q := sk.get_bone_pose_rotation(b)
		q = q * Quaternion((inv * AX_SIDE).normalized(), dl) * Quaternion((inv * AX_LIFT).normalized(), du)
		sk.set_bone_pose_rotation(b, q.normalized())
