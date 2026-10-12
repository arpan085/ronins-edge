extends Node
## v0.13 river check: boots the real game, frames the main river from a few
## vantage points and, because the screenshots cannot be eyeballed here,
## measures them: every shot is rendered twice, with and without the water
## node, and the difference is the water mask (coverage, mean colour, foam
## share, an ASCII map of where it drew).

var world = null
var out_dir := "user://rivershots"
var cam: Camera3D

func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with(key + "="): return s.substr(key.length() + 1)
	return def

func _ready() -> void:
	get_viewport().get_window().size = Vector2i(int(_arg("w", "800")), int(_arg("h", "450")))
	DirAccess.make_dir_recursive_absolute(out_dir)
	await get_tree().create_timer(0.5).timeout
	var main = get_parent().get_node_or_null("Main")
	main.start_world(false)
	for i in 400:
		await get_tree().process_frame
		world = main.get("world")
		if world != null and bool(world.get("loaded")): break
	if world == null:
		print("RIVERSHOTS FAIL world"); get_tree().quit(1); return
	var pf = get_node_or_null("/root/Perf")
	if pf != null and pf.has_method("apply_quality"): pf.apply_quality(int(_arg("q", "2")))
	print("RIVERSHOTS water ", world.water.stats(), " falls at ", world.water.fall_points.size())
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 8000.0
	world.add_child(cam)
	cam.current = true
	var hud = world.get("hud")
	if hud != null and "visible" in hud: hud.set("visible", false)
	for sc in _scenarios():
		await _shot(sc)
	print("RIVERSHOTS DONE")
	get_tree().quit(0)

func _scenarios() -> Array:
	var t = world.terrain
	var rm: Dictionary = t.river_main
	var P: Array = rm.get("points", [])
	var out := []
	var pt := func(i: int) -> Vector3:
		var q: Array = P[clampi(i, 0, P.size() - 1)]
		return Vector3(float(q[0]), float(q[1]), float(q[2]))
	var only := _arg("only", "")
	# cascade below s~514: look back up at it from 24 m downstream
	var c0: Vector3 = pt.call(290)
	var c1: Vector3 = pt.call(262)
	out.append({"n": "cascade", "eye": c0 + Vector3(4, 4.5, 0), "at": c1 + Vector3(0, 1.0, 0), "tod": 10.5})
	# lake fall: from out over the lake
	var falls: Array = rm.get("falls", [])
	for f in falls:
		if bool(f.get("lake", false)):
			var lip := Vector3(float(f.x), float(f.top), float(f.z))
			var d := Vector3(float(f.dx), 0, float(f.dz)).normalized()
			var e := lip + d * 22.0 + Vector3(-d.z, 0, d.x) * 6.0
			e.y = float(t.water_level) + 3.5
			out.append({"n": "lakefall", "eye": e, "at": lip + d * 1.5 + Vector3(0, -1.2, 0), "tod": 15.0})
	# upper falls pair
	var u0: Vector3 = pt.call(145); var u1: Vector3 = pt.call(128)
	out.append({"n": "upper", "eye": u0 + Vector3(5, 3.5, 0), "at": u1, "tod": 9.0})
	# a calm reach from the bank, looking downstream
	var r0: Vector3 = pt.call(380); var r1: Vector3 = pt.call(400)
	var side := Vector3(-(r1.z - r0.z), 0, r1.x - r0.x).normalized()
	out.append({"n": "reach", "eye": r0 + side * 7.0 + Vector3(0, 2.6, 0), "at": r1, "tod": 12.0})
	# overhead: straight down on a bend (checks the ribbon edges vs the banks)
	var b0: Vector3 = pt.call(200)
	out.append({"n": "overhead", "eye": b0 + Vector3(0.1, 38.0, 0), "at": b0, "tod": 12.0})
	# the source spring
	var s0: Vector3 = pt.call(0); var s1: Vector3 = pt.call(10)
	out.append({"n": "spring", "eye": s1 + Vector3(3, 3.0, 2), "at": s0, "tod": 11.0})
	# ground shots (no water mask): the v0.13 terrain material
	var zs: Dictionary = world.data.get("zones", {})
	var zp := func(zn: String) -> Vector3:
		var q: Dictionary = zs.get(zn, {"x": 700, "z": 700})
		var x := float(q.get("x", 700)); var z := float(q.get("z", 700))
		return Vector3(x, t.sample_height(x, z), z)
	var g0: Vector3 = zp.call("grassland")
	out.append({"n": "field", "eye": g0 + Vector3(0, 2.2, 0), "at": g0 + Vector3(30, -1.5, 18), "tod": 10.0, "mask": false})
	var f0: Vector3 = zp.call("forest")
	out.append({"n": "forest", "eye": f0 + Vector3(4, 2.0, 4), "at": f0 + Vector3(24, -0.5, 14), "tod": 10.0, "mask": false})
	var s0z: Vector3 = zp.call("shrine")
	out.append({"n": "shrine", "eye": s0z + Vector3(-22, 3.5, -8), "at": s0z + Vector3(8, 0.5, 6), "tod": 10.5, "mask": false})
	var b0z: Vector3 = zp.call("bamboo")
	out.append({"n": "bamboo", "eye": b0z + Vector3(-8, 2.0, -6), "at": b0z + Vector3(14, 2.5, 10), "tod": 11.0, "mask": false})
	out.append({"n": "vista", "eye": f0 + Vector3(-95, 38, -75), "at": f0 + Vector3(10, 0.0, 10), "tod": 15.0, "mask": false})
	var v0: Vector3 = zp.call("village")
	out.append({"n": "village", "eye": v0 + Vector3(-6, 2.4, -4), "at": v0 + Vector3(14, -0.5, 10), "tod": 16.0, "mask": false})
	var m0: Vector3 = zp.call("mountain")
	out.append({"n": "mountain", "eye": m0 + Vector3(-20, 6.0, 20), "at": m0 + Vector3(10, 0.0, -10), "tod": 14.0, "mask": false})
	var k0: Vector3 = pt.call(330)
	var k1: Vector3 = pt.call(334)
	var ks := Vector3(-(k1.z - k0.z), 0, k1.x - k0.x).normalized()
	out.append({"n": "bank", "eye": k0 + ks * 6.0 + Vector3(0, 1.8, 0), "at": k0 - ks * 1.0, "tod": 11.0})
	if only != "":
		var keep := []
		for o in out:
			if (only.split(",") as Array).has(str(o.n)): keep.append(o)
		out = keep
	return out

func _mats() -> Array:
	var w = world.water
	return [w.get("_river_mat"), w.get("_mat"), w.get("_sheet_mat"), w.get("_pool_mat")]

var _env_saved := []

## The mask pass has to survive the grade: ACES turns a bright saturated
## emissive into white and glow bleeds it across the frame, so the tone
## mapper, glow and auto exposure are neutralised while it renders.
func _neutral_grade(on: bool) -> void:
	var we := get_tree().root.find_children("*", "WorldEnvironment", true, false)
	if we.is_empty(): return
	var e: Environment = (we[0] as WorldEnvironment).environment
	var ca = (we[0] as WorldEnvironment).camera_attributes
	if on:
		_env_saved = [e.tonemap_mode, e.glow_enabled, e.tonemap_exposure, ca.auto_exposure_enabled if ca != null else false,
			e.adjustment_enabled]
		e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		e.glow_enabled = false
		e.tonemap_exposure = 1.0
		e.adjustment_enabled = false
		if ca != null: ca.auto_exposure_enabled = false
	elif _env_saved.size() == 5:
		e.tonemap_mode = _env_saved[0]
		e.glow_enabled = _env_saved[1]
		e.tonemap_exposure = _env_saved[2]
		if ca != null: ca.auto_exposure_enabled = _env_saved[3]
		e.adjustment_enabled = _env_saved[4]

func _debug(on: bool) -> void:
	_neutral_grade(on)
	if cam.attributes != null: pass
	var m := _mats()
	var tints := [Color(1, 0, 1), Color(1, 1, 0)]
	for i in 2:
		if m[i] == null: continue
		(m[i] as ShaderMaterial).set_shader_parameter("debug_mode", 10 if on else 0)
		(m[i] as ShaderMaterial).set_shader_parameter("debug_tint", tints[i])
	for i in [2, 3]:
		if m[i] != null: (m[i] as ShaderMaterial).set_shader_parameter("debug_solid", on)

func _shot(sc: Dictionary) -> void:
	world.set_time_of_day(float(sc.get("tod", 12.0)))
	world.set_weather("clear", true)
	var eye: Vector3 = sc.eye
	var at: Vector3 = sc.at
	# never inside a bank: at least 1.6 m over the ground under the eye
	eye.y = maxf(eye.y, world.terrain.sample_height(eye.x, eye.z) + 1.6)
	if world.has_method("warp_to"): world.warp_to(Vector3(eye.x, world.terrain.sample_height(eye.x, eye.z) + 0.2, eye.z))
	for i in int(_arg("settle", "40")): await get_tree().process_frame
	cam.global_position = eye
	cam.look_at(at, Vector3.UP)
	cam.current = true
	for i in 6: await get_tree().process_frame
	var a := get_viewport().get_texture().get_image()
	a.save_png("%s/%s.png" % [out_dir, str(sc.n)])
	if not bool(sc.get("mask", true)):
		_ground_stats(str(sc.n), a, eye, at)
		# the same frame without grass blades / bushes: terrain material only
		var fol: Array = get_tree().root.find_children("Foliage*", "", true, false)
		for f in fol: f.set("visible", false)
		for i in 3: await get_tree().process_frame
		var c := get_viewport().get_texture().get_image()
		c.save_png("%s/%s_bare.png" % [out_dir, str(sc.n)])
		_ground_stats(str(sc.n) + "_bare", c, eye, at)
		# layer weights (terrain debug_view 1), neutral grade
		var tm = world.terrain.get("_mat")
		if tm != null:
			_neutral_grade(true)
			(tm as ShaderMaterial).set_shader_parameter("debug_view", 1)
			for i in 3: await get_tree().process_frame
			var d := get_viewport().get_texture().get_image()
			(tm as ShaderMaterial).set_shader_parameter("debug_view", 0)
			_neutral_grade(false)
			_layer_stats(str(sc.n), d, c)
		for f in fol: f.set("visible", true)
		return
	_debug(true)
	for i in 3: await get_tree().process_frame
	var b := get_viewport().get_texture().get_image()
	_debug(false)
	b.save_png("%s/%s_mask.png" % [out_dir, str(sc.n)])
	_measure(str(sc.n), a, b, eye, at)

func _cls(c: Color) -> int:
	if c.r > c.g + 0.25 and c.b > c.g + 0.25: return 1       # main river
	if c.r > c.b + 0.25 and c.g > c.b + 0.25: return 2       # lake / streams
	if c.g > c.r + 0.25 and c.b > c.r + 0.25: return 3       # falls / pools
	return 0

func _measure(nm: String, a: Image, b: Image, eye: Vector3, at: Vector3) -> void:
	var w := a.get_width(); var h := a.get_height()
	var gw := 50; var gh := 18
	var cnt := []; var fo := []; var sums := []; var whites := []; var ns := []
	for k in 4:
		ns.append(0); whites.append(0); sums.append(Vector3.ZERO)
	var cell_cls := PackedInt32Array(); cell_cls.resize(gw * gh * 4)
	var cell_w := PackedInt32Array(); cell_w.resize(gw * gh)
	var y := 0
	while y < h:
		var x := 0
		while x < w:
			var k := _cls(b.get_pixel(x, y))
			var ca := a.get_pixel(x, y)
			var gi := (y * gh / h) * gw + (x * gw / w)
			cell_cls[gi * 4 + k] += 1
			if k > 0:
				ns[k] += 1
				sums[k] += Vector3(ca.r, ca.g, ca.b)
				if ca.r > 0.70 and ca.g > 0.70 and ca.b > 0.70:
					whites[k] += 1
					cell_w[gi] += 1
			x += 2
		y += 2
	var tot := float((w / 2) * (h / 2))
	var line0 := "RIVERSHOT %s eye=(%.0f,%.1f,%.0f) at=(%.0f,%.1f,%.0f)" % [nm, eye.x, eye.y, eye.z, at.x, at.y, at.z]
	var names := ["", "river", "lake/streams", "falls"]
	for k in [1, 2, 3]:
		var m: Vector3 = sums[k] / maxf(1.0, float(ns[k]))
		line0 += "  %s=%.1f%% rgb(%.2f,%.2f,%.2f) white=%.0f%%" % [names[k], 100.0 * ns[k] / tot, m.x, m.y, m.z, 100.0 * whites[k] / maxf(1.0, float(ns[k]))]
	print(line0)
	var per := tot / float(gw * gh)
	for gy in gh:
		var line := ""
		for gx in gw:
			var gi := gy * gw + gx
			var best := 0; var bv := 0
			for k in [1, 2, 3]:
				if cell_cls[gi * 4 + k] > bv: bv = cell_cls[gi * 4 + k]; best = k
			if float(bv) < per * 0.15: line += "."
			else:
				var ch: String = ["", "r", "l", "f"][best]
				var water := 0
				for k in [1, 2, 3]: water += cell_cls[gi * 4 + k]
				if float(cell_w[gi]) > float(water) * 0.5: ch = ch.to_upper()
				line += ch
		print("  |", line, "|")

## debug_view 1 paints grass green, forest floor cyan, trail red, rock grey,
## mud magenta, river bed blue (emissive, neutral grade); each class also
## reports the mean colour of the bare (no foliage) frame under it.
func _layer_stats(nm: String, d: Image, bare: Image) -> void:
	var names := ["grass", "forest", "trail", "rock", "mud", "bed", "mixed"]
	var cnt := [0, 0, 0, 0, 0, 0, 0]
	var col := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var n := 0
	var h := d.get_height(); var w := d.get_width()
	var y := int(h * 0.45)
	while y < h:
		var x := 0
		while x < w:
			var c := d.get_pixel(x, y)
			var r := c.r > 0.6; var g := c.g > 0.6; var b := c.b > 0.6
			var k := 6
			if absf(c.r - c.g) < 0.12 and absf(c.g - c.b) < 0.12 and c.r > 0.3: k = 3
			elif g and not r and not b: k = 0
			elif g and b and not r: k = 1
			elif r and not g and not b: k = 2
			elif r and b and not g: k = 4
			elif b and not r and not g: k = 5
			cnt[k] += 1
			var bc := bare.get_pixel(x, y)
			col[k] += Vector3(bc.r, bc.g, bc.b)
			n += 1
			x += 3
		y += 3
	var line := "LAYERS %s" % nm
	for k in 7:
		if cnt[k] == 0: continue
		var m: Vector3 = col[k] / float(cnt[k])
		line += " | %s %.0f%% (%.2f,%.2f,%.2f)" % [names[k], 100.0 * cnt[k] / maxf(1.0, float(n)), m.x, m.y, m.z]
	print(line)

## Ground frames: mean colour / contrast of the lower part of the frame and a
## coarse luminance map, enough to catch a black, white or magenta ground.
func _ground_stats(nm: String, a: Image, eye: Vector3, at: Vector3) -> void:
	var w := a.get_width(); var h := a.get_height()
	var sum := Vector3.ZERO; var sq := 0.0; var n := 0; var dark := 0
	var y := int(h * 0.45)
	while y < h:
		var x := 0
		while x < w:
			var c := a.get_pixel(x, y)
			sum += Vector3(c.r, c.g, c.b)
			var l := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			sq += l * l
			if l < 0.03: dark += 1
			n += 1
			x += 3
		y += 3
	var m := sum / float(n)
	var ml := m.x * 0.2126 + m.y * 0.7152 + m.z * 0.0722
	print("GROUNDSHOT %s eye=(%.0f,%.1f,%.0f) lower-frame rgb(%.3f,%.3f,%.3f) lum %.3f sd %.3f dark %.1f%%"
		% [nm, eye.x, eye.y, eye.z, m.x, m.y, m.z, ml, sqrt(maxf(0.0, sq / float(n) - ml * ml)), 100.0 * dark / float(n)])
	var ramp := " .:-=+*#%@"
	for gy in 9:
		var line := ""
		for gx in 40:
			var c := a.get_pixel(int((float(gx) + 0.5) / 40.0 * w), int((float(gy) + 0.5) / 9.0 * h))
			var l := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			line += ramp[clampi(int(l * 10.0), 0, 9)]
		print("  |", line, "|")
