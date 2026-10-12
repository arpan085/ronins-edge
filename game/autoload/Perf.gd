extends Node
## Graphics quality presets, performance sampling and the debug overlay.

signal quality_applied(level: int)

## Four tiers, not three. `scale` is the 3D render scale, `foliage` and `trees`
## are placement-density multipliers (a phone should render fewer blades and
## fewer trunks, not the same world pulled closer), `sky_oct` is the cloud
## shader octave count and `shadow_dist` is the directional shadow range.
const PRESETS := {
	0: {"name": "Low", "shadow": 1024, "shadow_soft": 0, "msaa": 0, "scale": 0.68,
		"fog": 0.55, "particles": 0.30, "lod_bias": 2.2, "lights": 3, "ssao": false,
		"glow": false, "petals": 50, "foliage": 0.30, "trees": 0.45,
		"shadow_dist": 70.0, "sky_oct": 3,
		"sun_angle": 0.0, "shadow_blur": 0.0, "ssil": false, "volfog": 0.0},
	1: {"name": "Medium", "shadow": 2048, "shadow_soft": 1, "msaa": 1, "scale": 0.85,
		"fog": 0.8, "particles": 0.65, "lod_bias": 1.2, "lights": 5, "ssao": false,
		"glow": true, "petals": 140, "foliage": 0.58, "trees": 0.72,
		"shadow_dist": 120.0, "sky_oct": 4,
		"sun_angle": 0.35, "shadow_blur": 0.8, "ssil": false, "volfog": 0.0},
	2: {"name": "High", "shadow": 4096, "shadow_soft": 2, "msaa": 2, "scale": 1.0,
		"fog": 1.0, "particles": 1.0, "lod_bias": 0.0, "lights": 8, "ssao": true,
		"glow": true, "petals": 260, "foliage": 1.0, "trees": 1.0,
		"shadow_dist": 200.0, "sky_oct": 5,
		"sun_angle": 0.55, "shadow_blur": 1.0, "ssil": false, "volfog": 0.005},
	3: {"name": "Ultra", "shadow": 8192, "shadow_soft": 3, "msaa": 2, "scale": 1.0,
		"fog": 1.0, "particles": 1.35, "lod_bias": -0.6, "lights": 12, "ssao": true,
		"glow": true, "petals": 420, "foliage": 1.45, "trees": 1.30,
		"shadow_dist": 300.0, "sky_oct": 6,
		"sun_angle": 0.60, "shadow_blur": 1.2, "ssil": true, "volfog": 0.007},
}

var level := 2
var metrics := {"fps": 0.0, "frame_ms": 0.0, "draw_calls": 0, "primitives": 0, "objects": 0, "lights": 0}
var _acc := 0.0
var _frames := 0
var _sum_ms := 0.0
var _sum_draw := 0
var _sum_prims := 0
var _worst_ms := 0.0
var _peak_draw := 0
var overlay: Label = null

func _ready() -> void:
	level = int(Game.settings.get("quality", 2))
	process_mode = Node.PROCESS_MODE_ALWAYS

func preset() -> Dictionary:
	return PRESETS.get(level, PRESETS[2])

## Pick a starting tier from what the machine reports. Nothing here is a
## benchmark; it is a first guess that adaptive quality then corrects.
func autodetect() -> int:
	var os_name := OS.get_name()
	if os_name == "Android" or os_name == "iOS":
		return 0
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	if adapter.contains("llvmpipe") or adapter.contains("swiftshader") or adapter.contains("software"):
		return 0
	if OS.get_processor_count() <= 2:
		return 0
	if adapter.contains("intel") and not adapter.contains("arc"):
		return 1
	return 2

## v0.15: the level the streaming systems were last rebuilt for. Everything
## below the "push the density multipliers" line is expensive (grass chunks,
## the whole forest, the animals), so it only runs when the tier changes.
## Before this, Game.save_settings() called apply_quality on every settings
## write -- each tick of the music or sensitivity slider, every weapon swap
## that saved the last weapon -- and each call threw away every loaded grass
## chunk and respawned the wildlife. That was the lag when touching settings,
## and the reason grass vanished and crept back in from the player outwards.
var _systems_level := -1
var _render_level := -1
var _systems_world := 0

func apply_quality(l: int, force := false) -> void:
	level = clampi(l, 0, 3)
	var p := preset()
	var render_changed := force or level != _render_level
	_render_level = level
	var vp := get_viewport()
	if vp and render_changed:
		vp.scaling_3d_scale = float(p["scale"])
		# Changing the MSAA sample count recompiles every pipeline in Godot
		# 4.3 (a multi-second hitch), so only touch it when it really changes.
		if vp.msaa_3d != int(p["msaa"]): vp.msaa_3d = int(p["msaa"])
	var sun := get_tree().get_first_node_in_group("sun")
	if sun and sun is DirectionalLight3D:
		var sl: DirectionalLight3D = sun
		sl.directional_shadow_max_distance = float(p["shadow_dist"])
		sl.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sl.light_angular_distance = float(p["sun_angle"])
		sl.shadow_blur = float(p["shadow_blur"])
		sl.directional_shadow_blend_splits = level >= 1
	var vpr := get_viewport()
	if vpr and render_changed:
		RenderingServer.directional_shadow_atlas_set_size(int(p["shadow"]), true)
	# A soft sun costs nothing without a filter quality to match it.
	var sq: int = [RenderingServer.SHADOW_QUALITY_HARD,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH][clampi(int(p["shadow_soft"]), 0, 3)]
	RenderingServer.directional_soft_shadow_filter_set_quality(sq)
	RenderingServer.positional_soft_shadow_filter_set_quality(sq)
	var env := get_tree().get_first_node_in_group("world_env")
	if env and env is WorldEnvironment and env.environment:
		var e: Environment = env.environment
		var vf: float = float(p["volfog"])
		e.volumetric_fog_enabled = vf > 0.0
		e.volumetric_fog_density = vf
		e.ssao_enabled = bool(p["ssao"])
		e.ssil_enabled = bool(p["ssil"])
		e.glow_enabled = bool(p["glow"])
	# v0.17 moving cloud shadows on the landscape: High and Ultra
	RenderingServer.global_shader_parameter_set("cloud_shadow", 1.0 if level >= 2 else 0.0)
	var wpost := get_tree().get_first_node_in_group("world")
	if wpost != null and wpost.has_method("apply_post"):
		wpost.apply_post(level)
		# Fog distance is DayNight's job now; Perf used to overwrite fog_density
		# every time quality changed, which fought the time-of-day curve.
	# push the density multipliers into the streaming systems
	var w := get_tree().get_first_node_in_group("world")
	if w != null and (force or level != _systems_level or w.get_instance_id() != _systems_world):
		_systems_level = level
		_systems_world = w.get_instance_id()
		var fol = w.get("foliage")
		if fol != null and fol.has_method("set_quality"): fol.set_quality(level)
		var ts = w.get("tree_system")
		if ts != null and ts.has_method("set_quality"): ts.set_quality(level)
		var wl = w.get("wild")
		if wl != null and wl.has_method("rebuild"): wl.rebuild()
		var hd = w.get("hitodama")
		if hd != null and hd.has_method("set_quality"): hd.set_quality(level)
		var wtr = w.get("water")
		if wtr != null and wtr.has_method("set_quality"): wtr.set_quality(level)
		var ter = w.get("terrain")
		if ter != null and ter.has_method("set_quality"): ter.set_quality(level)
		var dn = w.get("daynight")
		if dn != null:
			dn.vol_base = float(p["volfog"])
			if dn.has_method("apply"): dn.apply(true)
		if dn != null and dn.sky_mat != null:
			dn.sky_mat.set_shader_parameter("octaves", int(p["sky_oct"]))
	quality_applied.emit(level)

## Adaptive quality: shed render scale when frames run long, restore it when
## they do not. Deliberately slow to react so it never oscillates mid-fight.
var adaptive := true
var budget_ms := 18.0
var _over := 0
var _under := 0
var _scale_now := 1.0

func _adapt(ms: float) -> void:
	if not adaptive: return
	var vp := get_viewport()
	if vp == null: return
	var base: float = float(preset()["scale"])
	_scale_now = vp.scaling_3d_scale
	if ms > budget_ms:
		_over += 1; _under = 0
		if _over >= 3:
			_over = 0
			vp.scaling_3d_scale = maxf(0.62, _scale_now - 0.06)
	elif ms < budget_ms * 0.72:
		_under += 1; _over = 0
		if _under >= 6:
			_under = 0
			vp.scaling_3d_scale = minf(base, _scale_now + 0.04)
	else:
		_over = 0; _under = 0

func _process(delta: float) -> void:
	_frames += 1
	_acc += delta
	var ms := delta * 1000.0
	_sum_ms += ms
	_worst_ms = maxf(_worst_ms, ms)
	var dc := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var pr := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_sum_draw += dc; _sum_prims += pr
	_peak_draw = maxi(_peak_draw, dc)
	if _acc >= 0.5:
		metrics = {
			"fps": float(_frames) / _acc,
			"frame_ms": _sum_ms / float(_frames),
			"draw_calls": dc, "primitives": pr,
			"avg_draw_calls": _sum_draw / float(_frames),
			"avg_primitives": _sum_prims / float(_frames),
			"peak_draw_calls": _peak_draw,
			"worst_ms": _worst_ms,
			"objects": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"lights": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		}
		_adapt(float(metrics["frame_ms"]))
		_frames = 0; _acc = 0.0; _sum_ms = 0.0; _sum_draw = 0; _sum_prims = 0
		if overlay and overlay.visible:
			overlay.text = "%.0f fps  %.1f ms  draws %d  prims %d\npeak draws %d  worst %.1f ms  nodes %d  q:%s" % [
				metrics["fps"], metrics["frame_ms"], metrics["draw_calls"], metrics["primitives"],
				_peak_draw, _worst_ms, metrics["objects"], preset()["name"]]

func reset_stats() -> void:
	_worst_ms = 0.0; _peak_draw = 0
