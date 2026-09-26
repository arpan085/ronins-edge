class_name Player
extends CharacterBody3D
## Kaito: third-person combat, 4 stances, posture, perfect deflect, combos,
## dodge i-frames, heavy attacks, deathblow, focus slow-motion.

signal died
signal hp_changed(hp: float, max_hp: float)
signal posture_changed(p: float, max_p: float)
signal focus_changed(f: float, max_f: float)
signal stance_changed(name: String)
signal lock_changed(target: Node3D)
signal deathblow_ready(target: Node3D)
signal combat_state_changed(in_combat: bool)

enum S {IDLE, MOVE, ATTACK, BLOCK, DODGE, HIT, STAGGER, DEATHBLOW, DEAD}

# Movement speeds are derived from the Blender clips at runtime (see _build_body)
# so the planted foot always matches the ground. These are only fallbacks.
var WALK_SPEED := 1.8
var RUN_SPEED := 3.6
var SPRINT_SPEED := 5.6
var SIDE_SPEED := 1.6
var BACK_SPEED := 1.2
const ACCEL := 28.0
const FRICTION := 34.0
const GRAVITY := 22.0
const JUMP_V := 8.2

const DEFLECT_WINDOW := 0.24
const DODGE_TIME := 0.58
const IFRAME_START := 0.05
const IFRAME_END := 0.44
const DODGE_SPEED := 8.2
const COMBO_WINDOW := 0.60
const BLOCK_POSTURE_RATE := 12.0
const POSTURE_RECOVER := 9.0
const POSTURE_RECOVER_DELAY := 0.9
const FOCUS_PER_DEFLECT := 22.0
const FOCUS_PER_DODGE := 8.0
const SLOWMO_TIME := 3.0
const SLOWMO_SCALE := 0.35

const ATTACKS := {
	"light1": {"clip": "Light1", "windup": 0.14, "active": 0.10, "total": 0.56, "dmg": 11.0,
		"posture": 13.0, "reach": 2.5, "arc": 120.0, "lunge": 2.4, "heavy": false, "next": "light2"},
	"light2": {"clip": "Light2", "windup": 0.13, "active": 0.10, "total": 0.56, "dmg": 12.0,
		"posture": 14.0, "reach": 2.5, "arc": 130.0, "lunge": 2.2, "heavy": false, "next": "light3"},
	"light3": {"clip": "Light3", "windup": 0.20, "active": 0.13, "total": 0.82, "dmg": 17.0,
		"posture": 20.0, "reach": 2.7, "arc": 150.0, "lunge": 3.0, "heavy": false, "next": ""},
	"heavy": {"clip": "Heavy", "windup": 0.34, "active": 0.16, "total": 1.10, "dmg": 26.0,
		"posture": 36.0, "reach": 3.0, "arc": 160.0, "lunge": 3.4, "heavy": true, "next": ""},
}

var state: int = S.IDLE
var hp := 100.0
var max_hp := 100.0
var posture := 0.0
var max_posture := 100.0
var focus := 0.0
var max_focus := 100.0
var stance := "stone"

var _state_t := 0.0
var _attack: String = ""
var _attack_t := 0.0
var _attack_hit_done := false
var _combo_next: String = ""
var _combo_t := 0.0
var _deflect_t := 0.0
var _blocking := false
var _posture_idle := 0.0
var _footstep_t := 0.0
var _slowmo_t := 0.0
var _dead := false
var _lock_target: Node3D = null
var _lock_scan_t := 0.0
var _in_combat := false
var _combat_t := 0.0
var _hitstop_t := 0.0
var _spirit_blade_t := 0.0
var _dmg_mult := 1.0
var _attack_speed := 1.0

var world: World
var camera: PlayerCamera
var anim: AnimationPlayer
var driver: AnimDriver
var skeleton: Skeleton3D
var trail: SwordTrail
var hurtbox: Area3D
var model_root: Node3D
var _move_vis := 0.0
var _base_speed := 0.0
var _want_yaw := 0.0
var _dodge_clip := "Dodge_F"
var _dodge_dir := Vector3.FORWARD
var _db_target: Node3D = null
var _knocked := false

func _ready() -> void:
	hp = Game.hp; posture = Game.posture; focus = Game.focus; stance = Game.stance
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(58.0)
	_build_body()
	_build_hurtbox()
	state = S.IDLE
	_want_yaw = rotation.y

func _build_body() -> void:
	driver = AnimDriver.new()
	driver.name = "AnimDriver"
	add_child(driver)
	if driver.build(self, "res://assets/models/Kaito_Ronin.glb", "kaito", true):
		anim = driver.anim_player
		skeleton = driver.skeleton
		model_root = driver.model_root
		WALK_SPEED = driver.speed_walk
		RUN_SPEED = driver.speed_jog
		SPRINT_SPEED = driver.speed_sprint
		SIDE_SPEED = driver.speed_side_fast
		BACK_SPEED = driver.speed_back_walk
	else:
		push_error("Kaito rig failed to build")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.72
	cs.shape = cap
	cs.position = Vector3(0, 0.86, 0)
	add_child(cs)
	trail = SwordTrail.new()
	trail.name = "SwordTrail"
	add_child(trail)
	if skeleton != null:
		trail.bind(skeleton, "hand.R")

func _build_hurtbox() -> void:
	hurtbox = Area3D.new()
	hurtbox.name = "Hurtbox"
	hurtbox.collision_layer = 4
	hurtbox.collision_mask = 0
	hurtbox.monitorable = true
	hurtbox.monitoring = false
	hurtbox.add_to_group("player_hurtbox")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	hurtbox.add_child(cs)
	add_child(hurtbox)

func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer: return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null: return r
	return null

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null: return r
	return null

func setup(w: World, cam: PlayerCamera) -> void:
	world = w
	camera = cam

## Back-compatible shim: routes a clip name into the correct animation layer.
func _play(clip: String, blend := 0.18, speed := 1.0) -> void:
	if driver == null or not driver.ok(): return
	if clip == "Idle":
		return
	driver.action(clip, speed, blend)

# ------------------------------------------------------------------ input
func _input_vector() -> Vector2:
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	v += Game.touch_move
	if v.length() > 1.0: v = v.normalized()
	return v

func _wants_sprint() -> bool:
	return Input.is_action_pressed("sprint") or Game.touch_sprint

# ------------------------------------------------------------------ loop
func _physics_process(delta: float) -> void:
	if _dead: return
	if _hitstop_t > 0.0:
		_hitstop_t -= delta
		velocity.x = 0.0; velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		return
	_state_t += delta
	if _slowmo_t > 0.0:
		_slowmo_t -= delta
		if _slowmo_t <= 0.0:
			Engine.time_scale = 1.0
	if _spirit_blade_t > 0.0:
		_spirit_blade_t -= delta
	_update_posture(delta)
	_update_lock(delta)
	_update_combat_flag(delta)
	match state:
		S.IDLE, S.MOVE: _state_locomotion(delta)
		S.ATTACK: _state_attack(delta)
		S.BLOCK: _state_block(delta)
		S.DODGE: _state_dodge(delta)
		S.HIT, S.STAGGER: _state_recover(delta)
		S.DEATHBLOW: _state_deathblow(delta)
	_apply_gravity(delta)
	move_and_slide()
	_tick_anim(delta)

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = -1.0

func _cam_basis() -> Basis:
	if camera == null: return Basis()
	var y := camera.get_yaw()
	return Basis(Vector3.UP, y)

func _desired_dir() -> Vector3:
	var v := _input_vector()
	if v.length() < 0.05: return Vector3.ZERO
	var b := _cam_basis()
	var d := (b * Vector3(v.x, 0, v.y)).normalized()
	return d

## When locked on, the stick still drives where we go; only the facing changes.
func _face_target_dir() -> Vector3:
	if _lock_target == null or not is_instance_valid(_lock_target): return Vector3.ZERO
	if not (state in [S.IDLE, S.MOVE, S.BLOCK]): return Vector3.ZERO
	var to := _lock_target.global_position - global_position
	to.y = 0
	return to.normalized() if to.length() > 0.1 else Vector3.ZERO

func _state_locomotion(delta: float) -> void:
	_attack = ""
	_combo_next = ""
	var v := _input_vector()
	var dir := _desired_dir()
	var target_speed := 0.0
	if v.length() > 0.05:
		target_speed = SPRINT_SPEED if _wants_sprint() else RUN_SPEED
		if v.length() < 0.55 and not _wants_sprint(): target_speed = WALK_SPEED
	var face := _face_target_dir()
	if face != Vector3.ZERO and dir != Vector3.ZERO and not _wants_sprint():
		# strafing: cap speed on an ellipse so we never outrun what the side and
		# backpedal clips can actually carry, which is what causes foot slide
		var fyaw := atan2(face.x, face.z)
		var loc: Vector3 = Basis(Vector3.UP, -fyaw) * dir
		var fw: float = -loc.z
		var sd: float = loc.x
		var fc: float = RUN_SPEED if fw >= 0.0 else BACK_SPEED
		var a: float = absf(fw) / maxf(fc, 0.1)
		var b: float = absf(sd) / maxf(SIDE_SPEED, 0.1)
		var cap: float = 1.0 / maxf(sqrt(a * a + b * b), 0.001)
		target_speed = minf(target_speed, cap)
	var hv := Vector3(velocity.x, 0, velocity.z)
	if dir != Vector3.ZERO:
		hv = hv.move_toward(dir * target_speed, ACCEL * delta)
		if face != Vector3.ZERO:
			_want_yaw = atan2(face.x, face.z)
			_face_dir(face, delta)
		else:
			_want_yaw = atan2(dir.x, dir.z)
			_face_dir(dir, delta)
	else:
		hv = hv.move_toward(Vector3.ZERO, FRICTION * delta)
	velocity.x = hv.x; velocity.z = hv.z
	state = S.MOVE if hv.length() > 0.4 else S.IDLE
	_move_vis = hv.length() / SPRINT_SPEED
	# inputs
	if Input.is_action_just_pressed("attack"):
		_start_attack("light1")
	elif Input.is_action_just_pressed("heavy"):
		_start_attack("heavy")
	elif Input.is_action_just_pressed("dodge"):
		_start_dodge()
	elif Input.is_action_just_pressed("block") or Game.touch_block:
		_begin_block()
	elif Input.is_action_just_pressed("stance"):
		_cycle_stance()
	elif Input.is_action_just_pressed("special"):
		_activate_focus()
	elif Input.is_action_just_pressed("lock_on"):
		_toggle_lock()
	elif Input.is_action_just_pressed("interact"):
		_try_deathblow_or_interact()
	# footsteps
	if is_on_floor() and hv.length() > 1.0:
		_footstep_t -= delta * (0.55 + hv.length() * 0.12)
		if _footstep_t <= 0.0:
			_footstep_t = 0.55
			Audio.play_sfx("footstep", global_position, randf_range(0.9, 1.15), -12.0)

func _face_dir(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01: return
	if driver != null and driver.turning(): return   # the turn clip owns rotation
	var target := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, target, clampf(delta * 12.0, 0.0, 1.0))

func _update_anim_locomotion() -> void:
	pass

func _tick_anim(delta: float) -> void:
	if driver == null or not driver.ok(): return
	var grounded := is_on_floor()
	var has_in := _input_vector().length() > 0.05
	var allow: bool = state in [S.IDLE, S.MOVE] and not _knocked
	var yaw := driver.tick(delta, velocity, _want_yaw, has_in, grounded, _blocking, allow)
	if driver.turning():
		rotation.y = yaw
	_move_vis = Vector3(velocity.x, 0, velocity.z).length() / maxf(SPRINT_SPEED, 0.1)
	var t: Node3D = _lock_target
	if t == null or not is_instance_valid(t):
		t = _nearest_enemy(16.0)
	if t != null:
		driver.look_at_point(t.global_position + Vector3(0, 1.35, 0))
	else:
		driver.look_clear()

func _nearest_enemy(rng: float) -> Node3D:
	if world == null: return null
	var best: Node3D = null
	var bd := rng
	for e in world.enemies:
		if not is_instance_valid(e) or e.is_dead: continue
		var d: float = e.global_position.distance_to(global_position)
		if d < bd:
			bd = d; best = e
	return best

# ------------------------------------------------------------------ attack
func _start_attack(key: String) -> void:
	if not ATTACKS.has(key): return
	_attack = key
	_attack_t = 0.0
	_attack_hit_done = false
	state = S.ATTACK
	_state_t = 0.0
	var a: Dictionary = ATTACKS[key]
	var clip := String(a["clip"])
	var spd: float = _attack_speed * float(Game.stance_info()["spd"])
	var clen: float = driver.rig.clip_len(clip) if driver != null and driver.ok() else 0.0
	if clen > 0.05:
		spd = clen / maxf(float(a["total"]), 0.1) * spd
	driver.action(clip, spd, 0.06)
	Audio.play_sfx("swing", global_position, randf_range(0.9, 1.15), -6.0)
	trail.start()

func _state_attack(delta: float) -> void:
	var a: Dictionary = ATTACKS[_attack]
	var spd := _attack_speed * float(Game.stance_info()["spd"])
	_attack_t += delta * spd
	var total: float = float(a["total"]) / spd
	var hv := Vector3(velocity.x, 0, velocity.z)
	var fwd := global_transform.basis.z
	if _attack_t < float(a["windup"]):
		hv = hv.move_toward(fwd * float(a["lunge"]) * 0.25, 16.0 * delta)
	elif _attack_t < float(a["windup"]) + float(a["active"]):
		hv = hv.move_toward(fwd * float(a["lunge"]), 40.0 * delta)
		if not _attack_hit_done:
			_attack_hit_done = true
			_do_hit_scan(a)
	else:
		hv = hv.move_toward(Vector3.ZERO, 18.0 * delta)
	velocity.x = hv.x; velocity.z = hv.z
	if _attack_t >= total:
		trail.stop()
		_combo_next = String(a["next"])
		_combo_t = COMBO_WINDOW
		state = S.IDLE
		_state_t = 0.0
	# allow queuing the next combo hit
	if Input.is_action_just_pressed("attack") and _attack_t > float(a["windup"]) + float(a["active"]) * 0.5:
		if _combo_next == "":
			_combo_next = String(a["next"])
		if _combo_next != "" and ATTACKS.has(_combo_next):
			_start_attack(_combo_next)
	if Input.is_action_just_pressed("dodge") and _attack_t > float(a["windup"]):
		trail.stop()
		_start_dodge()

func _do_hit_scan(a: Dictionary) -> void:
	var reach: float = float(a["reach"])
	var arc: float = float(a["arc"])
	var info := {
		"damage": float(a["dmg"]) * _dmg_mult * float(Game.stance_info()["dmg"]),
		"posture": float(a["posture"]) * float(Game.stance_info()["posture"]),
		"heavy": bool(a["heavy"]),
		"spirit": _spirit_blade_t > 0.0,
		"source": self,
	}
	var hits := _scan_hurtboxes(reach, arc, "enemy_hurtbox")
	for h in hits:
		var owner_node = h.get_parent()
		if owner_node != null and owner_node.has_method("take_hit"):
			owner_node.take_hit(info)
			_hitstop(0.055 if not info["heavy"] else 0.09)
			if world != null and world.hud != null:
				world.hud.flash_hit()
		if hits.size() > 0:
			Audio.play_sfx("impact", global_position, randf_range(0.9, 1.1), -4.0)

func _scan_hurtboxes(reach: float, arc: float, group: String) -> Array:
	var space := get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = reach
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	var fwd := global_transform.basis.z
	params.transform = Transform3D(Basis(), global_position + Vector3(0, 1.05, 0) + fwd * reach * 0.55)
	params.collision_mask = 4
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var out := []
	for r in space.intersect_shape(params, 12):
		var c = r.get("collider")
		if c == null or not (c is Area3D): continue
		if not c.is_in_group(group): continue
		var parent = c.get_parent()
		if parent == null or parent == self: continue
		var to = (parent.global_position + Vector3(0, 1.0, 0)) - (global_position + Vector3(0, 1.05, 0))
		to.y = 0
		if to.length() > 0.05 and rad_to_deg(fwd.angle_to(to.normalized())) > arc * 0.5:
			continue
		out.append(c)
	return out

# ------------------------------------------------------------------ block / deflect
func _begin_block() -> void:
	state = S.BLOCK
	_blocking = true
	_deflect_t = DEFLECT_WINDOW
	_state_t = 0.0
	if driver != null: driver.action("Deflect", 1.0, 0.04)
	Audio.play_sfx("deflect", global_position, 0.75, -14.0)

func _state_block(delta: float) -> void:
	_deflect_t = maxf(0.0, _deflect_t - delta)
	var hv := Vector3(velocity.x, 0, velocity.z)
	hv = hv.move_toward(Vector3.ZERO, 30.0 * delta)
	velocity.x = hv.x; velocity.z = hv.z
	if _lock_target != null and is_instance_valid(_lock_target):
		var to := _lock_target.global_position - global_position
		to.y = 0
		_face_dir(to.normalized(), delta * 1.5)
	var held := Input.is_action_pressed("block") or Game.touch_block
	if not held and _state_t > 0.12:
		_blocking = false
		state = S.IDLE
	if _state_t > 0.22 and _deflect_t <= 0.0 and held and driver != null:
		driver.travel("BlockIn")

func is_perfect_deflect() -> bool:
	return state == S.BLOCK and _deflect_t > 0.0

# ------------------------------------------------------------------ dodge
func _start_dodge() -> void:
	state = S.DODGE
	_state_t = 0.0
	_blocking = false
	var dir := _desired_dir()
	if dir == Vector3.ZERO: dir = global_transform.basis.z
	_dodge_dir = dir
	var local: Vector3 = Basis(Vector3.UP, -rotation.y) * dir
	var ang: float = rad_to_deg(atan2(-local.x, local.z))
	var clip := "Dodge_F"
	if absf(ang) >= 135.0: clip = "Dodge_B"
	elif ang > 45.0: clip = "Dodge_R"
	elif ang < -45.0: clip = "Dodge_L"
	if clip == "Dodge_F" and _wants_sprint() and driver != null and driver.rig.has_clip("Roll_F"):
		clip = "Roll_F"
	_dodge_clip = clip
	if driver != null:
		var cl: float = driver.rig.clip_len(clip)
		driver.action(clip, (cl / DODGE_TIME) if cl > 0.05 else 1.0, 0.05)
	Audio.play_sfx("swing", global_position, 0.7, -16.0)
	Audio.haptic("hit")

func _state_dodge(delta: float) -> void:
	var dir := _dodge_dir
	var t := _state_t / DODGE_TIME
	var curve := 1.0 if t < 0.45 else maxf(0.0, 1.0 - (t - 0.45) / 0.55)
	var spd := DODGE_SPEED * curve
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	if _state_t >= DODGE_TIME:
		state = S.IDLE

func has_iframes() -> bool:
	return state == S.DODGE and _state_t >= IFRAME_START and _state_t <= IFRAME_END

# ------------------------------------------------------------------ reactions
func _state_recover(delta: float) -> void:
	var hv := Vector3(velocity.x, 0, velocity.z)
	hv = hv.move_toward(Vector3.ZERO, 22.0 * delta)
	velocity.x = hv.x; velocity.z = hv.z
	var dur := 0.55 if state == S.HIT else 0.95
	if _state_t >= dur:
		state = S.IDLE

func take_hit(info: Dictionary) -> void:
	if _dead: return
	if has_iframes():
		_float_text("dodge", Color(0.7, 0.9, 1.0))
		_add_focus(FOCUS_PER_DODGE)
		return
	var dmg := float(info.get("damage", 10.0))
	if is_perfect_deflect():
		_perfect_deflect(info)
		return
	if state == S.BLOCK:
		dmg *= 0.22
		_add_posture(float(info.get("posture", 10.0)) * 0.75)
		Audio.play_sfx("deflect", global_position, 1.15, -8.0)
		Audio.haptic("hit")
		_damage(dmg, false)
		if _dead: return
		_hitstop(0.05)
		return
	_damage(dmg, true)
	if _dead: return
	_add_posture(float(info.get("posture", 10.0)) * 0.5)
	if posture >= max_posture:
		_enter_stagger()
	else:
		state = S.HIT
		_state_t = 0.0
		if driver != null:
			var src2 = info.get("source")
			var sp: Vector3 = global_position + global_transform.basis.z * 2.0
			if src2 != null and is_instance_valid(src2) and src2 is Node3D:
				sp = src2.global_position
			driver.reaction_from(sp, bool(info.get("heavy", false)))
	_hitstop(0.07)

func _perfect_deflect(info: Dictionary) -> void:
	Audio.play_sfx("deflect", global_position, 1.0, 0.0)
	Audio.haptic("deflect")
	_add_focus(FOCUS_PER_DEFLECT)
	_damage(0.0, false)
	var src = info.get("source")
	if src != null and is_instance_valid(src) and src.has_method("on_deflected"):
		src.on_deflected(self)
	if world != null and world.hud != null:
		world.hud.deflect_flash()
	if focus >= max_focus:
		Game.notice.emit("Focus ready — press Special for slow motion", "focus")
	_float_text("DEFLECT", Color(1.0, 0.95, 0.7))
	Quests.progress("deflect", "", 1)

func _damage(v: float, react: bool) -> void:
	if v > 0.0:
		hp = maxf(0.0, hp - v)
		Game.hp = hp
		hp_changed.emit(hp, max_hp)
		if react and world != null and world.hud != null:
			world.hud.damage_flash(v)
		if world != null and world.hitfx != null:
			world.hitfx.label(global_position, "-%d" % int(round(v)), Color(1.0, 0.45, 0.4))
	if hp <= 0.0:
		_die()

func _add_posture(v: float) -> void:
	posture = clampf(posture + v, 0.0, max_posture)
	_posture_idle = 0.0
	Game.posture = posture
	posture_changed.emit(posture, max_posture)

func _update_posture(delta: float) -> void:
	_posture_idle += delta
	if _posture_idle > POSTURE_RECOVER_DELAY and state != S.BLOCK:
		var rate := POSTURE_RECOVER * (1.0 + float(Game.stance_info()["posture"]) * 0.2)
		posture = maxf(0.0, posture - rate * delta)
		Game.posture = posture
		posture_changed.emit(posture, max_posture)

func _enter_stagger() -> void:
	state = S.STAGGER
	_state_t = 0.0
	posture = 0.0
	Game.posture = 0.0
	if driver != null: driver.stagger()
	Audio.play_sfx("posture_break", global_position, 1.0, -2.0)
	Audio.haptic("heavy")
	Game.notice.emit("Posture broken!", "warn")

func _add_focus(v: float) -> void:
	focus = clampf(focus + v, 0.0, max_focus)
	Game.focus = focus
	focus_changed.emit(focus, max_focus)

func _activate_focus() -> void:
	if focus < max_focus: 
		Game.notice.emit("Focus not ready", "warn")
		return
	focus = 0.0
	Game.focus = 0.0
	focus_changed.emit(focus, max_focus)
	_slowmo_t = SLOWMO_TIME
	Engine.time_scale = SLOWMO_SCALE
	_spirit_blade_t = 10.0
	_dmg_mult = 1.35
	Audio.play_sfx("heal", global_position, 0.8, -3.0)
	Game.notice.emit("Spirit Blade — time slows, damage up", "focus")

func _die() -> void:
	if _dead: return
	_dead = true
	state = S.DEAD
	Engine.time_scale = 1.0
	if driver != null: driver.death()
	velocity = Vector3.ZERO
	died.emit()

func revive() -> void:
	_dead = false
	hp = max_hp
	posture = 0.0
	focus = 0.0
	_dmg_mult = 1.0
	_spirit_blade_t = 0.0
	Engine.time_scale = 1.0
	state = S.IDLE
	_play("Idle", 0.2)
	hp_changed.emit(hp, max_hp)

func _hitstop(dur: float) -> void:
	_hitstop_t = maxf(_hitstop_t, dur)
	if camera != null:
		camera.shake(0.14 if dur < 0.07 else 0.24)

# ------------------------------------------------------------------ lock on / deathblow
func _toggle_lock() -> void:
	if _lock_target != null:
		_lock_target = null
		lock_changed.emit(null)
		return
	var best: Node3D = null
	var bd := 1e9
	if world == null: return
	for e in world.enemies:
		if not is_instance_valid(e) or e.is_dead: continue
		var d: float = e.global_position.distance_to(global_position)
		if d > 18.0: continue
		var to: Vector3 = (e.global_position - global_position).normalized()
		var fwd := global_transform.basis.z
		if fwd.dot(to) < 0.1: continue
		if d < bd: bd = d; best = e
	_lock_target = best
	lock_changed.emit(best)

func _update_lock(delta: float) -> void:
	if _lock_target != null and (not is_instance_valid(_lock_target) or _lock_target.is_dead):
		_lock_target = null
		lock_changed.emit(null)
	_lock_scan_t -= delta
	if _lock_target == null and _lock_scan_t <= 0.0:
		_lock_scan_t = 0.4

func locked_target() -> Node3D:
	return _lock_target

func _try_deathblow_or_interact() -> void:
	if world == null: return
	# deathblow first
	for e in world.enemies:
		if not is_instance_valid(e) or e.is_dead: continue
		if e.posture_broken and e.global_position.distance_to(global_position) < 3.6:
			_start_deathblow(e)
			return
	Game.notice.emit("Nothing to interact with", "warn")

func _start_deathblow(target: Node3D) -> void:
	state = S.DEATHBLOW
	_state_t = 0.0
	_db_target = target
	if driver != null: driver.action("Deathblow", 1.0, 0.06)
	Audio.play_sfx("deathblow", global_position, 1.0, 0.0)
	Audio.haptic("deathblow")
	var to := target.global_position - global_position
	to.y = 0
	_face_dir(to.normalized(), 1.0)
	if camera != null: camera.shake(0.35)
	if target.has_method("execute"):
		target.execute(self)

func _state_deathblow(delta: float) -> void:
	var hv := Vector3(velocity.x, 0, velocity.z)
	# close the remaining gap during the thrust so the blade actually connects
	if _db_target != null and is_instance_valid(_db_target) and _state_t < 0.55:
		var to: Vector3 = _db_target.global_position - global_position
		to.y = 0.0
		var d: float = to.length()
		if d > 1.35:
			hv = to.normalized() * clampf((d - 1.25) / 0.45, 0.0, 4.2)
		else:
			hv = hv.move_toward(Vector3.ZERO, 30.0 * delta)
		_want_yaw = atan2(to.x, to.z)
		rotation.y = lerp_angle(rotation.y, _want_yaw, clampf(delta * 14.0, 0.0, 1.0))
	else:
		hv = hv.move_toward(Vector3.ZERO, 30.0 * delta)
	velocity.x = hv.x; velocity.z = hv.z
	if _state_t > 1.75:
		state = S.IDLE
		_db_target = null

func deathblow_available() -> Node3D:
	if world == null: return null
	for e in world.enemies:
		if is_instance_valid(e) and not e.is_dead and e.posture_broken:
			if e.global_position.distance_to(global_position) < 3.6: return e
	return null

# ------------------------------------------------------------------ misc
func _cycle_stance() -> void:
	Game.cycle_stance(1)
	stance = Game.stance
	Audio.haptic("stance")
	Audio.play_sfx("ui", null, 1.2, -10.0)
	stance_changed.emit(stance)
	_float_text(String(Game.stance_info()["name"]), Color(0.9, 0.85, 0.6))

func _float_text(text: String, color: Color) -> void:
	if world != null and world.hitfx != null:
		world.hitfx.label(global_position, text, color)

func _update_combat_flag(delta: float) -> void:
	var n := 0
	if world != null:
		for e in world.enemies:
			if is_instance_valid(e) and not e.is_dead and e.in_combat and e.global_position.distance_to(global_position) < 25.0:
				n += 1
	var now := n > 0
	if now != _in_combat:
		_in_combat = now
		combat_state_changed.emit(now)
		Audio.set_combat(now)

func is_in_combat() -> bool:
	return _in_combat

func hp_ratio() -> float:
	return hp / max_hp
