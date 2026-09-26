class_name Captain
extends EnemyBase
## Samurai Captain: heavy nodachi, two attack patterns, high posture, boss.

func _configure() -> void:
	kind = "captain"
	is_boss = true
	hp = 130.0; max_hp = 130.0
	posture = 0.0; max_posture = 115.0
	move_speed = 3.6
	attack_range = 3.5
	windup = 0.72; active_time = 0.18; recover_time = 0.7
	cooldown = 1.15
	damage = 23.0; posture_dmg = 26.0
	reach = 3.2; arc = 150.0
	detect_radius = 22.0

func _model_path() -> String:
	return "res://assets/models/Captain_Ronin.glb"

var _phase := 1
var _phase_t := 0.0

func _attack_clip() -> String:
	if _attack_index == 2: return "Attack3"
	return "Attack1" if _attack_index == 0 else "Attack2"

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if is_dead: return
	if _phase == 1 and hp_ratio() < 0.5:
		_phase = 2
		_phase_t = 2.6
		_release_token()
		if driver != null and driver.rig.has_clip("PhaseTransition"):
			driver.abort_action()
			driver.action("PhaseTransition", 1.0, 0.14)
		cooldown = 0.85
		combo_chance = 0.55
		Game.notice.emit("The Captain sheds his restraint", "warn")
	if _phase_t > 0.0:
		_phase_t -= delta
		velocity.x = 0.0
		velocity.z = 0.0

func _attack_state(delta: float, pp: Vector3) -> void:
	super._attack_state(delta, pp)
	# captains sometimes chain a second swing instead of recovering
	if state == S.RECOVER and _has_token and _rng.randf() < (0.45 if _phase == 1 else 0.7):
		if _attack_index == 0: _attack_index = 1
		elif _attack_index == 1 and _phase == 2: _attack_index = 2
		else: return
		_attack_hit_done = false
		_attack_started = false
		_set_state(S.ATTACK)

func _perform_attack() -> void:
	Audio.play_sfx("swing", global_position, 0.7, -4.0)
	var mult: float = float([1.0, 1.25, 1.5][_attack_index]) * (1.0 if _phase == 1 else 1.15)
	var dmg: float = damage * mult
	var post: float = posture_dmg * mult
	_scan_and_hit(reach, arc, dmg, post)
	if _attack_index >= 1 and player != null:
		player._hitstop(0.09)
