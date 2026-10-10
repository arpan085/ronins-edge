class_name Weather
extends Node3D
## Weather system: states, smooth transitions, wind, and the visual response.
##
## A weather state is a set of targets (cloud cover, rain, fog, wind, wetness).
## Current values chase the targets, so weather rolls in rather than snapping.
## The system then drives every consumer: fog + sky via DayNight, wetness on
## terrain/grass/trees, wind on foliage, and rain/snow/mist particles. Nothing
## here is a fullscreen overlay - it all feeds the same world parameters.

signal changed(name: String)

const STATES := {
	# Even "clear" carries a working breeze now. At 0.45/0.20 the grass barely
	# stirred, and a still field is the one thing this landscape cannot be.
	#                  cloud rain snow fog   wind  gust  wet
	"clear":      {"cloud": 0.18, "rain": 0.0,  "snow": 0.0, "fog": 0.75, "wind": 0.62, "gust": 0.38, "wet": 0.0},
	"cloudy":     {"cloud": 0.55, "rain": 0.0,  "snow": 0.0, "fog": 1.05, "wind": 0.70, "gust": 0.35, "wet": 0.0},
	"light_rain": {"cloud": 0.75, "rain": 0.35, "snow": 0.0, "fog": 1.45, "wind": 0.85, "gust": 0.40, "wet": 0.55},
	"rain":       {"cloud": 0.90, "rain": 0.75, "snow": 0.0, "fog": 1.85, "wind": 1.10, "gust": 0.60, "wet": 0.90},
	"storm":      {"cloud": 1.00, "rain": 1.00, "snow": 0.0, "fog": 2.10, "wind": 2.30, "gust": 1.60, "wet": 1.00},
	"fog":        {"cloud": 0.70, "rain": 0.0,  "snow": 0.0, "fog": 4.20, "wind": 0.25, "gust": 0.10, "wet": 0.25},
	"mist":       {"cloud": 0.45, "rain": 0.0,  "snow": 0.0, "fog": 2.70, "wind": 0.42, "gust": 0.20, "wet": 0.18},
	"wind":       {"cloud": 0.35, "rain": 0.0,  "snow": 0.0, "fog": 0.95, "wind": 1.90, "gust": 1.20, "wet": 0.0},
	"snow":       {"cloud": 0.85, "rain": 0.0,  "snow": 1.0, "fog": 2.20, "wind": 0.90, "gust": 0.55, "wet": 0.15},
}

var current := "clear"
var target := "clear"
var cloud := 0.05
var rain := 0.0
var snow := 0.0
var fog := 0.75
var wind := 0.45
var gust := 0.2
var wet := 0.0
var wind_dir := Vector2(0.86, 0.51)
## v0.17 km of cloud drift (shader global cloud_time), random start
var cloud_t := randf() * 40.0
var quality := 2
var auto := true

var terrain: Terrain
var foliage: Foliage
var trees: TreeSystem
var daynight: DayNight
var player: Node3D

var _rain_p: GPUParticles3D
var _snow_p: GPUParticles3D
var _mist_p: GPUParticles3D
var _splash_p: GPUParticles3D
var _curtains: Node3D
var _auto_t := 0.0
var _gust_t := 0.0
var _dir_t := 0.0

func setup(t: Terrain, f: Foliage, tr: TreeSystem, dn: DayNight, p: Node3D) -> void:
	terrain = t; foliage = f; trees = tr; daynight = dn; player = p
	_build_particles()
	set_weather("clear", true)

# ------------------------------------------------------------------ particles
func _p(amount: int, lifetime: float, box: Vector3, vel: Vector3, spread: float,
		scale_min: float, scale_max: float, col: Color, grav: Vector3) -> GPUParticles3D:
	var ps := GPUParticles3D.new()
	ps.amount = amount
	ps.lifetime = lifetime
	ps.visibility_aabb = AABB(-box, box * 2.0)
	ps.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = vel.normalized()
	pm.spread = spread
	pm.initial_velocity_min = vel.length() * 0.8
	pm.initial_velocity_max = vel.length() * 1.2
	pm.gravity = grav
	pm.scale_min = scale_min
	pm.scale_max = scale_max
	pm.color = col
	ps.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.05, 0.42)
	ps.draw_pass_1 = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = col
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.disable_receive_shadows = true
	qm.material = mat
	add_child(ps)
	return ps

func _build_particles() -> void:
	_rain_p = _p(900, 1.1, Vector3(26, 1, 26), Vector3(0.6, -1, 0.3) * 17.0, 4.0,
		0.7, 1.5, Color(0.68, 0.76, 0.88, 0.55), Vector3(0, -24, 0))
	_snow_p = _p(500, 5.0, Vector3(26, 1, 26), Vector3(0.2, -1, 0.1) * 2.0, 26.0,
		0.5, 1.2, Color(0.95, 0.97, 1.0, 0.85), Vector3(0, -1.4, 0))
	var sq := _snow_p.draw_pass_1 as QuadMesh
	if sq != null: sq.size = Vector2(0.09, 0.09)
	_mist_p = _p(120, 9.0, Vector3(34, 5, 34), Vector3(1, 0.05, 0.4) * 0.7, 40.0,
		9.0, 22.0, Color(0.72, 0.78, 0.84, 0.055), Vector3(0, 0.05, 0))
	var mq := _mist_p.draw_pass_1 as QuadMesh
	if mq != null: mq.size = Vector2(1.0, 1.0)
	# ground splash ring when rain is heavy
	_splash_p = _p(260, 0.55, Vector3(14, 0.2, 14), Vector3(0, 1, 0) * 1.6, 55.0,
		0.25, 0.7, Color(0.78, 0.86, 0.95, 0.30), Vector3(0, -6.0, 0))
	var spq := _splash_p.draw_pass_1 as QuadMesh
	if spq != null: spq.size = Vector2(0.14, 0.05)
	_build_curtains()
	for p in [_rain_p, _snow_p, _mist_p, _splash_p]:
		p.emitting = false

## Distant rain curtains: a few large soft panels far from the camera so heavy
## weather reads at range instead of only near the player.
func _build_curtains() -> void:
	_curtains = Node3D.new()
	_curtains.name = "RainCurtains"
	add_child(_curtains)
	for i in 3:
		var q := QuadMesh.new()
		q.size = Vector2(260.0, 90.0)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.62, 0.70, 0.80, 0.0)
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.disable_receive_shadows = true
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_curtains.add_child(mi)

# ------------------------------------------------------------------ control
func set_weather(name: String, instant := false) -> void:
	if not STATES.has(name): return
	target = name
	if instant:
		var s: Dictionary = STATES[name]
		cloud = s["cloud"]; rain = s["rain"]; snow = s["snow"]
		fog = s["fog"]; wind = s["wind"]; gust = s["gust"]; wet = s["wet"]
		current = name
		_apply()
	changed.emit(name)

func set_quality(level: int) -> void:
	quality = level
	var muls: Array = [0.18, 0.45, 1.0, 1.5]
	var mul: float = float(muls[clampi(level, 0, 3)])
	if _rain_p != null: _rain_p.amount = maxi(24, int(900 * mul))
	if _snow_p != null: _snow_p.amount = maxi(16, int(500 * mul))
	if _mist_p != null: _mist_p.amount = maxi(8, int(120 * mul))
	if _splash_p != null: _splash_p.amount = maxi(0, int(260 * mul))
	if _curtains != null: _curtains.visible = level >= 1

func wind_vector() -> Vector3:
	return Vector3(wind_dir.x, 0.0, wind_dir.y) * (wind + gust)

# ------------------------------------------------------------------ frame
func _process(delta: float) -> void:
	# weather rolls in over ~12 s rather than switching
	var s: Dictionary = STATES.get(target, STATES["clear"])
	var k := clampf(delta * 0.085, 0.0, 1.0)
	cloud = lerpf(cloud, float(s["cloud"]), k)
	rain = lerpf(rain, float(s["rain"]), k)
	snow = lerpf(snow, float(s["snow"]), k)
	fog = lerpf(fog, float(s["fog"]), k)
	wind = lerpf(wind, float(s["wind"]), k)
	wet = lerpf(wet, float(s["wet"]), k * 0.6)
	current = target

	# gusts: slow random envelope so wind swells and drops
	_gust_t += delta
	var target_gust: float = float(s["gust"]) * (0.45 + 0.55 * (0.5 + 0.5 * sin(_gust_t * 0.37) * sin(_gust_t * 0.11 + 1.3)))
	gust = lerpf(gust, target_gust, clampf(delta * 0.8, 0.0, 1.0))
	cloud_t += delta * (0.006 + cloud * 0.012) * 1.6
	# wind direction drifts
	_dir_t += delta * 0.04
	wind_dir = Vector2(cos(_dir_t), sin(_dir_t * 0.7)).normalized()

	if auto:
		_auto_t += delta
		if _auto_t > 95.0:
			_auto_t = 0.0
			_pick_auto()
	_apply()
	_follow(delta)

func _pick_auto() -> void:
	var pool := ["clear", "clear", "cloudy", "light_rain", "mist", "wind", "rain", "cloudy", "fog", "storm"]
	if terrain != null and player != null and is_instance_valid(player):
		# snow only makes sense high in the mountains
		if player.global_position.y > 95.0:
			pool.append_array(["snow", "snow", "fog"])
	set_weather(pool[randi() % pool.size()])

func _apply() -> void:
	if daynight != null:
		# cloud cover flattens the light and lifts the fog
		daynight.fog_mul = fog
		daynight.light_mul = 1.0 - cloud * 0.45
		daynight.fog_tint = Color(1, 1, 1).lerp(Color(0.72, 0.76, 0.82), cloud * 0.8)
		# v0.17: mist, rain and fog thicken the air the sky is made of - the
		# horizon goes milky and the sun's glow spreads
		daynight.turbidity = clampf(1.25 + (fog - 0.75) * 0.55, 1.0, 3.5)
		# v0.17: the cloud field is shared by the sky and the landscape's cloud
		# shadows, so it lives in global shader uniforms. Drift is integrated
		# here: v0.16 multiplied TIME by a speed that changes with the weather,
		# which sent the whole deck racing whenever the weather turned.
		RenderingServer.global_shader_parameter_set("cloud_cover", clampf(0.18 + cloud * 0.80, 0.0, 1.0))
		RenderingServer.global_shader_parameter_set("cloud_storm", clampf((cloud - 0.6) * 2.5, 0.0, 1.0))
		RenderingServer.global_shader_parameter_set("cloud_time", cloud_t)
		daynight.apply()
	if terrain != null:
		terrain.set_wetness(wet)
		terrain.set_snow(snow)
	if foliage != null:
		foliage.set_wind(wind_dir, wind, gust)
		foliage.set_wetness(wet)
		foliage.set_snow(snow)
	if trees != null:
		trees.set_wind(wind_dir, wind, gust)
		trees.set_wetness(wet)
		trees.set_snow(snow)
	if _rain_p != null:
		_rain_p.emitting = rain > 0.04
		if _rain_p.emitting:
			var pm := _rain_p.process_material as ParticleProcessMaterial
			pm.direction = Vector3(wind_dir.x * (0.25 + wind * 0.35), -1.0, wind_dir.y * (0.25 + wind * 0.35)).normalized()
			pm.initial_velocity_min = 12.0 + rain * 12.0
			pm.initial_velocity_max = 18.0 + rain * 16.0
			pm.color = Color(0.68, 0.76, 0.88, 0.25 + rain * 0.45)
	if _splash_p != null:
		_splash_p.emitting = rain > 0.45
	if _snow_p != null:
		_snow_p.emitting = snow > 0.04
	if _mist_p != null:
		_mist_p.emitting = fog > 1.6
		if _mist_p.emitting:
			var pm2 := _mist_p.process_material as ParticleProcessMaterial
			pm2.color = Color(0.72, 0.78, 0.84, clampf(0.02 + fog * 0.022, 0.0, 0.12))
	if _curtains != null:
		var a := clampf(rain * 0.30 + snow * 0.16, 0.0, 0.34)
		for c in _curtains.get_children():
			var mi: MeshInstance3D = c
			var m := mi.material_override as StandardMaterial3D
			if m != null: m.albedo_color = Color(0.62, 0.70, 0.80, a)
			mi.visible = a > 0.01

func _follow(_delta: float) -> void:
	if player == null or not is_instance_valid(player): return
	var p := player.global_position
	if _rain_p != null: _rain_p.global_position = p + Vector3(0, 17, 0)
	if _snow_p != null: _snow_p.global_position = p + Vector3(0, 17, 0)
	if _mist_p != null: _mist_p.global_position = p + Vector3(0, 2.5, 0)
	if _splash_p != null: _splash_p.global_position = p + Vector3(0, 0.1, 0)
	if _curtains != null:
		for i in _curtains.get_child_count():
			var mi: MeshInstance3D = _curtains.get_child(i)
			var a := TAU * float(i) / float(_curtains.get_child_count())
			mi.global_position = p + Vector3(cos(a) * 190.0, 24.0, sin(a) * 190.0)

func describe() -> String:
	return current
