class_name SwordTrail
extends MeshInstance3D
## Ribbon trail that follows the katana blade during attacks.

var active := false
var _points: Array = []
var _max_points := 14
var _im: ImmediateMesh
var _mat: StandardMaterial3D
var _bone := -1
var _skeleton: Skeleton3D
var _tip_local := Vector3(0, 1.05, 0)
var _base_local := Vector3(0, 0.28, 0)
var _topology_dirty := true

func _ready() -> void:
	_im = ImmediateMesh.new()
	mesh = _im
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(0.85, 0.93, 1.0, 0.55)
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.disable_receive_shadows = true
	_mat.no_depth_test = false
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false

func bind(skeleton: Skeleton3D, bone_name: String = "hand.R") -> void:
	_skeleton = skeleton
	if skeleton == null: return
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_name(i) == bone_name:
			_bone = i
			break

func _process(_delta: float) -> void:
	if not active or _skeleton == null or _bone < 0:
		if visible: visible = false
		return
	var xf := _skeleton.global_transform * _skeleton.get_bone_global_pose(_bone)
	var base_p := xf * _base_local
	var tip_p := xf * _tip_local
	_points.push_back([base_p, tip_p])
	while _points.size() > _max_points:
		_points.pop_front()
	_rebuild()

func _rebuild() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_im.clear_surfaces()
	if _points.size() < 2:
		visible = false
		return
	visible = true
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _points.size():
		var t := float(i) / float(_points.size() - 1)
		var a: float = 1.0 - t
		_im.surface_set_color(Color(0.85, 0.93, 1.0, a * 0.5))
		_im.surface_add_vertex(to_local(_points[i][0]))
		_im.surface_set_color(Color(0.95, 0.98, 1.0, a * 0.22))
		_im.surface_add_vertex(to_local(_points[i][1]))
	_im.surface_end()

func start() -> void:
	active = true
	_points.clear()

func stop() -> void:
	active = false
	_points.clear()
