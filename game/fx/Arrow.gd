class_name Arrow
extends Node3D
## Simple visible projectile used by the archer enemy.

var velocity := Vector3.ZERO
var damage := 12.0
var posture := 10.0
var life := 3.0
var shooter: Node3D
var target_pos := Vector3.ZERO
var _trail: MeshInstance3D
var _hit := false

func _ready() -> void:
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.02; cyl.bottom_radius = 0.02; cyl.height = 0.9
	cyl.radial_segments = 5; cyl.rings = 1
	shaft.mesh = cyl
	shaft.rotation_degrees = Vector3(90, 0, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.35, 0.25, 0.14)
	shaft.material_override = m
	add_child(shaft)
	var tip := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0; cone.bottom_radius = 0.035; cone.height = 0.16; cone.radial_segments = 5
	tip.mesh = cone
	tip.rotation_degrees = Vector3(90, 0, 0)
	tip.position = Vector3(0, 0, -0.5)
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.75, 0.76, 0.8)
	tm.metallic = 1.0
	tm.roughness = 0.25
	tip.material_override = tm
	add_child(tip)
	_trail = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.03, 0.03, 1.1)
	_trail.mesh = box
	_trail.position = Vector3(0, 0, 0.7)
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.albedo_color = Color(0.9, 0.88, 0.7, 0.35)
	tmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_trail.material_override = tmat
	add_child(_trail)

func _physics_process(delta: float) -> void:
	if _hit: return
	life -= delta
	if life <= 0.0:
		queue_free(); return
	var step := velocity * delta
	global_position += step
	look_at(global_position + velocity.normalized(), Vector3.UP)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position - step, global_position + step * 1.2)
	q.collision_mask = 1 | 4
	q.collide_with_areas = true
	var hit := space.intersect_ray(q)
	if hit.is_empty(): return
	var c = hit.get("collider")
	if c is Area3D and (c as Area3D).is_in_group("player_hurtbox"):
		var p = (c as Area3D).get_parent()
		if p != null and p.has_method("take_hit"):
			p.take_hit({"damage": damage, "posture": posture, "heavy": false, "source": shooter})
		_hit = true
		queue_free()
		return
	if c is Node3D and not (c is Area3D):
		_hit = true
		queue_free()
