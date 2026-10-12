class_name CharWet
extends RefCounted
## v0.20: rain soaks the people as well as the ground.
## Weather.wet already darkens the terrain, grass and bark; the characters
## stayed bone dry in a storm. Every character material now registers here
## with what it is made of, and set_level() pulls each one towards its wet
## look: cloth and straw go darker (water fills the weave, so less light
## scatters back out) and a little less rough, skin and hair pick up a
## sheen, lacquer and iron get glossier. The dry values are kept, so drying
## out returns exactly to them. Weather drives the level with the same lag
## as the ground, so people soak through and dry off gradually.

## kind -> [albedo multiplier when soaked, roughness multiplier, clearcoat added]
const LOOK := {
	"cloth": [0.62, 0.78, 0.0],
	"straw": [0.70, 0.85, 0.0],
	"skin": [0.94, 0.62, 0.0],
	"hair": [0.80, 0.60, 0.0],
	"lacquer": [0.92, 0.55, 0.25],
	"metal": [0.90, 0.60, 0.0],
}
static var level := 0.0
## instance id -> [weakref(material), kind, albedo, roughness, clearcoat, clearcoat_roughness]
static var _mats := {}

static func track(m: Material, kind: String) -> void:
	if not (m is StandardMaterial3D) or not LOOK.has(kind): return
	var sm := m as StandardMaterial3D
	var id := sm.get_instance_id()
	if _mats.has(id): return
	_mats[id] = [weakref(sm), kind, sm.albedo_color, sm.roughness, sm.clearcoat, sm.clearcoat_roughness]
	if level > 0.0: _apply(sm, _mats[id])

static func tracked(m: Material) -> bool:
	return m != null and _mats.has(m.get_instance_id())

## the dry albedo of a material (what to copy when deriving a new one from it)
static func dry_albedo(m: StandardMaterial3D) -> Color:
	var id := m.get_instance_id()
	return _mats[id][2] if _mats.has(id) else m.albedo_color

static func count() -> int:
	return _mats.size()

static func set_level(w: float) -> void:
	w = clampf(w, 0.0, 1.0)
	if absf(w - level) < 0.01 and not (w == 0.0 and level != 0.0) and not (w == 1.0 and level != 1.0): return
	level = w
	for id in _mats.keys():
		var e: Array = _mats[id]
		var m = (e[0] as WeakRef).get_ref()
		if m == null:
			_mats.erase(id)
			continue
		_apply(m, e)

static func _apply(m: StandardMaterial3D, e: Array) -> void:
	var lk: Array = LOOK[e[1]]
	var a: Color = e[2]
	# pale cloth (white banners, headbands) darkens only half as much, so a
	# soaked flag still reads white instead of turning grey
	var ref := maxf(a.r, maxf(a.g, a.b)) / (2.0 if m.albedo_texture != null else 1.0)
	var k := lerpf(1.0, float(lk[0]), level * (1.0 - 0.5 * smoothstep(0.5, 0.9, ref)))
	m.albedo_color = Color(a.r * k, a.g * k, a.b * k, a.a)
	m.roughness = float(e[3]) * lerpf(1.0, float(lk[1]), level)
	if float(lk[2]) > 0.0 and m.clearcoat_enabled:
		m.clearcoat = minf(1.0, float(e[4]) + float(lk[2]) * level)
		m.clearcoat_roughness = float(e[5]) * lerpf(1.0, 0.5, level)

## duplicate a material at its dry values (a source may be soaked right now)
static func dry_copy(src: StandardMaterial3D) -> StandardMaterial3D:
	var d: StandardMaterial3D = src.duplicate()
	var id := src.get_instance_id()
	if _mats.has(id):
		var e: Array = _mats[id]
		d.albedo_color = e[2]; d.roughness = e[3]
		d.clearcoat = e[4]; d.clearcoat_roughness = e[5]
	return d
