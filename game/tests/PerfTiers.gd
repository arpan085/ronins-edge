extends Node
## Quality-tier cost measurement.
##
## Boots the real world, then walks the requested quality tiers at several
## vantage points and records what the renderer actually reports. On a software
## rasteriser the absolute frame time is meaningless, so the useful outputs are
## the geometry and draw-call budgets plus the RELATIVE cost between tiers on
## identical scenes. Nothing here is extrapolated to real hardware.

var world = null
var rows := []

func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with(key + "="): return s.substr(key.length() + 1)
	return def

func _ready() -> void:
	var settle := int(_arg("settle", "6"))
	get_viewport().get_window().size = Vector2i(640, 360)
	await get_tree().create_timer(0.4).timeout
	var main = get_parent().get_node_or_null("Main")
	main.start_world(false)
	for i in 300:
		await get_tree().process_frame
		world = main.get("world")
		if world != null and bool(world.get("loaded")): break
	if world == null:
		print("PERF FAIL no world"); get_tree().quit(); return
	var zones: Dictionary = (world.get("data") as Dictionary).get("zones", {})
	var spots: Array = _arg("spots", "grassland,forest,village,mountain").split(",")
	var tiers: Array = []
	for t in _arg("tiers", "0,1,2,3").split(","): tiers.append(int(t))
	print("PERF adapter=", RenderingServer.get_video_adapter_name(),
		" cpus=", OS.get_processor_count())
	for tier in tiers:
		Perf.adaptive = false
		Perf.apply_quality(tier)
		var fol = world.get("foliage")
		for sp in spots:
			if not zones.has(sp): continue
			var z: Dictionary = zones[sp]
			world.warp_to(Vector3(float(z["x"]), 0, float(z["z"])))
			world.set_time_of_day(12.0)
			world.set_weather("clear", true)
			if fol != null: fol.prime(world.get("player").global_position, 14)
			var hide := _arg("hide", "")
			if hide.find("trees") >= 0 and world.get("tree_system") != null: world.get("tree_system").visible = false
			if hide.find("grass") >= 0 and fol != null: fol.visible = false
			var ms := 0.0
			for i in settle:
				var t0 := Time.get_ticks_usec()
				await RenderingServer.frame_post_draw
				ms += float(Time.get_ticks_usec() - t0) / 1000.0
			ms /= float(settle)
			var fs: Dictionary = fol.stats() if fol != null else {}
			var ts: Dictionary = {}
			if world.get("tree_system") != null: ts = world.get("tree_system").stats()
			var sun = get_tree().get_first_node_in_group("sun")
			rows.append({
				"tier": Perf.preset()["name"], "spot": sp, "ms": ms,
				"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
				"prims": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
				"objs": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
				"grass": int(fs.get("instances", 0)),
				"grass_mm": int(fs.get("chunks", 0)),
				"trees": int(ts.get("trees", 0)),
				"tree_mm": int(ts.get("mm_nodes", 0)),
				"scale": float(get_viewport().scaling_3d_scale),
				"shadow": float(sun.directional_shadow_max_distance) if sun != null else 0.0,
			})
			var r: Dictionary = rows[-1]
			print("PERF %-6s %-10s ms=%8.1f draws=%5d prims=%9d objs=%5d grass=%7d trees=%6d tmm=%5d scale=%.2f shadow=%.0f" % [
				r["tier"], sp, ms, r["draws"], r["prims"], r["objs"], r["grass"],
				r["trees"], r["tree_mm"], r["scale"], r["shadow"]])
	var f := FileAccess.open("user://perf_tiers.csv", FileAccess.WRITE)
	if f != null:
		f.store_line("tier,spot,frame_ms,draw_calls,primitives,objects,grass_instances,grass_chunks,trees_placed,tree_mm_nodes,render_scale,shadow_dist_m")
		for r2 in rows:
			f.store_line("%s,%s,%.2f,%d,%d,%d,%d,%d,%d,%d,%.2f,%.0f" % [r2["tier"], r2["spot"],
				r2["ms"], r2["draws"], r2["prims"], r2["objs"], r2["grass"], r2["grass_mm"],
				r2["trees"], r2["tree_mm"], r2["scale"], r2["shadow"]])
		f.close()
	print("PERF DONE rows=", rows.size())
	get_tree().quit()
