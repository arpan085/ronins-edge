extends Node
## v0.16: the techniques screen on its own (no world), over a still frame.
##   renv.sh res://tests/SkillsShot.tscn -- out=/tmp/skills.png [bg=/path/frame.png] [sel=b_mikiri]

func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with(k + "="): return s.substr(k.length() + 1)
	return d

func _ready() -> void:
	get_viewport().get_window().size = Vector2i(1280, 720)
	var bgp := _arg("bg", "")
	if bgp != "" and FileAccess.file_exists(bgp):
		var img := Image.load_from_file(bgp)
		var tr := TextureRect.new()
		tr.texture = ImageTexture.create_from_image(img)
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		add_child(tr)
	else:
		var cr := ColorRect.new()
		cr.color = Color(0.2, 0.24, 0.2)
		cr.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(cr)
	Skills.reset()
	for id in _arg("own", "b_deflect,b_posture,s_silent,s_assassin,p_fox").split(","):
		if id != "": Skills.unlocked.append(String(id))
	Game.mastery_points = int(_arg("pts", "4"))
	var cl := CanvasLayer.new()
	cl.layer = 46
	cl.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(cl)
	var m = load("res://ui/SkillsMenu.gd").new()
	cl.add_child(m)
	await get_tree().process_frame
	m.open()
	m.selected = _arg("sel", "b_mikiri")
	m.queue_redraw()
	for i in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_arg("out", "/tmp/skills.png"))
	print("SKILLSHOT saved")
	get_tree().quit()
