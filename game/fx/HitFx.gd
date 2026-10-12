class_name HitFx
extends Node3D
## Pooled spark / deflect / posture-break bursts plus floating damage text.

const MAX_SPARKS := 10
var _pool: Array = []
var _cursor := 0
var _labels: Array = []

func _ready() -> void:
	for i in MAX_SPARKS:
		var p := GPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.amount = 14
		p.lifetime = 0.45
		p.explosiveness = 1.0
		p.local_coords = false
		var mat := ParticleProcessMaterial.new()
		mat.direction = Vector3(0, 1, 0)
		mat.spread = 70.0
		mat.initial_velocity_min = 3.0
		mat.initial_velocity_max = 8.0
		mat.gravity = Vector3(0, -14, 0)
		mat.scale_min = 0.25
		mat.scale_max = 0.6
		mat.color = Color(1.0, 0.86, 0.55)
		p.process_material = mat
		var q := QuadMesh.new()
		q.size = Vector2(0.12, 0.12)
		var qm := StandardMaterial3D.new()
		qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		qm.albedo_color = Color(1.0, 0.9, 0.6)
		# v0.16: soft round sparks; untextured quads froze into hard squares
		qm.albedo_texture = Ambience._mote()
		q.material = qm
		p.draw_pass_1 = q
		add_child(p)
		_pool.append(p)

func burst(pos: Vector3, kind: String) -> void:
	var p: GPUParticles3D = _pool[_cursor]
	_cursor = (_cursor + 1) % _pool.size()
	p.global_position = pos
	var mat: ParticleProcessMaterial = p.process_material
	mat.gravity = Vector3(0, -14, 0)
	mat.spread = 70.0
	mat.initial_velocity_min = 3.0
	# v0.16: surface_puff() shares this pool and used to leave its direction
	# and its scale (up to 2.1x after a hard landing) on the next burst
	mat.direction = Vector3(0, 1, 0)
	mat.scale_min = 0.25
	mat.scale_max = 0.6
	p.lifetime = 0.45
	match kind:
		"heal":
			# v0.15 gourd: soft green-gold motes drifting up round the body
			mat.color = Color(0.70, 1.0, 0.58)
			p.amount = 22
			p.lifetime = 1.1
			mat.spread = 180.0
			mat.initial_velocity_min = 0.4
			mat.initial_velocity_max = 1.4
			mat.gravity = Vector3(0, 1.6, 0)
		"deflect":
			mat.color = Color(1.0, 0.95, 0.75)
			p.amount = 24
			mat.initial_velocity_max = 11.0
		"posture":
			mat.color = Color(0.85, 0.92, 1.0)
			p.amount = 30
			mat.initial_velocity_max = 13.0
		"blood":
			mat.color = Color(0.65, 0.09, 0.08)
			p.amount = 18
			mat.initial_velocity_max = 6.0
		_:
			mat.color = Color(1.0, 0.86, 0.55)
			p.amount = 14
	p.restart()
	p.emitting = true

func heal_burst(pos: Vector3) -> void:
	burst(pos, "heal")

## Tiered impact. One call covers the whole reaction to a hit - sparks, screen
## shake, a directional camera push, a ring flash and hitstop - so light and
## heavy blows are separated by design instead of by whatever each call site
## happened to pass. Returns the hitstop duration in seconds.
##
## Tier by damage: 0 graze, 1 light, 2 solid, 3 heavy, 4 finisher.
const TIERS := [
	{"sparks": 8,  "shake": 0.05, "push": 0.10, "stop": 0.00, "ring": 0.0},
	{"sparks": 14, "shake": 0.10, "push": 0.22, "stop": 0.035, "ring": 0.5},
	{"sparks": 22, "shake": 0.18, "push": 0.42, "stop": 0.060, "ring": 0.9},
	{"sparks": 32, "shake": 0.30, "push": 0.70, "stop": 0.090, "ring": 1.3},
	{"sparks": 46, "shake": 0.46, "push": 1.05, "stop": 0.140, "ring": 1.9},
]

static func tier_for(dmg: float) -> int:
	if dmg < 6.0: return 0
	if dmg < 13.0: return 1
	if dmg < 22.0: return 2
	if dmg < 34.0: return 3
	return 4

func impact(pos: Vector3, dir: Vector3, dmg: float, kind := "spark") -> float:
	var ti := tier_for(dmg)
	var t: Dictionary = TIERS[ti]
	burst(pos, kind)
	var p: GPUParticles3D = _pool[(_cursor - 1 + _pool.size()) % _pool.size()]
	p.amount = int(t["sparks"])
	var cam = get_tree().get_first_node_in_group("player_camera")
	if cam != null:
		if cam.has_method("shake"): cam.shake(float(t["shake"]))
		if cam.has_method("impulse") and dir.length() > 0.001:
			cam.impulse(dir, float(t["push"]))
	if float(t["ring"]) > 0.0: _ring(pos, float(t["ring"]))
	return float(t["stop"])

## Expanding torus: a cheap, readable flash that scales with the hit.
func _ring(pos: Vector3, power: float) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.30
	tm.outer_radius = 0.42
	tm.rings = 10
	tm.ring_segments = 6
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.92, 0.70, clampf(0.55 * power, 0.0, 1.0))
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	add_child(mi)
	mi.global_position = pos
	mi.rotation = Vector3(randf() * 0.6 - 0.3, randf() * TAU, randf() * 0.6 - 0.3)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * (1.6 + power * 2.4), 0.22 + power * 0.06)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.24 + power * 0.06)
	tw.chain().tween_callback(mi.queue_free)

## Surface-coloured puff for footfalls, landings and weapon hits on the ground.
const SURFACE_COL := {
	"grass": Color(0.42, 0.52, 0.24), "dirt": Color(0.46, 0.38, 0.27),
	"rock": Color(0.55, 0.55, 0.56), "mud": Color(0.30, 0.24, 0.17),
	"water": Color(0.62, 0.74, 0.82),
}

func surface_puff(pos: Vector3, surface: String, power := 1.0) -> void:
	var p: GPUParticles3D = _pool[_cursor]
	_cursor = (_cursor + 1) % _pool.size()
	p.global_position = pos
	var mat: ParticleProcessMaterial = p.process_material
	mat.color = SURFACE_COL.get(surface, Color(0.5, 0.45, 0.38))
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 55.0 if surface != "water" else 30.0
	mat.initial_velocity_min = 0.6 * power
	mat.initial_velocity_max = 2.4 * power
	mat.gravity = Vector3(0, -7.0, 0)
	mat.scale_min = 0.2 * power
	mat.scale_max = 0.7 * power
	p.amount = clampi(int(5.0 * power) + 3, 3, 20)
	p.lifetime = 0.5
	p.restart()
	p.emitting = true

func label(pos: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 42
	l.modulate = color
	l.outline_size = 8
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	add_child(l)
	l.global_position = pos + Vector3(0, 1.9, 0)
	_labels.append(l)
	var tw := create_tween()
	tw.tween_property(l, "global_position", l.global_position + Vector3(0, 0.9, 0), 0.7)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(func():
		_labels.erase(l)
		l.queue_free())
