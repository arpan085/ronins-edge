class_name SpiritFox
extends Node3D
## v0.16 Fox Spirit (Spirit Bond path): a spectral fox that trots at Kaito's
## heel and, in a fight, every POUNCE_CD seconds leaps at the soldier about to
## strike him (EnemyBase.distract: the soldier wheels on the fox, drops his
## swing and cannot guard for DISTRACT seconds). Same fox.glb as the wildlife,
## drawn with an additive spirit shader, no collision: it is a ghost.

const POUNCE_CD := 16.0
const DISTRACT := 2.6
const FOX_SCALE := 0.085
const WALK_REF := 1.3
const RUN_REF := 7.0
const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.45, 0.85, 1.0, 1.0);
uniform float strength = 1.0;
uniform sampler2D tex : source_color, hint_default_white;
void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float lum = dot(texture(tex, UV).rgb, vec3(0.3, 0.59, 0.11));
	float flick = 0.85 + 0.15 * sin(TIME * 7.0 + VERTEX.y * 5.0);
	ALBEDO = tint.rgb * (0.10 + 0.28 * lum + 1.25 * fres) * strength * flick;
}
"""

var world: Node = null
var player: Node3D = null
var cooldown := 4.0
var state := "follow"          ## follow | leap | harry | back
var target: Node3D = null
var _t := 0.0
var _model: Node3D = null
var _ap: AnimationPlayer = null
var _clip := ""
var _mats: Array = []
var _from := Vector3.ZERO
var _fade := 0.0
var pounces := 0               ## for tests / the HUD
static var _shader: Shader = null

func setup(w: Node, p: Node3D) -> void:
	world = w
	player = p
	_build()
	global_position = _heel()
	Audio.play_sfx("fox_bark", global_position, 1.4, -6.0)

func _build() -> void:
	var ps: PackedScene = load("res://assets/animals/fox.glb")
	if ps == null: return
	_model = ps.instantiate() as Node3D
	_model.scale = Vector3.ONE * FOX_SCALE
	add_child(_model)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in m.mesh.get_surface_count():
			var sm := ShaderMaterial.new()
			sm.shader = _shader
			var src := m.mesh.surface_get_material(i)
			if src is BaseMaterial3D and (src as BaseMaterial3D).albedo_texture != null:
				sm.set_shader_parameter("tex", (src as BaseMaterial3D).albedo_texture)
			m.set_surface_override_material(i, sm)
			_mats.append(sm)
	var aps := _model.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		_ap = aps[0] as AnimationPlayer
		for an in ["idle", "walk", "run"]:
			if _ap.has_animation(an): _ap.get_animation(an).loop_mode = Animation.LOOP_LINEAR
	_play("idle")

func _play(c: String, spd := 1.0) -> void:
	if _ap == null or not _ap.has_animation(c): return
	_ap.speed_scale = spd
	if _clip == c and _ap.is_playing(): return
	_clip = c
	_ap.play(c, 0.2)

func _ground(p: Vector3) -> Vector3:
	if world != null and world.terrain != null and world.terrain.loaded:
		p.y = world.terrain.sample_height(p.x, p.z)
	return p

## Where the fox likes to be: a step behind and to the left of Kaito.
func _heel() -> Vector3:
	var b: Basis = player.global_transform.basis
	var back := -b.z
	back.y = 0.0
	back = back.normalized() if back.length() > 0.01 else Vector3.BACK
	var left := Vector3(back.z, 0.0, -back.x)
	return _ground(player.global_position + back * 1.7 + left * 1.1)

func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player): return
	_t += delta
	cooldown = maxf(0.0, cooldown - delta)
	var hidden: bool = player.has_method("is_mounted") and player.is_mounted()
	_fade = move_toward(_fade, 0.0 if hidden else 1.0, delta * 2.5)
	for m in _mats: (m as ShaderMaterial).set_shader_parameter("strength", _fade * (1.6 if state in ["leap", "harry"] else 1.0))
	visible = _fade > 0.02
	match state:
		"follow": _follow(delta)
		"leap": _leap(delta)
		"harry": _harry(delta)
		"back": _back(delta)

func _follow(delta: float) -> void:
	var goal := _heel()
	var to := goal - global_position
	to.y = 0.0
	var d := to.length()
	if d > 35.0:
		global_position = goal      # fast travel, a gallop: it simply appears
		return
	var spd := 0.0
	if d > 0.6: spd = clampf(d * 1.6, 1.0, 11.0)
	if spd > 0.0:
		var step := to.normalized() * minf(spd * delta, d)
		global_position = _ground(global_position + step)
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), clampf(delta * 8.0, 0.0, 1.0))
		if spd > 3.0: _play("run", clampf(spd / RUN_REF, 0.5, 1.8))
		else: _play("walk", clampf(spd / WALK_REF, 0.6, 2.0))
	else:
		var look: Vector3 = player.global_position - global_position
		rotation.y = lerp_angle(rotation.y, atan2(look.x, look.z), clampf(delta * 2.0, 0.0, 1.0))
		_play("idle")
	if cooldown <= 0.0 and player.has_method("is_in_combat") and player.is_in_combat():
		var e := _pick_target()
		if e != null: _pounce(e)

## The soldier winding up on Kaito, else the nearest one fighting him.
func _pick_target() -> Node3D:
	if world == null: return null
	var best: Node3D = null
	var bs := 1e9
	for e in world.enemies:
		if not is_instance_valid(e) or e.is_dead or not e.in_combat: continue
		var d: float = e.global_position.distance_to(player.global_position)
		if d > 12.0: continue
		var score := d
		if e.state == EnemyBase.S.ATTACK: score -= 20.0
		if e.is_blind(): score += 30.0
		if score < bs:
			bs = score
			best = e
	return best

func pounce_now() -> bool:
	var e := _pick_target()
	if e == null: return false
	_pounce(e)
	return true

func _pounce(e: Node3D) -> void:
	target = e
	state = "leap"
	_t = 0.0
	_from = global_position
	cooldown = POUNCE_CD
	pounces += 1
	_play("attack", 1.4)
	Audio.play_sfx("fox_bark", global_position, 1.25, 0.0)

func _leap(delta: float) -> void:
	if target == null or not is_instance_valid(target) or target.is_dead:
		state = "back"; _t = 0.0
		return
	var dur := 0.38
	var f := clampf(_t / dur, 0.0, 1.0)
	var dest: Vector3 = target.global_position + (_from - target.global_position).normalized() * 0.7
	var p := _from.lerp(dest, f)
	p = _ground(p)
	p.y += sin(f * PI) * 1.3
	global_position = p
	var to := dest - _from
	rotation.y = atan2(to.x, to.z)
	if f >= 1.0:
		target.distract(DISTRACT, self)
		if world != null and world.hitfx != null:
			world.hitfx.burst(target.global_position + Vector3(0, 1.0, 0), "deflect")
		state = "harry"
		_t = 0.0

func _harry(delta: float) -> void:
	if target == null or not is_instance_valid(target) or target.is_dead or _t > DISTRACT:
		state = "back"; _t = 0.0
		return
	# snapping round his legs
	var a := _t * 3.2
	var p: Vector3 = target.global_position + Vector3(sin(a), 0.0, cos(a)) * 0.9
	var prev := global_position
	global_position = _ground(p)
	var mv := global_position - prev
	if mv.length() > 0.001: rotation.y = atan2(mv.x, mv.z)
	_play("run", 0.9)
	if fmod(_t, 0.9) < delta: Audio.play_sfx("fox_bark", global_position, randf_range(1.2, 1.4), -4.0)

func _back(delta: float) -> void:
	var goal := _heel()
	var to := goal - global_position
	to.y = 0.0
	if to.length() < 1.0 or _t > 3.0:
		state = "follow"
		return
	global_position = _ground(global_position + to.normalized() * minf(9.0 * delta, to.length()))
	rotation.y = atan2(to.x, to.z)
	_play("run", 1.3)
