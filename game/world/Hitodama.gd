class_name Hitodama
extends Node3D
## v0.15 night: hitodama -- the spirit fires of Japanese folklore, pale blue
## flames that drift a man's height above the ground in forests, bamboo groves,
## shrines and ruins in the dead of night. They keep their distance: come too
## close and one gutters out, to reappear somewhere else in the dark. Purely
## atmosphere (no gameplay), a few cheap additive quads and, above the lowest
## quality tier, a small unshadowed light each so they tint the ground.

const COUNT_PER_TIER := [2, 3, 5, 6]
const BIOMES := {"forest": 1.0, "bamboo": 1.0, "shrine": 1.0, "ruins": 1.0, "tallgrass": 0.35,
	"grassland": 0.2, "rocky": 0.3, "alpine": 0.15}
const NEAR := 10.0        # closer than this and it vanishes
const FAR := 120.0        # further than this and it is recycled

var world: Node
var player: Node3D
var terrain: Terrain
var _wisps: Array[Node3D] = []
var _mat: ShaderMaterial
var _mesh: QuadMesh
var _rng := RandomNumberGenerator.new()
var _tick := 0.0
var _active := 0.0        # 0..1, how far into the deep night we are

func setup(w: Node, p: Node3D, t: Terrain) -> void:
	world = w
	player = p
	terrain = t
	_rng.seed = 4410
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/hitodama.gdshader")
	_mesh = QuadMesh.new()
	# about a head-sized ball of cold fire with its tongue above it
	_mesh.size = Vector2(0.75, 1.1)
	rebuild()

func rebuild() -> void:
	var n: int = COUNT_PER_TIER[clampi(Perf.level, 0, 3)]
	while _wisps.size() > n:
		_wisps.pop_back().queue_free()
	while _wisps.size() < n:
		_wisps.append(_make())

func _make() -> Node3D:
	var w := Node3D.new()
	w.name = "Hitodama%d" % _wisps.size()
	add_child(w)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	var m := _mat.duplicate() as ShaderMaterial
	m.set_shader_parameter("seed", _rng.randf() * 10.0)
	m.set_shader_parameter("fade", 0.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	w.add_child(mi)
	if Perf.level >= 1:
		var l := OmniLight3D.new()
		l.light_color = Color(0.48, 0.76, 1.0)
		l.light_energy = 0.0
		l.omni_range = 9.0
		l.omni_attenuation = 1.6
		l.shadow_enabled = false
		l.light_specular = 0.2
		l.distance_fade_enabled = true
		l.distance_fade_begin = 55.0
		l.distance_fade_length = 20.0
		w.add_child(l)
	w.set_meta("fade", 0.0)
	w.set_meta("want", 0.0)       # fade target
	w.set_meta("vel", Vector3.ZERO)
	w.set_meta("ph", _rng.randf() * TAU)
	w.set_meta("base", 1.6)
	w.set_meta("alive", false)
	w.visible = false
	return w

## the deep-night factor: nothing before 21:00, full from 22:00 to 03:30
func _night_amount() -> float:
	var h := float(world.get("time_of_day")) if world != null else 12.0
	if h >= 12.0: return clampf((h - 21.0) / 1.0, 0.0, 1.0)
	return clampf((4.2 - h) / 0.7, 0.0, 1.0)

func _place(w: Node3D) -> bool:
	var pp := player.global_position
	for i in 12:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(24.0, 70.0)
		var x := pp.x + sin(a) * r
		var z := pp.z + cos(a) * r
		if x < 30.0 or z < 30.0 or x > terrain.size - 30.0 or z > terrain.size - 30.0: continue
		if terrain.is_water(x, z): continue
		var chance: float = BIOMES.get(terrain.biome_at(x, z), 0.0)
		if _rng.randf() > chance: continue
		var base := _rng.randf_range(1.2, 2.3)
		w.global_position = Vector3(x, terrain.sample_height(x, z) + base, z)
		w.set_meta("base", base)
		w.set_meta("vel", Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(0.25, 0.55))
		w.set_meta("alive", true)
		w.set_meta("want", 1.0)
		w.visible = true
		return true
	return false

func _process(delta: float) -> void:
	if terrain == null or not terrain.loaded or player == null or not is_instance_valid(player): return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		_active = _night_amount()
		var wx = world.get("weather") if world != null else null
		if wx != null and float(wx.get("rain")) > 0.5: _active = 0.0
		if Game.cinematic: _active = 0.0
	var pp := player.global_position
	var t := Time.get_ticks_msec() * 0.001
	for w in _wisps:
		var alive := bool(w.get_meta("alive"))
		var fade := float(w.get_meta("fade"))
		if not alive:
			if _active > 0.2 and _rng.randf() < delta * 0.25: _place(w)
			continue
		var d := Vector2(w.global_position.x - pp.x, w.global_position.z - pp.z).length()
		if _active < 0.05 or d < NEAR or d > FAR:
			w.set_meta("want", 0.0)
		var want := float(w.get_meta("want")) * _active
		# vanishing is quick, appearing slow
		fade = move_toward(fade, want, delta * (0.9 if want < fade else 0.35))
		w.set_meta("fade", fade)
		if fade <= 0.001 and float(w.get_meta("want")) == 0.0:
			w.set_meta("alive", false)
			w.visible = false
			continue
		# wander: slow drift, turning now and then, bobbing on the air
		var v: Vector3 = w.get_meta("vel")
		v = v.rotated(Vector3.UP, sin(t * 0.37 + float(w.get_meta("ph"))) * delta * 0.6)
		w.set_meta("vel", v)
		var gp := w.global_position + v * delta
		var gh := terrain.sample_height(gp.x, gp.z)
		gp.y = lerpf(gp.y, gh + float(w.get_meta("base")) + sin(t * 1.3 + float(w.get_meta("ph"))) * 0.22, clampf(delta * 1.5, 0.0, 1.0))
		w.global_position = gp
		var flick := 0.85 + 0.15 * sin(t * 9.0 + float(w.get_meta("ph")) * 3.0)
		var mi := w.get_child(0) as MeshInstance3D
		(mi.material_override as ShaderMaterial).set_shader_parameter("fade", fade)
		if w.get_child_count() > 1:
			(w.get_child(1) as OmniLight3D).light_energy = 1.6 * fade * flick

func set_quality(_level: int) -> void:
	for w in _wisps: w.queue_free()
	_wisps.clear()
	rebuild()
