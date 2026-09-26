class_name EnemyBase
extends CharacterBody3D
## Shared enemy AI: idle/patrol/detect/chase/attack/recover/stagger/death,
## attack telegraphs, posture, hurtbox, spacing tokens and deflect reactions.

signal died(kind: String, zone: String)
signal posture_changed(cur: float, maxp: float)
signal hp_changed(cur: float, maxp: float)

enum S {IDLE, PATROL, INVESTIGATE, ALERT, CHASE, COMBAT_READY, ATTACK, RECOVER,
	STAGGER, KNOCKDOWN, RETURN, DEAD}
const DETECT := S.ALERT      # legacy alias

static var attackers := 0
const MAX_ATTACKERS := 2

var kind := "ashigaru"
var spawn_id := ""
var zone := "shrine"
var is_boss := false

var hp := 55.0
var max_hp := 55.0
var posture := 0.0
var max_posture := 60.0
var posture_broken := false
var is_dead := false
var death_timer := 0.0
var in_combat := false

var detect_radius := 18.0
var lose_radius := 34.0
var move_speed := 3.2
var attack_range := 2.8
var windup := 0.55
var active_time := 0.14
var recover_time := 0.85
var cooldown := 1.5
var damage := 14.0
var posture_dmg := 16.0
var reach := 2.6
var arc := 120.0
var combo_chance := 0.25

var state: int = S.IDLE
var _t := 0.0
var _cd := 0.0
var _stagger_t := 0.0
var _has_token := false
var _patrol_origin := Vector3.ZERO
var _patrol_target := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _attack_hit_done := false
var _attack_index := 0
var _hit_flash := 0.0
var _want_yaw := 0.0
var _knock_t := 0.0
var _alert_t := 0.0
var _suspicion := 0.0
var _circle_dir := 1.0
var _idle_variant := 0
var _attack_started := false
var _stagger_started := false

var world: World
var player: Player
var anim: AnimationPlayer
var driver: AnimDriver
var skeleton: Skeleton3D
var hurtbox: Area3D
var model_root: Node3D
var _telegraph: MeshInstance3D
var _telegraph_mat: StandardMaterial3D
var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D
var _weapon_mesh: MeshInstance3D

func _ready() -> void:
	_rng.seed = hash(spawn_id) + 991
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(58.0)
	_configure()
	_build_body()
	_build_hurtbox()
	_build_telegraph()
	_patrol_origin = global_position
	_want_yaw = rotation.y
	_circle_dir = 1.0 if _rng.randf() < 0.5 else -1.0
	state = S.IDLE

# ---- overridable ----
func _configure() -> void:
	pass
func _model_path() -> String:
	return "res://assets/models/Ashigaru_Ronin.glb"
func _perform_attack() -> void:
	pass

func _build_body() -> void:
	driver = AnimDriver.new()
	driver.name = "AnimDriver"
	add_child(driver)
	if driver.build(self, _model_path(), kind, false):
		anim = driver.anim_player
		skeleton = driver.skeleton
		model_root = driver.model_root
		_weapon_mesh = _find_weapon(model_root)
		move_speed = clampf(move_speed, driver.speed_walk * 0.8, driver.speed_jog * 1.5)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.72
	cs.shape = cap
	cs.position = Vector3(0, 0.86, 0)
	add_child(cs)

func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls or (cls == "AnimationPlayer" and n is AnimationPlayer) or (cls == "Skeleton3D" and n is Skeleton3D):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null: return r
	return null

func _find_weapon(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and String(n.name).to_lower().contains("weapon"):
		return n
	for c in n.get_children():
		var r := _find_weapon(c)
		if r != null: return r
	return null

func _build_hurtbox() -> void:
	hurtbox = Area3D.new()
	hurtbox.name = "Hurtbox"
	hurtbox.collision_layer = 4
	hurtbox.collision_mask = 0
	hurtbox.monitoring = false
	hurtbox.monitorable = true
	hurtbox.add_to_group("enemy_hurtbox")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.46
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	hurtbox.add_child(cs)
	add_child(hurtbox)

func _build_telegraph() -> void:
	_telegraph = MeshInstance3D.new()
	_telegraph.name = "Telegraph"
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	_telegraph.mesh = q
	_telegraph_mat = StandardMaterial3D.new()
	_telegraph_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_telegraph_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_telegraph_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_telegraph_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_telegraph_mat.albedo_color = Color(0.9, 0.25, 0.12, 0.0)
	_telegraph_mat.disable_receive_shadows = true
	_telegraph.material_override = _telegraph_mat
	_telegraph.rotation_degrees = Vector3(-90, 0, 0)
	_telegraph.position = Vector3(0, 0.06, -1.3)
	_telegraph.visible = false
	add_child(_telegraph)

	_marker = MeshInstance3D.new()
	_marker.name = "Marker"
	var sp := SphereMesh.new()
	sp.radius = 0.11
	sp.height = 0.22
	_marker.mesh = sp
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_mat.albedo_color = Color(1, 0.3, 0.2, 0.0)
	_marker.material_override = _marker_mat
	_marker.position = Vector3(0, 2.05, 0)
	_marker.visible = false
	add_child(_marker)

func setup(w: World, p: Player) -> void:
	world = w
	player = p

func _play(clip: String, blend := 0.18, speed := 1.0) -> void:
	if driver == null or not driver.ok(): return
	if clip == "Idle" or clip == "Walk" or clip == "Run": return
	driver.action(clip, speed, blend)

## Feed movement into the animation tree; returns the yaw to adopt.
func _anim_tick(delta: float, allow_loco := true) -> void:
	if driver == null or not driver.ok(): return
	var yaw := driver.tick(delta, velocity, _want_yaw,
		Vector3(velocity.x, 0, velocity.z).length() > 0.2, is_on_floor(), false, allow_loco)
	if driver.turning():
		rotation.y = yaw
	if player != null and is_instance_valid(player) and in_combat:
		driver.look_at_point(player.global_position + Vector3(0, 1.35, 0))
	else:
		driver.look_clear()

# ------------------------------------------------------------------ AI
func _physics_process(delta: float) -> void:
	if _hit_flash > 0.0:
		_hit_flash -= delta
	if is_dead:
		death_timer += delta
		velocity.x = 0.0; velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		_anim_tick(delta, false)
		return
	if player == null or not is_instance_valid(player): return
	_t += delta
	_cd = maxf(0.0, _cd - delta)
	var pp := player.global_position
	var dist := global_position.distance_to(pp)
	match state:
		S.IDLE:
			_idle(delta, dist)
		S.PATROL:
			_patrol(delta, dist)
		S.INVESTIGATE:
			_investigate(delta, pp, dist)
		S.ALERT:
			_alert(delta, pp, dist)
		S.CHASE:
			_chase(delta, pp, dist)
		S.COMBAT_READY:
			_combat_ready(delta, pp, dist)
		S.ATTACK:
			_attack_state(delta, pp)
		S.RECOVER:
			_recover(delta, pp, dist)
		S.STAGGER:
			_stagger(delta)
		S.KNOCKDOWN:
			_knockdown_state(delta)
		S.RETURN:
			_return_to_patrol(delta, dist)
	_apply_gravity(delta)
	move_and_slide()
	var loco_ok: bool = state not in [S.ATTACK, S.STAGGER, S.KNOCKDOWN, S.DEAD]
	_anim_tick(delta, loco_ok)
	_update_telegraph(delta)

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	elif velocity.y < 0.0:
		velocity.y = -1.0

func _set_state(s: int) -> void:
	if state == S.ATTACK and s != S.ATTACK:
		_release_token()
		_telegraph.visible = false
	state = s
	_t = 0.0

func _idle(delta: float, dist: float) -> void:
	velocity.x = lerpf(velocity.x, 0.0, 8.0 * delta)
	velocity.z = lerpf(velocity.z, 0.0, 8.0 * delta)
	if is_boss and driver != null and driver.rig.has_clip("Idle_Boss"):
		driver.travel("IdleBoss")
	if dist < detect_radius:
		_begin_alert()
	elif dist < detect_radius * 1.55:
		_suspicion += delta
		if _suspicion > 0.8:
			_suspicion = 0.0
			_set_state(S.INVESTIGATE)
	elif _t > 3.0:
		_patrol_target = _patrol_origin + Vector3(_rng.randf_range(-8, 8), 0, _rng.randf_range(-8, 8))
		_set_state(S.PATROL)

func _begin_alert() -> void:
	in_combat = true
	_alert_t = 0.0
	_set_state(S.ALERT)
	if driver != null:
		if is_boss and driver.rig.has_clip("Intimidate"):
			driver.action("Intimidate", 1.0, 0.12)
		elif driver.rig.has_clip("Alert"):
			driver.action("Alert", 1.0, 0.10)
	Audio.play_sfx("enemy_attack", global_position, 1.35, -12.0)

func _investigate(delta: float, pp: Vector3, dist: float) -> void:
	velocity.x = lerpf(velocity.x, 0.0, 7.0 * delta)
	velocity.z = lerpf(velocity.z, 0.0, 7.0 * delta)
	if driver != null and driver.rig.has_clip("Investigate"):
		driver.travel("Investigate")
	if dist < detect_radius:
		_begin_alert()
		return
	if _t > 3.4:
		if driver != null: driver.travel("Move")
		_set_state(S.RETURN)

func _alert(delta: float, pp: Vector3, dist: float) -> void:
	velocity.x = lerpf(velocity.x, 0.0, 9.0 * delta)
	velocity.z = lerpf(velocity.z, 0.0, 9.0 * delta)
	_face_towards(pp, delta, 5.0)
	_alert_t += delta
	var hold: float = 1.6 if is_boss else 0.75
	if _alert_t > hold:
		if is_boss and driver != null and driver.rig.has_clip("EnterCombat"):
			driver.action("EnterCombat", 1.0, 0.14)
		_set_state(S.CHASE)

func _return_to_patrol(delta: float, dist: float) -> void:
	if dist < detect_radius:
		_begin_alert()
		return
	var to := _patrol_origin - global_position
	to.y = 0
	if to.length() < 1.4 or _t > 8.0:
		in_combat = false
		_set_state(S.IDLE)
		return
	_move_dir(to.normalized(), driver.speed_walk if driver != null else 1.4, delta)

func _patrol(delta: float, dist: float) -> void:
	if dist < detect_radius:
		_begin_alert()
		return
	if dist < detect_radius * 1.55:
		_suspicion += delta
		if _suspicion > 1.1:
			_suspicion = 0.0
			_set_state(S.INVESTIGATE)
			return
	var to := _patrol_target - global_position
	to.y = 0
	if to.length() < 1.2 or _t > 7.0:
		_set_state(S.IDLE)
		return
	_move_dir(to.normalized(), (driver.speed_walk if driver != null else 1.4), delta)

func _chase(delta: float, pp: Vector3, dist: float) -> void:
	if dist > lose_radius:
		in_combat = false
		_set_state(S.RETURN)
		return
	_face_towards(pp, delta, 4.0)
	var want := attack_range * 0.92
	var to := pp - global_position
	to.y = 0
	var dir := to.normalized()
	# separation from other enemies so groups do not clump
	var sep := Vector3.ZERO
	if world != null:
		for e in world.enemies:
			if e == self or not is_instance_valid(e) or e.is_dead: continue
			var d := global_position.distance_to(e.global_position)
			if d < 2.6 and d > 0.01:
				sep += (global_position - e.global_position).normalized() * (2.6 - d) * 0.6
	if dist > want:
		_move_dir((dir + sep).normalized(), move_speed, delta)
	else:
		_set_state(S.COMBAT_READY)

func _combat_ready(delta: float, pp: Vector3, dist: float) -> void:
	if dist > lose_radius:
		in_combat = false
		_set_state(S.RETURN)
		return
	_face_towards(pp, delta, 6.0)
	var to := pp - global_position
	to.y = 0
	var dir := to.normalized()
	var sep := Vector3.ZERO
	if world != null:
		for e in world.enemies:
			if e == self or not is_instance_valid(e) or e.is_dead: continue
			var d := global_position.distance_to(e.global_position)
			if d < 2.8 and d > 0.01:
				sep += (global_position - e.global_position).normalized() * (2.8 - d) * 0.7
	if dist > attack_range * 1.25:
		_set_state(S.CHASE)
		return
	# circle at spacing; waiting enemies read as patient rather than frozen
	var strafe := Vector3(-dir.z, 0, dir.x) * _circle_dir
	var push := dir * (0.0 if dist > attack_range * 0.85 else -0.8)
	var mv := (strafe * 0.7 + push + sep)
	if mv.length() > 0.05:
		_move_dir(mv.normalized(), driver.speed_walk * 0.9 if driver != null else 1.3, delta)
	else:
		_move_dir(Vector3.ZERO, 0.0, delta)
	if _t > 2.2:
		_circle_dir = -_circle_dir
		_t = 0.0
	if _cd <= 0.0 and dist <= attack_range * 1.15:
		if _take_token():
			_has_token = true
			_attack_hit_done = false
			_attack_started = false
			_attack_index = 0
			_set_state(S.ATTACK)
			Audio.play_sfx("enemy_attack", global_position, randf_range(0.9, 1.15), -6.0)

func _attack_state(delta: float, pp: Vector3) -> void:
	velocity.x = lerpf(velocity.x, 0.0, 10.0 * delta)
	velocity.z = lerpf(velocity.z, 0.0, 10.0 * delta)
	if _t < windup:
		_face_towards(pp, delta, 3.0)
		if not _attack_started:
			_attack_started = true
			var clip := _attack_clip()
			var sp := 1.0
			if driver != null and driver.ok():
				var cl := driver.rig.clip_len(clip)
				if cl > 0.05:
					sp = cl / maxf(windup + active_time + recover_time, 0.2)
				driver.action(clip, clampf(sp, 0.55, 1.9), 0.08)
	elif _t < windup + active_time:
		if not _attack_hit_done:
			_attack_hit_done = true
			_perform_attack()
	else:
		_release_token()
		_cd = cooldown * _rng.randf_range(0.8, 1.25)
		_set_state(S.RECOVER)

func _recover(delta: float, pp: Vector3, dist: float) -> void:
	velocity.x = lerpf(velocity.x, 0.0, 6.0 * delta)
	velocity.z = lerpf(velocity.z, 0.0, 6.0 * delta)
	_face_towards(pp, delta, 2.0)
	if _t > recover_time:
		_set_state(S.COMBAT_READY)

func _stagger(delta: float) -> void:
	velocity.x = lerpf(velocity.x, 0.0, 8.0 * delta)
	velocity.z = lerpf(velocity.z, 0.0, 8.0 * delta)
	_stagger_t += delta
	if not _stagger_started:
		_stagger_started = true
		if driver != null: driver.stagger()
	if _stagger_t > 5.0:
		posture_broken = false
		posture = max_posture * 0.5
		posture_changed.emit(posture, max_posture)
		_stagger_started = false
		_set_state(S.COMBAT_READY)

func _knockdown_state(delta: float) -> void:
	velocity.x = lerpf(velocity.x, 0.0, 10.0 * delta)
	velocity.z = lerpf(velocity.z, 0.0, 10.0 * delta)
	_knock_t += delta
	if _knock_t > 2.1:
		_knock_t = 0.0
		if driver != null: driver.getup()
		_set_state(S.COMBAT_READY)

func knock_down() -> void:
	if is_dead or state == S.KNOCKDOWN: return
	if driver != null: driver.knockdown()
	_knock_t = 0.0
	_release_token()
	_set_state(S.KNOCKDOWN)

func _move_dir(dir: Vector3, speed: float, delta: float) -> void:
	var hv := Vector3(velocity.x, 0, velocity.z)
	hv = hv.move_toward(dir * speed, 18.0 * delta)
	velocity.x = hv.x; velocity.z = hv.z

func _face_towards(p: Vector3, delta: float, rate: float) -> void:
	var to := p - global_position
	to.y = 0
	if to.length() < 0.05: return
	var target := atan2(to.x, to.z)
	_want_yaw = target
	if driver != null and driver.turning(): return
	rotation.y = lerp_angle(rotation.y, target, clampf(delta * rate, 0.0, 1.0))

func _attack_clip() -> String:
	return "Attack"

# ------------------------------------------------------------------ tokens
func _take_token() -> bool:
	if attackers < MAX_ATTACKERS:
		attackers += 1
		return true
	return false

func _release_token() -> void:
	if _has_token:
		_has_token = false
		attackers = maxi(0, attackers - 1)

# ------------------------------------------------------------------ telegraph
func _update_telegraph(delta: float) -> void:
	var show := state == S.ATTACK and _t < windup
	_marker.visible = show or state == S.STAGGER or in_combat
	_telegraph.visible = show
	if show:
		var p := clampf(_t / maxf(windup, 0.05), 0.0, 1.0)
		_telegraph_mat.albedo_color = Color(0.95, 0.30, 0.10, 0.10 + p * 0.42)
		var w := reach * (1.4 + p * 0.5)
		_telegraph.scale = Vector3(w, 1.0, 1.0)
		_telegraph.position = Vector3(0, 0.06, -reach * 0.55)
	if _marker.visible:
		var m := 0.35 + 0.35 * sin(_t * 6.0)
		if state == S.STAGGER:
			_marker_mat.albedo_color = Color(1.0, 0.85, 0.2, 0.85)
		elif in_combat:
			_marker_mat.albedo_color = Color(1.0, 0.25, 0.15, m)
		else:
			_marker_mat.albedo_color = Color(1.0, 0.8, 0.3, m * 0.4)
	if _weapon_mesh != null:
		var glow := 0.0
		if state == S.ATTACK and _t < windup:
			glow = clampf(_t / maxf(windup, 0.05), 0.0, 1.0)
		_weapon_mesh.scale = Vector3.ONE * (1.0 + glow * 0.06)

# ------------------------------------------------------------------ combat
func take_hit(info: Dictionary) -> void:
	if is_dead: return
	var dmg := float(info.get("damage", 10.0))
	if posture_broken:
		dmg *= 1.6
	hp = maxf(0.0, hp - dmg)
	hp_changed.emit(hp, max_hp)
	if not posture_broken:
		posture = clampf(posture + float(info.get("posture", 10.0)), 0.0, max_posture)
		posture_changed.emit(posture, max_posture)
	in_combat = true
	if world != null and world.hitfx != null:
		world.hitfx.burst(global_position + Vector3(0, 1.1, 0), "blood" if dmg > 14.0 else "spark")
		world.hitfx.label(global_position, "%d" % int(round(dmg)), Color(1.0, 0.95, 0.6))
	if hp <= 0.0:
		_die()
		return
	if posture >= max_posture and not posture_broken:
		_break_posture()
	elif state in [S.IDLE, S.PATROL, S.CHASE, S.RECOVER] and dmg > 6.0:
		# light hit reaction: brief flinch, keeps combat readable
		_hit_flash = 0.12

func _break_posture() -> void:
	posture_broken = true
	posture = max_posture
	_release_token()
	_set_state(S.STAGGER)
	_stagger_t = 0.0
	Audio.play_sfx("posture_break", global_position, 1.0, -2.0)
	if world != null:
		if world.hitfx != null:
			world.hitfx.burst(global_position + Vector3(0, 1.2, 0), "posture")
		if world.hud != null:
			world.hud.notify_posture_break(self)
	Game.notice.emit("%s's posture broken — Deathblow available" % kind.capitalize(), "warn")

func on_deflected(deflector: Node) -> void:
	# a perfect deflect staggers the attacker and costs it posture
	posture = clampf(posture + 22.0, 0.0, max_posture)
	posture_changed.emit(posture, max_posture)
	_release_token()
	velocity = -global_transform.basis.z * 2.4
	if posture >= max_posture:
		_break_posture()
	else:
		_set_state(S.RECOVER)
		_t = -0.25
	if world != null and world.hitfx != null:
		world.hitfx.burst(global_position + Vector3(0, 1.3, 0), "deflect")
	Audio.play_sfx("deflect", global_position, 1.1, -4.0)

func execute(by: Node) -> void:
	if is_dead: return
	hp = 0.0
	if world != null and world.hitfx != null:
		world.hitfx.burst(global_position + Vector3(0, 1.0, 0), "blood")
	_die()

func _die() -> void:
	if is_dead: return
	is_dead = true
	death_timer = 0.0
	_release_token()
	_telegraph.visible = false
	_marker.visible = false
	_set_state(S.DEAD)
	if driver != null:
		if is_boss and driver.rig.has_clip("Defeat"):
			driver.abort_action(); driver.abort_reaction()
			driver.action("Defeat", 1.0, 0.12)
		else:
			driver.death()
	collision_layer = 0
	if hurtbox != null: hurtbox.collision_layer = 0
	Audio.play_sfx("impact", global_position, 0.7, -6.0)
	died.emit(kind, zone)

func hp_ratio() -> float:
	return hp / max_hp

func posture_ratio() -> float:
	return posture / max_posture

func is_alive() -> bool:
	return not is_dead

func display_name() -> String:
	return kind.capitalize()

func _exit_tree() -> void:
	_release_token()

func _scan_and_hit(p_reach: float, p_arc: float, dmg: float, post: float) -> void:
	var space := get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = p_reach
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	var fwd := global_transform.basis.z
	params.transform = Transform3D(Basis(), global_position + Vector3(0, 1.05, 0) + fwd * p_reach * 0.5)
	params.collision_mask = 4
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var hit_any := false
	for r in space.intersect_shape(params, 8):
		var c = r.get("collider")
		if c == null or not (c is Area3D): continue
		if not (c as Area3D).is_in_group("player_hurtbox"): continue
		var p = (c as Area3D).get_parent()
		if p == null or not p.has_method("take_hit"): continue
		var to = (p.global_position + Vector3(0, 1.0, 0)) - (global_position + Vector3(0, 1.05, 0))
		to.y = 0
		if to.length() > 0.05 and rad_to_deg(fwd.angle_to(to.normalized())) > p_arc * 0.5:
			continue
		p.take_hit({"damage": dmg, "posture": post, "heavy": dmg > 20.0, "source": self})
		hit_any = true
	if hit_any and world != null and world.hitfx != null:
		world.hitfx.burst(global_position + fwd * p_reach * 0.6 + Vector3(0, 1.1, 0), "spark")
