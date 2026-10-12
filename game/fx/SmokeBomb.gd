class_name SmokeBomb
extends Node3D
## v0.16 smoke bomb (Shinobi Arts): a grey cloud ~5.5 m across that lasts ~8 s.
## Soldiers caught in the burst are blinded (EnemyBase.blind) and can be
## assassinated; those fighting you from outside it lose you and go searching
## (EnemyBase.lose_track). While you stand inside it you cannot be seen
## (Player.in_smoke -> stealth_visibility 0). Particles are CPU billboards so
## it costs the same on the software renderer as on a GPU.

const RADIUS := 5.5
const LIFE := 8.0
const FADE := 2.0
const BLIND_TIME := 4.5
const LOSE_RADIUS := 18.0

var age := 0.0
var _caught := {}
var _world: Node = null
var _puffs: Array = []
static var _tex: Texture2D = null

func _ready() -> void:
	add_to_group("smoke_cloud")
	_build_particles()

## True while the cloud is thick enough to hide someone standing at p.
func covers(p: Vector3) -> bool:
	if age > LIFE - FADE * 0.5: return false
	var d := Vector2(p.x - global_position.x, p.z - global_position.z).length()
	return d < RADIUS * 0.9 * clampf(age / 0.35, 0.35, 1.0) and absf(p.y - global_position.y) < 3.0

func burst(w: Node, by: Node3D = null) -> void:
	_world = w
	Audio.play_sfx("smoke", global_position, 1.0, 2.0)
	Audio.play_sfx("cloth", global_position, 0.7, 0.0)
	if w == null or not "enemies" in w: return
	for e in w.enemies:
		if not is_instance_valid(e) or e.is_dead: continue
		var d: float = e.global_position.distance_to(global_position)
		if d < RADIUS:
			e.blind(BLIND_TIME)
			_caught[e.get_instance_id()] = true
		elif d < LOSE_RADIUS and e.in_combat:
			e.lose_track(global_position)
	if by != null and by.has_method("make_noise"): by.make_noise(6.0, 0.4)

func _physics_process(delta: float) -> void:
	age += delta
	if age > LIFE + 0.5:
		queue_free()
		return
	# walking into the cloud blinds too (once per soldier, shorter)
	if _world != null and age < LIFE - FADE and "enemies" in _world:
		for e in _world.enemies:
			if not is_instance_valid(e) or e.is_dead: continue
			var id: int = e.get_instance_id()
			if _caught.has(id): continue
			var d: float = Vector2(e.global_position.x - global_position.x, e.global_position.z - global_position.z).length()
			if d < RADIUS * 0.8:
				_caught[id] = true
				e.blind(2.5)

func _process(_delta: float) -> void:
	# thin the cloud out over the last FADE seconds
	var f := clampf((LIFE - age) / FADE, 0.0, 1.0)
	for p in _puffs:
		var m: StandardMaterial3D = (p as CPUParticles3D).material_override
		if m != null: m.albedo_color.a = 0.82 * f

static func _puff_texture() -> Texture2D:
	if _tex != null: return _tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 1601
	noise.frequency = 0.09
	for y in n:
		for x in n:
			var dx := (float(x) + 0.5) / float(n) * 2.0 - 1.0
			var dy := (float(y) + 0.5) / float(n) * 2.0 - 1.0
			var r := sqrt(dx * dx + dy * dy)
			var a := clampf(1.0 - r, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			var nz := 0.65 + 0.35 * noise.get_noise_2d(float(x), float(y))
			var shade := 0.82 + 0.18 * (1.0 - dy) * 0.5
			img.set_pixel(x, y, Color(shade, shade, shade * 0.98, clampf(a * nz, 0.0, 1.0)))
	_tex = ImageTexture.create_from_image(img)
	return _tex

func _make_emitter(amount: int, life: float, explos: float, radius: float, vel: float, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = explos
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = vel * 0.5
	p.initial_velocity_max = vel
	p.damping_min = 2.0
	p.damping_max = 3.2
	p.gravity = Vector3(0, 0.22, 0)
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -14.0
	p.angular_velocity_max = 14.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.25
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.45))
	sc.add_point(Vector2(0.35, 1.0))
	sc.add_point(Vector2(1.0, 1.35))
	p.scale_amount_curve = sc
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.12, 0.7, 1.0])
	g.colors = PackedColorArray([Color(0.86, 0.86, 0.85, 0.0), Color(0.80, 0.80, 0.79, 0.95),
		Color(0.70, 0.71, 0.72, 0.75), Color(0.66, 0.67, 0.69, 0.0)])
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _puff_texture()
	m.albedo_color = Color(1, 1, 1, 0.82)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	p.material_override = m
	p.position = Vector3(0, 0.9, 0)
	p.emitting = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

func _build_particles() -> void:
	# the pop: a dense ball that blooms out to the radius in a second
	var a := _make_emitter(34, 4.6, 0.92, 1.0, 6.5, 2.6)
	add_child(a)
	_puffs.append(a)
	# the body: slower puffs that keep the cloud standing for its life
	var b := _make_emitter(30, 3.4, 0.0, RADIUS * 0.62, 1.2, 3.0)
	b.one_shot = false
	add_child(b)
	_puffs.append(b)
	var t := get_tree().create_timer(LIFE - FADE - 0.6, false)
	t.timeout.connect(func(): if is_instance_valid(b): b.emitting = false)
