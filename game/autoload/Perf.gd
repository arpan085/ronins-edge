extends Node
## Graphics quality presets, performance sampling and the debug overlay.

signal quality_applied(level: int)

const PRESETS := {
	0: {"name": "Low", "shadow": 1024, "shadow_soft": 0, "msaa": 0, "scale": 0.7,
		"fog": 0.55, "particles": 0.35, "lod_bias": 2.0, "lights": 3, "ssao": false, "glow": false, "petals": 60},
	1: {"name": "Medium", "shadow": 2048, "shadow_soft": 1, "msaa": 1, "scale": 0.85,
		"fog": 0.8, "particles": 0.7, "lod_bias": 1.0, "lights": 5, "ssao": false, "glow": true, "petals": 140},
	2: {"name": "High", "shadow": 4096, "shadow_soft": 2, "msaa": 2, "scale": 1.0,
		"fog": 1.0, "particles": 1.0, "lod_bias": 0.0, "lights": 8, "ssao": true, "glow": true, "petals": 260},
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

func apply_quality(l: int) -> void:
	level = clampi(l, 0, 2)
	var p := preset()
	# render scale + msaa on the active viewport
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = float(p["scale"])
		vp.msaa_3d = int(p["msaa"])
	var sun := get_tree().get_first_node_in_group("sun")
	if sun and sun is DirectionalLight3D:
		sun.directional_shadow_max_distance = 60.0 + 40.0 * float(level)
		sun.shadow_bias = 0.06
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	var env := get_tree().get_first_node_in_group("world_env")
	if env and env is WorldEnvironment and env.environment:
		var e: Environment = env.environment
		e.volumetric_fog_enabled = false
		e.ssao_enabled = bool(p["ssao"]) and level >= 2
		e.glow_enabled = bool(p["glow"])
		e.fog_density = 0.0016 * float(p["fog"])
	quality_applied.emit(level)

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
		_frames = 0; _acc = 0.0; _sum_ms = 0.0; _sum_draw = 0; _sum_prims = 0
		if overlay and overlay.visible:
			overlay.text = "%.0f fps  %.1f ms  draws %d  prims %d\npeak draws %d  worst %.1f ms  nodes %d  q:%s" % [
				metrics["fps"], metrics["frame_ms"], metrics["draw_calls"], metrics["primitives"],
				_peak_draw, _worst_ms, metrics["objects"], preset()["name"]]

func reset_stats() -> void:
	_worst_ms = 0.0; _peak_draw = 0
