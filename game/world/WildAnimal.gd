class_name WildAnimal
extends Node3D
## v0.15: one animal of the wildlife system -- a skinned, animated model with a
## small brain (Wildlife.gd spawns, budgets and harvests them).
##
## Prey (sika deer, foxes) graze, lift their heads at a noise and bolt from a
## careless approach: how far they hear you depends on how fast you move and
## whether they are facing you, so walking (walk toggle) up from behind while
## a deer has its head down gets you within a lunge. Boars stand their ground
## and charge. Wolves hunt in packs at night, circling and darting in one at a
## time. Anything can be cut down; a carcass can be harvested for meat.

enum S { IDLE, GRAZE, LOOK, WALK, ALERT, FLEE, CHARGE, ATTACK, RECOVER, STALK, HURT, DEAD }
## walking pace (walk toggle) and below is quiet; above it every m/s is heard
const QUIET_SPEED := 1.7
## boar: how long it runs on past you after a charge before it skids round
const RUN_ON := 0.7

var sp := ""
var d: Dictionary = {}
var wild: Node = null           # Wildlife
var state := S.IDLE
var hp := 30.0
var max_hp := 30.0
var is_dead := false
var harvested := false
var heading := 0.0              # yaw, +Z forward
var speed := 0.0
var pack_id := -1
var slot := 0.0                 # wolves: angle of this one around the player
var despawn := false            # set by Wildlife when it wants it gone

var _t := 0.0
var _dur := 3.0
var _alert := 0.0
var _goal := 0.0                # heading the brain wants
var _pivot: Node3D
var _model: Node3D
var _ap: AnimationPlayer
var _clip := ""
var _hurt: Area3D
var _struck := false            # attack already landed this lunge
var _dead_t := 0.0
var _sink := -1.0
var _roll := 0.0                # procedural death roll (boar has no clip)
var _cool := 0.0
var _tick := 0.0
var _dt := 0.016
var _run := false               # wolves: running (not trotting) while stalking
var _dist := 999.0
var _cmin := 999.0              # closest approach during this charge
var _pp := Vector3.INF          # player position at the last think
var _avoid := 1.0               # side it last swerved to round bad ground
var _charges := 0               # boar: passes made in this fight
var _growl_t := 2.0
var _rng := RandomNumberGenerator.new()

func setup(species: String, data: Dictionary, owner_wild: Node, seed_v: int) -> void:
	sp = species
	d = data
	wild = owner_wild
	_rng.seed = seed_v
	max_hp = float(d["hp"])
	hp = max_hp
	name = "Wild_%s_%d" % [sp, seed_v % 10000]
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	var ps: PackedScene = load(String(d["scene"]))
	if ps != null:
		_model = ps.instantiate() as Node3D
		_model.scale = Vector3.ONE * float(d["scale"])
		_model.rotation.y = float(d.get("yaw", 0.0))
		_model.position.y = float(d.get("lift", 0.0))
		_pivot.add_child(_model)
		for mi in _model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var aps := _model.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			_ap = aps[0] as AnimationPlayer
			for an in ["idle", "eat", "look", "walk", "run"]:
				if _ap.has_animation(an):
					_ap.get_animation(an).loop_mode = Animation.LOOP_LINEAR
	_build_hurtbox()
	heading = _rng.randf() * TAU
	_goal = heading
	rotation.y = heading
	_enter(S.GRAZE if _rng.randf() < 0.5 else S.IDLE)

func _build_hurtbox() -> void:
	_hurt = Area3D.new()
	_hurt.name = "Hurtbox"
	_hurt.collision_layer = 4
	_hurt.collision_mask = 0
	_hurt.monitoring = false
	_hurt.monitorable = true
	_hurt.add_to_group("enemy_hurtbox")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	var r: float = float(d["radius"])
	cap.radius = r
	cap.height = maxf(float(d["length"]), r * 2.0 + 0.05)
	cs.shape = cap
	cs.rotation.x = PI * 0.5
	cs.position = Vector3(0, float(d["height"]) * 0.55, 0)
	_hurt.add_child(cs)
	add_child(_hurt)

# ------------------------------------------------------------------ queries
func is_prey() -> bool:
	return String(d["kind"]) == "prey"

func is_predator() -> bool:
	return String(d["kind"]) == "wolf"

func unaware() -> bool:
	return state in [S.IDLE, S.GRAZE, S.LOOK, S.WALK]

func display_name() -> String:
	return String(d["label"])

# ------------------------------------------------------------------ anim
func _play(clip: String, spd := 1.0, blend := 0.25) -> void:
	if _ap == null: return
	var c := clip
	var k := spd
	var alias: Dictionary = d.get("alias", {})
	if not _ap.has_animation(c) and alias.has(clip):
		var al: Array = alias[clip]
		c = String(al[0])
		k *= float(al[1])
	if not _ap.has_animation(c): c = "idle"
	if not _ap.has_animation(c): return
	_ap.speed_scale = k
	if _clip == c and _ap.is_playing(): return
	_clip = c
	_ap.play(c, blend)

func _enter(s: int) -> void:
	state = s
	_t = 0.0
	_struck = false
	match s:
		S.IDLE:
			_dur = _rng.randf_range(2.0, 5.0)
			_play("idle")
		S.GRAZE:
			_dur = _rng.randf_range(5.0, 12.0)
			_play("eat")
		S.LOOK:
			_dur = _rng.randf_range(2.5, 4.5)
			_play("look")
		S.WALK:
			_dur = _rng.randf_range(3.0, 7.0)
			_goal = heading + _rng.randf_range(-1.4, 1.4)
			_play("walk")
		S.ALERT:
			_dur = 0.9
			_play("look" if is_prey() else "idle")
		S.FLEE:
			_dur = _rng.randf_range(6.0, 9.0)
			_play("run")
		S.CHARGE:
			_dur = 6.0
			_cmin = 999.0
			_play("run")
		S.ATTACK:
			_dur = float(d.get("atk_time", 0.8))
			_play(String(d.get("atk_clip", "attack")), float(d.get("atk_speed", 1.0)), 0.1)
		S.RECOVER:
			if String(d["kind"]) == "boar":
				_dur = RUN_ON + _rng.randf_range(1.3, 1.7)
				# run on past you: veer off to whichever side it is already going
				if _pp != Vector3.INF:
					var ta := atan2(_pp.x - global_position.x, _pp.z - global_position.z)
					var sd := signf(angle_difference(ta, heading))
					if sd == 0.0: sd = 1.0 if _rng.randf() < 0.5 else -1.0
					_goal = heading + sd * 0.45
				_play("walk", 0.6)
			else:
				_dur = _rng.randf_range(1.2, 2.0)
				_play("run")
		S.STALK:
			_dur = _rng.randf_range(2.5, 5.0)
			_play("walk")
		S.HURT:
			_dur = 0.45
			if _ap != null and _ap.has_animation("hit"): _play("hit", 1.6, 0.08)
		S.DEAD:
			_play("die", 1.0, 0.12)

# ------------------------------------------------------------------ combat
## Player._hit_scan calls this through the "enemy_hurtbox" area.
func take_hit(info: Dictionary) -> void:
	if is_dead: return
	var dmg := float(info.get("damage", 10.0))
	# a prey animal that has only lifted its head is still caught flat-footed;
	# a boar snorting at you is not
	var sneak := unaware() or (state == S.ALERT and is_prey())
	if sneak and not is_predator(): dmg *= 2.5
	hp = maxf(0.0, hp - dmg)
	var src = info.get("source", null)
	var dir := Vector3.ZERO
	if src != null and is_instance_valid(src) and src is Node3D:
		dir = global_position - (src as Node3D).global_position
		dir.y = 0.0
		dir = dir.normalized()
	var w = wild.get("world") if wild != null else null
	if w != null and w.get("hitfx") != null:
		w.hitfx.impact(global_position + Vector3(0, float(d["height"]) * 0.6, 0), dir, dmg, "blood")
		w.hitfx.label(global_position + Vector3(0, float(d["height"]), 0), "%d" % int(round(dmg)), Color(1.0, 0.95, 0.6))
	Audio.play_sfx(String(d.get("sfx_hurt", "")), global_position, _rng.randf_range(0.9, 1.1), 0.0)
	if hp <= 0.0:
		_die(sneak)
		return
	match String(d["kind"]):
		"prey":
			_goal = atan2(dir.x, dir.z) if dir != Vector3.ZERO else heading
			_enter(S.FLEE)
			if wild != null: wild.alarm(global_position, self)
		"boar":
			if hp < max_hp * 0.3:
				_flee_from(src)
			elif state in [S.IDLE, S.GRAZE, S.LOOK, S.WALK]:
				_goal = atan2(-dir.x, -dir.z) if dir != Vector3.ZERO else heading
				_charges = 0
				_enter(S.ALERT)
				_dur = 0.5
			elif state == S.RECOVER:
				_t = maxf(0.0, _t - 0.25)     # flinches; the opening lasts a moment longer
			# mid-charge or mid-gore it just keeps coming
		"wolf":
			_enter(S.HURT)

## the player parried it (Player._perfect_deflect): knocked off balance --
## a wolf reels back, a boar skids round with its flank open
func on_deflected(_by) -> void:
	if is_dead: return
	match String(d["kind"]):
		"wolf":
			_release()
			_enter(S.HURT)
			_dur = 0.9
		"boar":
			_enter(S.RECOVER)
			_t = RUN_ON

func _flee_from(src) -> void:
	if src != null and is_instance_valid(src) and src is Node3D:
		var away: Vector3 = global_position - (src as Node3D).global_position
		_goal = atan2(away.x, away.z)
	_enter(S.FLEE)

func _die(clean: bool) -> void:
	is_dead = true
	speed = 0.0
	_hurt.set_deferred("monitorable", false)
	_hurt.remove_from_group("enemy_hurtbox")
	_enter(S.DEAD)
	Audio.play_sfx("bodyfall", global_position, _rng.randf_range(0.85, 1.0), -2.0)
	if wild != null: wild.on_killed(self, clean)

## the meat is taken; the carcass sinks away and the slot respawns elsewhere
func take_carcass() -> void:
	harvested = true
	_sink = 0.0

# ------------------------------------------------------------------ brain
## p: player position, pv: player ground speed (m/s), dt: frame time.
## Called by Wildlife at a reduced rate for distant animals.
func think(p: Vector3, pv: float, dt: float, night: bool, terrain: Terrain) -> void:
	_dt = dt
	_t += dt
	_cool = maxf(0.0, _cool - dt)
	if is_dead:
		_update_dead(dt)
		return
	var to := Vector2(p.x - global_position.x, p.z - global_position.z)
	var dist := to.length()
	_dist = dist
	_pp = p
	var to_ang := atan2(to.x, to.y)
	match String(d["kind"]):
		"prey": _brain_prey(dist, to_ang, pv, night)
		"boar": _brain_boar(dist, to_ang, pv, night)
		"wolf": _brain_wolf(dist, to_ang, p, night)
	_move(dt, terrain)

## How far away this animal picks you up. It hears you all round, louder the
## faster you move (walking is quiet, running is not), and with its head up
## and facing your way it also sees you -- much further, unless you freeze.
func detect_radius(pv: float, to_ang: float, night: bool) -> float:
	var sv: float = float(d["sense_v"])
	var noise := pv * 0.9 if pv <= QUIET_SPEED else QUIET_SPEED * 0.9 + (pv - QUIET_SPEED) * sv
	var r: float = float(d["sense"]) + noise
	if state == S.GRAZE: r *= 0.8
	var facing := cos(angle_difference(heading, to_ang))     # 1 = looking straight at you
	if facing > 0.25 and state != S.GRAZE:
		var see := (7.0 + pv * 2.5) if pv > 0.25 else 2.5
		see *= clampf((facing - 0.25) / 0.45, 0.0, 1.0)
		if night: see *= 0.5
		r = maxf(r, see)
	return r

func _brain_prey(dist: float, to_ang: float, pv: float, night: bool) -> void:
	var hr := detect_radius(pv, to_ang, night)
	var moving := pv > 0.25
	var loud := clampf((pv - QUIET_SPEED) / 3.0, 0.0, 1.0)     # 0 walking .. 1 running
	match state:
		S.IDLE, S.GRAZE, S.LOOK, S.WALK, S.ALERT:
			# right on top of it and moving (or anywhere near it at a run):
			# no second look, it just goes
			if (moving and dist < hr * lerpf(0.45, 0.7, loud)) or dist < 1.1:
				_bolt(to_ang)
				return
			# suspicion builds while you move inside the ring (faster the
			# closer and the louder you are) and drains while you freeze
			if dist < hr:
				if moving: _alert += (0.45 + 1.6 * (1.0 - dist / hr)) * (1.0 + loud * 1.2) * _dt
				else: _alert -= 0.25 * _dt
			else:
				_alert -= 0.4 * _dt
			_alert = clampf(_alert, 0.0, 1.0)
			if _alert >= 1.0:
				_bolt(to_ang)
				return
			if state == S.ALERT:
				# head up, turning to find you: freeze and it may settle
				_goal = to_ang
				if _alert <= 0.0 and _t > 2.0: _enter(S.LOOK)
			elif _alert > 0.3:
				_goal = to_ang
				_enter(S.ALERT)
			elif _t > _dur:
				_next_idle()
		S.FLEE:
			# keep running away from the player, bending around bad ground
			if dist < 40.0: _goal = lerp_angle(_goal, to_ang + PI, 0.08)
			if _t > _dur and dist > float(d.get("safe", 55.0)):
				_alert = 0.0
				_enter(S.WALK)

func _bolt(to_ang: float) -> void:
	_alert = 0.0
	_goal = to_ang + PI + _rng.randf_range(-0.5, 0.5)
	_enter(S.FLEE)
	if wild != null: wild.alarm(global_position, self)
	Audio.play_sfx(String(d.get("sfx_alarm", "")), global_position, _rng.randf_range(0.92, 1.08), 0.0)

func _brain_boar(dist: float, to_ang: float, pv: float, night: bool) -> void:
	var hr: float = float(d["sense"]) + pv * float(d["sense_v"])
	match state:
		S.IDLE, S.GRAZE, S.LOOK, S.WALK:
			if dist < hr:
				_goal = to_ang
				_charges = 0
				_enter(S.ALERT)
				Audio.play_sfx(String(d.get("sfx_alarm", "")), global_position, _rng.randf_range(0.9, 1.05), 0.0)
				return
			if _t > _dur: _next_idle()
		S.ALERT:
			# head down, a snort, then the charge: the tell you can dodge.
			# Back well off before it commits and it lets you go.
			_goal = to_ang
			if dist > hr * 1.8 + 3.0:
				_enter(S.GRAZE)
			elif _t > _dur:
				_charges += 1
				_enter(S.CHARGE)
		S.CHARGE:
			_goal = to_ang
			_cmin = minf(_cmin, dist)
			if dist < 1.9 and not Game.cinematic:
				_enter(S.ATTACK)
			elif _cmin < 4.0 and dist > _cmin + 1.2:
				# you got out of its line: it overshoots and skids round
				_enter(S.RECOVER)
			elif dist > 30.0 or _t > 7.0:
				_enter(S.WALK)
		S.ATTACK:
			if not _struck and _t > _dur * 0.4:
				_struck = true
				_bite(dist, 2.2)
			if _t > _dur:
				_enter(S.RECOVER)
		S.RECOVER:
			# carries on past you, then skids to a stop and wheels round --
			# the opening to cut it -- then snorts and comes again, unless
			# you have put distance between you or it has had enough
			if _t >= RUN_ON: _goal = to_ang
			if _t > _dur:
				if dist > 22.0 or _charges >= 4:
					_enter(S.WALK)
				else:
					_charges += 1
					_goal = to_ang
					_enter(S.ALERT)
					_dur = 0.55
		S.FLEE:
			if dist < 40.0: _goal = lerp_angle(_goal, to_ang + PI, 0.08)
			if _t > _dur and dist > 45.0: _enter(S.WALK)

func _brain_wolf(dist: float, to_ang: float, p: Vector3, night: bool) -> void:
	if not night and state != S.FLEE:
		_goal = to_ang + PI
		_enter(S.FLEE)
		return
	match state:
		S.IDLE, S.GRAZE, S.LOOK, S.WALK, S.STALK:
			if state != S.STALK: _enter(S.STALK)
			# circle the player at a set radius, closing in from the dark
			var ring := 11.0 if dist < 40.0 else 0.0
			slot += _dt * 0.22
			var target := Vector2(p.x, p.z) + Vector2(sin(slot), cos(slot)) * ring
			var tv := target - Vector2(global_position.x, global_position.z)
			_goal = atan2(tv.x, tv.y)
			_run = tv.length() > 14.0
			_play("run" if _run else "walk")
			# a low growl from the dark now and then once it is close
			_growl_t -= _dt
			if dist < 15.0 and _growl_t <= 0.0:
				_growl_t = _rng.randf_range(4.0, 9.0)
				Audio.play_sfx("wolf_growl", global_position, _rng.randf_range(0.85, 1.0), -7.0)
			if _t > _dur and dist < 16.0 and _cool <= 0.0 and not Game.cinematic \
					and wild != null and wild.take_attack_token(self):
				_enter(S.CHARGE)
		S.CHARGE:
			_goal = to_ang
			if dist < 2.1: _enter(S.ATTACK)
			elif _t > 4.0:
				_release()
				_enter(S.STALK)
		S.ATTACK:
			_goal = to_ang
			if not _struck and _t > _dur * 0.45:
				_struck = true
				_bite(dist, 2.4)
			if _t > _dur:
				_goal = to_ang + PI + _rng.randf_range(-0.7, 0.7)
				_enter(S.RECOVER)
		S.RECOVER:
			if _t > _dur:
				_release()
				_cool = _rng.randf_range(2.5, 5.0)
				_enter(S.STALK)
		S.HURT:
			if _t > _dur:
				_release()
				_goal = to_ang + PI
				_cool = 3.0
				_enter(S.RECOVER)
		S.FLEE:
			_goal = lerp_angle(_goal, to_ang + PI, 0.05)
			if dist > 120.0: despawn = true

func _release() -> void:
	if wild != null: wild.release_attack_token(self)

func _bite(dist: float, reach: float) -> void:
	if dist > reach or wild == null: return
	# only what is in front of its jaws (or tusks): a sidestep makes it miss
	if _pp != Vector3.INF:
		var ta := atan2(_pp.x - global_position.x, _pp.z - global_position.z)
		if absf(angle_difference(heading, ta)) > 0.85: return
	var pl = wild.get("player")
	if pl == null or not is_instance_valid(pl) or not pl.has_method("take_hit"): return
	if bool(pl.get("cinematic")): return
	pl.take_hit({"damage": float(d["dmg"]), "posture": float(d["dmg"]) * 1.3,
		"heavy": String(d["kind"]) == "boar", "source": self})
	Audio.play_sfx(String(d.get("sfx_attack", "")), global_position, _rng.randf_range(0.9, 1.1), 0.0)

func _next_idle() -> void:
	var r := _rng.randf()
	if state == S.WALK or state == S.LOOK:
		_enter(S.GRAZE if r < 0.6 else S.IDLE)
	elif state == S.GRAZE:
		_enter(S.LOOK if r < 0.35 and _ap != null and _ap.has_animation("look") else (S.WALK if r < 0.7 else S.IDLE))
	else:
		_enter(S.GRAZE if r < 0.5 else S.WALK)

# ------------------------------------------------------------------ motion
func _target_speed() -> float:
	match state:
		S.WALK, S.STALK:
			if state == S.STALK and _run: return float(d["run"]) * 0.8
			return float(d["walk"])
		S.FLEE: return float(d["run"])
		S.CHARGE: return float(d.get("charge", d["run"]))
		S.RECOVER:
			if String(d["kind"]) == "boar": return float(d["run"]) * 0.75 if _t < RUN_ON else 0.0
			return float(d["run"]) * 0.8
		S.ATTACK: return float(d.get("lunge", 1.5))
	return 0.0

func _bad_ground(x: float, z: float, terrain: Terrain) -> bool:
	if x < 26.0 or z < 26.0 or x > terrain.size - 26.0 or z > terrain.size - 26.0: return true
	return terrain.is_water(x, z) or terrain.sample_height(x, z) < terrain.water_level + 0.5 \
			or terrain.slope_at(x, z) > 0.5

## the heading nearest `want` whose next few metres are walkable: water,
## cliffs and the map edge are run round, keeping to the side it chose last
func _clear_heading(want: float, terrain: Terrain) -> float:
	var pos := global_position
	for off in [0.0, 0.45, 0.9, 1.4, 2.0, 2.6]:
		for k in (1 if off == 0.0 else 2):
			var sgn := _avoid if k == 0 else -_avoid
			var h: float = want + off * sgn
			if not _bad_ground(pos.x + sin(h) * 2.5, pos.z + cos(h) * 2.5, terrain) \
					and not _bad_ground(pos.x + sin(h) * 5.0, pos.z + cos(h) * 5.0, terrain):
				if off > 0.0: _avoid = sgn
				return h
	return want + PI

func _move(dt: float, terrain: Terrain) -> void:
	var ts := _target_speed()
	speed = move_toward(speed, ts, (14.0 if ts > speed else 10.0) * dt)
	var turn: float = float(d.get("turn", 3.0))
	match state:
		S.FLEE: turn *= 1.6
		# a charge commits: far out it homes in, the last few metres it
		# runs straight, so a sidestep or a dodge takes you out of its line
		S.CHARGE: turn *= 1.6 if _dist > 6.0 else 0.28
		S.ATTACK: turn *= 0.25
		S.ALERT: turn *= 0.55 if is_prey() else 1.4
		S.RECOVER: turn *= 0.6 if String(d["kind"]) == "boar" else 1.0
	var want := _goal
	if speed > 0.3 and terrain != null:
		want = _clear_heading(_goal, terrain)
	heading = lerp_angle(heading, want, clampf(dt * turn, 0.0, 1.0))
	if speed > 0.01 and terrain != null:
		var pos := global_position
		var nx := pos.x + sin(heading) * speed * dt
		var nz := pos.z + cos(heading) * speed * dt
		if _bad_ground(nx, nz, terrain):
			speed *= 0.5
		else:
			pos.x = nx
			pos.z = nz
		# never run through the player: stop at the edge of their body (a
		# boar that has just gored you bowls on through)
		var bowl := state == S.RECOVER and _t < RUN_ON and String(d["kind"]) == "boar"
		if _pp != Vector3.INF and not bowl:
			var dx := pos.x - _pp.x
			var dz := pos.z - _pp.z
			var l := sqrt(dx * dx + dz * dz)
			var along := absf(cos(angle_difference(heading, atan2(-dx, -dz))))
			var sep: float = lerpf(float(d["radius"]), float(d["length"]) * 0.5, along) + 0.38
			if l < sep and l > 0.001:
				pos.x = _pp.x + dx / l * sep
				pos.z = _pp.z + dz / l * sep
		global_position = pos
	if terrain != null:
		var gp := global_position
		gp.y = terrain.sample_height(gp.x, gp.z)
		global_position = gp
		# lean into the slope so the body does not float on hillsides
		var n: Vector3 = terrain.sample_normal(gp.x, gp.z)
		var fw := Vector3(sin(heading), 0.0, cos(heading))
		var pitch := -asin(clampf(fw.dot(n), -0.6, 0.6)) * 0.8
		_pivot.rotation.x = lerpf(_pivot.rotation.x, pitch, clampf(dt * 5.0, 0.0, 1.0))
	rotation.y = heading
	# gait speed follows ground speed so feet do not skate
	if _ap != null and state in [S.WALK, S.FLEE, S.CHARGE, S.RECOVER, S.STALK]:
		var running := state in [S.FLEE, S.CHARGE] or (state == S.RECOVER and String(d["kind"]) != "boar") \
				or (state == S.STALK and _run)
		var ref: float = float(d["run_ref"]) if running else float(d["walk_ref"])
		_ap.speed_scale = clampf(maxf(speed, 0.5) / maxf(ref, 0.1), 0.3, 2.5)

func _update_dead(dt: float) -> void:
	_dead_t += dt
	if not _ap or not _ap.has_animation("die"):
		# no death clip: roll onto the side
		_roll = minf(1.0, _roll + dt * 2.4)
		_pivot.rotation.z = lerpf(0.0, PI * 0.5, _roll * _roll * (3.0 - 2.0 * _roll))
		_pivot.position.y = sin(_roll * PI * 0.5) * float(d["height"]) * 0.28
		if _ap != null: _ap.speed_scale = 0.0
	if _sink >= 0.0:
		_sink += dt
		_pivot.position.y -= dt * 0.6
		if _sink > 1.6: despawn = true

## distance LOD from Wildlife: animation off far away, model hidden beyond view
func set_lod(dist: float) -> void:
	var far := dist > 110.0
	if _ap != null:
		_ap.active = not far
	if _model != null:
		_model.visible = dist < float(d.get("view", 220.0))
