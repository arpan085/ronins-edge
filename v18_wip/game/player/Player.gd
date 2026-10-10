class_name Player
extends CharacterBody3D
## Kaito, the ronin.  A plain state machine on top of PlayerRig.
##
## Locomotion picks the clip that matches the real ground speed (walk, run,
## sprint, strafes and backpedal when locked on) and scales its playback so feet
## do not slide.  Weapons are data: every move is a clip, a hit window measured
## from the clip itself, damage/posture/reach/lunge numbers and the clip time at
## which the next queued move may start.  The blade only leaves or enters the
## saya when the player asks (draw / sheathe key, or an attack from a sheathed
## blade, which becomes a quick draw).  Nothing sheathes on its own.

signal died
signal hp_changed(hp: float, max_hp: float)
signal posture_changed(p: float, max_p: float)
signal focus_changed(f: float, max_f: float)
signal stamina_changed(s: float, max_s: float)
signal stance_changed(name: String)
signal lock_changed(target: Node3D)
signal deathblow_ready(target: Node3D)
signal combat_state_changed(in_combat: bool)
signal weapon_changed(id: String)
signal mount_changed(mounted: bool)

enum S {IDLE, MOVE, ATTACK, BLOCK, DODGE, HIT, STAGGER, DEATHBLOW, DEAD, DRAW, JUMP, MOUNTED, MOUNTING, SWIM,
	THROW, ASSASSIN}

# ---------------------------------------------------------------- tuning
const WALK_SPEED := 1.45
const RUN_SPEED := 4.9
const SPRINT_SPEED := 8.2
const GUARD_SPEED := 1.7
const STRAFE_SPEED := 3.3
const BACK_SPEED := 1.6
const ACCEL := 20.0
const SPRINT_ACCEL := 8.5
const DECEL := 24.0
const AIR_ACCEL := 6.0
const GRAVITY := 20.0
const JUMP_V := 6.6
const COYOTE_TIME := 0.14
const HARD_LAND_V := 12.0
const DEFLECT_WINDOW := 0.24
const COMBO_RESET := 0.7
const BUFFER_TIME := 0.32
const POSTURE_RECOVER := 9.0
const POSTURE_RECOVER_DELAY := 0.9
const FOCUS_PER_DEFLECT := 22.0
const FOCUS_PER_DODGE := 8.0
const SLOWMO_TIME := 3.0
const SLOWMO_SCALE := 0.35
## A light attack this soon after a perfect deflect becomes the riposte.
const RIPOSTE_WINDOW := 0.9
## Plunging cut: downward speed once the windup is done.
const PLUNGE_V := 11.0
## Swimming. Depths are water over the ground at the feet. The body (capsule,
## camera pivot, hurtbox) floats with its feet SWIM_BODY under the surface;
## the Swim clips are authored with their root AT the water line, so the rig
## is lifted to put that root SINK under the surface (treading / stroking).
const SWIM_ENTER := 1.3
const SWIM_EXIT := 1.0
const SWIM_BODY := 1.2
const SWIM_SINK_IDLE := 0.12
const SWIM_SINK_FWD := 0.06
const SWIM_SPEED := 2.2
const SWIM_FAST := 3.5
const SWIM_DRAIN := 9.0
const SWIM_CLIP_SPEED := 1.8
## Stamina: every committed action spends it, sprinting drains it, and it comes
## back quickly once you stop spending. At 0 you are winded: no sprint until it
## has recovered a third, and a longer pause before it starts refilling.
const STAMINA_REGEN := 32.0
const STAMINA_DELAY := 0.65
const STAMINA_WINDED_DELAY := 1.3
const SPRINT_DRAIN := 12.0
const STAMINA_COST := {"dodge": 15.0, "roll": 21.0, "jump": 9.0, "kick": 11.0, "light": 8.0,
	"heavy": 17.0, "sprint": 4.0, "mounted": 5.0}
const WEAPON_STAMINA := {"fists": 0.65, "katana": 1.0, "yari": 1.1, "nodachi": 1.35}

## Native ground speed of each locomotion clip at 1x (measured on the rig).
const CLIP_SPEED := {"Walk": 1.03, "Jog_Fwd": 5.7, "Sprint": 8.8, "K_Strafe_L": 3.2,
	"K_Strafe_R": 3.2, "K_Walk_Back": 1.35}

const WEAPON_ORDER := ["katana", "nodachi", "yari", "fists"]
const WEAPONS := {
	"katana": {"name": "Katana", "light": ["k_a", "k_b", "k_diag", "k_c"], "heavy": ["k_heavy", "k_heavy2"],
		"sprint": "k_dash", "air": "k_air", "riposte": "k_riposte", "guard": ["Sword_Idle", 0.62], "block": ["Sword_Block", 0.45], "blade": true},
	"nodachi": {"name": "Nodachi", "light": ["n_a", "n_b"], "heavy": ["n_spin"],
		"sprint": "n_stab", "air": "n_air", "riposte": "n_riposte", "guard": ["K_2H_Idle", 0.3], "block": ["Sword_Block", 0.45], "blade": true},
	"yari": {"name": "Yari", "light": ["y_a", "y_b", "y_c"], "heavy": ["y_sweep"],
		"sprint": "y_dash", "air": "y_air", "riposte": "y_riposte", "guard": ["K_2H_Idle", 0.3], "block": ["Sword_Block", 0.45], "blade": true},
	"fists": {"name": "Fists", "light": ["jab", "cross", "hook"], "heavy": ["lunge_punch"],
		"sprint": "lunge_punch", "air": "", "riposte": "f_riposte", "guard": ["K_Unarmed_Idle", 0.3], "block": ["Punch_Jab", 0.04], "blade": false},
}
## clip: library clip.  from/end: clip time range played.  spd: playback rate.
## hit: clip-time window in which the sweep is live.  chain: clip time from which a
## queued follow-up may start.  lunge: forward speed (m/s) during the strike.
const MOVES := {
	"k_a": {"clip": "Sword_Regular_A", "spd": 1.05, "hit": [0.21, 0.31], "end": 0.43, "chain": 0.30,
		"rec": "Sword_Regular_A_Rec", "dmg": 14.0, "pos": 12.0, "reach": 2.4, "arc": 160.0, "lunge": 2.6},
	"k_b": {"clip": "Sword_Regular_B", "spd": 1.05, "hit": [0.23, 0.33], "end": 0.53, "chain": 0.34,
		"rec": "Sword_Regular_B_Rec", "dmg": 15.0, "pos": 13.0, "reach": 2.4, "arc": 160.0, "lunge": 2.8},
	"k_c": {"clip": "Sword_Regular_C", "from": 0.26, "spd": 1.3, "hit": [0.61, 0.72], "end": 1.2, "chain": 0.9,
		"dmg": 22.0, "pos": 20.0, "reach": 2.6, "arc": 190.0, "lunge": 3.6},
	"k_heavy": {"clip": "K_2H_Chop", "from": 0.18, "spd": 1.2, "hit": [0.77, 0.90], "end": 1.3, "chain": 1.05,
		"dmg": 30.0, "pos": 34.0, "reach": 2.6, "arc": 120.0, "lunge": 2.2, "heavy": true},
	"k_heavy2": {"clip": "Sword_Attack", "spd": 1.1, "hit": [0.36, 0.50], "end": 1.15, "chain": 0.9,
		"dmg": 28.0, "pos": 30.0, "reach": 2.6, "arc": 170.0, "lunge": 3.0, "heavy": true},
	"k_dash": {"clip": "Sword_Dash", "spd": 1.15, "hit": [0.29, 0.42], "end": 1.1, "chain": 0.8,
		"dmg": 24.0, "pos": 22.0, "reach": 2.7, "arc": 130.0, "lunge": 8.0},
	"n_a": {"clip": "K_2H_Slice", "from": 0.08, "spd": 1.05, "hit": [0.36, 0.47], "end": 1.0, "chain": 0.62,
		"dmg": 22.0, "pos": 18.0, "reach": 2.9, "arc": 190.0, "lunge": 2.2},
	"n_b": {"clip": "K_2H_Chop", "from": 0.2, "spd": 1.15, "hit": [0.78, 0.90], "end": 1.3, "chain": 1.0,
		"dmg": 30.0, "pos": 28.0, "reach": 3.0, "arc": 120.0, "lunge": 2.4, "heavy": true},
	"n_spin": {"clip": "K_2H_Spin", "from": 0.3, "spd": 1.2, "hit": [0.66, 1.12], "end": 1.9, "chain": 1.5,
		"dmg": 34.0, "pos": 36.0, "reach": 3.0, "arc": 360.0, "lunge": 1.6, "heavy": true},
	"n_stab": {"clip": "K_2H_Stab", "from": 0.1, "spd": 1.1, "hit": [0.34, 0.46], "end": 1.1, "chain": 0.8,
		"dmg": 26.0, "pos": 22.0, "reach": 3.1, "arc": 70.0, "lunge": 8.0},
	"y_a": {"clip": "K_1H_Stab", "from": 0.1, "spd": 1.15, "hit": [0.36, 0.48], "end": 0.95, "chain": 0.6,
		"dmg": 16.0, "pos": 12.0, "reach": 3.4, "arc": 60.0, "lunge": 2.4},
	"y_b": {"clip": "K_2H_Stab", "from": 0.1, "spd": 1.15, "hit": [0.34, 0.46], "end": 1.05, "chain": 0.7,
		"dmg": 19.0, "pos": 15.0, "reach": 3.5, "arc": 60.0, "lunge": 2.8},
	"y_sweep": {"clip": "K_2H_Spin", "from": 0.3, "spd": 1.25, "hit": [0.66, 1.12], "end": 1.9, "chain": 1.5,
		"dmg": 26.0, "pos": 34.0, "reach": 3.4, "arc": 360.0, "lunge": 1.2, "heavy": true},
	"y_dash": {"clip": "K_2H_Stab", "from": 0.1, "spd": 1.1, "hit": [0.34, 0.46], "end": 1.05, "chain": 0.8,
		"dmg": 24.0, "pos": 20.0, "reach": 3.6, "arc": 60.0, "lunge": 8.0},
	"jab": {"clip": "Punch_Jab", "spd": 1.25, "hit": [0.16, 0.27], "end": 0.52, "chain": 0.24,
		"dmg": 6.0, "pos": 7.0, "reach": 1.7, "arc": 100.0, "lunge": 1.6, "unarmed": true},
	"cross": {"clip": "Punch_Cross", "spd": 1.25, "hit": [0.17, 0.28], "end": 0.6, "chain": 0.3,
		"dmg": 8.0, "pos": 9.0, "reach": 1.7, "arc": 100.0, "lunge": 1.8, "unarmed": true},
	"hook": {"clip": "Melee_Hook", "spd": 1.0, "hit": [0.23, 0.32], "end": 0.47, "chain": 0.4,
		"rec": "Melee_Hook_Rec", "dmg": 11.0, "pos": 14.0, "reach": 1.8, "arc": 140.0, "lunge": 2.0, "unarmed": true},
	"lunge_punch": {"clip": "K_Punch", "from": 0.12, "spd": 1.15, "hit": [0.38, 0.50], "end": 0.95, "chain": 0.7,
		"dmg": 13.0, "pos": 18.0, "reach": 1.9, "arc": 90.0, "lunge": 4.5, "unarmed": true, "heavy": true},
	"kick": {"clip": "K_Kick", "spd": 1.2, "hit": [0.40, 0.58], "end": 0.93, "chain": 0.7,
		"dmg": 6.0, "pos": 32.0, "reach": 1.9, "arc": 90.0, "lunge": 1.4, "unarmed": true, "kick": true},
	# v0.13: a fourth katana cut, plunging cuts, ripostes, a yari swing.
	# Timings from the clips' hand-speed peaks (K_1H_Diag 0.50 s, K_1H_Horiz
	# 0.34 s, K_1H_JumpChop 0.78 s; the jump chop's own hop is skipped by
	# starting at 0.45 and holding the raised blade at 0.64 until landing).
	"k_diag": {"clip": "K_1H_Diag", "from": 0.12, "spd": 1.2, "hit": [0.42, 0.56], "end": 0.95, "chain": 0.62,
		"dmg": 17.0, "pos": 15.0, "reach": 2.5, "arc": 170.0, "lunge": 3.0},
	"k_air": {"clip": "K_1H_JumpChop", "from": 0.45, "hold": 0.64, "spd": 1.25, "hit": [0.70, 0.86], "end": 1.22, "chain": 9.0,
		"dmg": 30.0, "pos": 34.0, "reach": 2.8, "arc": 360.0, "lunge": 0.0, "air": true, "heavy": true},
	"n_air": {"clip": "K_1H_JumpChop", "from": 0.45, "hold": 0.64, "spd": 1.15, "hit": [0.70, 0.88], "end": 1.25, "chain": 9.0,
		"dmg": 38.0, "pos": 40.0, "reach": 3.1, "arc": 360.0, "lunge": 0.0, "air": true, "heavy": true},
	"y_air": {"clip": "K_1H_JumpChop", "from": 0.45, "hold": 0.64, "spd": 1.2, "hit": [0.70, 0.86], "end": 1.22, "chain": 9.0,
		"dmg": 28.0, "pos": 36.0, "reach": 3.2, "arc": 360.0, "lunge": 0.0, "air": true, "heavy": true},
	"k_riposte": {"clip": "K_1H_Horiz", "from": 0.1, "spd": 1.5, "hit": [0.26, 0.42], "end": 0.9, "chain": 0.55,
		"dmg": 26.0, "pos": 48.0, "reach": 2.6, "arc": 160.0, "lunge": 3.4, "riposte": true},
	"n_riposte": {"clip": "K_2H_Slice", "from": 0.2, "spd": 1.4, "hit": [0.36, 0.47], "end": 0.95, "chain": 0.6,
		"dmg": 32.0, "pos": 52.0, "reach": 3.0, "arc": 190.0, "lunge": 3.0, "riposte": true},
	"y_riposte": {"clip": "K_1H_Stab", "from": 0.15, "spd": 1.45, "hit": [0.36, 0.48], "end": 0.9, "chain": 0.6,
		"dmg": 24.0, "pos": 46.0, "reach": 3.5, "arc": 70.0, "lunge": 4.0, "riposte": true},
	"f_riposte": {"clip": "Melee_Hook", "spd": 1.2, "hit": [0.23, 0.32], "end": 0.47, "chain": 0.4,
		"rec": "Melee_Hook_Rec", "dmg": 12.0, "pos": 40.0, "reach": 1.9, "arc": 140.0, "lunge": 2.6, "unarmed": true, "riposte": true},
	"y_c": {"clip": "K_1H_Horiz", "from": 0.08, "spd": 1.15, "hit": [0.26, 0.42], "end": 0.95, "chain": 0.6,
		"dmg": 18.0, "pos": 20.0, "reach": 3.3, "arc": 200.0, "lunge": 2.2},
	"ride_a": {"clip": "Sword_Regular_A", "spd": 1.0, "hit": [0.21, 0.32], "end": 0.43, "chain": 0.34,
		"dmg": 18.0, "pos": 14.0, "reach": 2.9, "arc": 240.0, "lunge": 0.0, "mounted": true},
	"ride_b": {"clip": "Sword_Regular_B", "spd": 1.0, "hit": [0.23, 0.33], "end": 0.53, "chain": 0.38,
		"dmg": 18.0, "pos": 14.0, "reach": 2.9, "arc": 240.0, "lunge": 0.0, "mounted": true},
}

# ---------------------------------------------------------------- state
var state: int = S.IDLE
var hp := 100.0
var max_hp := 100.0
var posture := 0.0
var max_posture := 100.0
var focus := 0.0
var max_focus := 100.0
var stamina := 100.0
var max_stamina := 100.0
var winded := false            ## hit 0: no sprint until it recovers
var _stamina_idle := 0.0
var _stamina_flash := 0.0     ## HUD: > 0 right after an action was refused
var stance := "stone"
var weapon := "katana"
var drawn := false
var walk_mode := false

var world: World
var camera: PlayerCamera
var rig: PlayerRig
var anim: AnimationPlayer
var skeleton: Skeleton3D
var trail: SwordTrail
var hurtbox: Area3D
var body_shape: CollisionShape3D
var horse: Node3D = null

var _state_t := 0.0
var _gait := 0
var _move_id := ""
var _move: Dictionary = {}
var _move_t := 0.0
var _hit_ids := {}
var _queued := ""
var _combo := {"light": -1, "heavy": -1, "punch": -1}
var _combo_t := 0.0
var _buf := {}
var _deflect_t := 0.0
var _blocking := false
var _posture_idle := 0.0
var _footstep_t := 0.0
var _surface := "grass"
var _coyote := 0.0
var _air_t := 0.0
var _fall_v := 0.0
var _land_t := 0.0
var _slowmo_t := 0.0
var _dead := false
var _lock_target: Node3D = null
var _in_combat := false
var _hitstop_t := 0.0
var _spirit_blade_t := 0.0
var _dmg_mult := 1.0
var _dodge_dir := Vector3.FORWARD
var _dodge_side := false
var _dodge_len := 1.0
var _iframe := Vector2.ZERO
var _db_target: Node3D = null
var _react_len := 0.4
var _react_push := Vector3.ZERO
var _yaw_rate := 0.0
var _lean := 0.0
var _riposte_t := 0.0        ## > 0: the next light attack is a riposte
var _plunge_t := 0.0
var _plunge_landed := false
var _water_surf := -INF      ## water surface over the player, -INF on dry land
var _stroke_t := 0.0
# draw / sheathe
var _carry := 0              ## 1 drawing, -1 sheathing, 0 idle
var _carry_t := 0.0
var _carry_len := 0.5
var _carry_swapped := false
var _after_draw := ""
# riding
var _mount_t := 0.0
var _mount_from := Transform3D()
var _mount_up := true

func _ready() -> void:
	hp = Game.hp; posture = Game.posture; focus = Game.focus; stance = Game.stance
	collision_layer = 2
	collision_mask = 1 | 8   # world + map bounds
	floor_max_angle = deg_to_rad(58.0)
	floor_snap_length = 0.5
	floor_block_on_wall = true
	floor_constant_speed = true
	safe_margin = 0.02
	max_slides = 6
	_build_body()
	_build_hurtbox()
	state = S.IDLE

func _build_body() -> void:
	rig = PlayerRig.new()
	rig.name = "Rig"
	add_child(rig)
	if rig.build():
		anim = rig.anim
		skeleton = rig.skeleton
	else:
		push_error("Player: rig failed to build")
	body_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.78
	body_shape.shape = cap
	body_shape.position = Vector3(0, 0.89, 0)
	add_child(body_shape)
	trail = SwordTrail.new()
	trail.name = "SwordTrail"
	add_child(trail)
	if skeleton != null:
		trail.bind(skeleton, "hand_r")
	weapon = String(Game.settings.get("last_weapon", "katana"))
	if not WEAPONS.has(weapon): weapon = "katana"
	drawn = false
	if rig.ok: rig.set_weapon(weapon, false)

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

func setup(w: World, cam: PlayerCamera) -> void:
	world = w
	camera = cam

# ---------------------------------------------------------------- input
## v0.14: true while a story cinematic plays - all player input is ignored
var cinematic := false

func _act(a: String) -> bool:
	return not cinematic and InputMap.has_action(a) and Input.is_action_just_pressed(a)

func _held(a: String) -> bool:
	return not cinematic and InputMap.has_action(a) and Input.is_action_pressed(a)

const BUFFERED := ["attack", "heavy", "kick", "punch", "dodge", "jump"]

func _poll_buffer(delta: float) -> void:
	for k in _buf.keys():
		_buf[k] = float(_buf[k]) - delta
		if float(_buf[k]) <= 0.0: _buf.erase(k)
	for a in BUFFERED:
		if _act(a): _buf[a] = BUFFER_TIME
	if Game.touch_block and not _blocking: pass

func _take(a: String) -> bool:
	if _buf.has(a):
		_buf.erase(a)
		return true
	return false

func _unhandled_input(ev: InputEvent) -> void:
	if _dead or cinematic or ev.is_echo(): return
	if ev.is_action_pressed("weapon_next"): _cycle_weapon(1)
	elif ev.is_action_pressed("weapon_prev"): _cycle_weapon(-1)

func _move_input() -> Vector2:
	if cinematic: return Vector2.ZERO
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	v += Game.touch_move
	if v.length() > 1.0: v = v.normalized()
	return v

func _cam_yaw() -> float:
	return camera.get_yaw() if camera != null else rotation.y + PI

## Camera-relative wish direction (length = stick magnitude, 0..1).
func _desired_dir() -> Vector3:
	var v := _move_input()
	if v.length() < 0.08: return Vector3.ZERO
	var yaw := _cam_yaw()
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return right * v.x - fwd * v.y

func _sprinting() -> bool:
	return (_held("sprint") or Game.touch_sprint) and not winded and stamina > 0.0

func _fwd() -> Vector3:
	return global_transform.basis.z

# ---------------------------------------------------------------- loop
func _physics_process(delta: float) -> void:
	if _dead:
		rig.update_saya_hand(delta, false)
		_apply_gravity(delta)
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		move_and_slide()
		return
	_update_healing(delta)
	_tick_v16(delta)
	if state == S.MOUNTED or state == S.MOUNTING:
		_state_t += delta
		_poll_buffer(delta)
		if _act("heal"): drink_gourd()
		_update_posture(delta)
		_update_stamina(delta)
		_update_lock(delta)
		_update_combat_flag(delta)
		if state == S.MOUNTING: _state_mounting(delta)
		else: _state_mounted(delta)
		_tick_layer(delta)
		return
	if _hitstop_t > 0.0:
		_hitstop_t -= delta
		velocity.x = 0.0; velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		return
	_state_t += delta
	_poll_buffer(delta)
	if _slowmo_t > 0.0:
		_slowmo_t -= delta / maxf(Engine.time_scale, 0.05)
		if _slowmo_t <= 0.0: Engine.time_scale = 1.0
	if _spirit_blade_t > 0.0:
		_spirit_blade_t -= delta
		if _spirit_blade_t <= 0.0: _dmg_mult = 1.0
	_combo_t = maxf(0.0, _combo_t - delta)
	_riposte_t = maxf(0.0, _riposte_t - delta)
	if _combo_t <= 0.0 and state != S.ATTACK:
		_combo = {"light": -1, "heavy": -1, "punch": -1}
	_update_posture(delta)
	_update_stamina(delta)
	_update_lock(delta)
	_update_combat_flag(delta)
	_update_carry(delta)
	_global_keys()
	_check_water()
	match state:
		S.IDLE, S.MOVE: _state_locomotion(delta)
		S.ATTACK: _state_attack(delta)
		S.BLOCK: _state_block(delta)
		S.DODGE: _state_dodge(delta)
		S.HIT, S.STAGGER: _state_recover(delta)
		S.DEATHBLOW: _state_deathblow(delta)
		S.JUMP: _state_air(delta)
		S.SWIM: _state_swim(delta)
		S.THROW: _state_throw(delta)
		S.ASSASSIN: _state_assassin(delta)
	if state != S.SWIM: _apply_gravity(delta)
	var was_floor := is_on_floor()
	move_and_slide()
	_after_move(delta, was_floor)
	_tick_layer(delta)
	_tick_lean(delta)
	rig.update_saya_hand(delta, _saya_hand_wanted())
	var hs := Vector2(velocity.x, velocity.z).length()
	rig.update_anatomy(delta, maxf((100.0 - stamina) / 60.0, 0.75 if hs > 6.5 else 0.0))

## v0.18: the left hand rests on the katana's saya while it is sheathed and the
## hands are free: standing, walking, running, crouching and in the air.
func _saya_hand_wanted() -> bool:
	if drawn or _carry != 0 or _move_id != "": return false
	if weapon != "katana" and weapon != "fists": return false
	return state == S.IDLE or state == S.MOVE or state == S.JUMP

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
		_fall_v = minf(_fall_v, velocity.y)
	elif velocity.y < 0.0:
		velocity.y = -1.0

## Keys that work in any grounded state that is not a hard commitment.
func _global_keys() -> void:
	if _act("lock_on"): _toggle_lock()
	if _act("stance"): _cycle_stance()
	if _act("special"): _activate_focus()
	if _act("heal"): drink_gourd()
	if _act("walk"):
		walk_mode = not walk_mode
		_float_text("Walk" if walk_mode else "Run", Color(0.85, 0.85, 0.8))
	if _act("call_horse") and world != null and world.has_method("call_horse"):
		world.call_horse()
	if _act("crouch") and state in [S.IDLE, S.MOVE, S.BLOCK]:
		set_crouch(not crouching)
	if _act("smoke"): throw_smoke()
	for i in 4:
		if _act("weapon_%d" % (i + 1)): select_weapon(WEAPON_ORDER[i])
	if state in [S.IDLE, S.MOVE, S.BLOCK]:
		if _act("sheathe"):
			if drawn or _carry == 1: begin_sheathe()
			else: begin_draw()
		if _act("interact"): _interact()

# ---------------------------------------------------------------- locomotion
func _state_locomotion(delta: float) -> void:
	var dir := _desired_dir()
	var mag := minf(1.0, dir.length())
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var sprint := _sprinting() and mag > 0.2
	if sprint and crouching: set_crouch(false)     # stand up into the sprint
	var locked := _lock_target != null and not sprint
	var target_speed := 0.0
	if mag > 0.0:
		if crouching: target_speed = lerpf(0.7, CROUCH_SPEED, clampf((mag - 0.2) / 0.5, 0.0, 1.0))
		elif walk_mode and not sprint: target_speed = WALK_SPEED
		elif sprint: target_speed = SPRINT_SPEED
		else: target_speed = lerpf(WALK_SPEED, RUN_SPEED, clampf((mag - 0.25) / 0.45, 0.0, 1.0))
		if locked:
			var loc := global_transform.basis.inverse() * dir.normalized()
			var cap := STRAFE_SPEED if loc.z > -0.3 else BACK_SPEED
			if loc.z > 0.7: cap = RUN_SPEED
			target_speed = minf(target_speed, cap)
		target_speed *= _ground_factor(dir)
	var accel := ACCEL
	if target_speed > RUN_SPEED + 0.5 and hv.length() > RUN_SPEED - 0.5: accel = SPRINT_ACCEL
	if mag > 0.0:
		hv = hv.move_toward(dir.normalized() * target_speed, accel * delta)
	else:
		hv = hv.move_toward(Vector3.ZERO, DECEL * delta)
	velocity.x = hv.x; velocity.z = hv.z
	# facing
	if locked and is_instance_valid(_lock_target):
		var to := _lock_target.global_position - global_position
		to.y = 0.0
		_face(to, delta, 12.0)
	elif mag > 0.0:
		var rate := lerpf(13.0, 6.5, clampf(hv.length() / SPRINT_SPEED, 0.0, 1.0))
		_face(dir, delta, rate)
	state = S.MOVE if hv.length() > 0.25 or mag > 0.0 else S.IDLE
	_loco_anim(hv, locked)
	_footsteps(delta, hv)
	# actions
	if _take("jump") and (is_on_floor() or _coyote > 0.0):
		set_crouch(false)
		_start_jump()
	elif _take("dodge"):
		_start_dodge()
	elif _held("block") or Game.touch_block:
		_begin_block()
	elif _take("attack"):
		var at: Node3D = assassination_target() if crouching else null
		if at != null: _start_assassination(at)
		elif _shadow_win > 0.0 and _try_shadow_step(): pass
		elif hv.length() > SPRINT_SPEED * 0.8 and not locked: attack_key("sprint")
		else: attack_key("light")
	elif _take("heavy"):
		attack_key("heavy")
	elif _take("kick"):
		_start_move("kick")
	elif _take("punch"):
		attack_key("punch")

func _ground_factor(dir: Vector3) -> float:
	var f := 1.0
	var t = world.terrain if world != null else null
	if t != null and t.loaded:
		_surface = t.surface_at(global_position.x, global_position.z)
		match _surface:
			"mud": f *= 0.72
			"water":
				# ankle-deep fords barely slow you; waist-deep water does
				var wd: float = t.water_depth_at(global_position.x, global_position.z)
				f *= lerpf(0.86, 0.5, clampf((wd - 0.15) / 0.9, 0.0, 1.0))
			_: pass
		if dir != Vector3.ZERO:
			# terrain grade along the wish direction (origin is at the feet)
			var ahead := global_position + dir.normalized() * 1.6
			var rise: float = t.sample_height(ahead.x, ahead.z) - t.sample_height(global_position.x, global_position.z)
			var grade: float = clampf(rise / 1.6, -1.0, 1.0)
			f *= 1.0 - maxf(grade, 0.0) * 0.35 + maxf(-grade, 0.0) * 0.1
	if _land_t > 0.0: f *= 0.55
	return f

func _face(dir: Vector3, delta: float, rate: float) -> void:
	if dir.length() < 0.01: return
	var want := atan2(dir.x, dir.z)
	var diff := wrapf(want - rotation.y, -PI, PI)
	var step := clampf(diff, -rate * delta, rate * delta)
	rotation.y = wrapf(rotation.y + step, -PI, PI)
	_yaw_rate = lerpf(_yaw_rate, step / maxf(delta, 0.001), clampf(delta * 10.0, 0.0, 1.0))

func _face_now(dir: Vector3) -> void:
	if dir.length() < 0.01: return
	rotation.y = atan2(dir.x, dir.z)

## Idle / walk / run / sprint (or strafe set when locked) with hysteresis, and
## playback rate matched to the real speed.
func _loco_anim(hv: Vector3, locked: bool) -> void:
	if rig == null or not rig.ok: return
	if _land_t > 0.0 and hv.length() < 1.0: return
	var sp := hv.length()
	if crouching:
		# v0.16 crouch: deep crouch idle / crouch walk, rate matched to speed
		if sp < 0.15: rig.play("Crouch_Idle", 0.25, 1.0)
		else: rig.play("Crouch_Fwd", 0.22, clampf(sp / CROUCH_CLIP_SPEED, 0.6, 1.9))
		_gait = 1
		return
	if locked and sp > 0.3:
		var loc := global_transform.basis.inverse() * hv
		var clip := ""
		if absf(loc.z) >= absf(loc.x) * 0.9:
			if loc.z < 0.0: clip = "K_Walk_Back"
		else:
			clip = "K_Strafe_L" if loc.x > 0.0 else "K_Strafe_R"
		if clip != "":
			rig.play(clip, 0.2, clampf(sp / float(CLIP_SPEED[clip]), 0.6, 1.5))
			_gait = 2
			return
	match _gait:
		0: if sp > 0.35: _gait = 1
		1:
			if sp < 0.18: _gait = 0
			elif sp > 2.7: _gait = 2
		2:
			if sp < 2.3: _gait = 1
			elif sp > 6.7: _gait = 3
		3: if sp < 6.2: _gait = 2
	match _gait:
		0: rig.play("Idle", 0.25, 1.0)
		1: rig.play("Walk", 0.22, clampf(sp / 1.03, 0.75, 1.8))
		2: rig.play("Jog_Fwd", 0.2, clampf(sp / 5.7, 0.62, 1.2))
		3: rig.play("Sprint", 0.2, clampf(sp / 8.8, 0.8, 1.2))

func _footsteps(delta: float, hv: Vector3) -> void:
	if not is_on_floor() or hv.length() < 0.8: return
	_footstep_t -= delta * (0.9 + hv.length() * 0.28)
	if _footstep_t > 0.0: return
	_footstep_t = 0.55
	var pitch := 1.0
	var lvl := -12.0
	match _surface:
		"grass": pitch = 1.08; lvl = -14.0
		"dirt": pitch = 0.96
		"rock": pitch = 1.14; lvl = -9.0
		"mud": pitch = 0.82; lvl = -11.0
		"water": pitch = 0.90; lvl = -10.0
	if crouching: lvl -= 9.0
	if Skills.has("s_silent"): lvl -= 4.0
	Audio.play_sfx("footstep_" + _surface, global_position, pitch * randf_range(0.95, 1.06), lvl)
	if world != null and world.hitfx != null and hv.length() > 4.0:
		world.hitfx.surface_puff(global_position, _surface, clampf(hv.length() / SPRINT_SPEED, 0.2, 1.0) * 0.8)

func _after_move(delta: float, was_floor: bool) -> void:
	if is_on_floor():
		if not was_floor or state == S.JUMP:
			_on_land()
		_coyote = COYOTE_TIME
		_air_t = 0.0
		_fall_v = 0.0
	else:
		_coyote = maxf(0.0, _coyote - delta)
		_air_t += delta
		if state in [S.IDLE, S.MOVE] and _air_t > 0.22 and velocity.y < -2.0:
			state = S.JUMP
			rig.play("Jump", 0.25, 1.0)
	_land_t = maxf(0.0, _land_t - delta)

# ---------------------------------------------------------------- jump / fall
func _start_jump() -> void:
	if not _spend(STAMINA_COST["jump"]): return
	crouching = false
	state = S.JUMP
	_state_t = 0.0
	_coyote = 0.0
	velocity.y = JUMP_V
	rig.play("Jump_Start", 0.08, 1.6, 0.22, true)
	Audio.play_sfx("cloth", global_position, 1.05, -3.0)

func _state_air(delta: float) -> void:
	var dir := _desired_dir()
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var cap := maxf(hv.length(), RUN_SPEED * 0.7)
	if dir != Vector3.ZERO:
		hv = hv.move_toward(dir.normalized() * cap, AIR_ACCEL * delta)
		_face(dir, delta, 5.0)
	velocity.x = hv.x; velocity.z = hv.z
	if rig.current() == "Jump_Start" and (_state_t > 0.45 or velocity.y < -1.0):
		rig.play("Jump", 0.3, 1.0)
	# plunging cut: attack in the air with a blade out
	if _take("attack") and drawn and _carry == 0 and _air_t > 0.06:
		var aid := String(WEAPONS[weapon].get("air", ""))
		if aid != "":
			_plunge_t = 0.0
			_plunge_landed = false
			_start_move(aid)

func _on_land() -> void:
	var impact := -_fall_v
	if state == S.JUMP:
		state = S.IDLE
		_state_t = 0.0
		var hv := Vector3(velocity.x, 0.0, velocity.z)
		if hv.length() < 2.0 or impact > HARD_LAND_V:
			rig.play("Jump_Land", 0.08, 1.5, 0.05, true)
			_land_t = 0.35 if impact > HARD_LAND_V else 0.18
		if camera != null and impact > 6.0: camera.land_dip(clampf((impact - 6.0) / 8.0, 0.0, 1.0))
		Audio.play_sfx("footstep_" + _surface, global_position, 0.9, 2.0)
		if impact > 6.0: Audio.play_sfx("land", global_position, 1.0, clampf(impact - 10.0, -6.0, 2.0))
		if impact > 17.0:
			_damage((impact - 17.0) * 3.0, true)

# ---------------------------------------------------------------- swimming
## Deep water (the lake, the river's pools) is swum, not walked on the bed:
## the blade goes back in its saya, the body floats with the head clear, and
## a fast stroke costs stamina like a sprint.
func _check_water() -> void:
	if world == null or world.terrain == null or not world.terrain.loaded: return
	var t = world.terrain
	var p := global_position
	_water_surf = t.water_surface_y(p.x, p.z)
	if _water_surf == -INF:
		if state == S.SWIM: _leave_swim()
		return
	var depth: float = _water_surf - t.sample_height(p.x, p.z)
	if state == S.SWIM:
		if depth < SWIM_EXIT: _leave_swim()
	elif depth > SWIM_ENTER and p.y < _water_surf - 0.7 and state != S.DEATHBLOW:
		_enter_swim()

func is_swimming() -> bool:
	return state == S.SWIM

## HUD: a perfect deflect just happened and a light attack will riposte.
func riposte_ready() -> bool:
	return _riposte_t > 0.0 and state in [S.BLOCK, S.IDLE, S.MOVE]

func _enter_swim() -> void:
	crouching = false
	var impact := clampf(-velocity.y / 9.0, 0.25, 1.0)
	state = S.SWIM
	_state_t = 0.0
	_stroke_t = 0.6
	trail.stop()
	_blocking = false
	_queued = ""
	_buf.clear()
	_carry = 0
	if rig != null and rig.ik != null: rig.ik.influence = 0.0
	if weapon == "fists": drawn = false
	elif drawn: _set_drawn(false)
	rig.set_speed(1.0)
	if _lock_target != null:
		_lock_target = null
		lock_changed.emit(null)
	velocity.y *= 0.25
	_fall_v = 0.0
	var at := Vector3(global_position.x, _water_surf, global_position.z)
	Audio.play_sfx("footstep_water", at, 0.62, 2.0 + impact * 4.0)
	if impact > 0.5: Audio.play_sfx("bodyfall", at, 0.7, -4.0)
	if world != null and world.hitfx != null: world.hitfx.surface_puff(at, "water", 0.8 + impact)
	rig.play("Swim_Idle", 0.3, 1.0)

func _leave_swim() -> void:
	state = S.IDLE
	_state_t = 0.0
	_gait = 0
	rig.play("Idle", 0.3, 1.0)

func _state_swim(delta: float) -> void:
	var dir := _desired_dir()
	var mag := minf(1.0, dir.length())
	var fast := _sprinting() and mag > 0.2 and stamina > 0.5
	var target := (SWIM_FAST if fast else SWIM_SPEED) * mag
	if fast: _drain(SWIM_DRAIN * delta)
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if mag > 0.0: hv = hv.move_toward(dir.normalized() * target, 2.8 * delta)
	else: hv = hv.move_toward(Vector3.ZERO, 1.8 * delta)
	velocity.x = hv.x; velocity.z = hv.z
	if mag > 0.0: _face(dir, delta, 3.4)
	var sp := hv.length()
	# buoyancy: a damped spring to the floating height with a slow bob; the
	# rig is lifted so the clip's water line sits at the surface, a moving
	# swimmer lying flatter and riding higher
	var sink := lerpf(SWIM_SINK_IDLE, SWIM_SINK_FWD, clampf(sp / 1.4, 0.0, 1.0))
	var want_y := _water_surf - SWIM_BODY + sin(_state_t * 2.1) * 0.03
	var vy := clampf((want_y - global_position.y) * 4.0, -4.0, 2.5)
	velocity.y = lerpf(velocity.y, vy, clampf(delta * 6.0, 0.0, 1.0))
	rig.position.y = move_toward(rig.position.y, SWIM_BODY - sink, delta * 3.0)
	if sp > 0.45: rig.play("Swim_Fwd", 0.4, clampf(sp / SWIM_CLIP_SPEED, 0.75, 1.5))
	else: rig.play("Swim_Idle", 0.45, 1.0)
	_stroke_t -= delta * (0.55 + sp * 0.4)
	if _stroke_t <= 0.0:
		_stroke_t = 1.0
		var at := Vector3(global_position.x, _water_surf, global_position.z)
		Audio.play_sfx("footstep_water", at, randf_range(0.66, 0.8), -5.0 if sp > 0.45 else -13.0)
		if sp > 0.45 and world != null and world.hitfx != null:
			world.hitfx.surface_puff(at + _fwd() * 0.5, "water", 0.35 + sp * 0.1)

# ---------------------------------------------------------------- weapons
func select_weapon(id: String) -> void:
	if not WEAPONS.has(id) or state in [S.ATTACK, S.DEATHBLOW, S.DEAD, S.SWIM]: return
	if id == weapon:
		if not drawn: begin_draw()
		return
	var was_drawn := drawn or _carry == 1
	_combo = {"light": -1, "heavy": -1, "punch": -1}
	_carry = 0
	rig.ik.influence = 0.0
	weapon = id
	drawn = false
	rig.set_weapon(id, false)
	Game.settings["last_weapon"] = id
	weapon_changed.emit(id)
	Audio.play_sfx("ui_select", null, 1.1, -2.0)
	_float_text(String(WEAPONS[id]["name"]), Color(0.92, 0.86, 0.66))
	if id == "fists" or was_drawn:
		begin_draw()

func _cycle_weapon(step: int) -> void:
	var i := WEAPON_ORDER.find(weapon)
	select_weapon(WEAPON_ORDER[posmod(i + step, WEAPON_ORDER.size())])

func weapon_name() -> String:
	return String(WEAPONS[weapon]["name"])

func is_sheathed() -> bool:
	return not drawn

func begin_draw(fast := false, then := "") -> void:
	if weapon == "fists":
		drawn = true
		rig.set_weapon("fists", true)
		if then != "": _start_move(then)
		return
	if drawn:
		if then != "": _start_move(then)
		return
	if _carry == 1:
		if then != "": _after_draw = then
		return
	_carry = 1
	_carry_t = 0.0
	_carry_len = 0.30 if fast else 0.52
	_carry_swapped = false
	_after_draw = then
	_iai_pending = then != "" and Skills.has("b_iai")
	rig.reach_for(rig.weapon_mesh_name(weapon))

## Whoosh per weapon: fists are quick and light, the long weapons heavier.
func _swing_sound(heavy: bool) -> void:
	var pitch := 1.0
	match weapon:
		"fists": pitch = 1.25
		"nodachi": pitch = 0.88
		"yari": pitch = 0.93
	Audio.play_sfx("swing_heavy" if heavy else "swing_light", global_position, pitch * randf_range(0.95, 1.05), -3.0 if weapon == "fists" else 0.0)

func begin_sheathe() -> void:
	if weapon == "fists":
		drawn = false
		rig.set_weapon("fists", false)
		return
	if not drawn or _carry == -1: return
	_carry = -1
	_carry_t = 0.0
	_carry_len = 0.62
	_carry_swapped = false
	_after_draw = ""

## Hand-to-hilt reach: the IK pulls the right hand onto the grip, the weapon
## changes parent at the moment the hand is on it, and the IK lets go so the
## arm carries the blade out (or the hand leaves the sheathed hilt).
func _update_carry(delta: float) -> void:
	if rig == null or rig.ik == null: return
	if _carry == 0:
		rig.ik.influence = move_toward(rig.ik.influence, 0.0, delta * 6.0)
		return
	if state in [S.HIT, S.STAGGER, S.DODGE, S.DEAD, S.JUMP]:
		# interrupted: finish instantly so the blade is never left in limbo
		if _carry == 1: _set_drawn(true)
		else: _set_drawn(false)
		_carry = 0
		_iai_pending = false
		return
	_carry_t += delta
	var swap := _carry_len * (0.45 if _carry == 1 else 0.58)
	var f := 0.0
	if _carry_t < swap: f = smoothstep(0.0, swap, _carry_t)
	else: f = 1.0 - smoothstep(swap, _carry_len, _carry_t)
	if _carry == 1 and not _carry_swapped: rig.reach_for(rig.weapon_mesh_name(weapon))
	elif _carry == -1: rig.reach_for_mount(rig.weapon_mesh_name(weapon))
	rig.ik.influence = f
	if not _carry_swapped and _carry_t >= swap:
		_carry_swapped = true
		_set_drawn(_carry == 1)
		Audio.play_sfx("draw" if _carry == 1 else "sheathe", global_position, 1.0 if weapon == "katana" else 0.9, 0.0)
	if _carry_t >= _carry_len:
		var then := _after_draw
		_carry = 0
		_after_draw = ""
		if then != "" and state in [S.IDLE, S.MOVE, S.BLOCK]:
			_start_move(then)
		_iai_pending = false

func _set_drawn(v: bool) -> void:
	drawn = v
	rig.set_drawn(v)

## Which move a button means for the current weapon, advancing that combo.
func attack_key(kind: String) -> void:
	var w: Dictionary = WEAPONS[weapon]
	var id := ""
	match kind:
		"light", "heavy":
			var list: Array = w[kind]
			if kind == "light" and _riposte_t > 0.0 and String(w.get("riposte", "")) != "":
				# answer a perfect deflect: one fast, heavy-posture cut
				_riposte_t = 0.0
				var rid := String(w["riposte"])
				if not bool(MOVES[rid].get("unarmed", false)) and not drawn:
					begin_draw(true, rid)
				else:
					_start_move(rid)
				return
			_combo[kind] = (int(_combo[kind]) + 1) % list.size()
			id = list[_combo[kind]]
			_combo["heavy" if kind == "light" else "light"] = -1
		"sprint": id = String(w["sprint"])
		"punch":
			var pl := ["jab", "cross", "hook"]
			_combo["punch"] = (int(_combo["punch"]) + 1) % pl.size()
			id = pl[_combo["punch"]]
	if id == "": return
	var m: Dictionary = MOVES[id]
	if not bool(m.get("unarmed", false)) and not drawn:
		begin_draw(true, id)
		return
	_start_move(id)

## Compatibility with older callers/tests.
func _start_attack(key: String) -> void:
	if key.begins_with("light"): attack_key("light")
	elif key.begins_with("heavy"): attack_key("heavy")
	else: attack_key(key)

func _start_move(id: String) -> void:
	if not MOVES.has(id): return
	var m: Dictionary = MOVES[id]
	if not rig.has_clip(String(m["clip"])): return
	if not _spend(_move_cost(id, m)): return
	_move_id = id
	_move = m
	_move_t = float(m.get("from", 0.0))
	_hit_ids = {}
	crouching = false
	_shadow_mult = 1.0
	_iai_move = _iai_pending and not bool(m.get("unarmed", false))
	_iai_pending = false
	_iai_shown = false
	_queued = ""
	state = S.ATTACK
	_state_t = 0.0
	var spd := float(m["spd"]) * float(Game.stance_info()["spd"])
	rig.play(String(m["clip"]), 0.07, spd, _move_t, true)
	# aim: stick direction, else lock target, else a nearby enemy in front
	var dir := _desired_dir()
	var tgt := _lock_target if _lock_target != null else _nearest_enemy(4.5, 75.0)
	if tgt != null and is_instance_valid(tgt):
		var to := tgt.global_position - global_position
		to.y = 0.0
		if dir == Vector3.ZERO or to.normalized().dot(dir.normalized()) > 0.3:
			dir = to
	if dir != Vector3.ZERO: _face_now(dir)
	if not bool(m.get("unarmed", false)) and rig.blade_node() != null:
		_bind_trail()
		trail.local_space = false
		trail.start()
	_swing_sound(bool(m.get("heavy", false)))

## The ribbon covers the last ~60 cm of the blade (the whole shaft of a yari
## made a sheet the size of a door on a sweep).
func _bind_trail() -> void:
	var tip := maxf(0.6, rig.blade_length())
	trail.bind_node(rig.blade_node(), maxf(0.25, tip - 0.62), tip)

func _state_attack(delta: float) -> void:
	var m := _move
	if bool(m.get("air", false)):
		_state_air_attack(delta)
		return
	var spd := float(m["spd"]) * float(Game.stance_info()["spd"])
	_move_t += delta * spd
	var h: Array = m["hit"]
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var fwd := _fwd()
	var lunge := float(m["lunge"])
	var tgt := _lock_target if _lock_target != null else _nearest_enemy(4.0, 60.0)
	if tgt != null and is_instance_valid(tgt):
		var gap := Vector3(tgt.global_position.x - global_position.x, 0.0, tgt.global_position.z - global_position.z).length()
		if gap < 1.45: lunge = 0.0
		elif _move_t < float(h[1]): _face((tgt.global_position - global_position) * Vector3(1, 0, 1), delta, 9.0)
	if _move_t < float(h[0]) - 0.12:
		hv = hv.move_toward(fwd * lunge * 0.3, 20.0 * delta)
	elif _move_t < float(h[1]):
		hv = hv.move_toward(fwd * lunge, 45.0 * delta)
	else:
		hv = hv.move_toward(Vector3.ZERO, 22.0 * delta)
	velocity.x = hv.x; velocity.z = hv.z
	if _move_t >= float(h[0]) and _move_t <= float(h[1]) + 0.02:
		_hit_scan(m)
	# queue the follow-up
	for k in ["attack", "heavy", "punch", "kick"]:
		if _buf.has(k) and _move_t > float(h[0]) - 0.05:
			_buf.erase(k)
			_queued = k
	if _queued != "" and _move_t >= float(m["chain"]):
		var q := _queued
		_queued = ""
		trail.stop()
		_combo_t = COMBO_RESET
		match q:
			"attack": attack_key("light")
			"heavy": attack_key("heavy")
			"punch": attack_key("punch")
			"kick": _start_move("kick")
		return
	if _move_t > float(h[0]) and _take("dodge"):
		if _start_dodge(): return
	if _move_t >= float(m["end"]):
		trail.stop()
		_combo_t = COMBO_RESET
		state = S.IDLE
		_state_t = 0.0
		_gait = 0
		if m.has("rec") and rig.has_clip(String(m["rec"])):
			rig.play(String(m["rec"]), 0.1, 1.15, 0.0, true)
			_land_t = 0.0

## Plunging cut: the windup plays on the way up, the pose holds while the body
## drops, and the cut (a full circle, so it also clears a crowd) lands with
## the feet.
func _state_air_attack(delta: float) -> void:
	var m := _move
	var h: Array = m["hit"]
	var spd := float(m["spd"]) * float(Game.stance_info()["spd"])
	var hold := float(m.get("hold", float(h[0]) - 0.04))
	if not _plunge_landed and not is_on_floor():
		_plunge_t += delta
		if _move_t < hold:
			_move_t += delta * spd
			rig.set_speed(spd)
		else:
			rig.set_speed(0.0)
		if _plunge_t > 0.14: velocity.y = minf(velocity.y, -PLUNGE_V)
		var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(_fwd() * 2.2, 8.0 * delta)
		velocity.x = hv.x; velocity.z = hv.z
		if _plunge_t > 3.0:
			# a very long drop: give the cut up and just fall
			trail.stop()
			state = S.JUMP
			_state_t = 0.0
			rig.set_speed(1.0)
			rig.play("Jump", 0.2, 1.0)
		return
	if not _plunge_landed:
		_plunge_landed = true
		_move_t = maxf(_move_t, hold)
		rig.set_speed(spd)
		Audio.play_sfx("land", global_position, 0.8, 1.0)
		Audio.play_sfx("footstep_" + _surface, global_position, 0.75, 2.0)
		if world != null and world.hitfx != null:
			world.hitfx.surface_puff(global_position, _surface, 1.4)
		if camera != null: camera.land_dip(0.55)
		Audio.haptic("hit")
		_fall_v = 0.0
	_move_t += delta * spd
	velocity.x = move_toward(velocity.x, 0.0, 24.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 24.0 * delta)
	if _move_t >= float(h[0]) and _move_t <= float(h[1]) + 0.02:
		_hit_scan(m)
	if _move_t > float(h[1]) and _take("dodge"):
		if _start_dodge(): return
	if _move_t >= float(m["end"]):
		trail.stop()
		_combo_t = COMBO_RESET
		state = S.IDLE
		_state_t = 0.0
		_gait = 0

func _hit_scan(m: Dictionary) -> void:
	var reach := float(m["reach"])
	var arc := float(m["arc"])
	var stance_i: Dictionary = Game.stance_info()
	# v0.16 Spirit Blade Mastery: unblockable, +50% posture. Iaijutsu: the
	# first cut out of the sheath. Shadow Step: the strike from behind.
	var mastery := _spirit_blade_t > 0.0 and Skills.has("p_blade")
	# the draw-cut / Shadow Step bonus belongs to the ground cut that started
	# it, never to a later air or mounted swing
	if state != S.ATTACK:
		_iai_move = false
		_shadow_mult = 1.0
	var dmg_v := float(m["dmg"]) * _dmg_mult * float(stance_i["dmg"]) * _shadow_mult
	var pos_v := float(m["pos"]) * float(stance_i["posture"])
	if mastery: pos_v *= 1.5
	if _iai_move:
		dmg_v *= 1.8
		pos_v *= 2.0
	var info := {
		"damage": dmg_v,
		"posture": pos_v,
		"heavy": bool(m.get("heavy", false)) or _shadow_mult > 1.0 or _iai_move,
		"spirit": _spirit_blade_t > 0.0,
		"source": self,
		"kick": bool(m.get("kick", false)),
		"unblockable": mastery or _iai_move,
	}
	var any := false
	for h in _scan_hurtboxes(reach, arc, "enemy_hurtbox"):
		var e = h.get_parent()
		if e == null or _hit_ids.has(e.get_instance_id()): continue
		_hit_ids[e.get_instance_id()] = true
		if e.has_method("take_hit"):
			e.take_hit(info)
			any = true
			if bool(m.get("kick", false)) and e.has_method("knock_down") and not bool(e.get("is_dead")):
				if float(e.get("posture")) >= float(e.get("max_posture")) * 0.55: e.knock_down()
	if any and bool(m.get("riposte", false)):
		_float_text("RIPOSTE", Color(1.0, 0.82, 0.45))
		Audio.play_sfx("clash", global_position, 0.8, -2.0)
		if camera != null: camera.impulse(_fwd(), 0.05)
		_hitstop(0.13)
	elif any and bool(m.get("air", false)) and camera != null:
		camera.impulse(Vector3.DOWN, 0.05)
	if any:
		make_noise(15.0, 0.6)
		if _iai_move and not _iai_shown:
			_iai_shown = true
			_float_text("IAI", Color(1.0, 0.86, 0.5))
		_hitstop(0.055 if not info["heavy"] else 0.09)
		if world != null and world.hud != null: world.hud.flash_hit()
		Audio.play_sfx("hit_blunt" if weapon == "fists" else "hit_blade", global_position, randf_range(0.94, 1.06), 0.0 if info["heavy"] else -2.0)
		if camera != null: camera.impulse(_fwd(), 0.02 if not info["heavy"] else 0.035)

func _scan_hurtboxes(reach: float, arc: float, group: String) -> Array:
	var space := get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = reach
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	var fwd := _fwd()
	var off := 0.0 if arc >= 300.0 else reach * 0.45
	params.transform = Transform3D(Basis(), global_position + Vector3(0, 1.05, 0) + fwd * off)
	params.collision_mask = 4
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var out := []
	for r in space.intersect_shape(params, 16):
		var c = r.get("collider")
		if c == null or not (c is Area3D) or not c.is_in_group(group): continue
		var parent = c.get_parent()
		if parent == null or parent == self: continue
		var to: Vector3 = parent.global_position - global_position
		to.y = 0.0
		if to.length() > reach + 0.6: continue
		if arc < 300.0 and to.length() > 0.3 and rad_to_deg(fwd.angle_to(to.normalized())) > arc * 0.5:
			continue
		out.append(c)
	return out

func _nearest_enemy(rng: float, half_angle: float) -> Node3D:
	if world == null: return null
	var best: Node3D = null
	var bd := rng
	var fwd := _fwd()
	for e in world.enemies:
		if not is_instance_valid(e) or e.is_dead: continue
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > bd: continue
		if d > 0.5 and rad_to_deg(fwd.angle_to(to / d)) > half_angle: continue
		bd = d
		best = e
	return best

# ---------------------------------------------------------------- guard / deflect
func _begin_block() -> void:
	state = S.BLOCK
	_state_t = 0.0
	_blocking = true
	var bonus := 0.06 if stance == "moon" else 0.0
	_deflect_t = (DEFLECT_WINDOW + bonus) * (1.2 if Skills.has("b_deflect") else 1.0)
	crouching = false
	if not drawn and weapon != "fists": begin_draw(true)
	elif weapon == "fists" and not drawn: begin_draw()

func _state_block(delta: float) -> void:
	_deflect_t = maxf(0.0, _deflect_t - delta)
	var dir := _desired_dir()
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if dir != Vector3.ZERO: hv = hv.move_toward(dir.normalized() * GUARD_SPEED, ACCEL * delta)
	else: hv = hv.move_toward(Vector3.ZERO, DECEL * delta)
	velocity.x = hv.x; velocity.z = hv.z
	var face := Vector3.ZERO
	if _lock_target != null and is_instance_valid(_lock_target):
		face = _lock_target.global_position - global_position
	else:
		var yaw := _cam_yaw()
		face = Vector3(-sin(yaw), 0.0, -cos(yaw))
	face.y = 0.0
	_face(face, delta, 10.0)
	_loco_anim(hv, true)
	if not (_held("block") or Game.touch_block):
		state = S.IDLE
		_blocking = false
		return
	if _take("attack"):
		_blocking = false
		attack_key("light")
	elif _take("dodge") and _start_dodge():
		_blocking = false
	elif _take("kick"):
		_start_move("kick")
		if state != S.BLOCK: _blocking = false

func is_perfect_deflect() -> bool:
	return state == S.BLOCK and _deflect_t > 0.0

# ---------------------------------------------------------------- dodge
func _start_dodge() -> bool:
	if stamina <= 0.5:
		_refuse()
		return false
	crouching = false
	_dodge_spd = 1.0
	if Skills.has("b_mikiri") and _try_mikiri(): return true
	var dir := _desired_dir()
	var locked := _lock_target != null and is_instance_valid(_lock_target)
	_dodge_side = false
	state = S.DODGE
	_state_t = 0.0
	trail.stop()
	if dir == Vector3.ZERO:
		# no stick: a quick backstep out of range rather than a roll into the enemy
		dir = -_fwd()
		locked = true
	if locked:
		var loc := global_transform.basis.inverse() * dir.normalized()
		if loc.z < 0.5:
			_dodge_side = true
			var clip := "K_Dodge_B"
			if absf(loc.x) > absf(loc.z): clip = "K_Dodge_L" if loc.x > 0.0 else "K_Dodge_R"
			_dodge_dir = dir.normalized()
			_dodge_len = 0.5
			_iframe = Vector2(0.02, 0.3)
			rig.play(clip, 0.06, 0.8, 0.0, true)
			Audio.play_sfx("cloth", global_position, 1.0, -2.0)
			_spend(STAMINA_COST["dodge"])
			return true
	_dodge_dir = dir.normalized() if dir != Vector3.ZERO else _fwd()
	_face_now(_dodge_dir)
	_dodge_len = 1.0
	_iframe = Vector2(0.04, 0.44)
	rig.play("Roll", 0.06, 1.45, 0.0, true)
	Audio.play_sfx("cloth", global_position, 1.0, -2.0)
	Audio.haptic("hit")
	_spend(STAMINA_COST["roll"])
	return true

func _state_dodge(delta: float) -> void:
	var t := _state_t / _dodge_len
	var spd := 0.0
	if _dodge_side: spd = lerpf(7.5, 0.5, clampf(t * 1.3, 0.0, 1.0))
	else: spd = lerpf(7.4, 2.2, clampf((t - 0.15) / 0.6, 0.0, 1.0))
	var hv := _dodge_dir * spd * _dodge_spd
	velocity.x = hv.x; velocity.z = hv.z
	if _shadow_win > 0.0 and _take("attack") and _try_shadow_step(): return
	if _state_t >= _dodge_len * (0.8 if _dodge_side else 0.86):
		state = S.IDLE
		_state_t = 0.0
		_gait = 2 if _desired_dir() != Vector3.ZERO else 0

func has_iframes() -> bool:
	return state == S.DODGE and _state_t >= _iframe.x and _state_t <= _iframe.y

# ---------------------------------------------------------------- reactions
func _state_recover(delta: float) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, 14.0 * delta)
	if _state_t < 0.2: hv = _react_push * (1.0 - _state_t / 0.2)
	velocity.x = hv.x; velocity.z = hv.z
	if _state_t >= _react_len:
		state = S.IDLE
		_state_t = 0.0
		_gait = 0

func take_hit(info: Dictionary) -> void:
	if _dead or cinematic: return
	if has_iframes():
		_float_text("dodge", Color(0.7, 0.9, 1.0))
		_add_focus(FOCUS_PER_DODGE)
		_arm_shadow_step(info.get("source"))
		return
	var dmg := float(info.get("damage", 10.0))
	var src = info.get("source")
	var src_pos: Vector3 = global_position + _fwd() * 2.0
	if src != null and is_instance_valid(src) and src is Node3D: src_pos = (src as Node3D).global_position
	if state == S.MOUNTED or state == S.MOUNTING:
		_damage(dmg * 0.8, true)
		_hitstop(0.05)
		return
	if state == S.SWIM:
		# no guard and no footing: the blow lands, but there is nothing to stagger
		_damage(dmg, true)
		_hitstop(0.05)
		return
	# v0.16 perilous (危): a sweep passes under a jump; neither can be blocked,
	# and only a perfect deflect (or Mikiri) answers a thrust
	var per := String(info.get("perilous", ""))
	if per == "sweep" and (state == S.JUMP or not is_on_floor()):
		_float_text("JUMPED", Color(0.75, 0.92, 1.0))
		_add_focus(FOCUS_PER_DODGE * 1.5)
		return
	crouching = false
	if per != "" and state == S.BLOCK and not (per == "thrust" and is_perfect_deflect()):
		_blocking = false
		state = S.IDLE
		_float_text("危", Color(1.0, 0.3, 0.2))
	if is_perfect_deflect():
		_perfect_deflect(info, src_pos)
		return
	if state == S.BLOCK:
		dmg *= 0.22
		var pd := float(info.get("posture", 10.0))
		var sc := pd * 0.35
		# an empty stamina bar can't soak the blow: the guard buckles sooner
		_add_posture(pd * (0.75 if stamina >= sc else 1.1) * (0.85 if Skills.has("b_posture") else 1.0))
		_drain(sc)
		Audio.play_sfx("block", global_position, 1.0, 0.0)
		Audio.haptic("hit")
		if world != null and world.hitfx != null:
			world.hitfx.impact(global_position + Vector3(0, 1.3, 0) + (src_pos - global_position).normalized() * 0.5,
				(global_position - src_pos).normalized(), 4.0, "spark")
		_damage(dmg, false)
		if _dead: return
		if posture >= max_posture: _enter_stagger()
		else: _hitstop(0.05)
		return
	_damage(dmg, true)
	if _dead: return
	_add_posture(float(info.get("posture", 10.0)) * 0.5)
	trail.stop()
	if posture >= max_posture:
		_enter_stagger()
	else:
		state = S.HIT
		_state_t = 0.0
		var heavy := bool(info.get("heavy", false))
		var away := global_position - src_pos
		away.y = 0.0
		_react_push = away.normalized() * (3.2 if heavy else 1.2)
		if heavy:
			_react_len = 0.75
			rig.play("Hit_Knockback", 0.05, 1.1, 0.0, true)
		else:
			_react_len = 0.36
			rig.play("Hit_Chest" if randf() < 0.5 else "Hit_Head", 0.05, 1.0, 0.0, true)
	_hitstop(0.07)

func _perfect_deflect(info: Dictionary, src_pos: Vector3) -> void:
	_riposte_t = RIPOSTE_WINDOW
	Audio.play_sfx("clash", global_position, 1.0, 2.0)
	Audio.haptic("deflect")
	_add_focus(FOCUS_PER_DEFLECT)
	_set_stamina(stamina + 10.0)
	if Skills.has("p_mend"): heal(3.0)
	make_noise(14.0, 0.5)
	var src = info.get("source")
	if src != null and is_instance_valid(src) and src.has_method("on_deflected"):
		src.on_deflected(self)
	if world != null:
		if world.hud != null: world.hud.deflect_flash()
		if world.hitfx != null:
			world.hitfx.impact(global_position + Vector3(0, 1.35, 0) + (src_pos - global_position).normalized() * 0.6,
				(src_pos - global_position).normalized(), 18.0, "spark")
	if focus >= max_focus:
		Game.notice.emit("Focus ready — press %s for Spirit Blade" % Game.bind_label("special"), "focus")
	_float_text("DEFLECT", Color(1.0, 0.95, 0.7))
	Quests.progress("deflect", "", 1)

func _damage(v: float, react: bool) -> void:
	if v > 0.0:
		_since_hurt = 0.0
		hp = maxf(0.0, hp - v)
		Game.hp = hp
		hp_changed.emit(hp, max_hp)
		if react and world != null and world.hud != null: world.hud.damage_flash(v)
		if world != null and world.hitfx != null:
			world.hitfx.label(global_position, "-%d" % int(round(v)), Color(1.0, 0.45, 0.4))
	if hp <= 0.0: _die()

func _add_posture(v: float) -> void:
	posture = clampf(posture + v, 0.0, max_posture)
	_posture_idle = 0.0
	Game.posture = posture
	posture_changed.emit(posture, max_posture)

func _update_posture(delta: float) -> void:
	_posture_idle += delta
	if _posture_idle > POSTURE_RECOVER_DELAY and state != S.BLOCK and posture > 0.0:
		var rate := POSTURE_RECOVER * (1.0 + float(Game.stance_info()["posture"]) * 0.2)
		if Skills.has("b_posture"): rate *= 1.3
		posture = maxf(0.0, posture - rate * delta)
		Game.posture = posture
		posture_changed.emit(posture, max_posture)

# ---------------------------------------------------------------- stamina
func _update_stamina(delta: float) -> void:
	_stamina_flash = maxf(0.0, _stamina_flash - delta)
	var mounted := state == S.MOUNTED or state == S.MOUNTING
	var hv := Vector3(velocity.x, 0.0, velocity.z).length()
	if not mounted and state == S.MOVE and is_on_floor() and hv > RUN_SPEED + 0.6 and _sprinting():
		_drain(SPRINT_DRAIN * delta)
		return
	# nothing refills mid-commitment: the pause starts when the action ends
	if not mounted and state in [S.ATTACK, S.DODGE, S.JUMP, S.STAGGER]: return
	_stamina_idle += delta
	if stamina >= max_stamina: return
	if _stamina_idle < (STAMINA_WINDED_DELAY if winded else STAMINA_DELAY): return
	var rate := STAMINA_REGEN
	if state == S.BLOCK: rate *= 0.4
	elif state == S.SWIM: rate *= 0.5
	elif hv > 0.5 and not mounted: rate *= 0.85
	_set_stamina(stamina + rate * delta)
	if winded and stamina >= max_stamina * 0.34: winded = false

func _set_stamina(v: float) -> void:
	v = clampf(v, 0.0, max_stamina)
	if is_equal_approx(v, stamina): return
	stamina = v
	stamina_changed.emit(stamina, max_stamina)

## Take stamina without a gate (sprinting, blocked blows).
func _drain(v: float) -> void:
	if v <= 0.0: return
	_set_stamina(stamina - v)
	_stamina_idle = 0.0
	if stamina <= 0.0 and not winded:
		winded = true
		_stamina_flash = 0.8
		Audio.play_sfx("cloth", global_position, 0.8, -6.0)

## An action may start while anything is left in the tank (it can overdraw to 0,
## which winds you); with nothing left it is refused.
func _spend(v: float) -> bool:
	if stamina <= 0.5 and v > 0.0:
		_refuse()
		return false
	_drain(v)
	return true

func _refuse() -> void:
	if _stamina_flash < 0.3:
		_float_text("Winded", Color(0.95, 0.78, 0.42))
	_stamina_flash = 0.8

func _move_cost(id: String, m: Dictionary) -> float:
	if bool(m.get("mounted", false)): return STAMINA_COST["mounted"]
	if bool(m.get("kick", false)): return STAMINA_COST["kick"]
	var c: float = STAMINA_COST["heavy"] if bool(m.get("heavy", false)) else STAMINA_COST["light"]
	if id == String(WEAPONS[weapon]["sprint"]): c += STAMINA_COST["sprint"]
	var w := "fists" if bool(m.get("unarmed", false)) else weapon
	return c * float(WEAPON_STAMINA.get(w, 1.0))

func stamina_ratio() -> float:
	return stamina / maxf(max_stamina, 1.0)

func _enter_stagger() -> void:
	state = S.STAGGER
	_state_t = 0.0
	_react_len = 1.25
	_react_push = Vector3.ZERO
	posture = 0.0
	Game.posture = 0.0
	posture_changed.emit(posture, max_posture)
	_blocking = false
	rig.play("K_Hit_B", 0.06, 0.72, 0.0, true)
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
	_spirit_blade_t = 15.0 if Skills.has("p_blade") else 10.0
	_dmg_mult = 1.35
	Audio.play_sfx("heal", global_position, 0.8, -3.0)
	if Skills.has("p_blade"):
		Game.notice.emit("Spirit Blade — time slows, your cuts pass through any guard", "focus")
	else:
		Game.notice.emit("Spirit Blade — time slows, damage up", "focus")

# ---------------------------------------------------------------- healing (v0.15)
## Three ways to get health back, none of which existed before:
##  * the gourd (B): a drink restores GOURD_HEAL over GOURD_TIME, a few drinks
##    per fill; refilled at checkpoints/shrines, by herbs and by hunted meat;
##  * natural recovery: out of combat and unhurt for REGEN_DELAY seconds, health
##    climbs back at REGEN_RATE per second;
##  * Game.heal_player() for pickups (hidden caches, herbs, meat).
const GOURD_HEAL := 45.0
const GOURD_TIME := 1.2
const REGEN_DELAY := 7.0
const REGEN_RATE := 2.5
var _heal_left := 0.0
var _since_hurt := 99.0
var _heal_tip := false
var heal_glow := 0.0          ## 0..1, read by the HUD and the drink effect

func heal(v: float) -> void:
	if _dead or v <= 0.0: return
	hp = minf(max_hp, hp + v)
	Game.hp = hp
	hp_changed.emit(hp, max_hp)
	heal_glow = 1.0

func drink_gourd() -> void:
	if _dead or cinematic: return
	if _heal_left > 0.0: return
	if Game.gourd <= 0:
		Game.notice.emit("Gourd is empty — rest at a shrine or checkpoint, gather herbs or hunt", "warn")
		return
	if hp >= max_hp - 0.5:
		Game.notice.emit("Already at full health", "warn")
		return
	Game.set_gourd(Game.gourd - 1)
	_heal_left = GOURD_HEAL
	Audio.play_sfx("drink", global_position, 1.0, 0.0)
	_float_text("+%d" % int(GOURD_HEAL), Color(0.62, 1.0, 0.62))
	if world != null and world.hitfx != null and world.hitfx.has_method("heal_burst"):
		world.hitfx.heal_burst(global_position + Vector3(0, 1.1, 0))

func _update_healing(delta: float) -> void:
	_since_hurt += delta
	heal_glow = maxf(0.0, heal_glow - delta * 1.4)
	if _dead: return
	if _heal_left > 0.0:
		var step := minf(_heal_left, GOURD_HEAL / GOURD_TIME * delta)
		_heal_left -= step
		heal(step)
	elif _since_hurt > REGEN_DELAY and not Game.in_combat and hp < max_hp:
		hp = minf(max_hp, hp + REGEN_RATE * delta)
		Game.hp = hp
		hp_changed.emit(hp, max_hp)
	if not _heal_tip and hp < max_hp * 0.55 and Game.gourd > 0 and not cinematic:
		_heal_tip = true
		Game.notice.emit("Wounded — press %s to drink from your gourd" % Game.bind_label("heal"), "tip")

func _die() -> void:
	if _dead: return
	if state == S.MOUNTED or state == S.MOUNTING: _drop_from_horse()
	_dead = true
	state = S.DEAD
	Engine.time_scale = 1.0
	trail.stop()
	rig.play("Death01", 0.12, 1.0, 0.0, true)
	velocity = Vector3.ZERO
	died.emit()

func revive() -> void:
	_dead = false
	hp = max_hp
	_heal_left = 0.0
	_since_hurt = 99.0
	posture = 0.0
	focus = 0.0
	winded = false
	_set_stamina(max_stamina)
	_dmg_mult = 1.0
	_spirit_blade_t = 0.0
	crouching = false
	_chain_t = 0.0
	_shadow_win = 0.0
	_assassin_target = null
	Engine.time_scale = 1.0
	state = S.IDLE
	_state_t = 0.0
	_gait = 0
	rig.play("Idle", 0.2, 1.0, 0.0, true)
	hp_changed.emit(hp, max_hp)
	posture_changed.emit(posture, max_posture)
	focus_changed.emit(focus, max_focus)

func _hitstop(dur: float) -> void:
	_hitstop_t = maxf(_hitstop_t, dur)
	if camera != null: camera.shake(0.14 if dur < 0.07 else 0.24)

# ---------------------------------------------------------------- lock-on / deathblow / interact
func _toggle_lock() -> void:
	if _lock_target != null:
		_lock_target = null
		lock_changed.emit(null)
		return
	var best: Node3D = null
	var bd := 1e9
	if world == null: return
	var yaw := _cam_yaw()
	var cam_fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	for e in world.enemies:
		if not is_instance_valid(e) or e.is_dead: continue
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		var d: float = to.length()
		if d > 20.0: continue
		var score := d * (1.6 - cam_fwd.dot(to.normalized()))
		if score < bd: bd = score; best = e
	_lock_target = best
	lock_changed.emit(best)
	if best == null: Game.notice.emit("No enemy to lock on to", "warn")

func _update_lock(_delta: float) -> void:
	if _lock_target != null and (not is_instance_valid(_lock_target) or _lock_target.is_dead
			or _lock_target.global_position.distance_to(global_position) > 30.0):
		_lock_target = null
		lock_changed.emit(null)

func locked_target() -> Node3D:
	return _lock_target

func _interact() -> void:
	var t := deathblow_available()
	if t != null:
		_start_deathblow(t)
		return
	var a := assassination_target()
	if a != null:
		_start_assassination(a)
		return
	if world != null and world.has_method("horse_near") and world.horse_near(self):
		mount(world.horse)

func _try_deathblow_or_interact() -> void:
	_interact()

func _start_deathblow(target: Node3D) -> void:
	if not drawn and weapon != "fists": _set_drawn(true)
	state = S.DEATHBLOW
	_state_t = 0.0
	_db_target = target
	rig.play("K_2H_Stab" if weapon != "fists" else "K_Punch", 0.06, 0.95, 0.1, true)
	Audio.play_sfx("deathblow", global_position, 1.0, 0.0)
	Audio.play_sfx("drum", null, 1.0, 0.0)
	Audio.haptic("deathblow")
	Audio.haptic("deathblow")
	var to := target.global_position - global_position
	to.y = 0
	_face_now(to)
	if camera != null: camera.shake(0.35)
	if target.has_method("execute"): target.execute(self)

func _state_deathblow(delta: float) -> void:
	var hv := Vector3(velocity.x, 0, velocity.z)
	if _db_target != null and is_instance_valid(_db_target) and _state_t < 0.5:
		var to: Vector3 = _db_target.global_position - global_position
		to.y = 0.0
		var d: float = to.length()
		if d > 1.3: hv = to.normalized() * clampf((d - 1.2) / 0.4, 0.0, 4.5)
		else: hv = hv.move_toward(Vector3.ZERO, 30.0 * delta)
		_face(to, delta, 14.0)
	else:
		hv = hv.move_toward(Vector3.ZERO, 30.0 * delta)
	velocity.x = hv.x; velocity.z = hv.z
	if _state_t > 1.45:
		state = S.IDLE
		_db_target = null

func deathblow_available() -> Node3D:
	if world == null: return null
	for e in world.enemies:
		if is_instance_valid(e) and not e.is_dead and e.posture_broken:
			if e.global_position.distance_to(global_position) < 3.6: return e
	return null

# ---------------------------------------------------------------- riding
func is_mounted() -> bool:
	return state == S.MOUNTED or state == S.MOUNTING

func mount(h: Node3D) -> void:
	crouching = false
	if h == null or not is_instance_valid(h) or is_mounted(): return
	horse = h
	rig.fit_rider("Driving")
	_lock_target = null
	lock_changed.emit(null)
	if drawn and weapon != "katana" and weapon != "fists": _set_drawn(false)
	if weapon == "fists": _set_drawn(false)
	state = S.MOUNTING
	_state_t = 0.0
	_mount_up = true
	_mount_from = global_transform
	velocity = Vector3.ZERO
	body_shape.disabled = true
	collision_layer = 0
	rig.play("Jump_Start", 0.1, 1.4, 0.1, true)
	if h.has_method("set_rider"): h.set_rider(self)
	mount_changed.emit(true)

func dismount() -> void:
	if state != S.MOUNTED: return
	state = S.MOUNTING
	_state_t = 0.0
	_mount_up = false
	_mount_from = global_transform
	rig.play("Jump", 0.15, 1.0)
	rig.release_reins()
	if horse != null and horse.has_method("set_rider"): horse.set_rider(null)

func _drop_from_horse() -> void:
	rig.release_reins()
	if horse != null and is_instance_valid(horse) and horse.has_method("set_rider"): horse.set_rider(null)
	var side: Vector3 = global_position + global_transform.basis.x * 1.2
	global_position = side
	rotation = Vector3(0, rotation.y, 0)
	body_shape.disabled = false
	collision_layer = 2
	rig.legs.influence = 0.0
	state = S.IDLE
	mount_changed.emit(false)

## Where the reins end: the rider's fists (Horse draws the reins to them).
func rein_grip_points() -> PackedVector3Array:
	if rig == null or not is_mounted(): return PackedVector3Array()
	return rig.rein_points()

func reins_held(side: String) -> bool:
	return rig != null and rig.reins_held(side)

## Where the player root goes so the seated pelvis rests on the saddle.
func _seat() -> Transform3D:
	if horse != null and is_instance_valid(horse) and horse.has_method("seat_transform"):
		var st: Transform3D = horse.seat_transform()
		return st * Transform3D(Basis(), Vector3(-rig.rider_pelvis.x, 0.11 - rig.rider_pelvis.y, -rig.rider_pelvis.z))
	return global_transform

func _state_mounting(delta: float) -> void:
	var dur := 0.55 if _mount_up else 0.5
	var f := clampf(_state_t / dur, 0.0, 1.0)
	var e := f * f * (3.0 - 2.0 * f)
	var seat := _seat()
	var a: Transform3D
	var b: Transform3D
	if _mount_up:
		a = _mount_from; b = seat
	else:
		a = seat
		var side := seat.origin + seat.basis.x * 1.15
		side.y = seat.origin.y - 1.2
		if world != null and world.terrain != null and world.terrain.loaded:
			side.y = world.terrain.sample_height(side.x, side.z)
		b = Transform3D(Basis(Vector3.UP, atan2(seat.basis.z.x, seat.basis.z.z)), side)
	var p := a.origin.lerp(b.origin, e) + Vector3.UP * sin(f * PI) * 0.45
	var q := a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), e)
	global_transform = Transform3D(Basis(q), p)
	rig.legs.influence = e if _mount_up else 1.0 - e
	if f >= 1.0:
		if _mount_up:
			state = S.MOUNTED
			_state_t = 0.0
			rig.play("Driving", 0.2, 1.0)
		else:
			rotation = Vector3(0, rotation.y, 0)
			body_shape.disabled = false
			collision_layer = 2
			velocity = Vector3.ZERO
			rig.legs.influence = 0.0
			state = S.IDLE
			_state_t = 0.0
			_gait = 0
			horse = null
			mount_changed.emit(false)

func _state_mounted(delta: float) -> void:
	if horse == null or not is_instance_valid(horse):
		_drop_from_horse()
		return
	global_transform = _seat()
	velocity = horse.velocity if "velocity" in horse else Vector3.ZERO
	rig.legs.influence = 1.0
	if rig.current() != "Driving" and _move_id == "": rig.play("Driving", 0.2, 1.0)
	# hands on the reins: both, or the left alone while the sword is out;
	# a two-handed mounted cut lets go for the swing
	var hs: float = clampf(absf(float(horse.get("_speed"))) / 12.5, 0.0, 1.0)
	var give := Vector3(0.0, sin(_state_t * 9.0) * 0.012, sin(_state_t * 9.0 + 0.6) * 0.03) * hs
	rig.update_reins(delta, _move_id == "", _move_id == "" and not drawn and _carry == 0, give)
	if _act("interact") or _act("mount"):
		if deathblow_available() == null:
			dismount()
			return
	if _act("sheathe"):
		if weapon != "katana": select_weapon("katana")
		elif drawn: _set_drawn(false)
		else: _set_drawn(true)
	if _act("lock_on"): _toggle_lock()
	# mounted sword cuts: the arms play the swing on the upper layer, legs stay in the stirrups
	if _move_id == "" and (_take("attack") or _take("heavy")) and _spend(STAMINA_COST["mounted"]):
		if weapon != "katana": select_weapon("katana")
		if not drawn: _set_drawn(true)
		var id := "ride_a" if int(_combo["light"]) % 2 == 0 else "ride_b"
		_combo["light"] = int(_combo["light"]) + 1
		_move_id = id
		_move = MOVES[id]
		_move_t = 0.0
		_hit_ids = {}
		rig.set_layer_arms(true)
		rig.set_layer_clip(String(_move["clip"]), -1.0, 1.0)
		rig.layer.clip_t = 0.0
		rig.layer.loop = false
		rig.layer.influence = 1.0
		_bind_trail()
		trail.local_space = true
		trail.start()
		_swing_sound(false)
	if _move_id != "":
		_move_t += delta * float(_move["spd"])
		var h: Array = _move["hit"]
		if _move_t >= float(h[0]) and _move_t <= float(h[1]): _hit_scan(_move)
		if _move_t >= float(_move["end"]):
			_move_id = ""
			trail.stop()
			rig.layer.loop = true
			_combo_t = COMBO_RESET

# ---------------------------------------------------------------- visual layers
## Upper-body layer: the guard pose while moving/idling with a weapon out, the
## block pose while guarding, and the arms of mounted cuts.
func _tick_layer(delta: float) -> void:
	if rig == null or not rig.ok: return
	rig.layer.advance(delta)
	if (state == S.MOUNTED or state == S.MOUNTING) and _move_id != "":
		return
	var want := 0.0
	var w: Dictionary = WEAPONS[weapon]
	if state == S.BLOCK and (drawn or _carry == 1):
		var b: Array = w["block"]
		rig.set_layer_clip(String(b[0]), float(b[1]))
		rig.set_layer_arms(true)
		want = 1.0
	elif state in [S.IDLE, S.MOVE] and drawn and _carry == 0 and not crouching and not rig.current().ends_with("_Rec"):
		var g: Array = w["guard"]
		rig.set_layer_clip(String(g[0]), float(g[1]))
		rig.set_layer_arms(_gait <= 1 or weapon == "fists")
		want = 1.0
	elif state == S.MOUNTED and drawn:
		rig.set_layer_clip("Sword_Idle", 0.62)
		rig.set_layer_arms(false)
		want = 1.0
	var rate := 7.0 if want > rig.layer.influence else 9.0
	rig.layer.influence = move_toward(rig.layer.influence, want, delta * rate)

## Lean into turns and sprints.
func _tick_lean(delta: float) -> void:
	if rig == null: return
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var want := 0.0
	if state == S.MOVE and is_on_floor():
		# v0.14: max ~6 deg (was 11.5): a runner leans into a curve, he does
		# not tip over like a motorbike when the camera swings
		want = clampf(-_yaw_rate * 0.022 * clampf(hv.length() / 6.0, 0.0, 1.0), -0.105, 0.105)
	_lean = lerpf(_lean, want, clampf(delta * 6.0, 0.0, 1.0))
	rig.rotation.z = _lean
	# out of the water: the swim lift eases off as you stand up
	if state != S.SWIM and rig.position.y != 0.0:
		rig.position.y = move_toward(rig.position.y, 0.0, delta * 3.2)
	_yaw_rate = lerpf(_yaw_rate, 0.0, clampf(delta * 4.0, 0.0, 1.0))

# ---------------------------------------------------------------- misc
func _cycle_stance() -> void:
	Game.cycle_stance(1)
	stance = Game.stance
	Audio.haptic("stance")
	Audio.play_sfx("ui_select", null, 1.0, 0.0)
	stance_changed.emit(stance)
	_float_text(String(Game.stance_info()["name"]), Color(0.9, 0.85, 0.6))

func _float_text(text: String, color: Color) -> void:
	if world != null and world.hitfx != null:
		world.hitfx.label(global_position, text, color)

var _boss_fight: Node3D = null

func _update_combat_flag(_delta: float) -> void:
	var n := 0
	var boss: Node3D = null
	if world != null:
		for e in world.enemies:
			if is_instance_valid(e) and not e.is_dead and e.in_combat and e.global_position.distance_to(global_position) < 25.0:
				n += 1
				if e.is_boss: boss = e
	var now := n > 0
	if now != _in_combat:
		_in_combat = now
		combat_state_changed.emit(now)
		Audio.set_combat(now)
	# a captain in the fight takes over the score; his fall gets a stinger
	if boss != _boss_fight:
		if boss == null and _boss_fight != null and is_instance_valid(_boss_fight) and _boss_fight.is_dead:
			Audio.play_sfx("taiko", null, 1.0, 0.0)
		_boss_fight = boss
		Audio.set_boss(boss != null)

func is_in_combat() -> bool:
	return _in_combat

func hp_ratio() -> float:
	return hp / max_hp

# ================================================================ v0.16 stealth & techniques
## Crouch (C): slower, quieter, harder to see - and in tall grass nearly
## invisible. Enemies read stealth_visibility() and noise_radius() every frame
## (EnemyBase._perceive). Assassination, the smoke bomb, Mikiri Counter, Shadow
## Step and the passive techniques all live below; Skills.has() gates them.
const CROUCH_SPEED := 1.45
const CROUCH_CLIP_SPEED := 0.84      ## Crouch_Fwd ground speed at 1x (measured, tests/ClipProbe16)
const ASSASSIN_RANGE := 2.5
const CHAIN_RANGE := 8.0
const BLIND_RANGE := 3.6
const CHAIN_WINDOW := 1.6
const SHADOW_WINDOW := 0.7
const SHADOW_COOLDOWN := 8.0
const MIKIRI_RANGE := 4.2
const SMOKE_RELEASE := 0.30
const SMOKE_TIME := 0.62
const SHADOW_MOVE := {"katana": "k_heavy2", "nodachi": "n_b", "yari": "y_b", "fists": "lunge_punch"}

var crouching := false
var _crouch_told := false
var _noise_pulse := 0.0
var _noise_pulse_t := 0.0
var _chain_t := 0.0
var _assassin_target: Node3D = null
var _assassin_from := Vector3.ZERO
var _assassin_dest := Vector3.ZERO
var _assassin_dash := 0.2
var _assassin_struck := false
var _assassin_count := 0
var _shadow_win := 0.0
var _shadow_src: Node3D = null
var _shadow_cd := 0.0
var _shadow_mult := 1.0
var _dodge_spd := 1.0
var _iai_pending := false
var _iai_move := false
var _iai_shown := false
var _smoke_thrown := false
var _smoke_frame := -1
var _smoke_here := false
var _cover_t := 0.0
var _cover := 0.0
var _guard_tip := false

func _tick_v16(delta: float) -> void:
	_noise_pulse_t = maxf(0.0, _noise_pulse_t - delta)
	if _noise_pulse_t <= 0.0: _noise_pulse = 0.0
	_chain_t = maxf(0.0, _chain_t - delta)
	_shadow_win = maxf(0.0, _shadow_win - delta)
	_shadow_cd = maxf(0.0, _shadow_cd - delta)
	_cover_t -= delta
	if _cover_t <= 0.0:
		_cover_t = 0.25
		_cover = _cover_here() if crouching else 0.0
	if crouching and (state in [S.SWIM, S.MOUNTED, S.MOUNTING, S.DEAD] or _air_t > 0.35):
		crouching = false

func is_crouching() -> bool:
	return crouching

func set_crouch(v: bool) -> void:
	if v == crouching: return
	if v and (_dead or state in [S.SWIM, S.MOUNTED, S.MOUNTING, S.DEAD, S.JUMP] or not is_on_floor()):
		return
	crouching = v
	_cover_t = 0.0
	if v and _blocking:
		_blocking = false
		state = S.IDLE
	Audio.play_sfx("cloth", global_position, 0.9 if v else 1.05, -6.0)
	if v and not _crouch_told:
		_crouch_told = true
		Game.notice.emit("Crouched — quieter and harder to see. Tall grass hides you; stay out of their eyeline", "quest")

## 0..1: how much tall grass / undergrowth there is to hide in at the feet.
func _cover_here() -> float:
	var t = world.terrain if world != null else null
	if t == null or not t.loaded: return 0.0
	var x := global_position.x
	var z := global_position.z
	var g: float = t.grass_density_at(x, z)
	match String(t.biome_at(x, z)):
		"tallgrass": return clampf((g - 0.25) / 0.4, 0.0, 1.0)
		"shore": return clampf((g - 0.35) / 0.4, 0.0, 1.0) * 0.8
		"bamboo", "forest": return clampf((g - 0.3) / 0.5, 0.0, 1.0) * 0.6
		"grassland", "shrine", "village", "farmland": return clampf((g - 0.6) / 0.35, 0.0, 1.0) * 0.6
	return 0.0

func cover() -> float:
	return _cover if crouching else 0.0

## 0..1.3 multiplier on how quickly a soldier who has you in view notices you.
func stealth_visibility() -> float:
	if in_smoke(): return 0.0
	if state == S.MOUNTED or state == S.MOUNTING: return 1.4
	var sp := Vector3(velocity.x, 0.0, velocity.z).length()
	var v := 1.0
	if crouching:
		v = 0.42 if sp < 0.3 else 0.55
		v *= 1.0 - 0.7 * _cover
	elif sp < 0.3: v = 0.62
	elif sp < 2.2: v = 0.78
	elif sp < 6.5: v = 1.0
	else: v = 1.3
	if state in [S.ATTACK, S.DEATHBLOW, S.BLOCK, S.HIT, S.STAGGER]: v = maxf(v, 1.0)
	return v

## How far away (m) a soldier can hear you right now.
func noise_radius() -> float:
	var r := 0.0
	if state == S.MOUNTED or state == S.MOUNTING:
		r = 16.0
	else:
		var sp := Vector3(velocity.x, 0.0, velocity.z).length()
		if sp < 0.3: r = 0.0
		elif crouching: r = 1.2
		elif sp < 2.2: r = 3.0
		elif sp < 6.5: r = 7.0
		else: r = 12.0
		if state == S.ATTACK: r = maxf(r, 9.0)
		elif state == S.DODGE: r = maxf(r, 5.0)
	if Skills.has("s_silent"): r *= 0.5
	return maxf(r, _noise_pulse)

## A loud moment (steel on steel): heard out to `radius` for `t` seconds.
func make_noise(radius: float, t: float) -> void:
	_noise_pulse = maxf(_noise_pulse, radius)
	_noise_pulse_t = maxf(_noise_pulse_t, t)

func in_smoke() -> bool:
	var f := Engine.get_physics_frames()
	if f == _smoke_frame: return _smoke_here
	_smoke_frame = f
	_smoke_here = false
	if not is_inside_tree(): return false
	for c in get_tree().get_nodes_in_group("smoke_cloud"):
		if is_instance_valid(c) and c.has_method("covers") and c.covers(global_position):
			_smoke_here = true
			break
	return _smoke_here

## An enemy blocked the cut: the blade rebounds.
func on_guarded(_enemy: Node) -> void:
	_hitstop(0.05)
	_drain(3.0)
	if camera != null: camera.impulse(-_fwd(), 0.03)
	Audio.haptic("hit")
	make_noise(14.0, 0.5)
	if not _guard_tip:
		_guard_tip = true
		Game.notice.emit("Blocked — heavy attacks and kicks break a guard; Spirit Blade Mastery cuts through", "warn")

# ---------------------------------------------------------------- Mikiri Counter
## Dodge INTO a perilous thrust that is about to land: the spear is stamped
## down, the attacker loses half its posture and the next light attack is a
## riposte.
func _try_mikiri() -> bool:
	if world == null: return false
	var dir := _desired_dir()
	var toward := dir.normalized() if dir != Vector3.ZERO else _fwd()
	for e in world.enemies:
		if not is_instance_valid(e) or e.is_dead or not e.has_method("perilous_kind"): continue
		if e.perilous_kind() != "thrust": continue
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > MIKIRI_RANGE or d < 0.2: continue
		if toward.dot(to / d) < 0.45: continue
		if e.perilous_progress() < 0.3: continue
		if not e.mikiri(self): continue
		state = S.DODGE
		_state_t = 0.0
		trail.stop()
		_dodge_side = true
		_dodge_dir = to / d
		_dodge_spd = clampf((d - 1.2) / 3.0, 0.0, 0.8)
		_dodge_len = 0.62
		_iframe = Vector2(0.0, 0.62)
		_face_now(to)
		rig.play("K_Kick", 0.05, 1.35, 0.0, true)
		_riposte_t = RIPOSTE_WINDOW + 0.4
		_add_focus(18.0)
		_spend(STAMINA_COST["dodge"] * 0.5)
		Audio.haptic("deflect")
		if camera != null: camera.impulse(to / d, 0.05)
		_hitstop(0.08)
		make_noise(14.0, 0.5)
		return true
	return false

# ---------------------------------------------------------------- Shadow Step
func _arm_shadow_step(src) -> void:
	if not Skills.has("p_step") or _shadow_cd > 0.0: return
	if src == null or not is_instance_valid(src) or not (src is Node3D): return
	if not src.has_method("perilous_kind"): return
	if (src as Node3D).global_position.distance_to(global_position) > 7.0: return
	_shadow_src = src
	_shadow_win = SHADOW_WINDOW

func shadow_step_ready() -> bool:
	return _shadow_win > 0.0 and _shadow_src != null and is_instance_valid(_shadow_src)

## Appear behind the enemy you just dodged and cut (x1.6 damage, heavy).
func _try_shadow_step() -> bool:
	var e: Node3D = _shadow_src
	_shadow_win = 0.0
	_shadow_src = null
	if e == null or not is_instance_valid(e) or bool(e.get("is_dead")): return false
	var back: Vector3 = -e.global_transform.basis.z
	back.y = 0.0
	if back.length() < 0.01: return false
	back = back.normalized()
	var dest: Vector3 = e.global_position + back * 1.35
	var t = world.terrain if world != null else null
	if t != null and t.loaded:
		dest.y = t.sample_height(dest.x, dest.z) + 0.05
		if absf(dest.y - e.global_position.y) > 1.2: return false
		if t.water_depth_at(dest.x, dest.z) > 0.9: return false
	var xf := global_transform
	xf.origin = dest + Vector3(0, 0.15, 0)
	if test_move(xf, Vector3(0, 0.05, 0)): return false
	var from := global_position
	global_position = dest
	velocity = Vector3.ZERO
	var to: Vector3 = e.global_position - dest
	to.y = 0.0
	_face_now(to)
	if world != null and world.hitfx != null:
		world.hitfx.burst(from + Vector3(0, 1.0, 0), "deflect")
		world.hitfx.burst(dest + Vector3(0, 1.0, 0), "deflect")
	Audio.play_sfx("whistle", global_position, 1.5, -10.0)
	_shadow_cd = SHADOW_COOLDOWN
	_float_text("SHADOW STEP", Color(0.55, 0.85, 1.0))
	if not drawn and weapon != "fists": _set_drawn(true)
	_start_move(String(SHADOW_MOVE.get(weapon, "k_heavy2")))
	_shadow_mult = 1.6
	return true

# ---------------------------------------------------------------- assassination
## The enemy E (or attack while crouched) would assassinate right now, or null.
## Within CHAIN_WINDOW of a kill and with Chain Assassination the reach is
## CHAIN_RANGE and a soldier that has only just noticed you still counts.
func assassination_target() -> Node3D:
	if world == null or not Skills.has("s_assassin"): return null
	var chain := _chain_t > 0.0 and Skills.has("s_chain")
	if state == S.ASSASSIN:
		if not chain or not _assassin_struck or _state_t < 0.3: return null
	elif not state in [S.IDLE, S.MOVE]:
		return null
	var best: Node3D = null
	var best_d := INF
	var base := CHAIN_RANGE if chain else ASSASSIN_RANGE
	for e in world.enemies:
		if not is_instance_valid(e) or e.is_dead or e == _assassin_target: continue
		if not e.has_method("can_be_assassinated"): continue
		var d: float = e.global_position.distance_to(global_position)
		# a soldier blinded by smoke can be reached from a little further
		var lim := base
		if e.has_method("is_blind") and e.is_blind(): lim = maxf(base, BLIND_RANGE)
		if d > lim or d >= best_d: continue
		if absf(e.global_position.y - global_position.y) > 1.6: continue
		if not e.can_be_assassinated(self, chain): continue
		best_d = d
		best = e
	return best

func _start_assassination(e: Node3D) -> void:
	if e == null or not is_instance_valid(e): return
	var chained := state == S.ASSASSIN
	state = S.ASSASSIN
	_state_t = 0.0
	_blocking = false
	trail.stop()
	_assassin_target = e
	_assassin_struck = false
	_assassin_count = _assassin_count + 1 if chained else 1
	_chain_t = 0.0
	# come in from behind the victim, close enough for the blade
	var back: Vector3 = -e.global_transform.basis.z
	back.y = 0.0
	back = back.normalized() if back.length() > 0.01 else (global_position - e.global_position).normalized()
	_assassin_from = global_position
	_assassin_dest = e.global_position + back * 0.95
	_assassin_dest.y = global_position.y
	var d := _assassin_from.distance_to(_assassin_dest)
	_assassin_dash = clampf(d / 14.0, 0.08, 0.45)
	if chained:
		rig.play("Sword_Dash", 0.05, 1.6, 0.15, true)
	if not drawn and weapon != "fists": _set_drawn(true)
	e.assassinated(self)
	Audio.play_sfx("cloth", global_position, 1.2, -4.0)

func _state_assassin(delta: float) -> void:
	var e := _assassin_target
	if not _assassin_struck:
		if _state_t < _assassin_dash and e != null and is_instance_valid(e):
			var to := _assassin_dest - global_position
			to.y = 0.0
			var left := maxf(_assassin_dash - _state_t, delta)
			var v := to / left
			if v.length() > 16.0: v = v.normalized() * 16.0
			velocity.x = v.x; velocity.z = v.z
			var look: Vector3 = e.global_position - global_position
			look.y = 0.0
			_face(look, delta, 20.0)
			return
		_assassin_struck = true
		_state_t = 0.0
		velocity.x = 0.0; velocity.z = 0.0
		if e != null and is_instance_valid(e):
			var look2: Vector3 = e.global_position - global_position
			look2.y = 0.0
			_face_now(look2)
		var clip := "K_1H_Stab" if weapon in ["katana", "fists"] else "K_2H_Stab"
		if weapon == "fists": clip = "K_Punch"
		rig.play(clip, 0.06, 1.3, 0.15, true)
		Audio.play_sfx("hit_blade", global_position, 0.8, 2.0)
		Audio.play_sfx("deathblow", global_position, 1.15, -6.0)
		Audio.haptic("deathblow")
		if camera != null: camera.shake(0.18)
		_chain_t = CHAIN_WINDOW
		Game.add_xp(1)
		Quests.progress("assassinate", "", 1)
		return
	velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
	# Chain Assassination: the next one, before he can shout
	if (_take("attack") or _act("interact")) and Skills.has("s_chain"):
		var nxt := assassination_target()
		if nxt != null:
			_start_assassination(nxt)
			return
	if _state_t > 0.95:
		state = S.IDLE
		_state_t = 0.0
		_gait = 0
		_assassin_target = null

func chain_ready() -> bool:
	return _chain_t > 0.0 and Skills.has("s_chain") and assassination_target() != null

# ---------------------------------------------------------------- smoke bomb
func throw_smoke() -> void:
	if _dead or cinematic: return
	if not Skills.has("s_smoke"):
		Game.notice.emit("Smoke Bomb is a Shinobi Arts technique — %s opens techniques" % Game.bind_label("skills"), "warn")
		return
	if Game.smoke <= 0:
		Game.notice.emit("No smoke bombs left — rest at a shrine or checkpoint", "warn")
		return
	var ok := state in [S.IDLE, S.MOVE, S.BLOCK]
	if state == S.ATTACK and not _move.is_empty() and _move_t > float((_move["hit"] as Array)[1]): ok = true
	if not ok: return
	_blocking = false
	trail.stop()
	state = S.THROW
	_state_t = 0.0
	_smoke_thrown = false
	rig.play("K_Throw", 0.06, 1.7, 0.1, true)
	Audio.play_sfx("cloth", global_position, 1.1, -3.0)

func _state_throw(delta: float) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, 20.0 * delta)
	velocity.x = hv.x; velocity.z = hv.z
	if not _smoke_thrown and _state_t >= SMOKE_RELEASE:
		_smoke_thrown = true
		Game.set_smoke(Game.smoke - 1)
		var b := SmokeBomb.new()
		var parent: Node = world if world != null else get_parent()
		parent.add_child(b)
		b.global_position = global_position + _fwd() * 0.6
		b.burst(world, self)
	if _state_t >= SMOKE_TIME:
		state = S.IDLE
		_state_t = 0.0
		_gait = 0
	elif _smoke_thrown and _take("dodge"):
		_start_dodge()
