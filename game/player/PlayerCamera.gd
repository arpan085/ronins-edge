class_name PlayerCamera
extends SpringArm3D
## Third-person combat camera: orbit, lock-on, collision, shake, FOV kick.

var target: Node3D
var yaw := 0.0
var pitch := -0.22
var distance := 4.6
var _shake := 0.0
var _shake_t := 0.0
var _cam: Camera3D
var _look := Vector2.ZERO
var _fov_base := 68.0
var _fov_kick := 0.0
var _lock: Node3D

func _ready() -> void:
	spring_length = distance
	margin = 0.25
	collision_mask = 1
	_cam = Camera3D.new()
	_cam.fov = _fov_base
	_cam.near = 0.08
	_cam.far = 900.0
	add_child(_cam)

func setup(t: Node3D) -> void:
	target = t

func get_yaw() -> float:
	return yaw

func cam() -> Camera3D:
	return _cam

func set_lock(l: Node3D) -> void:
	_lock = l

func add_look(delta_look: Vector2) -> void:
	var sens := 0.0022 * float(Game.settings.get("camera_sens", 1.0))
	yaw -= delta_look.x * sens
	pitch = clampf(pitch - delta_look.y * sens * (-1.0 if bool(Game.settings.get("invert_y", false)) else 1.0), -0.95, 0.55)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		add_look((event as InputEventMouseMotion).relative)

func shake(amount: float) -> void:
	_shake = maxf(_shake, amount * float(Game.settings.get("shake", 1.0)))

func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target): return
	# lock-on aims the camera at the target
	if _lock != null and is_instance_valid(_lock):
		var to := _lock.global_position + Vector3(0, 1.0, 0) - (target.global_position + Vector3(0, 1.4, 0))
		var want_yaw := atan2(-to.x, -to.z) + PI
		var want_pitch := clampf(-atan2(to.y, Vector2(to.x, to.z).length()), -0.6, 0.35)
		yaw = lerp_angle(yaw, want_yaw, clampf(delta * 6.0, 0.0, 1.0))
		pitch = lerpf(pitch, want_pitch, clampf(delta * 5.0, 0.0, 1.0))
	var pivot := target.global_position + Vector3(0, 1.45, 0)
	global_position = global_position.lerp(pivot, clampf(delta * 14.0, 0.0, 1.0))
	rotation = Vector3(pitch, yaw, 0)
	spring_length = lerpf(spring_length, distance, clampf(delta * 6.0, 0.0, 1.0))
	# sprint FOV kick
	var hv := Vector3(target.velocity.x, 0, target.velocity.z).length() if target is CharacterBody3D else 0.0
	_fov_kick = lerpf(_fov_kick, clampf((hv - 5.0) / 5.0, 0.0, 1.0), clampf(delta * 3.0, 0.0, 1.0))
	_cam.fov = _fov_base + _fov_kick * 7.0
	# shake
	if _shake > 0.001:
		_shake_t += delta * 34.0
		var s := _shake
		_cam.h_offset = sin(_shake_t * 1.7) * s * 0.22
		_cam.v_offset = cos(_shake_t * 2.3) * s * 0.22
		_shake = maxf(0.0, _shake - delta * 1.9)
	else:
		_cam.h_offset = lerpf(_cam.h_offset, 0.0, 0.3)
		_cam.v_offset = lerpf(_cam.v_offset, 0.0, 0.3)

func is_locked() -> bool:
	return _lock != null and is_instance_valid(_lock)
