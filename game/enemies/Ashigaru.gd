class_name Ashigaru
extends EnemyBase
## Spear foot soldier: mid range thrust, moderate speed.

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

func _model_path() -> String:
	return "res://assets/models/Ashigaru_Ronin.glb"

func _attack_clip() -> String:
	return "Attack" if _attack_index == 0 else "Sweep"

func _perform_attack() -> void:
	Audio.play_sfx("swing", global_position, 0.85, -8.0)
	if _rng.randf() < 0.35: _attack_index = 1 - _attack_index
	_scan_and_hit(reach, arc, damage, posture_dmg)
