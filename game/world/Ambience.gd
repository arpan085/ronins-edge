class_name Ambience
extends Node3D
## Ambient life: the small moving things that make a world feel inhabited.
##
## Everything here follows the player, is gated on conditions (biome, weather,
## time of day) and scales with the quality tier, so it costs nothing on a
## phone and fills the frame on desktop. Nothing here is gameplay.

var world: Node3D
var player: Node3D
var terrain: Terrain

var _leaves: GPUParticles3D
var _pollen: GPUParticles3D
var _dust: GPUParticles3D
var _flies: GPUParticles3D
var _drips: GPUParticles3D
var _birds: Array[Node3D] = []
var _bird_t := 0.0
var _tick := 0.0

const BIRDS_PER_TIER := [0, 3, 6, 9]

func setup(w: Node3D, p: Node3D, t: Terrain) -> void:
	world = w; player = p; terrain = t

func _ready() -> void:
	_leaves = _emitter(46, 7.0, Color(0.52, 0.42, 0.20), Vector3(0, -0.7, 0), 16.0, 0.22)
	_pollen = _emitter(70, 9.0, Color(0.96, 0.92, 0.62), Vector3(0, 0.05, 0), 12.0, 0.07)
	_dust   = _emitter(40, 6.0, Color(0.62, 0.56, 0.44), Vector3(0, -0.2, 0), 14.0, 0.14)
	_flies  = _emitter(34, 5.5, Color(0.85, 1.0, 0.45), Vector3(0, 0.0, 0), 8.0, 0.09)
	_drips  = _emitter(30, 1.3, Color(0.70, 0.82, 0.90), Vector3(0, -6.0, 0), 13.0, 0.05)
	for e in [_leaves, _pollen, _dust, _flies, _drips]:
		e.emitting = false
	_rebuild_birds()

func _emitter(amount: int, life: float, col: Color, grav: Vector3, box: float,
		size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life * 0.5
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-box, -box * 0.5, -box), Vector3(box * 2, box * 1.6, box * 2))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(box, box * 0.45, box)
	m.gravity = grav
	m.direction = Vector3(1, 0.2, 0.4)
	m.spread = 180.0
	m.initial_velocity_min = 0.2
	m.initial_velocity_max = 1.1
	m.angular_velocity_min = -90.0
	m.angular_velocity_max = 90.0
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.9
	m.turbulence_noise_scale = 1.6
	m.scale_min = 0.6
	m.scale_max = 1.4
	m.color = col
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.vertex_color_use_as_albedo = true
	qm.albedo_color = col
	# Soft round motes, not hard squares. Untextured unshaded quads read as
	# flat coloured rectangles floating in the air, which is exactly how the
	# leaves and pollen looked in the world shots.
	qm.albedo_texture = _mote()
	q.material = qm
	p.draw_pass_1 = q
	add_child(p)
	return p

static var _mote_tex: ImageTexture = null

## A small radial alpha gradient shared by every emitter.
static func _mote() -> ImageTexture:
	if _mote_tex != null: return _mote_tex
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := float(n - 1) * 0.5
	for y in n:
		for x in n:
			var d: float = Vector2(float(x) - c, float(y) - c).length() / c
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_mote_tex = ImageTexture.create_from_image(img)
	return _mote_tex

## Circling birds, built as simple two-triangle gliders on a slow orbit. Not
## wildlife AI - just silhouettes that keep the sky from being empty.
func _rebuild_birds() -> void:
	for b in _birds:
		if is_instance_valid(b): b.queue_free()
	_birds.clear()
	var n: int = BIRDS_PER_TIER[clampi(Perf.level, 0, 3)]
	if n <= 0: return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri in [[Vector3(0, 0, -0.5), Vector3(-0.9, 0.12, 0.3), Vector3(0, 0, 0.25)],
			[Vector3(0, 0, -0.5), Vector3(0, 0, 0.25), Vector3(0.9, 0.12, 0.3)]]:
		for v in tri:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2.ZERO)
			st.add_vertex(v)
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.09, 0.11)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.9
	for i in n:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.set_meta("r", 34.0 + randf() * 60.0)
		mi.set_meta("h", 26.0 + randf() * 34.0)
		mi.set_meta("sp", 0.12 + randf() * 0.16)
		mi.set_meta("ph", randf() * TAU)
		add_child(mi)
		_birds.append(mi)

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player): return
	var pos := player.global_position
	global_position = pos
	_tick += delta
	if _tick > 0.55:
		_tick = 0.0
		_update_conditions(pos)
	# birds glide on slow circles overhead
	_bird_t += delta
	for b in _birds:
		if not is_instance_valid(b): continue
		var r: float = float(b.get_meta("r"))
		var h: float = float(b.get_meta("h"))
		var sp: float = float(b.get_meta("sp"))
		var ph: float = float(b.get_meta("ph"))
		var a := _bird_t * sp + ph
		var bp := pos + Vector3(cos(a) * r, h + sin(a * 2.3) * 2.5, sin(a) * r)
		b.global_position = bp
		b.rotation = Vector3(0.0, -a + PI * 0.5, sin(a * 2.0) * 0.25)

func _update_conditions(pos: Vector3) -> void:
	if terrain == null or not terrain.loaded: return
	var biome := terrain.biome_at(pos.x, pos.z)
	var wx := "clear"
	var wind := 0.6
	var night := false
	if world != null:
		if world.has_method("weather_name"): wx = str(world.weather_name())
		var wsys = world.get("weather")
		if wsys != null: wind = float(wsys.get("wind"))
		var dn = world.get("daynight")
		if dn != null and dn.has_method("is_night"): night = bool(dn.is_night())
	var raining := wx == "rain" or wx == "storm"
	var q := clampf(float(Perf.preset().get("particles", 1.0)), 0.0, 2.0)
	var wooded := biome == "forest" or biome == "bamboo"
	var open := biome == "grassland" or biome == "tallgrass" or biome == "farmland"
	var arid := biome == "rocky" or biome == "alpine"

	_toggle(_leaves, wooded and not raining, int(46 * q), 1.0 + wind)
	_toggle(_pollen, open and not raining and not night, int(70 * q), 0.6 + wind * 0.4)
	_toggle(_dust, (arid or (open and wind > 1.1)) and not raining, int(40 * q), 0.8 + wind)
	# fireflies: night, calm, near water or under trees
	var near_water := terrain.river_at(pos.x, pos.z) > 0.2 \
		or terrain.river_prox_at(pos.x, pos.z) > 0.25 \
		or pos.y < terrain.water_level + 4.0
	_toggle(_flies, night and not raining and (near_water or wooded), int(34 * q), 0.4)
	# canopy drips keep falling for a while after the rain stops
	_toggle(_drips, wooded and raining, int(30 * q), 1.0)

func _toggle(p: GPUParticles3D, on: bool, amount: int, speed: float) -> void:
	if p == null: return
	if amount <= 0: on = false
	if on:
		if p.amount != amount: p.amount = maxi(amount, 1)
		p.speed_scale = speed
		if not p.emitting: p.emitting = true
	elif p.emitting:
		p.emitting = false

func set_quality(_level: int) -> void:
	_rebuild_birds()
