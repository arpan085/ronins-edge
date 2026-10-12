class_name Ashigaru
extends EnemyBase
## Spear foot soldier: mid range thrust, moderate speed. v0.16: blocks now and
## then, and sometimes commits to a perilous (危) thrust or leg sweep.

func _configure() -> void:
	kind = "ashigaru"
	hp = 58.0; max_hp = 58.0
	posture = 0.0; max_posture = 62.0
	move_speed = 3.25
	attack_range = 2.9
	windup = 0.58; active_time = 0.15; recover_time = 0.8
	cooldown = 1.45
	damage = 14.0; posture_dmg = 17.0
	reach = 2.7; arc = 110.0
	detect_radius = 18.0
	guard_chance = 0.30
	perilous_thrust = 0.14
	perilous_sweep = 0.12
	delay_chance = 0.15
	feint_chance = 0.0

func _model_path() -> String:
	return "res://assets/models/Ashigaru_Ronin.glb"

func _begin_attack() -> void:
	super._begin_attack()
	# plain attacks mix the straight thrust with a wide swing
	if _perilous == "" and _rng.randf() < 0.35: _attack_index = 1

func _attack_clip() -> String:
	if _perilous == "sweep": return "Sweep"
	if _perilous == "thrust": return "Attack"
	return "Attack" if _attack_index == 0 else "Sweep"

func _perform_attack() -> void:
	Audio.play_sfx("swing_heavy" if _perilous != "" else "swing_light", global_position, 0.9, -3.0)
	var a := arc if _attack_index == 0 else maxf(arc, 150.0)
	_scan_and_hit(reach, a, damage, posture_dmg)
