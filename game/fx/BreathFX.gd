class_name BreathFX
extends Node3D
## v0.21: breath you can see in the cold.
## On a snowy day, a clear night or a foggy dawn every nearby character
## breathes out a small cloud of vapour. The puffs are timed by the anatomy
## layer's own breathing (Anatomy.exhales counts each exhale), so a winded
## fighter puffs fast and hard and a sentry slowly. Two one-shot CPU
## emitters alternate so a quick breath never cuts off the previous cloud;
## the vapour is left behind in world space as the character moves on.
## Only characters at LOD 0-1 (about 32 m) breathe visibly; the dead do not.

## 0 = warm .. 1 = freezing; set by Weather from snow, night and fog
static var cold := 0.0

var anatomy: Anatomy
var driver: Node          ## UBCDriver for soldiers (LOD and death), null for the player
var puffs := 0
var stopped := false
var _seen := 0
var _p: Array[CPUParticles3D] = []
var _i := 0
static var _mesh: QuadMesh

const MOUTH := Vector3(0.0, 1.618, 0.104)   ## bind pose, model space (see FacialHair)

static func attach(sk: Skeleton3D, an: Anatomy, drv: Node = null) -> BreathFX:
	var hi := sk.find_bone("Head")
	if hi < 0 or an == null: return null
	var sock := BoneAttachment3D.new()
	sock.name = "Sock_Breath"
	sock.bone_name = "Head"
	sk.add_child(sock)
	var b := BreathFX.new()
	b.name = "Breath"
	b.anatomy = an
	b.driver = drv
	sock.add_child(b)
	b.transform = sk.get_bone_global_rest(hi).affine_inverse() * Transform3D(Basis(), MOUTH)
	return b

func _ready() -> void:
	# headless runs (tests) have no renderer to draw particles with: count only
	if DisplayServer.get_name() == "headless": return
	for k in 2:
		var p := CPUParticles3D.new()
		p.name = "Puff%d" % k
		p.emitting = false
		p.one_shot = true
		p.amount = 12
		p.lifetime = 1.7
		p.explosiveness = 0.7
		p.randomness = 0.3
		p.local_coords = false
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.015
		p.direction = Vector3(0, -0.25, 1)
		p.spread = 16.0
		p.initial_velocity_min = 0.22
		p.initial_velocity_max = 0.38
		p.gravity = Vector3(0, 0.07, 0)    # breath is warm: the cloud lifts as it slows
		p.damping_min = 0.35
		p.damping_max = 0.55
		p.angle_min = 0.0
		p.angle_max = 360.0
		p.scale_amount_min = 0.075
		p.scale_amount_max = 0.105
		var sc := Curve.new()
		sc.max_value = 3.0
		sc.add_point(Vector2(0.0, 0.5)); sc.add_point(Vector2(0.25, 1.0)); sc.add_point(Vector2(1.0, 2.4))
		p.scale_amount_curve = sc
		p.mesh = _quad()
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		_p.append(p)

static func _quad() -> QuadMesh:
	if _mesh != null: return _mesh
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.3, Color(1, 1, 1, 0.62)); g.add_point(0.62, Color(1, 1, 1, 0.18))
	var gt := GradientTexture2D.new()
	gt.gradient = g; gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 64; gt.height = 64
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.92, 0.95)
	m.albedo_texture = gt
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true   # without this the quads ignore the particle scale (1 m blobs)
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_mesh = QuadMesh.new()
	_mesh.material = m
	return _mesh

func stop() -> void:
	stopped = true

func _process(_dt: float) -> void:
	if anatomy == null or not is_instance_valid(anatomy): return
	var n: int = anatomy.exhales
	if n == _seen: return
	_seen = n
	if stopped or cold < 0.12: return
	if driver != null and int(driver.get("lod_level")) > 1: return
	puff()

func puff() -> void:
	puffs += 1
	if _p.is_empty(): return
	var p := _p[_i]
	_i = (_i + 1) % _p.size()
	var ex: float = anatomy.exertion if anatomy != null else 0.0
	var a := clampf(0.11 * cold * (1.0 + 0.6 * ex), 0.0, 0.19)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	ramp.add_point(0.08, Color(1, 1, 1, a))
	ramp.add_point(0.4, Color(1, 1, 1, a * 0.55))
	p.color_ramp = ramp
	p.initial_velocity_max = 0.38 + 0.3 * ex
	p.restart()
