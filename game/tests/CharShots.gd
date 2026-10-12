extends Node3D
## Character sheet: front / three-quarter / side / back plus a head close-up,
## on a neutral backdrop. This is the view you actually judge a character on.

var cam: Camera3D
var rig: Node3D
var driver: Node
var shots: Array = []
var idx := -1
var t := 0.0
var saved := 0
var bind_mode := false
var clip_name := ""
var hips_idx := -1

func _ready() -> void:
	get_viewport().get_window().size = Vector2i(760, 1000)
	var kind := "kaito"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("kind="): kind = a.split("=")[1]
	_stage()
	rig = Node3D.new()
	add_child(rig)
	driver = AnimDriver.new()
	rig.add_child(driver)
	var glb := "res://assets/models/%s_Ronin.glb" % kind.capitalize()
	if not driver.build(rig, glb, kind, true):
		print("CHAR: build failed"); get_tree().quit(); return
	var ua: PackedStringArray = OS.get_cmdline_user_args()
	if driver.rig != null and driver.rig.tree != null and not ua.has("rest"):
		driver.rig.tree.active = true
		driver.rig.travel("Idle")
	# A/B switches for diagnosis: `hide=leather` makes every surface whose
	# material name contains the text invisible, `rest` leaves the skeleton in
	# its bind pose, `only=7_torso,9_hip` renders just those shots.
	var hide_key := ""
	var only := ""
	for a4 in ua:
		if a4.begins_with("hide="): hide_key = a4.split("=")[1]
		if a4.begins_with("only="): only = a4.split("=")[1]
	# Pose check: `clip=Heavy at=0.2,0.5,0.8` freezes the animation tree and
	# seeks the named clip to each time, so the skinning can be judged in the
	# poses that actually stretch it (twist, bend, lunge) rather than in idle.
	var at_times: Array = []
	for a5 in ua:
		if a5.begins_with("clip="): clip_name = a5.split("=")[1]
		if a5.begins_with("at="):
			for part in a5.split("=")[1].split(","):
				at_times.append(float(part))
	if hide_key != "":
		_hide(rig, hide_key)
	if ua.has("nolod"):
		get_viewport().mesh_lod_threshold = 0.0
	if ua.has("bind"):
		bind_mode = true
		process_priority = 1000      # run after the animation nodes
	# Sword carry. The katana is skinned to weapon.R under the hand, so the
	# only way to see whether the blade actually seats in the saya is to look
	# at the hip with the carry blend on. An offset sweep in one run beats one
	# run per guess.
	var carry_mode := ""
	for a2 in OS.get_cmdline_user_args():
		if a2.begins_with("carry="): carry_mode = a2.split("=")[1]
	if carry_mode != "" and driver.carry != null:
		driver.carry.blend = 1.0
	shots = [
		{"n": "1_front", "yaw": 0.0, "h": 0.95, "d": 2.9, "fov": 34.0},
		{"n": "2_three_q", "yaw": 38.0, "h": 0.95, "d": 2.9, "fov": 34.0},
		{"n": "3_side", "yaw": 90.0, "h": 0.95, "d": 2.9, "fov": 34.0},
		{"n": "4_back", "yaw": 180.0, "h": 0.95, "d": 2.9, "fov": 34.0},
		{"n": "5_head", "yaw": 18.0, "h": 1.660, "d": 0.70, "fov": 30.0},
		{"n": "6_hands", "yaw": 52.0, "h": 0.90, "d": 0.46, "fov": 34.0, "tx": 0.24, "tz": 0.02},
		{"n": "7_torso", "yaw": 0.0, "h": 1.22, "d": 1.30, "fov": 32.0},
		{"n": "8_legs", "yaw": 0.0, "h": 0.45, "d": 1.60, "fov": 32.0},
		{"n": "9_hip", "yaw": 118.0, "h": 0.98, "d": 1.45, "fov": 34.0},
	]
	if carry_mode == "sweep":
		shots = []
		for i in CARRY_TRIES.size():
			shots.append({"n": "c%d_hip" % i, "yaw": 132.0, "h": 0.92, "d": 1.15,
				"fov": 38.0, "carry": i})
			shots.append({"n": "c%d_side" % i, "yaw": 90.0, "h": 1.00, "d": 2.2,
				"fov": 34.0, "carry": i})
	if only != "":
		var keep: PackedStringArray = only.split(",")
		var kept: Array = []
		for sh in shots:
			if keep.has(String(sh["n"])): kept.append(sh)
		shots = kept
	if clip_name != "" and driver.anim_player != null:
		if driver.rig != null and driver.rig.tree != null:
			driver.rig.tree.active = false
		if at_times.is_empty(): at_times.append(0.0)
		hips_idx = driver.skeleton.find_bone("hips")
		driver.anim_player.play(clip_name)
		driver.anim_player.pause()
		var expanded: Array = []
		for tt in at_times:
			for sh2 in shots:
				var s2: Dictionary = sh2.duplicate()
				s2["n"] = "%s_%s_t%03d" % [sh2["n"], clip_name, int(round(float(tt) * 100.0))]
				s2["at"] = float(tt)
				expanded.append(s2)
		shots = expanded
	idx = 0
	_place()

func _hide(node: Node, key: String) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i)
				if m != null and m.resource_name.to_lower().contains(key):
					var inv := StandardMaterial3D.new()
					inv.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					inv.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
					mi.set_surface_override_material(i, inv)
	for c in node.get_children():
		_hide(c, key)

func _stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.20, 0.21, 0.24)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.60, 0.70)
	e.ambient_light_energy = 0.30
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_white = 2.0
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-26.0, 30.0, 0.0)
	key.light_energy = 1.7
	key.light_color = Color(1.0, 0.97, 0.92)
	key.shadow_enabled = not OS.get_cmdline_user_args().has("noshadow")
	# A 100 m default shadow range spends its texels on empty floor, and the
	# forehead is a near-grazing surface, so the skull self-shadowed in clean
	# bands -- one per cross-section row -- that looked like dark chevrons
	# painted on the face. Tighten the range and lift the normal bias.
	key.directional_shadow_max_distance = 7.0
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.shadow_bias = 0.010
	key.shadow_normal_bias = 0.8
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-14.0, -128.0, 0.0)
	fill.light_energy = 0.55
	fill.light_color = Color(0.72, 0.80, 0.95)
	add_child(fill)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12.0, 12.0)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.26, 0.26, 0.28)
	fm.roughness = 0.95
	floor_mi.material_override = fm
	add_child(floor_mi)
	cam = Camera3D.new()
	add_child(cam)

## Candidate seatings for the blade in the saya: position offset from the
## scabbard bone, then rotation.
## c0 is the reference: carry OFF, so the saya is visible empty and every
## other frame can be compared against where it actually sits.
const CARRY_TRIES := [
	[Vector3(0, -0.19, 0), Vector3(24, 0, 0)],       # 0: blend forced to 0
	[Vector3(0, -0.19, 0), Vector3(24, 0, 0)],       # 1: the derived seating
	[Vector3(0, -0.13, 0), Vector3(24, 0, 0)],
	[Vector3(0, -0.25, 0), Vector3(24, 0, 0)],
	[Vector3(0, -0.19, 0), Vector3(24, 8, 0)],
	[Vector3(0, -0.19, 0), Vector3(204, 0, 0)],
]

func _place() -> void:
	var s: Dictionary = shots[idx]
	if s.has("carry") and driver != null and driver.carry != null:
		var ci: int = int(s["carry"])
		var c: Array = CARRY_TRIES[ci]
		driver.carry.set_offset(c[0], c[1])
		driver.carry.blend = 0.0 if ci == 0 else 1.0
	if s.has("at") and driver != null and driver.anim_player != null:
		driver.anim_player.seek(float(s["at"]), true)
	_aim(s)
	t = 0.0

## Point the camera at the shot's target. In a clip pose the root moves (a
## roll travels 2 m), so the target follows the hips on the ground plane.
func _aim(s: Dictionary) -> void:
	var a: float = deg_to_rad(float(s["yaw"]))
	var d: float = float(s["d"])
	var h: float = float(s["h"])
	cam.fov = float(s["fov"])
	var tgt := Vector3(float(s.get("tx", 0.0)), h, float(s.get("tz", 0.0)))
	if s.has("at") and hips_idx >= 0 and driver.skeleton != null:
		var hp: Vector3 = (driver.skeleton.global_transform * driver.skeleton.get_bone_global_pose(hips_idx)).origin
		tgt.x += hp.x
		tgt.z += hp.z
	cam.global_position = tgt + Vector3(sin(a) * d, 0.10, cos(a) * d)
	cam.look_at(tgt)

func _bind_pose(node: Node) -> void:
	if node is Skeleton3D:
		(node as Skeleton3D).reset_bone_poses()
	for c in node.get_children():
		_bind_pose(c)

func _process(delta: float) -> void:
	if idx < 0 or idx >= shots.size(): return
	if bind_mode:
		_bind_pose(rig)
	t += delta
	if shots[idx].has("at"): _aim(shots[idx])
	if t < 0.55: return
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://char")
	img.save_png("user://char/%s.png" % shots[idx]["n"])
	saved += 1
	print("CHAR shot %s" % shots[idx]["n"])
	idx += 1
	if idx >= shots.size():
		print("CHAR_DONE saved=%d" % saved)
		get_tree().quit()
		return
	_place()
