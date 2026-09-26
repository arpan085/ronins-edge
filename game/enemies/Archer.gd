class_name Archer
extends EnemyBase
## Ranged bowman: keeps distance, telegraphed shot with a travelling arrow.

func _configure() -> void:
	kind = "archer"
	hp = 42.0; max_hp = 42.0
	posture = 0.0; max_posture = 46.0
	move_speed = 3.0
	attack_range = 13.0
	windup = 0.95; active_time = 0.12; recover_time = 1.05
	cooldown = 2.1
	damage = 12.0; posture_dmg = 12.0
	reach = 1.6; arc = 60.0
	detect_radius = 22.0

func _model_path() -> String:
	return "res://assets/models/Archer_Ronin.glb"

func _attack_clip() -> String:
	return "Shoot"

func _chase(delta: float, pp: Vector3, dist: float) -> void:
	if dist > lose_radius:
		in_combat = false
		_set_state(S.IDLE)
		return
	_face_towards(pp, delta, 4.0)
	var to := pp - global_position
	to.y = 0
	var dir := to.normalized()
	# archers back away to keep a firing lane
	if dist < attack_range * 0.55:
		# nervous: break away fast rather than hold ground
		_move_dir(-dir, move_speed * 0.95, delta)
		if driver != null and _t > 0.9 and driver.rig.has_clip("BackStep"):
			_t = 0.0
			driver.action("BackStep", 1.0, 0.08)
	elif dist > attack_range * 0.95:
		_move_dir(dir, move_speed, delta)
	else:
		_move_dir(Vector3.ZERO, 0.0, delta)
		if driver != null and driver.rig.has_clip("HoldDraw"):
			driver.travel("HoldDraw")
		if _cd <= 0.0 and _take_token():
			_has_token = true
			_attack_hit_done = false
			_attack_started = false
			_set_state(S.ATTACK)
			Audio.play_sfx("enemy_attack", global_position, 1.3, -8.0)

func _perform_attack() -> void:
	if player == null: return
	var a := Arrow.new()
	get_tree().current_scene.add_child(a)
	var from := global_position + Vector3(0, 1.5, 0)
	var to := player.global_position + Vector3(0, 1.0, 0)
	a.global_position = from
	a.velocity = (to - from).normalized() * 34.0
	a.damage = damage
	a.posture = posture_dmg
	a.shooter = self
	Audio.play_sfx("swing", global_position, 1.4, -10.0)
