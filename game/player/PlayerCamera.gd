class_name PlayerCamera
extends SpringArm3D
## Third-person combat camera.
##
## Everything here is about making the camera feel like a operator rather than a
## rigid boom: the follow is damped separately on the horizontal and vertical
## axes (vertical much softer, so stairs and slopes do not bob the frame), the
## aim leads the player's velocity, speed drives FOV / arm length / bank with a
## fast attack and a slow release, landings get a critically damped dip, and
## impacts can push the camera directionally instead of only shaking it.

var target: Node3D
var yaw := 0.0
var pitch := -0.22
var distance := 4.6

var _cam: Camera3D
## Base field of view (Settings > Field of view, default 60). v0.13 ran at 68
## and widened another 8.5 degrees whenever you sprinted or galloped, which is
## the "why is it so wide sometimes" fisheye look.
var _fov_base := 60.0
var _pitch_eff := -0.22
var _world: Node = null
## The lens never goes lower than this over the ground beneath it. A camera
## sitting in the grass looking up is a wall of giant blades.
const CLEAR := 0.85
var _lock: Node3D

# follow / look-ahead state
var _pos_h := Vector3.ZERO
var _pos_y := 0.0
var _lead := Vector3.ZERO
var _speed := 0.0

# feel state
var _fov_kick := 0.0
var _bank := 0.0
var _arm_extra := 0.0
var _dip := 0.0
var _dip_v := 0.0
var _breath := 0.0
var _ride := 0.0                ## 0 on foot .. 1 in the saddle (eased)

# impact state
var _shake := 0.0
var _shake_t := 0.0
var _imp := Vector2.ZERO
var _imp_v := Vector2.ZERO

const FOLLOW_H := 13.0          # horizontal follow stiffness
const FOLLOW_V := 6.5           # vertical follow stiffness (softer on purpose)
const LEAD_MAX := 1.35          # metres the aim leads the player's velocity

func _ready() -> void:
	add_to_group("player_camera")
	spring_length = distance
	margin = 0.28
	collision_mask = 1
	_cam = Camera3D.new()
	_fov_base = clampf(float(Game.settings.get("fov", 60.0)), 45.0, 85.0)
	_cam.fov = _fov_base
	_cam.near = 0.08
	# 900 m clipped the mountains and the far LOD ring the terrain streams in.
	_cam.far = 8000.0   # v0.17: the mountain ring reaches 4.7 km beyond the map edge (6.9 km corner to corner)
	add_child(_cam)

func setup(t: Node3D) -> void:
	target = t
	if t != null:
		_pos_h = t.global_position
		_pos_y = t.global_position.y + 1.45

## Jump straight to the target (after teleports / fast travel).
func snap() -> void:
	if target == null: return
	_pos_h = target.global_position
	_pos_y = target.global_position.y + 1.45
	_lead = Vector3.ZERO
	_speed = 0.0
	_pitch_eff = pitch

## Highest pitch (most upward look) that keeps the lens CLEAR metres above the
## terrain under it. The boom puts the camera at pivot + R(pitch, yaw) * (0,0,L),
## so its height over the pivot is -sin(pitch) * L.
func _ground_safe_pitch(p: float, L: float) -> float:
	if _world == null or not is_instance_valid(_world):
		_world = get_tree().get_first_node_in_group("world")
	if _world == null: return p
	var t = _world.get("terrain")
	if t == null or not t.has_method("sample_height"): return p
	var out := p
	for it in 2:
		var back := Basis.from_euler(Vector3(out, yaw, 0.0)) * Vector3(0, 0, maxf(L, 0.5))
		var cw := global_position + back
		var gh: float = t.sample_height(cw.x, cw.z)
		var need := (gh + CLEAR - global_position.y) / maxf(L, 0.5)
		if -sin(out) < need:
			out = minf(out, -asin(clampf(need, -0.95, 0.95)))
	return out

func get_yaw() -> float:
	return yaw

func cam() -> Camera3D:
	return _cam

func set_lock(l: Node3D) -> void:
	_lock = l

func is_locked() -> bool:
	return _lock != null and is_instance_valid(_lock)

func add_look(delta_look: Vector2) -> void:
	var sens := 0.0022 * float(Game.settings.get("camera_sens", 1.0))
	yaw -= delta_look.x * sens
	var iv := -1.0 if bool(Game.settings.get("invert_y", false)) else 1.0
	pitch = clampf(pitch - delta_look.y * sens * iv, -0.95, 0.40)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		add_look((event as InputEventMouseMotion).relative)

## Undirected rattle. Use for ambience and small hits.
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount * float(Game.settings.get("shake", 1.0)))

## Directional push. `dir` is a world direction; the camera is kicked opposite
## to it in screen space, which is what sells the weight of a landed hit.
func impulse(dir: Vector3, amount: float) -> void:
	var s := float(Game.settings.get("shake", 1.0))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var d := dir.normalized()
	_imp_v += Vector2(-d.dot(right), d.dot(fwd)) * amount * 14.0 * s

## One-shot vertical dip, used on landings. `f` is 0..1 of a hard landing.
func land_dip(f: float) -> void:
	_dip_v -= clampf(f, 0.0, 1.5) * 7.0

func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target): return
	var d := clampf(delta, 0.0, 0.05)

	# ---- lock-on ----------------------------------------------------------
	if is_locked():
		var to := _lock.global_position + Vector3(0, 1.0, 0) - (target.global_position + Vector3(0, 1.4, 0))
		var want_yaw := atan2(-to.x, -to.z) + PI
		var want_pitch := clampf(-atan2(to.y, Vector2(to.x, to.z).length()), -0.6, 0.35)
		yaw = lerp_angle(yaw, want_yaw, clampf(d * 6.0, 0.0, 1.0))
		pitch = lerpf(pitch, want_pitch, clampf(d * 5.0, 0.0, 1.0))

	# ---- riding: higher pivot, longer boom, FOV scaled to gallop speeds ----
	var riding: bool = target.has_method("is_mounted") and target.is_mounted()
	_ride = lerpf(_ride, 1.0 if riding else 0.0, clampf(d * 2.2, 0.0, 1.0))

	# ---- velocity + look-ahead --------------------------------------------
	var vel := Vector3.ZERO
	if target is CharacterBody3D: vel = (target as CharacterBody3D).velocity
	var hv := Vector3(vel.x, 0, vel.z)
	_speed = lerpf(_speed, hv.length(), clampf(d * 7.0, 0.0, 1.0))
	var want_lead: Vector3 = hv.normalized() * clampf(_speed / lerpf(8.0, 14.0, _ride), 0.0, 1.0) * LEAD_MAX * (1.0 + _ride * 0.6)
	if is_locked(): want_lead *= 0.35
	_lead = _lead.lerp(want_lead, clampf(d * 3.4, 0.0, 1.0))

	# ---- split-axis follow ------------------------------------------------
	var pivot := target.global_position + _lead
	_pos_h = _pos_h.lerp(Vector3(pivot.x, _pos_h.y, pivot.z), clampf(d * FOLLOW_H, 0.0, 1.0))
	_pos_y = lerpf(_pos_y, pivot.y + 1.45 + _ride * 0.55, clampf(d * lerpf(FOLLOW_V, 9.0, _ride), 0.0, 1.0))

	# ---- landing dip (critically damped spring) ---------------------------
	_dip_v += (-_dip * 90.0 - _dip_v * 13.5) * d
	_dip += _dip_v * d
	_dip = clampf(_dip, -0.55, 0.25)

	# ---- idle breathing ---------------------------------------------------
	_breath += d * (0.7 + _speed * 0.10)
	var breathe := sin(_breath) * 0.018 * clampf(1.0 - _speed / 3.0, 0.0, 1.0)

	global_position = Vector3(_pos_h.x, _pos_y + _dip + breathe, _pos_h.z)

	# ---- speed-driven FOV / arm / bank: fast attack, slow release ----------
	var sp01 := clampf((_speed - lerpf(4.2, 7.5, _ride)) / lerpf(5.2, 7.0, _ride), 0.0, 1.0)
	_fov_kick = _toward(_fov_kick, sp01, d, 5.2, 1.7)
	_arm_extra = _toward(_arm_extra, sp01, d, 3.2, 1.3)
	# no camera roll: a tilting horizon read as a glitch, not as speed
	_bank = 0.0

	var tight := 0.0 if not is_locked() else 1.0
	# looking up pulls the camera in toward the shoulder instead of sinking it
	# into the ground behind the player
	var up_pull := clampf(pitch / 0.40, 0.0, 1.0) * 0.40
	var want_len := (distance + _ride * 1.5 + _arm_extra * (0.55 + _ride * 0.4) - tight * 0.45) * (1.0 - up_pull)
	spring_length = lerpf(spring_length, want_len, clampf(d * 6.0, 0.0, 1.0))
	_fov_base = clampf(float(Game.settings.get("fov", 60.0)), 45.0, 85.0)
	_cam.fov = _fov_base + _fov_kick * 2.5 - tight * 2.0
	_pitch_eff = lerpf(_pitch_eff, _ground_safe_pitch(pitch, spring_length), clampf(d * 12.0, 0.0, 1.0))
	rotation = Vector3(_pitch_eff, yaw, 0.0)

	# ---- impacts ----------------------------------------------------------
	_imp_v += (-_imp * 240.0 - _imp_v * 19.0) * d
	_imp += _imp_v * d
	_imp = _imp.limit_length(0.35)
	var off := _imp
	if _shake > 0.001:
		_shake_t += d * 34.0
		off += Vector2(sin(_shake_t * 1.7), cos(_shake_t * 2.3)) * _shake * 0.22
		_shake = maxf(0.0, _shake - d * 1.9)
	_cam.h_offset = off.x
	_cam.v_offset = off.y

## Asymmetric approach: rises at `up` per second, falls at `down`.
func _toward(cur: float, want: float, d: float, up: float, down: float) -> float:
	var k := up if want > cur else down
	return lerpf(cur, want, clampf(d * k, 0.0, 1.0))
