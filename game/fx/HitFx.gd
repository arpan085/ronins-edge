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
		q.material = qm
		p.draw_pass_1 = q
		add_child(p)
		_pool.append(p)

func burst(pos: Vector3, kind: String) -> void:
	var p: GPUParticles3D = _pool[_cursor]
	_cursor = (_cursor + 1) % _pool.size()
	p.global_position = pos
	var mat: ParticleProcessMaterial = p.process_material
	match kind:
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
