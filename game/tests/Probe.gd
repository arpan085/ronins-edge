extends Node
## Culling probe: the test that found the terrain winding bug.
##
## Overrides the terrain material with an unshaded flat colour and renders the
## same vantage twice - once with cull_back, once with cull_disabled. If the two
## frames differ, the terrain triangles are wound so that Godot treats their
## visible side as the back face. That is exactly what was happening: with
## cull_back the frame was empty (what looked like ground was the fogged sky
## dome), and with cull_disabled the terrain filled the lower half of the frame.

func _ready() -> void:
	get_viewport().get_window().size = Vector2i(640, 360)
	DirAccess.make_dir_recursive_absolute("user://probe")
	await get_tree().create_timer(0.4).timeout
	var main = get_parent().get_node_or_null("Main")
	main.start_world(false)
	var world = null
	for i in 300:
		await get_tree().process_frame
		world = main.get("world")
		if world != null and bool(world.get("loaded")): break
	if world == null:
		print("PROBE FAIL no world"); get_tree().quit(); return
	var terrain = world.get("terrain")
	var zones: Dictionary = (world.get("data") as Dictionary).get("zones", {})
	if zones.has("grassland"):
		var z: Dictionary = zones["grassland"]
		world.warp_to(Vector3(float(z["x"]), 0, float(z["z"])))
	world.set_time_of_day(12.0)
	world.set_weather("clear", true)
	for mode in [BaseMaterial3D.CULL_BACK, BaseMaterial3D.CULL_DISABLED]:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.0, 1.0, 0.2)
		m.cull_mode = mode
		var n := 0
		for c in terrain.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).material_override = m
				n += 1
		for i in 8:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var tag := "cull_back" if mode == BaseMaterial3D.CULL_BACK else "cull_disabled"
		img.save_png("user://probe/%s.png" % tag)
		# count how much of the frame the flat colour covers
		var green := 0
		var total := 0
		var y := 0
		while y < img.get_height():
			var x := 0
			while x < img.get_width():
				var c2 := img.get_pixel(x, y)
				if c2.g > 0.55 and c2.r < 0.35: green += 1
				total += 1
				x += 4
			y += 4
		print("PROBE %-14s chunks=%d coverage=%.1f%%" % [tag, n, 100.0 * float(green) / maxf(float(total), 1.0)])
	print("PROBE DONE")
	get_tree().quit()
