class_name MatPolish
extends RefCounted
## Godot-only material features glTF cannot carry.
##
## Character materials come out of Blender as base colour, metallic, roughness
## and a normal map, because that is all glTF has. Everything that makes skin
## look like skin and lacquer look like lacquer -- subsurface scattering,
## clearcoat, rim, anisotropy -- has no glTF equivalent and was simply absent
## in game. This walks the imported rig once and puts it back, matched on the
## material names the build script assigns.

## name fragment -> what to do with it
const RULES := {
	# No transmittance. Godot estimates thickness for transmittance from the
	# shadow map, and the wig shell is tucked *inside* the skull -- so the hair
	# was casting into the shadow map and the forehead showed a stack of dark
	# chevrons in the exact shape of the hair rings hidden behind it.
	#
	# The chevrons came back after that was fixed, and this time the hair and
	# hat were innocent: hiding either left them, hiding SSS removed them.
	# Godot's screen-space blur rejects a neighbour only when its depth differs
	# by more than `subsurface_scattering_depth_scale` (default 0.01), and the
	# brows and lashes stand 4-6 mm off the skin -- inside that tolerance -- so
	# the blur dragged their black onto the shadowed forehead as evenly spaced
	# ghost copies, at 0.7 m and again at 2.9 m. No strength, kernel scale or
	# quality setting cured it; depth_scale 0.001 in project.godot does, at
	# full SSS strength.
	"skin": {"sss": 0.26, "rough": 0.62,
			 "spec": 0.34, "rim": 0.22, "rim_tint": 0.45,
			 "ntex": "leather_n.png", "uvs": 14.0, "ndepth": 0.18},
	"sclera": {"rough": 0.10, "spec": 0.85},
	"iris": {"rough": 0.06, "spec": 1.0, "clear": 0.9, "clear_rough": 0.03},
	# Was rough 0.40 / spec 0.48 / aniso 0.72: from behind, the one view a
	# third-person camera shows all game, that made the head a black bowling
	# ball with a single blue-white streak across it.
	"hair": {"rough": 0.58, "spec": 0.30, "aniso": 0.45, "rim": 0.16,
			 "rim_tint": 0.2},
	"cloth": {"rough": 0.96, "spec": 0.08, "rim": 0.16, "rim_tint": 0.7,
			  "uvs": 9.0, "ndepth": 0.85},
	"lacing": {"rough": 0.90, "spec": 0.12, "rim": 0.14, "rim_tint": 0.7,
			   "uvs": 14.0, "ndepth": 0.8},
	"leather": {"rough": 0.74, "spec": 0.26, "clear": 0.14, "clear_rough": 0.55,
				"uvs": 5.0, "ndepth": 1.0},
	"lacquer": {"rough": 0.26, "spec": 0.55, "clear": 0.42, "clear_rough": 0.14,
				"ntex": "metal_n.png", "uvs": 3.0, "ndepth": 0.35},
	"armor": {"rough": 0.70, "spec": 0.30, "clear": 0.07, "clear_rough": 0.45,
			  "uvs": 6.0, "ndepth": 0.50},
	"helmet": {"rough": 0.38, "spec": 0.62, "clear": 0.30, "clear_rough": 0.22,
			   "uvs": 4.0, "ndepth": 0.8},
	"blade": {"rough": 0.13, "spec": 1.0, "aniso": 0.55, "uvs": 2.0,
			  "ndepth": 0.35},
	"gold": {"rough": 0.32, "spec": 0.85, "ntex": "metal_n.png", "uvs": 4.0,
			 "ndepth": 0.30},
	"brass": {"rough": 0.40, "spec": 0.75, "ntex": "metal_n.png", "uvs": 4.0,
			  "ndepth": 0.30},
	"kasa": {"rough": 0.92, "spec": 0.10, "rim": 0.24, "rim_tint": 0.6,
			 "uvs": 7.0, "ndepth": 0.45},
	"jingasa": {"rough": 0.46, "spec": 0.45, "clear": 0.35, "clear_rough": 0.24},
	"wood": {"rough": 0.76, "spec": 0.22, "uvs": 6.0, "ndepth": 0.9},
}

## Two things get restored here.
##
## "ntex": Blender only exports a normal map when the build script asked for
## one, and several materials (skin, lacquer, gold) were authored flat. With
## no surface break-up at all they read as vacuum-formed plastic.
##
## "uvs": the build tiles every texture with a Mapping node, and glTF has no
## way to express one -- the exporter writes the raw UVs and silently drops
## the scale. Every character normal map was therefore stretched 4x to 10x too
## large, which is why the cloth looked like painted vinyl. The numbers here
## are the uv_scale the build script passes to make_mat.
const TEX_DIR := "res://assets/textures/"
static var _tex_cache := {}


static func apply(root: Node) -> int:
	var seen := {}
	var n := 0
	for mi in _meshes(root):
		var mesh: Mesh = mi.mesh
		if mesh == null: continue
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			if m == null or not (m is StandardMaterial3D): continue
			var sm: StandardMaterial3D = m
			# materials are shared between surfaces; only touch each once
			if seen.has(sm.get_instance_id()): continue
			seen[sm.get_instance_id()] = true
			if _tune(sm): n += 1
	return n

static func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D: out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out

static func _tune(sm: StandardMaterial3D) -> bool:
	var nm := sm.resource_name.to_lower()
	var rule: Dictionary = {}
	for key in RULES.keys():
		if nm.contains(key):
			rule = RULES[key]
			break
	if rule.is_empty(): return false
	if rule.has("rough"): sm.roughness = float(rule["rough"])
	if rule.has("spec"): sm.metallic_specular = float(rule["spec"])
	if rule.has("sss"):
		sm.subsurf_scatter_enabled = true
		sm.subsurf_scatter_strength = float(rule["sss"])
		sm.subsurf_scatter_skin_mode = true
		if rule.has("sss_col"):
			sm.subsurf_scatter_transmittance_enabled = true
			sm.subsurf_scatter_transmittance_color = rule["sss_col"]
			sm.subsurf_scatter_transmittance_depth = float(rule.get("sss_depth", 0.12))
	if rule.has("clear"):
		sm.clearcoat_enabled = true
		sm.clearcoat = float(rule["clear"])
		sm.clearcoat_roughness = float(rule.get("clear_rough", 0.1))
	if rule.has("aniso"):
		sm.anisotropy_enabled = true
		sm.anisotropy = float(rule["aniso"])
	if rule.has("rim"):
		sm.rim_enabled = true
		sm.rim = float(rule["rim"])
		sm.rim_tint = float(rule.get("rim_tint", 0.5))
	if rule.has("ntex") and sm.normal_texture == null:
		var t := _tex(str(rule["ntex"]))
		if t != null:
			sm.normal_enabled = true
			sm.normal_texture = t
	if sm.normal_texture != null and rule.has("ndepth"):
		sm.normal_enabled = true
		sm.normal_scale = float(rule["ndepth"])
	if rule.has("uvs"):
		var k := float(rule["uvs"])
		sm.uv1_scale = Vector3(k, k, 1.0)
	# The build bakes ambient occlusion and hem grime into COLOR_0. Nothing
	# reads it unless the material is told to, and Godot's glTF importer
	# leaves this off by default, so the whole bake was dead data.
	sm.vertex_color_use_as_albedo = true
	sm.vertex_color_is_srgb = false
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return true

static func _tex(name: String) -> Texture2D:
	if _tex_cache.has(name): return _tex_cache[name]
	var path := TEX_DIR + name
	var t: Texture2D = null
	if ResourceLoader.exists(path): t = load(path) as Texture2D
	_tex_cache[name] = t
	return t
