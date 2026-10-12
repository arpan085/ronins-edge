class_name FacialHair
extends RefCounted
## v0.19: facial hair grown out of the face itself.
## Every soldier shares one head, so a moustache or a beard is the cheapest
## way to tell them apart up close. A style is a soft mask over the face
## skin (bind-pose model space: +Z is the front of the face). The triangles
## under it are copied together with their own bone weights, pushed out
## along the skin normal by a few millimetres (thicker where the mask is
## strong, and lofted under the chin) and cut by a streaky alpha noise, so
## the edge breaks up into strands instead of ending on a painted line. The
## shell shares the head's skin, so it deforms exactly like the face under it.

const HEAD_MESH := "SuperHero_Male"
const STYLES := ["none", "stubble", "moustache", "droop", "goatee", "beard"]
## style -> [thickness m, alpha scissor]
const SHAPE := {
	"stubble": [0.0006, 0.92],      # [thickness, opacity] - blended, not cut
	"moustache": [0.0042, 0.38],
	"droop": [0.0042, 0.38],
	"goatee": [0.0045, 0.40],
	"beard": [0.0050, 0.42],
}

static var _mesh_cache := {}
static var _mat_cache := {}
static var _tex: ImageTexture
static var _tex_soft: ImageTexture

static func grow(body: Node, style: String, col: Color) -> MeshInstance3D:
	if not SHAPE.has(style): return null
	var head := _find_mesh(body, HEAD_MESH)
	if head == null or head.mesh == null: return null
	var mesh := _mesh_for(head.mesh, style)
	if mesh == null: return null
	var mi := MeshInstance3D.new()
	mi.name = "FacialHair"
	mi.mesh = mesh
	mi.skin = head.skin
	head.get_parent().add_child(mi)
	mi.transform = head.transform
	mi.skeleton = head.skeleton
	mi.material_override = _material(style, col)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func _find_mesh(n: Node, nm: String) -> MeshInstance3D:
	if n is MeshInstance3D and String(n.name) == nm: return n
	for c in n.get_children():
		var r := _find_mesh(c, nm)
		if r != null: return r
	return null

static func _ss(a: float, b: float, v: float) -> float:
	return smoothstep(a, b, v)

## 0..1 coverage of one style at a bind-pose point
static func mask(style: String, p: Vector3) -> float:
	var ax := absf(p.x)
	var th := absf(atan2(p.x, p.z + 0.01))     # 0 = front of the face, PI/2 = beside the ear
	# the lips stay bare in every style
	var lips := _ss(0.030, 0.024, ax) * _ss(1.6045, 1.6075, p.y) * _ss(1.6335, 1.6305, p.y)
	# upper lip skin, from the lip line up to the nose, a little wider at the bottom
	var half := 0.023 + (1.645 - p.y) * 0.75
	var mous := _ss(half + 0.004, half - 0.002, ax) * _ss(1.6285, 1.6315, p.y) * _ss(1.6465, 1.6425, p.y) * _ss(0.055, 0.07, p.z)
	match style:
		"moustache":
			return clampf(mous - lips * 0.6, 0.0, 1.0)
		"droop":
			# ends that run down past the corners of the mouth to the jaw
			var droop := _ss(0.018, 0.024, ax) * _ss(0.040, 0.034, ax) * _ss(1.592, 1.598, p.y) * _ss(1.640, 1.632, p.y) * _ss(0.05, 0.065, p.z)
			return clampf(maxf(mous, droop) - lips, 0.0, 1.0)
		"goatee":
			var chin := _ss(0.030, 0.022, ax) * _ss(1.568, 1.578, p.y) * _ss(1.609, 1.604, p.y) * _ss(0.035, 0.055, p.z)
			return clampf(maxf(mous, chin) - lips, 0.0, 1.0)
		"beard", "stubble":
			# from under the chin up the jaw to the sideburns, cheeks left clear
			var up := lerpf(1.625, 1.685, _ss(0.35, 1.45, th))
			var lo := lerpf(1.553, 1.618, _ss(0.25, 1.30, th))
			var band := _ss(lo - 0.004, lo + 0.006, p.y) * _ss(up + 0.004, up - 0.006, p.y) * _ss(1.75, 1.45, th)
			return clampf(maxf(band, mous) - lips, 0.0, 1.0)
	return 0.0

## extra loft under the chin, where a real beard hangs instead of lying flat
static func _volume(style: String, p: Vector3) -> float:
	if style != "beard" and style != "goatee": return 0.0
	return 0.006 * _ss(0.045, 0.0, absf(p.x)) * _ss(1.606, 1.574, p.y)

static func _mesh_for(src: Mesh, style: String) -> ArrayMesh:
	var key := "%d:%s" % [src.get_instance_id(), style]
	if _mesh_cache.has(key): return _mesh_cache[key]
	var arr := src.surface_get_arrays(0)
	var vt: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		for i in vt.size(): idx.append(i)
	var bones = arr[Mesh.ARRAY_BONES]
	var wts = arr[Mesh.ARRAY_WEIGHTS]
	var nb := 0
	if bones != null and (bones as PackedInt32Array).size() > 0: nb = (bones as PackedInt32Array).size() / vt.size()
	var w := PackedFloat32Array(); w.resize(vt.size())
	for i in vt.size(): w[i] = mask(style, vt[i])
	var thick: float = SHAPE[style][0]
	var st := SurfaceTool.new()
	# must precede begin(): SurfaceTool ignores it once begun
	if nb > 0: st.set_skin_weight_count(SurfaceTool.SKIN_8_WEIGHTS if nb == 8 else SurfaceTool.SKIN_4_WEIGHTS)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := 0
	for t in range(0, idx.size(), 3):
		if w[idx[t]] <= 0.01 and w[idx[t + 1]] <= 0.01 and w[idx[t + 2]] <= 0.01: continue
		tris += 1
		for k in 3:
			var i := idx[t + k]
			var p := vt[i]
			st.set_color(Color(1, 1, 1, w[i]))
			# arc length around the head and height, so strands run downwards
			st.set_uv(Vector2(atan2(p.x, p.z + 0.01) * 0.09, -p.y))
			st.set_normal(nrm[i])
			if nb > 0:
				var bi := PackedInt32Array(); var bw := PackedFloat32Array()
				for j in nb:
					bi.append((bones as PackedInt32Array)[i * nb + j]); bw.append((wts as PackedFloat32Array)[i * nb + j])
				st.set_bones(bi); st.set_weights(bw)
			st.add_vertex(p + nrm[i] * (thick * (0.3 + 0.7 * w[i]) + _volume(style, p) * w[i]))
	if tris == 0: return null
	st.index()
	var out := ArrayMesh.new()
	var fl: int = src.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, fl)
	_mesh_cache[key] = out
	return out

## grey strand clumps ~1 mm wide and ~4 mm long, alpha cut by the same noise
## (soft: the stubble version, a mottled opacity instead of a cut)
static func _strands(soft := false) -> ImageTexture:
	if soft and _tex_soft != null: return _tex_soft
	if not soft and _tex != null: return _tex
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.16
	fn.fractal_octaves = 2
	fn.seed = 1907
	var src := fn.get_seamless_image(64, 64)
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var n := src.get_pixel(x, y).r
			var a := clampf(0.35 + 0.65 * n, 0.0, 1.0) if soft else clampf((n - 0.12) * 1.7, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.72 + 0.28 * n, 0.72 + 0.28 * n, 0.72 + 0.28 * n, a))
	img.generate_mipmaps()
	if soft:
		_tex_soft = ImageTexture.create_from_image(img)
		return _tex_soft
	_tex = ImageTexture.create_from_image(img)
	return _tex

static func _material(style: String, col: Color) -> StandardMaterial3D:
	var key := "%s:%s" % [style, col.to_html()]
	if _mat_cache.has(key): return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.resource_name = "FacialHair"
	m.albedo_color = col
	m.albedo_texture = _strands()
	m.vertex_color_use_as_albedo = true
	m.uv1_scale = Vector3(1.0 / 0.012, 1.0 / 0.040, 1.0)
	if style == "stubble":
		# a few days' growth reads as a shadow over the jaw, not as hairs
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var sc := col.lerp(Color(0.12, 0.13, 0.16), 0.5)
		m.albedo_color = Color(sc.r, sc.g, sc.b, float(SHAPE[style][1]))
		m.albedo_texture = _strands(true)
		m.uv1_scale = Vector3(1.0 / 0.006, 1.0 / 0.010, 1.0)
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	else:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = float(SHAPE[style][1])
	m.roughness = 0.82
	m.metallic_specular = 0.3
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mat_cache[key] = m
	CharWet.track(m, "hair")
	return m
