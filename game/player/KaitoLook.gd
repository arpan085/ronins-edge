class_name KaitoLook
extends RefCounted
## v0.23 Kaito's own look, on top of CharDress: loose, wavy hair to the jaw and
## the nape instead of the topknot and headband (hair cards and the face sculpt
## come from tools/kaito_head_v23.py, baked into assets/char/Kaito.glb), and
## stubble grown out of the face by FacialHair.

## the 3D brow shell gives way to brows painted into the skin (thick, low, nearly straight)
const HIDE := ["Ponytail", "Hachimaki", "Eyebrows"]
const STUBBLE := Color(0.075, 0.055, 0.045)

static func apply(model: Node) -> void:
	for mi in _meshes(model, []):
		var n := String(mi.name)
		if HIDE.has(n): mi.visible = false
		elif n == "KaitoHair": _hair(mi)
		elif n == "Hair": _cap(mi)
	FacialHair.grow(model, "stubble", STUBBLE)

static func _hair(mi: MeshInstance3D) -> void:
	if mi.mesh == null: return
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s)
		if not (m is StandardMaterial3D): continue
		var h := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
		h.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		h.alpha_scissor_threshold = 0.38
		h.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		h.cull_mode = BaseMaterial3D.CULL_DISABLED
		# hair cards stand at grazing angles to both the light and the eye, where the
		# default Fresnel turns them into tan mirrors: low specular caps the sheen
		h.roughness = 0.68
		h.metallic_specular = 0.2
		h.rim_enabled = false
		mi.set_surface_override_material(s, h)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

## the old slicked cap, smoothed onto the scalp, is only the dark base under the cards
static func _cap(mi: MeshInstance3D) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.040, 0.028, 0.020)
	m.roughness = 0.8
	for s in (mi.mesh.get_surface_count() if mi.mesh != null else 0):
		mi.set_surface_override_material(s, m)

static func _meshes(n: Node, acc: Array) -> Array:
	if n is MeshInstance3D: acc.append(n)
	for c in n.get_children(): _meshes(c, acc)
	return acc
