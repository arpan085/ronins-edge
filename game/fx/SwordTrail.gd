class_name SwordTrail
extends MeshInstance3D
## Ribbon trail that follows the blade during attacks.
##
## Samples are time-stamped: the ribbon keeps the last `life` seconds of the
## blade's path, fades by age (newest part bright, oldest gone), is smoothed
## with a Catmull-Rom spline so a low frame rate still draws an arc instead of
## a jagged fan, and fades out after stop() instead of vanishing.

var active := false
var life := 0.15                    ## seconds of blade path the ribbon keeps
var _points: Array = []             ## [base: Vector3, tip: Vector3, time: float]
var _clock := 0.0
var _im: ImmediateMesh
var _mat: StandardMaterial3D
var _bone := -1
var _skeleton: Skeleton3D
var _tip_local := Vector3(0, 1.05, 0)
var _base_local := Vector3(0, 0.28, 0)
var _node: Node3D = null            ## when set, the ribbon follows this weapon node's +Y axis
## Store the ribbon in the parent's frame instead of the world, so a cut made
## from a galloping horse draws an arc round the rider rather than a streak.
var local_space := false:
	set(v):
		if v != local_space: _points.clear()
		local_space = v

const MIN_STEP := 1.0 / 90.0        ## seconds between stored samples
const MAX_SAMPLES := 40
const SUBDIV_LEN := 0.07            ## metres of tip travel per spline sub-step

func _ready() -> void:
	_im = ImmediateMesh.new()
	mesh = _im
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# per-vertex colour carries the fade
	_mat.vertex_color_use_as_albedo = true
	_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.disable_receive_shadows = true
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

## Follow a weapon mesh instead of a bone: base/tip are distances along its +Y.
func bind_node(n: Node3D, base_y: float, tip_y: float) -> void:
	_node = n
	_base_local = Vector3(0, base_y, 0)
	_tip_local = Vector3(0, tip_y, 0)

func _process(delta: float) -> void:
	_clock += delta
	var have_node := _node != null and is_instance_valid(_node)
	if active and (have_node or (_skeleton != null and _bone >= 0)):
		var xf: Transform3D = _node.global_transform if have_node else _skeleton.global_transform * _skeleton.get_bone_global_pose(_bone)
		var base_p := xf * _base_local
		var tip_p := xf * _tip_local
		if local_space and get_parent() is Node3D:
			var inv := (get_parent() as Node3D).global_transform.affine_inverse()
			base_p = inv * base_p
			tip_p = inv * tip_p
		var n := _points.size()
		if n >= 2 and _clock - float(_points[n - 2][2]) < MIN_STEP:
			_points[n - 1] = [base_p, tip_p, _clock]     # keep the head on the blade
		else:
			_points.push_back([base_p, tip_p, _clock])
	# forget samples that have fully faded (keep one past the limit so the tail
	# end fades to nothing rather than being cut)
	while _points.size() > 2 and _clock - float(_points[1][2]) > life:
		_points.pop_front()
	while _points.size() > MAX_SAMPLES:
		_points.pop_front()
	if not active and (_points.is_empty() or _clock - float(_points[-1][2]) > life):
		_points.clear()
	_rebuild()

static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * p1) + (p2 - p0) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * u3)

func _rebuild() -> void:
	var n := _points.size()
	if n < 2:
		if visible:
			visible = false
			if _im != null: _im.clear_surfaces()
		return
	if DisplayServer.get_name() == "headless":
		return
	_im.clear_surfaces()
	visible = true
	var par := Transform3D()
	if local_space and get_parent() is Node3D: par = (get_parent() as Node3D).global_transform
	var inv := global_transform.affine_inverse() * par
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n - 1:
		var a0: Array = _points[maxi(i - 1, 0)]
		var a1: Array = _points[i]
		var a2: Array = _points[i + 1]
		var a3: Array = _points[mini(i + 2, n - 1)]
		var travel := ((a2[1] as Vector3) - (a1[1] as Vector3)).length()
		var steps := clampi(int(ceil(travel / SUBDIV_LEN)), 1, 8)
		var last := steps if i == n - 2 else steps - 1
		for s in range(0, last + 1):
			var u := float(s) / float(steps)
			var b := _cr(a0[0], a1[0], a2[0], a3[0], u)
			var t := _cr(a0[1], a1[1], a2[1], a3[1], u)
			var tm := lerpf(float(a1[2]), float(a2[2]), u)
			var a := clampf(1.0 - (_clock - tm) / life, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			_im.surface_set_color(Color(0.80, 0.90, 1.0, a * a * 0.14))
			_im.surface_add_vertex(inv * b)
			_im.surface_set_color(Color(0.95, 0.98, 1.0, a * 0.5))
			_im.surface_add_vertex(inv * t)
	_im.surface_end()

## Begin (or continue) recording. A trail still fading from the previous cut is
## kept only if it ended a moment ago, so chained cuts read as one sweep.
func start() -> void:
	if not active and not _points.is_empty() and _clock - float(_points[-1][2]) > 0.05:
		_points.clear()
	active = true

## Stop recording; what is drawn fades out over `life` seconds.
func stop() -> void:
	active = false

## Stop and remove the ribbon at once (teleports, death, weapon swaps).
func clear() -> void:
	active = false
	_points.clear()
	_rebuild()
