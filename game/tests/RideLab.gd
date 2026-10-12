extends Node3D
## Rider-on-horse render lab: floor, sun, the real Horse and Player, mounted
## through Player.mount(); renders a few camera angles per pose.
##   renv.sh res://tests/RideLab.tscn -- poses=idle,canter,cut views=side,front,back,q out=/tmp/ride

var horse: Horse
var player: Player
var cam: Camera3D
var out := "/tmp/ride"

func _ready() -> void:
	var ua := OS.get_cmdline_user_args()
	var poses := ["idle"]
	var views := ["side", "front", "q"]
	for a in ua:
		var s := String(a)
		if s.begins_with("poses="): poses = s.substr(6).split(",")
		elif s.begins_with("views="): views = s.substr(6).split(",")
		elif s.begins_with("out="): out = s.substr(4)
	get_viewport().get_window().size = Vector2i(560, 560)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.70)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.light_energy = 1.3
	add_child(sun)
	var floor := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(400, 1, 400)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	floor.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.36, 0.42, 0.28)
	mi.material_override = fm
	floor.add_child(mi)
	add_child(floor)
	horse = Horse.new()
	add_child(horse)
	player = Player.new()
	add_child(player)
	player.global_position = Vector3(1.4, 0, 0)
	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	await get_tree().create_timer(0.6).timeout
	player.mount(horse)
	await get_tree().create_timer(1.0).timeout
	for p in poses:
		await _pose(String(p))
		await player.rig.skeleton.skeleton_updated
		_probe(String(p))
		for v in views:
			await _view(String(v), String(p))
	get_tree().quit()

## numbers for the rein pose: did each fist reach its grip, where are the elbows
func _probe(p: String) -> void:
	var rig: PlayerRig = player.rig
	var sk := rig.skeleton
	var inv := rig.global_transform.affine_inverse()
	for side in ["l", "r"]:
		var k: SkeletonIK3D = rig.rein_ik.get(side)
		var hb := sk.find_bone("hand_" + side)
		var eb := sk.find_bone("lowerarm_" + side)
		var fist: Vector3 = sk.global_transform * (sk.get_bone_global_pose(hb) * PlayerRig.FIST)
		var want: Vector3 = rig.global_transform * (PlayerRig.REIN_GRIP[side] as Vector3)
		var elbow: Vector3 = sk.global_transform * sk.get_bone_global_pose(eb).origin
		print("REIN %s %s infl=%.2f miss=%.3f fist_rig=%s elbow_rig=%s" % [p, side, k.influence if k else -1.0,
			fist.distance_to(want), str((inv * fist).snapped(Vector3.ONE * 0.01)), str((inv * elbow).snapped(Vector3.ONE * 0.01))])
	var ends: PackedVector3Array = player.rein_grip_points()
	var bits: Array = horse.get("_bit")
	if bits.size() == 2 and ends.size() == 2:
		print("REIN %s bit->hand d=%.2f / %.2f" % [p, (bits[0] as Node3D).global_position.distance_to(ends[0]), (bits[1] as Node3D).global_position.distance_to(ends[1])])

func _pose(p: String) -> void:
	Input.action_release("move_forward")
	Input.action_release("sprint")
	match p:
		"idle":
			await get_tree().create_timer(0.8).timeout
		"canter":
			Input.action_press("move_forward")
			await get_tree().create_timer(2.5).timeout
		"gallop":
			Input.action_press("move_forward")
			Input.action_press("sprint")
			await get_tree().create_timer(3.5).timeout
		"cut":
			Input.action_press("attack")
			await get_tree().physics_frame
			await get_tree().physics_frame
			Input.action_release("attack")
			await get_tree().create_timer(0.3).timeout

func _view(v: String, p: String) -> void:
	var c := horse.global_position + Vector3(0, 1.45, 0)
	var yaw := horse.rotation.y
	var b := Basis(Vector3.UP, yaw)
	var off := Vector3(4.6, 0.4, 0)
	match v:
		"side": off = Vector3(4.6, 0.3, 0.2)
		"left": off = Vector3(-4.6, 0.3, 0.2)
		"front": off = Vector3(0.2, 0.4, 4.8)
		"back": off = Vector3(0.2, 0.9, -4.8)
		"q": off = Vector3(3.4, 1.4, 3.4)
		"top": off = Vector3(0.01, 5.5, 0.3)
		"close": off = Vector3(2.2, 0.5, 0.4); c += Vector3(0, 0.35, 0)
	cam.global_position = c + b * off
	cam.look_at(c, Vector3.UP)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s_%s_%s.png" % [out, p, v])
