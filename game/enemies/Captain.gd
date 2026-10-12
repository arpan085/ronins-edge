class_name Captain
extends EnemyBase
## Samurai Captain: heavy nodachi, two attack patterns, high posture, boss.

func _configure() -> void:
	kind = "captain"
	# v0.16: is_boss comes from the spawn table (only Kuroda in the keep); the
	# castle's other captains used to be bosses too and ended the story early
	hp = 130.0; max_hp = 130.0
	posture = 0.0; max_posture = 115.0
	move_speed = 3.6
	attack_range = 3.5
	windup = 0.72; active_time = 0.18; recover_time = 0.7
	cooldown = 1.15
	damage = 23.0; posture_dmg = 26.0
	reach = 3.2; arc = 150.0
	detect_radius = 22.0
	# v0.16 a duellist: guards often, feints, delays, and mixes in perilous cuts
	guard_chance = 0.5
	perilous_thrust = 0.12
	perilous_sweep = 0.0
	delay_chance = 0.22
	feint_chance = 0.18

func _model_path() -> String:
	return "res://assets/models/Captain_Ronin.glb"

var _phase := 1
var _phase_t := 0.0

func _attack_clip() -> String:
	if _perilous == "thrust": return "Attack2"
	if _perilous == "sweep": return "Attack3"
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
		perilous_thrust = 0.14
		perilous_sweep = 0.18
		guard_chance = 0.42
		if is_boss: Game.notice.emit("Kuroda sheds his restraint", "warn")
	if _phase_t > 0.0:
		_phase_t -= delta
		velocity.x = 0.0
		velocity.z = 0.0

## Captains chain a second (and in phase 2 a third) cut instead of recovering.
## (v0.16 fix: the old check ran after the attack token was already released,
## so the string never actually happened.) A perilous blow ends the string.
func _chain_next() -> bool:
	if _perilous != "" or _phase_t > 0.0: return false
	if _rng.randf() >= (0.45 if _phase == 1 else 0.7): return false
	if _attack_index == 0: _attack_index = 1
	elif _attack_index == 1 and _phase == 2: _attack_index = 2
	else: return false
	if driver != null: driver.abort_action()
	return true

func _perform_attack() -> void:
	Audio.play_sfx("swing_heavy", global_position, 0.85, 0.0)
	var mult: float = float([1.0, 1.25, 1.5][_attack_index]) * (1.0 if _phase == 1 else 1.15)
	var dmg: float = damage * mult
	var post: float = posture_dmg * mult
	_scan_and_hit(reach, arc, dmg, post)
	if _attack_index >= 1 and player != null:
		player._hitstop(0.09)
