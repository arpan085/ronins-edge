class_name AnimDriver
extends Node
## Owns every animation decision for one character: blend-space locomotion,
## start/stop/turn detection, layered actions and reactions, look-at, foot IK
## and animation LOD. Gameplay code reports intent; this decides what plays.

signal turn_started(degrees: float, duration: float)

const META_PATH := "res://assets/models/anim_meta.json"
static var _meta_cache := {}

var rig: AnimRig
var foot_ik: FootIK
var look: LookAtLayer
var lod: AnimLOD
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var model_root: Node3D
var kind := ""

var speed_walk := 1.8
var speed_jog := 4.0
var speed_sprint := 6.0

var _host: Node3D
var _turn_t := 0.0
var _turn_total := 0.0
var _turn_amount := 0.0
var _idle_t := 0.0
var _idle_var_t := 0.0
var _was_moving := false
var _start_t := 0.0
var _stop_t := 0.0
var _last_state := ""
var _react_lock := 0.0
var _grounded := true
var _rm_prev := Vector3.ZERO

# ---------------------------------------------------------------- build
static func _load_meta() -> Dictionary:
	if _meta_cache.is_empty():
		if ResourceLoader.exists(META_PATH) or FileAccess.file_exists(META_PATH):
			var f := FileAccess.open(META_PATH, FileAccess.READ)
			if f != null:
				var j = JSON.parse_string(f.get_as_text())
				if j is Dictionary: _meta_cache = j
		if _meta_cache.is_empty(): _meta_cache = {"_": {}}
	return _meta_cache

func build(host: Node3D, glb: String, character: String, is_player := false) -> bool:
	_host = host
	kind = character
	model_root = Node3D.new()
	model_root.name = "Model"
	# Blender exports the character facing glTF -Z, while every gameplay script
	# uses atan2(dir.x, dir.z), i.e. +Z forward. Turn the model once here so the
	# visual, the clip travel direction and the yaw convention all agree.
	model_root.rotation.y = PI
	host.add_child(model_root)
	var ps := load(glb) as PackedScene
	if ps == null:
		push_error("AnimDriver: model missing %s" % glb)
		return false
	var inst := ps.instantiate()
	model_root.add_child(inst)
	anim_player = _find(inst, "AnimationPlayer") as AnimationPlayer
	skeleton = _find(inst, "Skeleton3D") as Skeleton3D
	if anim_player == null or skeleton == null:
		push_error("AnimDriver: rig not found in %s" % glb)
		return false
	rig = AnimRig.new()
	rig.name = "AnimRig"
	add_child(rig)
	var meta: Dictionary = _load_meta().get(character, {})
	if not rig.setup(anim_player, skeleton, character, meta):
		return false
	foot_ik = FootIK.new()
	foot_ik.name = "FootIK"
	skeleton.add_child(foot_ik)
	look = LookAtLayer.new()
	look.name = "LookAt"
	skeleton.add_child(look)
	lod = AnimLOD.new()
	lod.name = "AnimLOD"
	lod.is_player = is_player
	add_child(lod)
	lod.setup(host, rig, foot_ik, look)
	_build_speed_table()
	var w := float(_row_target[3]) if _row_target.size() > 5 else 0.0
	var j := float(_row_target[4]) if _row_target.size() > 5 else 0.0
	var s := float(_row_target[5]) if _row_target.size() > 5 else 0.0
	if w > 0.3: speed_walk = w
	if j > speed_walk + 0.3: speed_jog = j
	else: speed_jog = speed_walk * 2.2
	if s > speed_jog + 0.3: speed_sprint = s
	else: speed_sprint = speed_jog * 1.45
	return true

var _row_y: Array = []
var _row_fwd: Array = []
var _row_side: Array = []
var _row_cad: Array = []
var _row_target: Array = []
var _row_side_t: Array = []
var speed_back_walk := 1.0
var speed_back_jog := 2.0
var speed_side := 1.0
var speed_side_fast := 1.6

func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls: return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null: return r
	return null

func ok() -> bool:
	return rig != null and rig.ok()

# ---------------------------------------------------------------- locomotion
## vel: world-space velocity. want_yaw: desired facing. Returns the yaw the host
## should adopt this frame, so turning animation and actual rotation stay in sync.
func tick(delta: float, vel: Vector3, want_yaw: float, has_input: bool,
		grounded := true, blocking := false, allow_loco := true) -> float:
	if not ok(): return want_yaw
	_grounded = grounded
	if foot_ik != null: foot_ik.set_grounded(grounded)
	rig.update(delta)
	if _react_lock > 0.0: _react_lock -= delta
	var yaw: float = _host.rotation.y
	var hv := Vector3(vel.x, 0.0, vel.z)
	var sp := hv.length()
	var local: Vector3 = Basis(Vector3.UP, -yaw) * hv
	var fwd := local.z          # +Z is forward in this project's yaw convention
	var side := -local.x        # and -X is the character's right
	var ay: float = clampf(_fwd_axis(fwd), -2.0, 3.0)
	var ax: float = _side_axis(side, ay)
	rig.set_locomotion(ax, ay)
	var blended := _blend_speed(ay, ax)
	if blended > 0.15 and sp > 0.15:
		# cadence, not stride, absorbs the remaining difference; a wide range is needed
		# because every clip shares one cycle length for phase coherence.
		rig.set_loco_speed(clampf(sp / blended, 0.45, 2.4))
	else:
		rig.set_loco_speed(1.0)
	rig.set_breathe(clampf(0.65 - sp * 0.08, 0.05, 0.65))
	if not allow_loco:
		return want_yaw
	# ------- turning: transfer weight, then rotate over the clip
	if _turn_t > 0.0:
		# rotate along an ease curve so the body turns after the weight shift
		var prev_f: float = 1.0 - clampf(_turn_t / maxf(_turn_total, 0.01), 0.0, 1.0)
		_turn_t -= delta
		var f: float = 1.0 - clampf(_turn_t / maxf(_turn_total, 0.01), 0.0, 1.0)
		var e0: float = prev_f * prev_f * (3.0 - 2.0 * prev_f)
		var e1: float = f * f * (3.0 - 2.0 * f)
		return yaw + _turn_amount * (e1 - e0)
	# Decaying peak, not last frame's speed: the stop clip is chosen when the
	# character has *recently* been running, and by the time speed has fallen
	# below the walk threshold the previous frame is already slow, so the run
	# stop never fired at all (caught by the QA state-coverage check).
	_peak_speed = maxf(sp, _peak_speed - delta * 5.0)
	var moving := sp > 0.45
	if sp < 0.40:
		_still_t += delta
		if _still_t > 0.18: _start_latch = true
	else:
		_still_t = 0.0
	var st := rig.loco_state()
	if not grounded:
		if st != "JumpAir" and st != "JumpUp": rig.travel("JumpAir")
	elif st == "JumpAir":
		rig.travel("JumpLand")
	elif blocking:
		if st != "BlockIn" and st != "BlockIdle": rig.travel("BlockIn")
	elif moving:
		_idle_t = 0.0
		if _start_latch and sp > speed_walk * 0.85 and rig.has_clip("Start_Run") \
				and st == "Move":
			_start_latch = false
			rig.travel("StartRun")
		elif st in ["IdleB", "IdleC", "BlockIn", "BlockIdle", "JumpLand"]:
			rig.travel("Move")
		# In-place turn only when the character is barely translating. The
		# threshold used to be 60% of jog speed, which is *above* walk speed,
		# so a turn-in-place clip played while the body kept travelling at
		# 1.2 m/s: the planted foot of the turn clip had to drag along with it
		# (measured 1.35 m/s of slide, and the heading hunted for over two
		# seconds as the turn re-triggered). Above this speed the body just
		# rotates smoothly under the locomotion blend, which is what a moving
		# turn should look like anyway.
		var dy: float = wrapf(want_yaw - yaw, -PI, PI)
		if absf(dy) > deg_to_rad(65.0) and sp < speed_walk * 0.45 and st == "Move":
			_begin_turn(dy)
	else:
		if _was_moving and sp < speed_walk * 0.9:
			if rig.has_clip("Stop_Run") and _peak_speed > speed_jog * 0.8:
				rig.travel("StopRun")
			elif rig.has_clip("Stop_Walk"):
				rig.travel("StopWalk")
		elif st in ["BlockIn", "BlockIdle"]:
			rig.travel("Move")
		else:
			_idle_t += delta
			_idle_var_t -= delta
			if _idle_t > 3.0 and _idle_var_t <= 0.0 and st == "Move":
				_idle_var_t = randf_range(7.0, 14.0)
				var pick: String = "IdleB" if randf() < 0.5 else "IdleC"
				rig.travel(pick)
			elif st in ["IdleB", "IdleC"] and _idle_var_t <= -4.0:
				rig.travel("Move")
		if has_input:
			var dy2: float = wrapf(want_yaw - yaw, -PI, PI)
			if absf(dy2) > deg_to_rad(65.0) and st == "Move":
				_begin_turn(dy2)
	_prev_speed = sp
	_was_moving = moving
	_last_state = st
	return want_yaw

var _prev_speed := 0.0
var _peak_speed := 0.0
var _still_t := 0.0
var _start_latch := false

func _begin_turn(dy: float) -> void:
	var deg: float = rad_to_deg(absf(dy))
	var right: bool = dy > 0.0
	var name := ""
	if deg > 135.0: name = "Turn_R180" if right else "Turn_L180"
	elif deg > 67.0: name = "Turn_R90" if right else "Turn_L90"
	else: name = "Turn_R45" if right else "Turn_L45"
	var st := name.replace("_", "")
	if not rig.has_clip(name): return
	rig.travel(st)
	_turn_total = maxf(rig.clip_len(name) * 0.72, 0.18)
	_turn_t = _turn_total
	_turn_amount = dy
	turn_started.emit(rad_to_deg(dy), _turn_total)

func turning() -> bool:
	return _turn_t > 0.0

## The blend grid is described by the speed its clips actually carry, measured
## in Blender from each planted-foot stance sweep. Mapping velocity -> blend
## position through those numbers (instead of guessed constants) is what keeps
## the feet matched to the ground.
func _build_speed_table() -> void:
	_row_y = [-2.0, -1.0, 0.0, 1.0, 2.0, 3.0]
	var fwd_clip := ["Jog_B", "Walk_B", "", "Walk_F", "Jog_F", "Sprint_F"]
	var side_clip := ["Jog_R", "Walk_R", "Walk_R", "Walk_R", "Jog_R", "Jog_R"]
	_row_fwd = []
	_row_side = []
	for i in range(_row_y.size()):
		var f := 0.0
		if fwd_clip[i] != "":
			f = absf(rig.clip_ground_vel(fwd_clip[i]).y)
			if f <= 0.01: f = rig.clip_ground_speed(fwd_clip[i])
			if _row_y[i] < 0.0: f = -f
		_row_fwd.append(f)
		var sv := rig.clip_ground_vel(side_clip[i])
		var sl: float = absf(sv.x)
		if sl <= 0.05: sl = maxf(rig.clip_ground_speed(side_clip[i]), 0.5)
		_row_side.append(sl)
	# monotonic guard so the inverse mapping below is always well defined
	for i in range(1, _row_y.size()):
		if _row_fwd[i] <= _row_fwd[i - 1]:
			_row_fwd[i] = _row_fwd[i - 1] + 0.25
	# Every clip shares one cycle length so the blend stays phase-coherent, so
	# the difference between a walk and a sprint is stride *and* cadence. These
	# factors are the cadence each tier is played back at; the ground speed the
	# tier represents is stride x cadence, and the runtime time-scale lands on
	# the same number, which is why the planted foot stays put.
	_row_cad = [1.45, 1.0, 1.0, 1.0, 1.55, 2.05]
	_row_target = []
	_row_side_t = []
	for i in range(_row_y.size()):
		_row_target.append(float(_row_fwd[i]) * float(_row_cad[i]))
		_row_side_t.append(float(_row_side[i]) * float(_row_cad[i]))
	speed_back_walk = absf(_row_target[1])
	speed_back_jog = absf(_row_target[0])
	speed_side = _row_side_t[3]
	speed_side_fast = _row_side_t[4]

func _lerp_rows(arr: Array, y: float) -> float:
	var yc: float = clampf(y, _row_y[0], _row_y[_row_y.size() - 1])
	for i in range(_row_y.size() - 1):
		if yc <= _row_y[i + 1]:
			var t: float = (yc - _row_y[i]) / (_row_y[i + 1] - _row_y[i])
			return lerpf(float(arr[i]), float(arr[i + 1]), t)
	return float(arr[arr.size() - 1])

## Inverse of the forward speed curve: metres per second -> grid row.
func _fwd_axis(fwd: float) -> float:
	if _row_fwd.is_empty(): return 0.0
	var n := _row_y.size()
	if fwd <= _row_target[0]: return _row_y[0]
	if fwd >= _row_target[n - 1]: return _row_y[n - 1]
	for i in range(n - 1):
		if fwd <= _row_target[i + 1]:
			var span: float = maxf(_row_target[i + 1] - _row_target[i], 0.01)
			return lerpf(_row_y[i], _row_y[i + 1], (fwd - _row_target[i]) / span)
	return 0.0

func _side_axis(side: float, y := 0.0) -> float:
	if _row_side.is_empty(): return 0.0
	var s: float = _lerp_rows(_row_side_t, y)
	return clampf(side / maxf(s, 0.2), -1.0, 1.0)

## Ground speed the blended pose carries at grid position (x, y).
func _blend_speed(y: float, x: float) -> float:
	if _row_fwd.is_empty(): return 0.0
	var f: float = _lerp_rows(_row_fwd, y)
	var s: float = _lerp_rows(_row_side, y) * absf(x)
	# the blend is linear, so the carried velocity vectors add linearly too
	f *= 1.0 - absf(x)
	return sqrt(f * f + s * s)

# ---------------------------------------------------------------- actions
func action(clip: String, speed := 1.0, xfade := 0.07) -> bool:
	if not ok(): return false
	return rig.play_action(clip, xfade, speed)

func action_active() -> bool:
	return ok() and rig.action_active()

func abort_reaction() -> void:
	if rig != null: rig.abort_reaction()

func abort_action() -> void:
	if ok(): rig.abort_action()

## Pick the reaction that matches where the hit came from.
func reaction_from(source_world: Vector3, heavy := false) -> void:
	if not ok(): return
	var to: Vector3 = source_world - _host.global_position
	to.y = 0.0
	var dirname := "F"
	if to.length() > 0.05:
		var local: Vector3 = Basis(Vector3.UP, -_host.rotation.y) * to.normalized()
		var ang: float = rad_to_deg(atan2(-local.x, local.z))
		if absf(ang) <= 50.0: dirname = "F"
		elif absf(ang) >= 130.0: dirname = "B"
		elif ang > 0.0: dirname = "R"
		else: dirname = "L"
	var clip := ("HitHeavy_" + dirname) if heavy else ("Hit_" + dirname)
	if not rig.has_clip(clip):
		clip = "HitHeavy_F" if heavy else "Hit_F"
	# slight randomisation so repeated hits never look copied
	rig.play_reaction(clip, randf_range(0.03, 0.06))
	rig.set_action_speed(randf_range(0.92, 1.10))
	_react_lock = 0.12

func stagger(variant := -1) -> void:
	if not ok(): return
	var v: int = variant if variant >= 0 else (0 if randf() < 0.5 else 1)
	rig.play_reaction("Stagger_" + ("A" if v == 0 else "B"), 0.05)

func knockdown() -> void:
	if ok(): rig.travel("Knocked")

func getup() -> void:
	if ok(): rig.travel("GetUp")

func death(variant := -1) -> void:
	if not ok(): return
	var v: int = variant if variant >= 0 else (0 if randf() < 0.5 else 1)
	var st := "DeathA" if v == 0 else "DeathB"
	if not rig.has_clip("Death_" + ("A" if v == 0 else "B")): st = "DeathA"
	rig.abort_action()
	rig.abort_reaction()
	rig.travel(st)

func travel(state: String) -> void:
	if ok(): rig.travel(state)

func loco_state() -> String:
	return rig.loco_state() if ok() else ""

# ---------------------------------------------------------------- look / ik
func look_at_point(p: Vector3) -> void:
	if look != null: look.look_at_point(p)

func look_clear() -> void:
	if look != null: look.clear()

func ankle_gaps() -> Dictionary:
	return foot_ik.debug_ankle_gap() if foot_ik != null else {}

func foot_world(s: String) -> Vector3:
	return foot_ik.foot_world(s) if foot_ik != null else Vector3.ZERO

func ankle_world(s: String) -> Vector3:
	return foot_ik.ankle_world(s) if foot_ik != null else Vector3.ZERO

# ---------------------------------------------------------------- root motion
## Motion-warped root motion: scale the authored travel to cover `want_distance`.
func consume_root_motion(warp := 1.0) -> Vector3:
	if not ok(): return Vector3.ZERO
	var d := rig.root_motion()
	d.y = 0.0
	return (model_root.global_transform.basis * d) * warp

func authored_distance(clip: String) -> float:
	var m := rig.clip_meta(clip)
	if not m.has("root_motion"): return 0.0
	var a: Array = m["root_motion"]
	return Vector2(float(a[0]), float(a[1])).length()

func warp_for(clip: String, want: float) -> float:
	var a := authored_distance(clip)
	if a < 0.05: return 1.0
	return clampf(want / a, 0.25, 4.0)
