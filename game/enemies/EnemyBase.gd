class_name EnemyBase
extends CharacterBody3D
## Shared enemy AI: idle/patrol/detect/chase/attack/recover/stagger/death,
## attack telegraphs, posture, hurtbox, spacing tokens and deflect reactions.
##
## v0.16 adds real perception and a smarter fight:
##  * awareness 0..1 built from sight (a view cone, distance, daylight, line of
##    sight and how visible the player is: crouching, tall grass, smoke) and
##    hearing (footsteps by gait, fighting nearby). Suspicious soldiers walk to
##    where they last noticed something; an alerted one shouts and the camp
##    within 22 m comes looking. They can lose you again (out of sight 5 s).
##  * guards: soldiers block cuts aimed at their front, more often when you
##    hammer them; blocked cuts still cost posture, kicks and heavy blows break
##    through more often, and posture drains back if you let them breathe.
##  * perilous attacks (危): a thrust that only a perfect deflect or a Mikiri
##    Counter answers, and a sweep you must jump or dodge; plus delayed swings
##    and feints from veterans, and spacing slots so a group surrounds you.

signal died(kind: String, zone: String)
signal posture_changed(cur: float, maxp: float)
signal hp_changed(cur: float, maxp: float)

enum S {IDLE, PATROL, INVESTIGATE, ALERT, CHASE, COMBAT_READY, ATTACK, RECOVER,
	STAGGER, KNOCKDOWN, RETURN, DEAD}
const DETECT := S.ALERT      # legacy alias

static var attackers := 0
const MAX_ATTACKERS := 2

# ---- v0.16 perception
const SIGHT_HALF := 60.0         # degrees either side: clear sight
const PERIPH_HALF := 105.0       # degrees: peripheral vision, much slower
const SIGHT_RATE := 2.6          # awareness per second, point blank in clear view
const HEAR_RATE := 1.5
const HEAR_CAP := 0.7            # noise alone makes them search, not fight
const AWARE_DECAY := 0.11
const SUSPECT := 0.34            # walk over and look
const ALLY_SHOUT := 22.0         # an alert carries this far through a camp
const LOSE_TIME := 5.0           # out of sight this long in a fight: search
# ---- v0.16 fight
const POSTURE_REGEN := 0.085     # fraction of max per second (full health)
const POSTURE_REGEN_DELAY := 1.6

var awareness := 0.0
var group := ""
var route: Array = []            # patrol waypoints (Vector3)
var post_yaw := 0.0              # the way a sentry faces at its post
var _route_i := 0
var _route_wait := 0.0
var _look_t := 0.0
var _last_known := Vector3.INF
var _los_ok := false
var _los_t := 0.0
var _lost_t := 0.0
var _blind_t := 0.0
var _distract_t := 0.0
var _distractor: Node3D = null
var _alert_flash := 0.0
var _being_assassinated := 0.0
var guard_chance := 0.3
var perilous_thrust := 0.0
var perilous_sweep := 0.0
var delay_chance := 0.12
var feint_chance := 0.0
var _pressure := 0.0
var _pressure_t := 0.0
var _guarding_t := 0.0
var _posture_idle := 0.0
var _perilous := ""
var _windup_mult := 1.0
var _feint := false
var _slot_angle := 0.0
var _slot_t := 0.0
static var _perilous_told := false

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
var _hitstop_t := 0.0
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
	collision_mask = 1 | 8   # world + map bounds
	floor_max_angle = deg_to_rad(58.0)
	floor_snap_length = 0.5
	floor_block_on_wall = true
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

## v0.18: soldiers share the player's realistic base body (UBCDriver); set
## false to bring back the old procedural models.
const UBC_BODIES := true

func _build_body() -> void:
	driver = UBCDriver.new() if UBC_BODIES else AnimDriver.new()
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
	cap.radius = 0.36
	cap.height = 1.78
	cs.shape = cap
	cs.position = Vector3(0, 0.89, 0)
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
	# v0.16 fix: _ready() runs inside add_child(), before the spawner has
	# placed the body, so the patrol origin used to be the world origin
	_patrol_origin = global_position
	_want_yaw = rotation.y
	if route.is_empty() and post_yaw == 0.0: post_yaw = rotation.y

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
	# Hitstop: a few frames of frozen animation on a solid connect. It is the
	# single cheapest thing that makes a hit feel like it landed.
	if _hitstop_t > 0.0:
		_hitstop_t -= delta
		velocity = Vector3.ZERO
		return
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
	_tick_v16(delta)
	# v0.16 held by an assassin: no struggle, no shout
	if _being_assassinated > 0.0:
		_being_assassinated -= delta
		velocity.x = 0.0; velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		_anim_tick(delta, false)
		if _being_assassinated <= 0.0:
			hp = 0.0
			hp_changed.emit(hp, max_hp)
			_die()
		return
	# v0.16 blinded by smoke: coughing, stumbling, harmless
	if _blind_t > 0.0:
		_blind_t -= delta
		velocity.x = lerpf(velocity.x, 0.0, 6.0 * delta)
		velocity.z = lerpf(velocity.z, 0.0, 6.0 * delta)
		_apply_gravity(delta)
		move_and_slide()
		_anim_tick(delta, true)
		_update_telegraph(delta)
		if _blind_t <= 0.0: _recover_sight()
		return
	var pp := player.global_position
	var dist := global_position.distance_to(pp)
	# story cinematics: nobody notices Kaito while the camera is away
	if Game.cinematic: dist = 1.0e6
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
	if in_combat and state in [S.CHASE, S.COMBAT_READY, S.RECOVER]:
		_track_lost(delta, pp, dist)
	_apply_gravity(delta)
	move_and_slide()
	var loco_ok: bool = state not in [S.ATTACK, S.STAGGER, S.KNOCKDOWN, S.DEAD]
	_anim_tick(delta, loco_ok)
	_update_telegraph(delta)

# ------------------------------------------------------------------ v0.16 perception
func _tick_v16(delta: float) -> void:
	_alert_flash = maxf(0.0, _alert_flash - delta)
	_distract_t = maxf(0.0, _distract_t - delta)
	_guarding_t = maxf(0.0, _guarding_t - delta)
	_pressure_t -= delta
	if _pressure_t <= 0.0: _pressure = maxf(0.0, _pressure - delta * 2.0)
	_los_t -= delta
	if _los_t <= 0.0:
		_los_t = 0.2 + _rng.randf() * 0.06
		_los_ok = _check_los()
	# posture drains back when the soldier is left alone, slower when hurt
	_posture_idle += delta
	if posture > 0.0 and not posture_broken and _posture_idle > POSTURE_REGEN_DELAY:
		posture = maxf(0.0, posture - max_posture * POSTURE_REGEN * (0.3 + 0.7 * hp_ratio()) * delta)
		posture_changed.emit(posture, max_posture)

func _check_los() -> bool:
	if player == null or not is_instance_valid(player): return false
	if global_position.distance_to(player.global_position) > detect_radius * 1.7: return false
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.62, 0)
	var h := 0.85 if player.is_crouching() else 1.35
	var to := player.global_position + Vector3(0, h, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = [get_rid(), player.get_rid()]
	return space.intersect_ray(q).is_empty()

func _forward_flat() -> Vector3:
	var f := global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD

## Angle (degrees) between where this soldier looks and the direction to p.
func _angle_to(p: Vector3) -> float:
	var to := p - global_position
	to.y = 0.0
	if to.length() < 0.01: return 0.0
	return rad_to_deg(_forward_flat().angle_to(to.normalized()))

## 0..1: how well this soldier sees the player this instant.
func _sight_factor(pp: Vector3, dist: float) -> float:
	if _blind_t > 0.0 or not _los_ok: return 0.0
	if player.in_smoke(): return 0.0
	var rng := detect_radius * 1.3
	if world != null and world.daynight != null:
		# moonlight still shows a silhouette; a dark night halves sight
		rng *= 0.42 + 0.58 * world.daynight.daylight()
	if dist > rng: return 0.0
	var ang := _angle_to(pp)
	var cone := 0.0
	if ang <= SIGHT_HALF: cone = 1.0
	elif ang <= PERIPH_HALF: cone = 0.3
	else: return 0.0
	var close := 1.0 - dist / rng
	return cone * player.stealth_visibility() * (0.22 + 0.78 * close * close)

func _perceive(delta: float, pp: Vector3, dist: float) -> void:
	if Game.cinematic:
		awareness = maxf(0.0, awareness - delta)
		return
	var mult := 0.6 if Skills.has("s_silent") else 1.0
	var sight := _sight_factor(pp, dist) * SIGHT_RATE * mult
	var nr := player.noise_radius()
	var hear := HEAR_RATE * (1.0 - dist / nr) * mult if dist < nr else 0.0
	if sight > 0.0:
		awareness = minf(1.0, awareness + sight * delta)
		_last_known = pp
	if hear > 0.0 and awareness < HEAR_CAP:
		awareness = minf(HEAR_CAP, awareness + hear * delta)
		_last_known = pp
	if sight <= 0.0 and hear <= 0.0:
		awareness = maxf(0.0, awareness - AWARE_DECAY * delta)
	# walking into someone is noticed, unless you are crouched at his back
	if dist < 1.5 and not (player.is_crouching() and _angle_to(pp) > 110.0):
		awareness = 1.0
		_last_known = pp

func _react_awareness() -> bool:
	if awareness >= 1.0:
		_begin_alert()
		return true
	if awareness >= SUSPECT and state != S.INVESTIGATE:
		_set_state(S.INVESTIGATE)
		return true
	return false

## In a fight but the player has slipped out of sight (smoke, cover, distance):
## after LOSE_TIME the soldier stops fighting and searches the last spot.
func _track_lost(delta: float, pp: Vector3, dist: float) -> void:
	var seen := _los_ok and not player.in_smoke() and dist < lose_radius
	if seen or dist < 4.0:
		_lost_t = 0.0
		_last_known = pp
		return
	_lost_t += delta
	if _lost_t > LOSE_TIME:
		_lost_t = 0.0
		lose_track(_last_known)

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
	_perceive(delta, player.global_position, dist)
	if _react_awareness(): return
	if not route.is_empty():
		if _t > _route_wait: _set_state(S.PATROL)
		return
	# sentries hold their post and look about; now and then they shift a step
	_look_t -= delta
	if _look_t <= 0.0:
		_look_t = 3.5 + _rng.randf() * 3.5
		_want_yaw = post_yaw + deg_to_rad(_rng.randf_range(-75.0, 75.0))
	if _t > 9.0 + _rng.randf() * 6.0:
		_patrol_target = _patrol_origin + Vector3(_rng.randf_range(-3.0, 3.0), 0, _rng.randf_range(-3.0, 3.0))
		_set_state(S.PATROL)

func _begin_alert(propagate := true) -> void:
	in_combat = true
	awareness = 1.0
	_alert_flash = 1.4
	_alert_t = 0.0
	_lost_t = 0.0
	if player != null and is_instance_valid(player): _last_known = player.global_position
	_set_state(S.ALERT)
	if driver != null:
		if is_boss and driver.rig.has_clip("Intimidate"):
			driver.action("Intimidate", 1.0, 0.12)
		elif driver.rig.has_clip("Alert"):
			driver.action("Alert", 1.0, 0.10)
	Audio.play_sfx("drum", global_position, 1.0, -2.0)
	# the shout carries through the camp
	if propagate and world != null and world.has_method("alert_allies"):
		world.alert_allies(self, _last_known)

## A comrade shouted: this one joins the fight (no shout of its own, so one
## alarm does not echo round the camp forever).
func ally_alert(pos: Vector3) -> void:
	if is_dead or in_combat or _being_assassinated > 0.0 or _blind_t > 0.0: return
	_begin_alert(false)
	_last_known = pos
	_alert_t = -_rng.randf_range(0.1, 0.5)     # a beat to react

func _investigate(delta: float, pp: Vector3, dist: float) -> void:
	_perceive(delta, pp, dist)
	if awareness >= 1.0:
		_begin_alert()
		return
	var goal := _last_known if _last_known != Vector3.INF else global_position
	var to := goal - global_position
	to.y = 0.0
	if to.length() > 1.6 and _t > 0.5:
		var spd := driver.speed_walk if driver != null else 1.4
		if awareness > 0.6 and driver != null: spd = driver.speed_jog * 0.75
		_move_dir(to.normalized(), spd, delta)
		_face_towards(goal, delta, 4.0)
	else:
		velocity.x = lerpf(velocity.x, 0.0, 7.0 * delta)
		velocity.z = lerpf(velocity.z, 0.0, 7.0 * delta)
		if _t <= 0.5: _face_towards(goal, delta, 3.0)
		elif driver != null and driver.rig.has_clip("Investigate"):
			driver.travel("Investigate")
	if (awareness < 0.08 and _t > 4.0) or _t > 16.0:
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
	_perceive(delta, player.global_position, dist)
	if _react_awareness(): return
	var home := _patrol_origin
	if not route.is_empty(): home = route[_route_i]
	var to := home - global_position
	to.y = 0
	if to.length() < 1.4 or _t > 20.0:
		in_combat = false
		_want_yaw = post_yaw
		_set_state(S.IDLE)
		return
	_move_dir(to.normalized(), driver.speed_walk if driver != null else 1.4, delta)
	_face_towards(home, delta, 4.0)

func _patrol(delta: float, dist: float) -> void:
	_perceive(delta, player.global_position, dist)
	if _react_awareness(): return
	var target := _patrol_target
	if not route.is_empty(): target = route[_route_i]
	var to := target - global_position
	to.y = 0
	if to.length() < 1.2 or _t > 30.0:
		if not route.is_empty():
			_route_i = (_route_i + 1) % route.size()
			_route_wait = 1.5 + _rng.randf() * 2.5
		_set_state(S.IDLE)
		return
	_move_dir(to.normalized(), (driver.speed_walk if driver != null else 1.4), delta)
	_face_towards(target, delta, 4.0)

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
	# v0.16 a spirit fox in its face: it turns on the fox and does not strike
	if _distract_t > 0.0 and _distractor != null and is_instance_valid(_distractor):
		_face_towards(_distractor.global_position, delta, 7.0)
		velocity.x = lerpf(velocity.x, 0.0, 8.0 * delta)
		velocity.z = lerpf(velocity.z, 0.0, 8.0 * delta)
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
	if dist > attack_range * 1.25 + 2.5:
		_set_state(S.CHASE)
		return
	# v0.16 spacing slots: the group spreads round the player instead of
	# queueing in front, so somebody is usually at your flank
	_slot_t -= delta
	if _slot_t <= 0.0:
		_slot_t = 0.7 + _rng.randf() * 0.3
		_slot_angle = _pick_slot(pp)
	var ring := maxf(attack_range * 1.05, 2.6)
	var want := pp + Vector3(sin(_slot_angle), 0.0, cos(_slot_angle)) * ring
	var mv := want - global_position
	mv.y = 0.0
	var strafe := Vector3(-dir.z, 0, dir.x) * _circle_dir
	if mv.length() > 0.8:
		mv = mv.normalized()
	else:
		mv = strafe * 0.35
	var push := dir * (0.0 if dist > attack_range * 0.85 else -0.8)
	var go := mv * 0.9 + push + sep
	if go.length() > 0.05:
		_move_dir(go.normalized(), driver.speed_walk * 1.05 if driver != null else 1.5, delta)
	else:
		_move_dir(Vector3.ZERO, 0.0, delta)
	if _t > 2.2:
		_circle_dir = -_circle_dir
		_t = 0.0
	if _cd <= 0.0 and dist <= attack_range * 1.15:
		if _take_token():
			_begin_attack()

## Even slots round the player for every melee soldier fighting near him; this
## one takes the slot nearest to where it already stands.
func _pick_slot(pp: Vector3) -> float:
	var mine := atan2(global_position.x - pp.x, global_position.z - pp.z)
	if world == null: return mine
	var others: Array = []
	for e in world.enemies:
		if e == self or not is_instance_valid(e) or e.is_dead or not e.in_combat: continue
		if e.kind == "archer": continue
		if e.global_position.distance_to(pp) > 9.0: continue
		others.append(atan2(e.global_position.x - pp.x, e.global_position.z - pp.z))
	if others.is_empty(): return mine
	# push away from the nearest neighbour on the circle
	var n := float(others.size() + 1)
	var gap := TAU / n
	var best := mine
	var best_d := 0.0
	for k in 12:
		var cand := mine + deg_to_rad(float(k - 6) * 15.0)
		var dmin := PI
		for o in others:
			dmin = minf(dmin, absf(angle_difference(cand, float(o))))
		var score := minf(dmin, gap) - absf(angle_difference(cand, mine)) * 0.15
		if score > best_d:
			best_d = score
			best = cand
	return best

## v0.16 every swing decides here: perilous (危) or plain, delayed or a feint.
func _begin_attack() -> void:
	_has_token = true
	_attack_hit_done = false
	_attack_started = false
	_attack_index = 0
	_feint = false
	_windup_mult = 1.0
	_perilous = _pick_perilous()
	if _perilous != "":
		_windup_mult = 1.45
		Audio.play_sfx("telegraph", global_position, 0.72, 3.0)
		if world != null and world.hud != null and world.hud.has_method("perilous_flash"):
			world.hud.perilous_flash(self)
		if not _perilous_told:
			_perilous_told = true
			Game.notice.emit("危 Perilous attack — a thrust only a perfect deflect stops; jump or dodge a sweep", "warn")
	elif _rng.randf() < delay_chance:
		_windup_mult = 1.5
	elif _rng.randf() < feint_chance:
		_feint = true
	_set_state(S.ATTACK)
	Audio.play_sfx("swing_light", global_position, randf_range(0.85, 0.95), -4.0)

func _pick_perilous() -> String:
	var r := _rng.randf()
	if r < perilous_thrust: return "thrust"
	if r < perilous_thrust + perilous_sweep: return "sweep"
	return ""

func _attack_state(delta: float, pp: Vector3) -> void:
	velocity.x = lerpf(velocity.x, 0.0, 10.0 * delta)
	velocity.z = lerpf(velocity.z, 0.0, 10.0 * delta)
	var wu := windup * _windup_mult
	if _t < wu:
		_face_towards(pp, delta, 3.0)
		if not _attack_started:
			_attack_started = true
			var clip := _attack_clip()
			var sp := 1.0
			if driver != null and driver.ok():
				var cl := driver.rig.clip_len(clip)
				if cl > 0.05:
					sp = cl / maxf(wu + active_time + recover_time, 0.2)
				driver.action(clip, clampf(sp, 0.55, 1.9), 0.08)
		# a veteran's feint: the blade comes up, stops, and comes again
		if _feint and _t > wu * 0.6:
			_feint = false
			if driver != null: driver.abort_action()
			_release_token()
			_cd = 0.0
			_set_state(S.COMBAT_READY)
			if _take_token():
				_begin_attack()
				_feint = false
	elif _t < wu + active_time:
		if not _attack_hit_done:
			_attack_hit_done = true
			_perform_attack()
	else:
		# a captain may run straight into the next cut of a string
		if _chain_next():
			_attack_hit_done = false
			_attack_started = false
			_perilous = ""
			_windup_mult = 0.85
			_t = 0.0
			return
		_release_token()
		_perilous = ""
		_cd = cooldown * _rng.randf_range(0.8, 1.25)
		_set_state(S.RECOVER)

## Override: return true to chain another swing instead of recovering.
func _chain_next() -> bool:
	return false

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
	# soldiers in armour do not swim: they stop where the water gets deep
	if world != null and world.terrain != null and dir != Vector3.ZERO:
		var ahead := global_position + dir * 1.3
		if world.terrain.water_depth_at(ahead.x, ahead.z) > 0.95:
			dir = Vector3.ZERO
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
	var wu := windup * _windup_mult
	var show := state == S.ATTACK and _t < wu
	_marker.visible = show or state == S.STAGGER or in_combat
	_telegraph.visible = show
	if show:
		var p := clampf(_t / maxf(wu, 0.05), 0.0, 1.0)
		if _perilous != "":
			# perilous: deep red and wider, it cannot be blocked
			_telegraph_mat.albedo_color = Color(1.0, 0.06, 0.04, 0.22 + p * 0.5)
			var wp := reach * (1.9 + p * 0.6) * (1.5 if _perilous == "sweep" else 1.0)
			_telegraph.scale = Vector3(wp, 1.0, 1.0)
		else:
			_telegraph_mat.albedo_color = Color(0.95, 0.30, 0.10, 0.10 + p * 0.42)
			var w := reach * (1.4 + p * 0.5)
			_telegraph.scale = Vector3(w, 1.0, 1.0)
		_telegraph.position = Vector3(0, 0.06, -reach * 0.55)
	if _marker.visible:
		var m := 0.35 + 0.35 * sin(_t * 6.0)
		if state == S.STAGGER:
			_marker_mat.albedo_color = Color(1.0, 0.85, 0.2, 0.85)
		elif _perilous != "" and show:
			_marker_mat.albedo_color = Color(1.0, 0.05, 0.05, 0.95)
		elif in_combat:
			_marker_mat.albedo_color = Color(1.0, 0.25, 0.15, m)
		else:
			_marker_mat.albedo_color = Color(1.0, 0.8, 0.3, m * 0.4)
	if _weapon_mesh != null:
		var glow := 0.0
		if state == S.ATTACK and _t < wu:
			glow = clampf(_t / maxf(wu, 0.05), 0.0, 1.0)
		_weapon_mesh.scale = Vector3.ONE * (1.0 + glow * 0.06)

# ------------------------------------------------------------------ combat
func take_hit(info: Dictionary) -> void:
	if is_dead or _being_assassinated > 0.0: return
	# v0.16 an unaware soldier hit out of nowhere is in the fight now - and a
	# cut from behind that he never saw coming lands at 2.5x
	var src_v = info.get("source", null)
	var sneak := false
	if not in_combat and state in [S.IDLE, S.PATROL, S.INVESTIGATE, S.RETURN]:
		if src_v != null and is_instance_valid(src_v) and src_v is Node3D:
			sneak = _angle_to((src_v as Node3D).global_position) > 100.0 or awareness < SUSPECT
		_begin_alert()
	if not sneak and _try_guard(info): return
	var dmg := float(info.get("damage", 10.0))
	if sneak:
		dmg *= 2.5
		if world != null and world.hitfx != null:
			world.hitfx.label(global_position + Vector3(0, 0.4, 0), "SNEAK ATTACK", Color(1.0, 0.8, 0.45))
	if posture_broken:
		dmg *= 1.6
	hp = maxf(0.0, hp - dmg)
	hp_changed.emit(hp, max_hp)
	_posture_idle = 0.0
	if not posture_broken:
		posture = clampf(posture + float(info.get("posture", 10.0)), 0.0, max_posture)
		posture_changed.emit(posture, max_posture)
	in_combat = true
	if world != null and world.hitfx != null:
		# One tiered call: sparks, shake, directional camera push, ring flash and
		# hitstop all scale with the damage instead of every call site guessing.
		var dir: Vector3 = Vector3.ZERO
		if src_v != null and is_instance_valid(src_v) and src_v is Node3D:
			dir = (global_position - (src_v as Node3D).global_position)
			dir.y = 0.0
			dir = dir.normalized()
		_hitstop_t = world.hitfx.impact(global_position + Vector3(0, 1.1, 0), dir, dmg,
			"blood" if dmg > 14.0 else "spark")
		world.hitfx.label(global_position, "%d" % int(round(dmg)), Color(1.0, 0.95, 0.6))
	if hp <= 0.0:
		_die()
		return
	if posture >= max_posture and not posture_broken:
		_break_posture()
	elif state in [S.IDLE, S.PATROL, S.CHASE, S.RECOVER] and dmg > 6.0:
		# light hit reaction: brief flinch, keeps combat readable
		_hit_flash = 0.12

## v0.16 guard: a soldier facing the cut may block it. Hammering one builds
## "pressure" (it reads the rhythm and blocks more), heavy blows get through
## more often and push more posture when they don't, kicks and Spirit Blade
## Mastery cuts always get through. Blocked cuts still cost posture.
func _try_guard(info: Dictionary) -> bool:
	if guard_chance <= 0.0 or posture_broken: return false
	if bool(info.get("unblockable", false)) or bool(info.get("kick", false)): return false
	if not in_combat or _blind_t > 0.0 or _distract_t > 0.0: return false
	if not state in [S.COMBAT_READY, S.RECOVER, S.CHASE]: return false
	var src = info.get("source", null)
	if src == null or not is_instance_valid(src) or not (src is Node3D): return false
	if _angle_to((src as Node3D).global_position) > 70.0: return false
	var heavy := bool(info.get("heavy", false))
	var ch := guard_chance + _pressure * 0.12
	if heavy: ch *= 0.5
	ch = clampf(ch, 0.0, 0.85)
	_pressure = minf(_pressure + 1.0, 4.0)
	_pressure_t = 1.4
	if _rng.randf() >= ch: return false
	var pd := float(info.get("posture", 10.0)) * (0.9 if heavy else 0.55)
	posture = clampf(posture + pd, 0.0, max_posture)
	posture_changed.emit(posture, max_posture)
	_posture_idle = 0.0
	_guarding_t = 0.4
	if driver != null and driver.ok():
		if driver.rig.has_clip("Block"): driver.action("Block", 1.5, 0.05)
		else: driver.reaction_from((src as Node3D).global_position, false)
	Audio.play_sfx("block", global_position, randf_range(0.95, 1.08), 0.0)
	if world != null and world.hitfx != null:
		world.hitfx.impact(global_position + Vector3(0, 1.25, 0) + _forward_flat() * 0.45, -_forward_flat(), 6.0, "spark")
		world.hitfx.label(global_position, "BLOCKED", Color(0.75, 0.85, 1.0))
	if src.has_method("on_guarded"): src.on_guarded(self)
	if posture >= max_posture:
		_break_posture()
	elif _pressure >= 2.0 and _cd > 0.25:
		_cd = 0.25      # it answers a flurry with a quick counter
	return true

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
	posture = clampf(posture + (30.0 if _perilous != "" else 22.0), 0.0, max_posture)
	posture_changed.emit(posture, max_posture)
	_posture_idle = 0.0
	_perilous = ""
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

# ------------------------------------------------------------------ v0.16 public
## "thrust" / "sweep" while a perilous attack is winding up or live, else "".
func perilous_kind() -> String:
	if state == S.ATTACK and not _attack_hit_done: return _perilous
	return ""

func perilous_progress() -> float:
	if state != S.ATTACK: return 0.0
	return clampf(_t / maxf(windup * _windup_mult, 0.05), 0.0, 1.0)

func windup_left() -> float:
	if state != S.ATTACK: return -1.0
	return windup * _windup_mult - _t

## Mikiri Counter: the player dodged into the thrust and stamped the spear down.
func mikiri(by: Node) -> bool:
	if perilous_kind() != "thrust": return false
	_perilous = ""
	_attack_hit_done = true
	if driver != null: driver.abort_action()
	_release_token()
	posture = clampf(posture + max_posture * 0.55, 0.0, max_posture)
	posture_changed.emit(posture, max_posture)
	_posture_idle = 0.0
	Audio.play_sfx("clash", global_position, 0.8, 3.0)
	if world != null and world.hitfx != null:
		world.hitfx.burst(global_position + Vector3(0, 0.6, 0) + _forward_flat() * 0.9, "deflect")
		world.hitfx.label(global_position, "MIKIRI", Color(1.0, 0.85, 0.5))
	if posture >= max_posture:
		_break_posture()
	else:
		_set_state(S.RECOVER)
		_t = -0.9
		if driver != null: driver.stagger()
	return true

## Smoke bomb: blinded for t seconds. Releases its turn to attack.
func blind(t: float) -> void:
	if is_dead: return
	_blind_t = maxf(_blind_t, t)
	_perilous = ""
	_release_token()
	if state == S.ATTACK and driver != null: driver.abort_action()
	_set_state(S.COMBAT_READY if in_combat else S.INVESTIGATE)
	if driver != null and driver.ok(): driver.stagger()

func is_blind() -> bool:
	return _blind_t > 0.0

func _recover_sight() -> void:
	# it coughs its way out of the smoke and starts looking for you
	in_combat = false
	awareness = 0.62
	_set_state(S.INVESTIGATE)

## Lost the player (smoke elsewhere, or out of sight too long): go and search.
func lose_track(pos: Vector3) -> void:
	if is_dead: return
	in_combat = false
	_perilous = ""
	_release_token()
	awareness = minf(awareness, 0.62)
	_last_known = pos
	_set_state(S.INVESTIGATE)

## Spirit fox pounce: the soldier wheels on the fox and holds its attack.
func distract(t: float, by: Node3D) -> void:
	if is_dead: return
	_distract_t = t
	_distractor = by
	if state == S.ATTACK and not _attack_hit_done:
		if driver != null: driver.abort_action()
		_release_token()
		_perilous = ""
		_set_state(S.COMBAT_READY)
	if driver != null and driver.ok(): driver.reaction_from(by.global_position, false)

## Something was heard at pos (a fight, a body falling, a shout).
func hear_noise(pos: Vector3, loud: float) -> void:
	if is_dead or in_combat or _being_assassinated > 0.0: return
	awareness = maxf(awareness, clampf(0.4 + loud * 0.35, 0.0, 0.9))
	_last_known = pos
	if state in [S.IDLE, S.PATROL, S.RETURN]:
		_set_state(S.INVESTIGATE)

## Assassination is possible on a soldier that is not fighting you, from
## behind or while it has not noticed you, or on one blinded by smoke.
func can_be_assassinated(by: Node3D, chain := false) -> bool:
	if is_dead or posture_broken or _being_assassinated > 0.0 or is_boss: return false
	if _blind_t > 0.0: return true
	# chain assassination: one that has only just turned to shout still dies
	if chain and (state == S.ALERT or not in_combat): return true
	if in_combat or awareness >= 1.0: return false
	return _angle_to(by.global_position) > 100.0 or awareness < SUSPECT

func assassinated(by: Node3D) -> void:
	if is_dead: return
	_being_assassinated = 0.42
	_release_token()
	_perilous = ""
	_blind_t = 0.0
	if driver != null and driver.ok(): driver.abort_action()
	if world != null and world.has_method("witness"):
		world.witness(self)

func awareness_ratio() -> float:
	return awareness

func alert_flash() -> float:
	return _alert_flash

func is_searching() -> bool:
	return state == S.INVESTIGATE

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
	Audio.play_sfx("bodyfall", global_position, 1.0, 0.0)
	died.emit(kind, zone)

func hp_ratio() -> float:
	return hp / max_hp

func posture_ratio() -> float:
	return posture / max_posture

func is_alive() -> bool:
	return not is_dead

func display_name() -> String:
	# v0.14: the story's villain, not just "Captain"
	if is_boss: return "Kuroda Masanori"
	return kind.capitalize()

func _exit_tree() -> void:
	_release_token()

func _scan_and_hit(p_reach: float, p_arc: float, dmg: float, post: float) -> void:
	var space := get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	# v0.16 perilous: a thrust hits harder, a sweep reaches wider round the front
	var kind_p := _perilous
	if kind_p != "":
		dmg *= 1.3
		post *= 1.5
		if kind_p == "sweep":
			p_reach += 0.4
			p_arc = maxf(p_arc, 220.0)
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
		p.take_hit({"damage": dmg, "posture": post, "heavy": dmg > 20.0 or kind_p != "", "source": self,
			"perilous": kind_p})
		hit_any = true
	if hit_any and world != null and world.hitfx != null:
		world.hitfx.burst(global_position + fwd * p_reach * 0.6 + Vector3(0, 1.1, 0), "spark")

