extends Node
## Environment verification harness.
## Boots the REAL game (Main.tscn), then walks a list of scenarios: teleports the
## player to a vantage point, sets time-of-day + weather, lets the world settle,
## screenshots, and records renderer metrics. Everything printed here is measured.

var world = null
var player = null
var cam_rig = null
var rows := []
var tag := "base"
var probes: Array[String] = []
var out_dir := "user://shots"

func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with(key + "="):
			return s.substr(key.length() + 1)
	return def

func _ready() -> void:
	process_priority = 900
	var q := int(_arg("q", "1"))
	var w := int(_arg("w", "960"))
	var h := int(_arg("h", "540"))
	var settle := int(_arg("settle", "12"))
	tag = _arg("tag", "base")
	get_viewport().get_window().size = Vector2i(w, h)
	DirAccess.make_dir_recursive_absolute(out_dir)

	await get_tree().create_timer(0.5).timeout
	var main = get_parent().get_node_or_null("Main")
	if main == null or not main.has_method("start_world"):
		print("ENVSHOTS FAIL: no Main"); _finish(tag); return
	main.start_world(false)
	# world build is async (awaits frames inside start_world)
	for i in 240:
		await get_tree().process_frame
		world = main.get("world")
		if world != null and bool(world.get("loaded")): break
	if world == null:
		print("ENVSHOTS FAIL: world null"); _finish(tag); return
	var pf = get_node_or_null("/root/Perf")
	if pf != null and pf.has_method("apply_quality"): pf.apply_quality(q)
	player = world.get("player")
	cam_rig = world.get("camera")
	print("ENVSHOTS world loaded player=", player != null, " cam=", cam_rig != null,
		" terrain=", world.get("terrain") != null)

	for sc in _scenarios():
		await _run_scenario(sc, settle)
	_finish(tag)

## Vantage points are resolved from world.json zones so they stay valid when the
## world is regenerated at a different scale.
func _scenarios() -> Array:
	var z: Dictionary = {}
	if world != null and typeof(world.get("data")) == TYPE_DICTIONARY:
		z = (world.get("data") as Dictionary).get("zones", {})
	var out := []
	var want := [
		{"n": "openfield", "zone": "grassland", "tod": 12.0, "wx": "clear", "yaw": 0.5},
		{"n": "forest",    "zone": "forest",  "tod": 10.0, "wx": "clear", "yaw": 1.9},
		{"n": "village",   "zone": "village", "tod": 17.4, "wx": "clear", "yaw": 2.6},
		{"n": "shrine",    "zone": "shrine",  "tod": 6.4,  "wx": "mist",  "yaw": 0.0},
		{"n": "castle",    "zone": "castle",  "tod": 13.0, "wx": "cloudy","yaw": 3.1},
		{"n": "mountain",  "zone": "mountain","tod": 15.0, "wx": "clear", "yaw": 2.2},
		{"n": "rain",      "zone": "forest",  "tod": 14.0, "wx": "rain",  "yaw": 1.2},
		{"n": "storm",     "zone": "grassland","tod": 16.0, "wx": "storm", "yaw": 0.8},
		{"n": "night",     "zone": "lake",    "tod": 23.0, "wx": "clear", "yaw": 0.4},
		{"n": "golden",    "zone": "shrine",  "tod": 18.3, "wx": "clear", "yaw": 1.4},
		# Reference framing: low sun dead ahead, camera behind the ronin, deep
		# grass. This is the shot the art direction is judged against.
		# tod 17.35 puts the sun at about 6 degrees of elevation and 107 of
		# azimuth; camera forward is (-sin yaw, 0, -cos yaw), so yaw -1.27
		# looks straight into it.
		{"n": "windfield", "zone": "grassland", "tod": 17.35, "wx": "clear",
		 "yaw": -1.27, "pitch": -0.04},
		# v0.15 night in the woods (hitodama country); only when asked for by name
		{"n": "nightwood", "zone": "forest", "tod": 23.5, "wx": "clear", "yaw": 1.9, "opt": true},
	]
	var only := _arg("only", "")
	for wv in want:
		if only != "" and not (only.split(",") as Array).has(str(wv["n"])): continue
		if only == "" and bool(wv.get("opt", false)): continue
		var zn: String = wv["zone"]
		if z.has(zn):
			var p: Dictionary = z[zn]
			wv["pos"] = Vector3(float(p.get("x", 0)), float(p.get("y", 10)), float(p.get("z", 0)))
			out.append(wv)
	return out

## Layer isolation. When a screenshot shows a surface nobody can identify,
## hiding one system at a time says which one drew it. Three extra frames,
## against three to five minutes for another whole run.
func _isolate(base_name: String) -> void:
	for nm in ["water", "foliage", "tree_system", "solids"]:
		var node = world.get(nm)
		if node == null or not (node is Node3D): continue
		var n3: Node3D = node
		var was := n3.visible
		n3.visible = false
		for _f in 3:
			await get_tree().process_frame
		var im := get_viewport().get_texture().get_image()
		im.save_png("%s/%s_no_%s.png" % [out_dir, base_name, nm])
		n3.visible = was
		print("ISO %s no_%s" % [base_name, nm])
	for _f in 2:
		await get_tree().process_frame

## v0.15: what each grass ring costs. Hides one population at a time and
## times two frames (software rendering, so only the ratios mean anything).
func _ring_perf(base_name: String) -> void:
	var fol = world.get("foliage")
	if fol == null: return
	var groups := {}
	for ch in fol.get_children():
		if ch is MultiMeshInstance3D:
			var mi := ch as MultiMeshInstance3D
			var sp := 0.0
			if mi.material_override is ShaderMaterial:
				sp = float((mi.material_override as ShaderMaterial).get_shader_parameter("spacing"))
			var key := "ring_sp%.2f" % sp
			if not groups.has(key): groups[key] = []
			groups[key].append(mi)
		elif ch is Node3D:
			groups["detail"] = [ch]
	var cases := ["all"]
	for k in groups.keys(): cases.append(k)
	cases.append("no_foliage")
	cases.append("no_trees")
	for cs in cases:
		var hidden := []
		if cs == "no_foliage":
			hidden = [fol]
		elif cs == "no_trees":
			var ts = world.get("tree_system")
			if ts != null: hidden = [ts]
		elif cs != "all":
			hidden = groups[cs]
		var was := []
		for n in hidden:
			was.append((n as Node3D).visible)
			(n as Node3D).visible = false
		await get_tree().process_frame
		var t0 := Time.get_ticks_usec()
		for _f in 2:
			await get_tree().process_frame
		var ms := float(Time.get_ticks_usec() - t0) / 2000.0
		var pr := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		print("RINGPERF %s %-12s ms=%8.1f prims=%8d n=%d" % [base_name, cs, ms, pr, hidden.size()])
		get_viewport().get_texture().get_image().save_png("%s/%s_rp_%s.png" % [out_dir, base_name, cs])
		for i in hidden.size():
			(hidden[i] as Node3D).visible = was[i]

## Grass shader debug views (grass_gpu.gdshader `dbg`): 2 = albedo as
## emission, 3 = white albedo (lighting only), 4 = normal. Tonemap linear and
## glow off so the PNG holds sRGB(value) directly.
func _grass_debug(base_name: String, modes: String) -> void:
	var fol = world.get("foliage")
	if fol == null: return
	var mats := []
	for ch in fol.get_children():
		if ch is MultiMeshInstance3D and (ch as MultiMeshInstance3D).material_override is ShaderMaterial:
			var m := (ch as MultiMeshInstance3D).material_override as ShaderMaterial
			if not mats.has(m): mats.append(m)
	var we = world.get("world_env")
	var env: Environment = we.environment if we != null else null
	var tm := 0
	var gl := false
	if env != null:
		tm = env.tonemap_mode
		gl = env.glow_enabled
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.glow_enabled = false
	# trees: LOD0 red, LOD1 green, LOD2 blue under mode 5
	var tmats := {}
	var ts = world.get("tree_system")
	if ts != null:
		var tm_d = ts.get("_mats")
		if tm_d is Dictionary:
			for k in (tm_d as Dictionary).keys():
				var parts := String(k).split("_")
				var lod := int(parts[parts.size() - 2]) if parts.size() >= 3 else 0
				tmats[tm_d[k]] = lod
	for md in modes.split(","):
		for m in mats: (m as ShaderMaterial).set_shader_parameter("dbg", int(md))
		for tm_m in tmats.keys():
			(tm_m as ShaderMaterial).set_shader_parameter("dbg", int(md) if int(md) in [2, 5] else 0)
			(tm_m as ShaderMaterial).set_shader_parameter("dbg_col", [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)][clampi(int(tmats[tm_m]), 0, 2)])
		for _f in 3:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/%s_gdbg%s.png" % [out_dir, base_name, md])
		print("GDBG %s mode=%s saved" % [base_name, md])
	for m in mats: (m as ShaderMaterial).set_shader_parameter("dbg", 0)
	for tm_m in tmats.keys(): (tm_m as ShaderMaterial).set_shader_parameter("dbg", 0)
	if env != null:
		env.tonemap_mode = tm
		env.glow_enabled = gl

## Exposure / bloom sweep.
## A single shot costs three to five minutes, almost all of it world build and
## the first frames; re-rendering the SAME settled frame at different post
## settings costs about ten seconds each. So grade the look in one world load
## instead of one run per candidate.
const SWEEP := [
	# blend, intensity, bloom, threshold, hdr_scale, exposure, white
	["add",      0.42, 0.05, 1.45, 1.8, 0.85, 4.0],  # v0 = shipped default
	["add",      0.42, 0.05, 1.45, 1.8, 1.00, 4.0],
	["add",      0.55, 0.06, 1.20, 2.0, 0.85, 4.0],
	["add",      0.42, 0.05, 1.45, 1.8, 0.70, 5.0],
]

## What is actually under the camera? A bald patch in a screenshot could be
## rock, a dirt road, water, or a grass chunk that failed to stream. Guessing
## from a 960x540 PNG is not evidence; sampling the terrain is.
func _probe_ground(base_name: String, pos: Vector3) -> void:
	var t = world.get("terrain")
	if t == null: return
	var counts := {}
	var dens := 0.0
	var below := 0
	var riv := 0
	var n := 0
	for gz in 25:
		for gx in 25:
			var x := pos.x + (float(gx) - 12.0) * 2.5
			var z := pos.z + (float(gz) - 12.0) * 2.5
			var s := str(t.surface_at(x, z))
			counts[s] = int(counts.get(s, 0)) + 1
			dens += float(t.grass_density_at(x, z))
			var y := float(t.sample_height(x, z))
			if y < float(t.get("water_level")) + 0.15: below += 1
			if float(t.river_channel_at(x, z)) > 0.5: riv += 1
			n += 1
	var line := ("PROBE %s pos=(%.0f,%.1f,%.0f) water_level=%.2f biome=%s surf=%s meanden=%.3f below_water=%d/%d river=%d"
		% [base_name, pos.x, pos.y, pos.z, float(t.get("water_level")),
		str(t.biome_at(pos.x, pos.z)), JSON.stringify(counts), dens / float(n), below, n, riv])
	print(line)
	probes.append(line)
	var pf := FileAccess.open("user://probe_%s.txt" % tag, FileAccess.WRITE)
	if pf != null:
		for l: String in probes: pf.store_line(l)
		pf.close()

func _sweep(base_name: String) -> void:
	var we := get_tree().root.find_children("*", "WorldEnvironment", true, false)
	if we.is_empty():
		print("SWEEP skip: no WorldEnvironment"); return
	var wenv: WorldEnvironment = we[0]
	var e: Environment = wenv.environment
	var ca := wenv.camera_attributes as CameraAttributesPractical
	var blends := {"add": Environment.GLOW_BLEND_MODE_ADDITIVE,
		"screen": Environment.GLOW_BLEND_MODE_SCREEN,
		"softlight": Environment.GLOW_BLEND_MODE_SOFTLIGHT}
	for i in SWEEP.size():
		var v: Array = SWEEP[i]
		e.glow_blend_mode = int(blends[str(v[0])])
		e.glow_intensity = float(v[1])
		e.glow_bloom = float(v[2])
		e.glow_hdr_threshold = float(v[3])
		e.glow_hdr_scale = float(v[4])
		e.tonemap_white = float(v[6])
		if ca != null:
			ca.auto_exposure_enabled = false
			ca.exposure_multiplier = float(v[5])
		for _f in 3:
			await get_tree().process_frame
		var im := get_viewport().get_texture().get_image()
		im.save_png("%s/%s_v%d.png" % [out_dir, base_name, i])
		print("SWEEP %s v%d %s i=%.2f thr=%.2f exp=%.2f white=%.1f"
			% [base_name, i, str(v[0]), float(v[1]), float(v[3]), float(v[5]), float(v[6])])

func _run_scenario(sc: Dictionary, settle: int) -> void:
	# time of day
	if world.has_method("set_time_of_day"):
		world.set_time_of_day(float(sc["tod"]))
	else:
		world.set("time_of_day", float(sc["tod"]))
	# weather (graceful: only if a weather system exists)
	var wx := str(sc.get("wx", "clear"))
	if world.has_method("set_weather"):
		world.set_weather(wx, true)
	# place the player and settle streamed content around the new position
	var pos: Vector3 = sc["pos"]
	var t = world.get("terrain")
	if t != null and t.has_method("sample_height"):
		pos.y = t.sample_height(pos.x, pos.z) + 1.2
	if world.has_method("warp_to"):
		world.warp_to(pos)
	elif player != null and is_instance_valid(player):
		player.global_position = pos
	if cam_rig != null and is_instance_valid(cam_rig):
		cam_rig.set("yaw", float(sc.get("yaw", 0.0)))
		cam_rig.set("pitch", float(sc.get("pitch", -0.16)))
		if cam_rig is Node3D:
			(cam_rig as Node3D).global_position = pos + Vector3(0, 1.45, 0)
	for i in settle:
		await get_tree().process_frame
	# nohud=1: a clean frame (HUD, story cards and dialogue hidden; film layer kept)
	if _arg("nohud", "") != "":
		for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
			if (cl as Node).name != "FilmLayer": (cl as CanvasLayer).visible = false
	# measure over a short window
	var f := 0
	var ms := 0.0
	var dc := 0
	var pr := 0
	var t0 := Time.get_ticks_usec()
	while f < 8:
		await get_tree().process_frame
		f += 1
		dc = maxi(dc, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		pr = maxi(pr, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	ms = float(Time.get_ticks_usec() - t0) / 1000.0 / float(f)
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, str(sc["n"])]
	img.save_png(path)
	if _arg("probe", "") != "":
		_probe_ground(str(sc["n"]), pos)
	if _arg("iso", "") != "":
		await _isolate(str(sc["n"]))
	if _arg("ringperf", "") != "":
		await _ring_perf(str(sc["n"]))
	if _arg("gdbg", "") != "":
		await _grass_debug(str(sc["n"]), _arg("gdbg", ""))
	if _arg("sweep", "") != "":
		await _sweep(str(sc["n"]))
	if _arg("wisps", "") != "":
		await _wisps(str(sc["n"]))
	var objs := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var es := {}
	if world.has_method("env_stats"): es = world.env_stats()
	var g: Dictionary = es.get("grass", {})
	var tstat: Dictionary = es.get("trees", {})
	rows.append({"scene": str(sc["n"]), "ms": ms, "draws": dc, "prims": pr, "objs": objs,
		"grass_inst": int(g.get("instances", 0)), "grass_chunks": int(g.get("chunks", 0)),
		"tree_nodes": int(tstat.get("mm_nodes", 0)), "trees": int(tstat.get("trees", 0))})
	print("SHOT %-10s ms=%7.1f draws=%5d prims=%8d grass_inst=%6d grass_chunks=%3d tree_mm=%4d wx=%s h=%.1f" % [
		str(sc["n"]), ms, dc, pr, int(g.get("instances", 0)), int(g.get("chunks", 0)),
		int(tstat.get("mm_nodes", 0)), str(es.get("weather", "?")), float(es.get("hour", 0.0))])
	_write_csv()

## Written after every shot, not just at the end: Godot block-buffers stdout
## when it is not a terminal, so a run that hangs on exit silently loses every
## measurement it took.
## v0.15: put the hitodama (spirit fires) where the camera can see them and
## photograph them -- in normal play they keep 13+ m away and appear slowly.
func _wisps(base_name: String) -> void:
	var hd = world.get("hitodama")
	if hd == null:
		print("ENVSHOTS wisps: no hitodama node"); return
	var cam := get_viewport().get_camera_3d()
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	var terr = world.get("terrain")
	var i := 0
	for w in hd.get("_wisps"):
		var d := 14.0 + 4.0 * i
		var p: Vector3 = cam.global_position + fwd * d + side * (float(i % 3) - 1.0) * 4.0
		var gy: float = terr.sample_height(p.x, p.z) if terr != null else p.y
		(w as Node3D).global_position = Vector3(p.x, gy + 1.6, p.z)
		w.set_meta("alive", true); w.set_meta("want", 1.0); w.set_meta("fade", 1.0)
		w.set_meta("base", 1.6); w.set_meta("vel", Vector3.ZERO)
		(w as Node3D).visible = true
		i += 1
	hd.set("_active", 1.0)
	hd.set("_tick", 999.0)
	for f in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s_wisps.png" % [out_dir, base_name])
	print("ENVSHOTS wisps shot: ", i, " spirit fires")

func _write_csv() -> void:
	var f := FileAccess.open("user://metrics_%s.csv" % tag, FileAccess.WRITE)
	if f != null:
		f.store_line("scene,frame_ms,draw_calls,primitives,visible_objects,grass_instances,grass_chunks,tree_mm_nodes")
		for r in rows:
			f.store_line("%s,%.2f,%d,%d,%d,%d,%d,%d" % [r["scene"], r["ms"], r["draws"], r["prims"],
				r["objs"], r["grass_inst"], r["grass_chunks"], r["tree_nodes"]])
		f.close()

func _finish(_tag: String) -> void:
	_write_csv()
	print("ENVSHOTS_DONE shots=", rows.size())
	get_tree().quit()
