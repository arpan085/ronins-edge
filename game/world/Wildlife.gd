class_name Wildlife
extends Node3D
## v0.15 wildlife: skinned, animated animals you can watch, stalk and hunt.
##
## Replaces the v0.14 primitive box animals. Models are free assets (see
## CREDITS.md) converted by tools/animals/convert_animals.py; each animal is a
## WildAnimal with its own small brain. This node keeps the population around
## the player (spawning herds out of sight, dropping animals that wander far),
## runs the brains at a distance-scaled rate, raises the alarm through a herd,
## hands out the wolves' attack token and pays out a harvested carcass.
##
## Hunting: prey hear you by your speed and see you when facing you. Walk
## (walk toggle) up from behind while a deer grazes and you can get inside a
## lunge; an unaware animal takes 2.5x damage. Press interact over the carcass
## to harvest it: meat heals and refills a gourd charge.
## Night: a wolf pack may pick up your trail in the wilds. They circle and dart
## in one at a time, and leave at dawn.

const COUNT_PER_TIER := [4, 6, 9, 12]
const SPECIES := {
	"doe": {"scene": "res://assets/animals/doe.glb", "label": "Sika doe", "kind": "prey",
		"scale": 0.245, "yaw": 0.0, "lift": 0.0, "hp": 26.0,
		"walk": 3.0, "run": 9.5, "walk_ref": 7.5, "run_ref": 8.5,
		"alias": {"walk": ["run", 0.4]}, "sense": 2.2, "sense_v": 2.7, "safe": 60.0, "turn": 3.0,
		"radius": 0.28, "length": 1.32, "height": 1.05,
		"meat": "venison", "heal": 35.0, "gourd": 1, "xp": 0,
		"sfx_alarm": "deer_alarm", "sfx_hurt": "deer_alarm",
		"weight": 0.34, "herd": [2, 3], "biomes": ["grassland", "tallgrass", "forest", "shrine", "farmland", "bamboo"]},
	"stag": {"scene": "res://assets/animals/stag.glb", "label": "Sika stag", "kind": "prey",
		"scale": 0.265, "yaw": 0.0, "lift": 0.0, "hp": 40.0,
		"walk": 3.0, "run": 9.8, "walk_ref": 7.5, "run_ref": 8.8,
		"alias": {"walk": ["run", 0.4]}, "sense": 2.5, "sense_v": 2.8, "safe": 65.0, "turn": 2.6,
		"radius": 0.31, "length": 1.45, "height": 1.2,
		"meat": "venison", "heal": 50.0, "gourd": 1, "xp": 1,
		"sfx_alarm": "deer_alarm", "sfx_hurt": "deer_alarm",
		"weight": 0.16, "herd": [1, 2], "biomes": ["grassland", "tallgrass", "forest", "shrine", "alpine", "rocky"]},
	"fox": {"scene": "res://assets/animals/fox.glb", "label": "Red fox", "kind": "prey",
		"scale": 0.085, "yaw": 0.0, "lift": 0.0, "hp": 14.0,
		"walk": 1.3, "run": 8.0, "walk_ref": 1.3, "run_ref": 7.0,
		"sense": 1.8, "sense_v": 2.4, "safe": 50.0, "turn": 4.0,
		"radius": 0.17, "length": 0.75, "height": 0.42,
		"meat": "fox", "heal": 15.0, "gourd": 0, "xp": 0,
		"sfx_alarm": "fox_bark", "sfx_hurt": "fox_bark",
		"weight": 0.2, "herd": [1, 1], "biomes": ["grassland", "farmland", "tallgrass", "forest", "village", "shrine", "rocky"]},
	"boar": {"scene": "res://assets/animals/boar.glb", "label": "Wild boar", "kind": "boar",
		"scale": 0.45, "yaw": PI, "lift": 0.46, "hp": 70.0,
		"walk": 1.2, "run": 7.0, "charge": 8.5, "walk_ref": 1.2, "run_ref": 1.2,
		"alias": {"run": ["walk", 1.0], "eat": ["idle", 1.0], "look": ["idle", 1.0], "die": ["idle", 1.0]},
		"sense": 4.5, "sense_v": 1.3, "turn": 3.2,
		"dmg": 14.0, "atk_time": 0.8, "lunge": 3.5,
		"radius": 0.36, "length": 1.35, "height": 0.95,
		"meat": "boar", "heal": 60.0, "gourd": 1, "xp": 1,
		"sfx_alarm": "boar_grunt", "sfx_hurt": "boar_squeal", "sfx_attack": "boar_grunt",
		"weight": 0.3, "herd": [1, 2], "biomes": ["forest", "bamboo", "tallgrass", "farmland", "rocky"]},
	"wolf": {"scene": "res://assets/animals/wolf.glb", "label": "Wolf", "kind": "wolf",
		"scale": 0.9, "yaw": 0.0, "lift": 0.0, "hp": 40.0,
		"walk": 3.0, "run": 9.0, "charge": 10.0, "walk_ref": 8.0, "run_ref": 8.0,
		"alias": {"walk": ["run", 0.4], "eat": ["idle", 1.0], "look": ["idle", 1.0]},
		"atk_clip": "attack2", "atk_speed": 1.6, "atk_time": 1.15, "lunge": 4.0, "dmg": 9.0, "turn": 4.5,
		"radius": 0.24, "length": 1.25, "height": 0.75, "view": 160.0,
		"meat": "wolf", "heal": 20.0, "gourd": 0, "xp": 1,
		"sfx_hurt": "wolf_yelp", "sfx_attack": "wolf_growl",
		"weight": 0.0, "herd": [2, 3], "biomes": []},
}
const MEAT := {"venison": "venison", "boar": "boar meat", "fox": "a fox pelt", "wolf": "a wolf pelt"}
## where wolves will not follow you
const SAFE_BIOMES := ["village", "shrine"]

var terrain: Terrain
var player: Node3D
var world: Node = null

var _animals: Array[WildAnimal] = []
var _target := -1
var _rng := RandomNumberGenerator.new()
var _spawn_cd := 0.0
var _serial := 0
var _pp_last := Vector3.INF
var _pv := 0.0
var _frame := 0
var _token: WildAnimal = null
var _pack_cd := 45.0            # first night pack no sooner than this
var _pack_alive := 0
var _pack_seq := 0
var _howl_t := 0.0
var _far_howl_t := 30.0
var _night := false
var kills := 0

func setup(t: Terrain, p: Node3D) -> void:
	terrain = t
	player = p
	world = get_parent()
	_rng.seed = 90210
	rebuild()

## Perf calls this on a quality change. The population only changes size: no
## animal is respawned unless the tier's count actually changed.
func rebuild() -> void:
	var n: int = COUNT_PER_TIER[clampi(Perf.level, 0, 3)]
	if n == _target: return
	_target = n
	var day := _day_animals()
	while day.size() > n:
		var a: WildAnimal = day.pop_back()
		_remove(a)

func _day_animals() -> Array[WildAnimal]:
	var out: Array[WildAnimal] = []
	for a in _animals:
		if is_instance_valid(a) and not a.is_predator(): out.append(a)
	return out

func animals() -> Array[WildAnimal]:
	return _animals

# ------------------------------------------------------------------ spawning
func _spawn(sp: String, pos: Vector3) -> WildAnimal:
	var a := WildAnimal.new()
	_serial += 1
	add_child(a)
	a.setup(sp, SPECIES[sp], self, _rng.randi() % 100000 + _serial)
	a.global_position = pos
	_animals.append(a)
	return a

func _remove(a: WildAnimal) -> void:
	if _token == a: _token = null
	_animals.erase(a)
	if is_instance_valid(a): a.queue_free()

func _pick_species(biome: String) -> String:
	var tot := 0.0
	for k in SPECIES.keys():
		var d: Dictionary = SPECIES[k]
		if (d["biomes"] as Array).has(biome): tot += float(d["weight"])
	if tot <= 0.0: return ""
	var r := _rng.randf() * tot
	for k in SPECIES.keys():
		var d: Dictionary = SPECIES[k]
		if not (d["biomes"] as Array).has(biome): continue
		r -= float(d["weight"])
		if r <= 0.0: return String(k)
	return ""

func _ground_ok(x: float, z: float) -> bool:
	if x < 30.0 or z < 30.0 or x > terrain.size - 30.0 or z > terrain.size - 30.0: return false
	if terrain.is_water(x, z): return false
	if terrain.sample_height(x, z) < terrain.water_level + 0.8: return false
	if terrain.slope_at(x, z) > 0.42: return false
	return true

## a spot `r0..r1` from the player, preferably behind the camera
func _find_spot(base: Vector3, r0: float, r1: float, behind := true) -> Vector3:
	var fwd := Vector3.FORWARD
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null: fwd = -cam.global_transform.basis.z
	var fa := atan2(fwd.x, fwd.z)
	for i in 24:
		var ang := _rng.randf() * TAU
		if behind and i < 16: ang = fa + PI + _rng.randf_range(-1.9, 1.9)
		var r := _rng.randf_range(r0, r1)
		var x := base.x + sin(ang) * r
		var z := base.z + cos(ang) * r
		if _ground_ok(x, z): return Vector3(x, terrain.sample_height(x, z), z)
	return Vector3.INF

func _spawn_herd(base: Vector3, initial: bool) -> void:
	var spot := _find_spot(base, 45.0 if initial else 80.0, 150.0 if initial else 170.0, not initial)
	if spot == Vector3.INF: return
	var biome := terrain.biome_at(spot.x, spot.z)
	var sp := _pick_species(biome)
	if sp == "": return
	var hr: Array = SPECIES[sp]["herd"]
	var n := _rng.randi_range(int(hr[0]), int(hr[1]))
	n = mini(n, _target - _day_animals().size())
	for i in maxi(n, 1):
		var p := spot + Vector3(_rng.randf_range(-6.0, 6.0), 0.0, _rng.randf_range(-6.0, 6.0))
		if not _ground_ok(p.x, p.z): p = spot
		p.y = terrain.sample_height(p.x, p.z)
		# a deer herd is mostly does with the odd stag
		var s2 := sp
		if sp == "doe" and i > 0 and _rng.randf() < 0.2: s2 = "stag"
		_spawn(s2, p)

func _spawn_pack(base: Vector3) -> void:
	var spot := _find_spot(base, 70.0, 95.0, true)
	if spot == Vector3.INF: return
	_pack_seq += 1
	var n := _rng.randi_range(2, 3)
	for i in n:
		var p := spot + Vector3(_rng.randf_range(-4.0, 4.0), 0.0, _rng.randf_range(-4.0, 4.0))
		if not _ground_ok(p.x, p.z): p = spot
		p.y = terrain.sample_height(p.x, p.z)
		var a := _spawn("wolf", p)
		a.pack_id = _pack_seq
		a.slot = TAU * float(i) / float(n)
	_pack_alive = n
	Audio.play_sfx("wolf_howl", spot, _rng.randf_range(0.95, 1.05), 4.0)
	Game.notice.emit("Wolves howl nearby…", "warn")

# ------------------------------------------------------------------ runtime
func is_night() -> bool:
	if world == null: return false
	var h := float(world.get("time_of_day"))
	return h < 5.3 or h > 19.6

func _process(delta: float) -> void:
	if terrain == null or not terrain.loaded or player == null or not is_instance_valid(player): return
	_frame += 1
	var pp := player.global_position
	if _pp_last != Vector3.INF and delta > 0.0:
		var v := Vector2(pp.x - _pp_last.x, pp.z - _pp_last.z).length() / delta
		if v > 40.0: v = 0.0     # a warp, not a sprint
		_pv = lerpf(_pv, v, clampf(delta * 6.0, 0.0, 1.0))
	_pp_last = pp
	_night = is_night()
	# keep the day population topped up, one herd at a time
	_spawn_cd -= delta
	if _spawn_cd <= 0.0 and _day_animals().size() < _target:
		_spawn_cd = 1.5
		_spawn_herd(pp, _frame < 30 or _animals.is_empty())
	_update_pack(delta, pp)
	for i in range(_animals.size() - 1, -1, -1):
		var a: WildAnimal = _animals[i]
		if not is_instance_valid(a):
			_animals.remove_at(i)
			continue
		var dist := Vector2(a.global_position.x - pp.x, a.global_position.z - pp.z).length()
		if a.despawn or dist > 280.0 or (a.is_dead and dist > 160.0):
			if a.is_predator() and not a.is_dead: _pack_alive = maxi(0, _pack_alive - 1)
			_remove(a)
			continue
		a.set_lod(dist)
		# distant brains tick less often (and take the whole elapsed time)
		var every := 1 if dist < 60.0 else (3 if dist < 140.0 else 8)
		a._tick += delta
		if (_frame + i) % every == 0:
			a.think(pp, _pv, a._tick, _night, terrain)
			a._tick = 0.0

func _update_pack(delta: float, pp: Vector3) -> void:
	_pack_cd -= delta
	if not _night:
		return
	# far-off howls on the wind long before (or without) a pack showing up
	_far_howl_t -= delta
	if _far_howl_t <= 0.0:
		_far_howl_t = _rng.randf_range(55.0, 120.0)
		if _pack_alive == 0:
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(220.0, 320.0)
			Audio.play_sfx("wolf_howl", pp + Vector3(sin(a) * r, 25.0, cos(a) * r), _rng.randf_range(0.9, 1.02), 0.0)
	if _pack_alive > 0:
		_howl_t -= delta
		if _howl_t <= 0.0:
			_howl_t = _rng.randf_range(25.0, 50.0)
			for a in _animals:
				if is_instance_valid(a) and a.is_predator() and not a.is_dead:
					Audio.play_sfx("wolf_howl", a.global_position, _rng.randf_range(0.92, 1.06), 2.0)
					break
		return
	if _pack_cd > 0.0 or Game.cinematic: return
	if SAFE_BIOMES.has(terrain.biome_at(pp.x, pp.z)): return
	_pack_cd = _rng.randf_range(150.0, 260.0)
	_spawn_pack(pp)
	_howl_t = _rng.randf_range(20.0, 35.0)

# ------------------------------------------------------------------ herd + pack
## a startled animal spooks the rest of its herd
func alarm(pos: Vector3, src: WildAnimal) -> void:
	if player == null: return
	var pp := player.global_position
	for a in _animals:
		if a == src or not is_instance_valid(a) or a.is_dead or not a.is_prey(): continue
		if a.global_position.distance_to(pos) < 32.0 and a.unaware():
			var away := a.global_position - pp
			a.set("_goal", atan2(away.x, away.z) + _rng.randf_range(-0.5, 0.5))
			a._enter(WildAnimal.S.FLEE)

func take_attack_token(a: WildAnimal) -> bool:
	if _token != null and is_instance_valid(_token) and not _token.is_dead and _token != a:
		return false
	_token = a
	return true

func release_attack_token(a: WildAnimal) -> void:
	if _token == a: _token = null

func on_killed(a: WildAnimal, clean: bool) -> void:
	kills += 1
	release_attack_token(a)
	var label := a.display_name()
	if a.is_predator():
		_pack_alive = maxi(0, _pack_alive - 1)
		# a pack that has lost most of its number gives up
		if _pack_alive <= 1:
			for o in _animals:
				if is_instance_valid(o) and o.is_predator() and not o.is_dead:
					o._enter(WildAnimal.S.FLEE)
			_pack_alive = 0
	var msg := ("Clean kill — %s" if clean and not a.is_predator() else "%s down") % label
	Game.notice.emit(msg + "  ·  harvest it (%s)" % Game.bind_label("interact"), "reward")

# ------------------------------------------------------------------ harvest
func carcass_near(pos: Vector3, r: float) -> WildAnimal:
	var best: WildAnimal = null
	var bd := r
	for a in _animals:
		if not is_instance_valid(a) or not a.is_dead or a.harvested: continue
		var dd := Vector2(a.global_position.x - pos.x, a.global_position.z - pos.z).length()
		if dd < bd and absf(a.global_position.y - pos.y) < 2.5:
			bd = dd
			best = a
	return best

func harvest_label(a: WildAnimal) -> String:
	return "Harvest %s" % String(MEAT.get(String(a.d["meat"]), "meat"))

func harvest(a: WildAnimal) -> void:
	if a == null or not is_instance_valid(a) or a.harvested: return
	a.take_carcass()
	var d: Dictionary = a.d
	var heal_v := float(d.get("heal", 0.0))
	if heal_v > 0.0: Game.heal_player(heal_v)
	var g := 0
	if int(d.get("gourd", 0)) > 0: g = Game.refill_gourd(int(d["gourd"]))
	var xp := int(d.get("xp", 0))
	if xp > 0: Game.add_xp(xp)
	Audio.play_sfx("harvest", a.global_position, 1.0, 0.0)
	Audio.play_sfx("heal", null, 1.0, -4.0)
	var parts: Array[String] = []
	if heal_v > 0.0: parts.append("+%d health" % int(heal_v))
	if g > 0: parts.append("+%d gourd" % g)
	if xp > 0: parts.append("+%d mastery" % xp)
	Game.notice.emit("Harvested %s — %s" % [String(MEAT.get(String(d["meat"]), "meat")), ", ".join(parts)], "reward")
