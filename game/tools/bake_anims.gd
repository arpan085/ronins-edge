extends SceneTree
## Bakes the player animation library.
##   godot --headless --path game -s tools/bake_anims.gd
## Reads the CC0 Universal Animation Library GLBs (v4/src/anim) and writes
## res://assets/anim/ronin_anims.res, retargeted onto the Ronin skeleton
## (identical bone names).  Track paths are rewritten to "Skeleton3D:<bone>" so the
## library plays on any AnimationPlayer whose root is the skeleton's parent.

const SRC := "/data/ronins_edge/v4/src/"
const CHAR := "res://assets/char/Ronin.glb"
const OUT := "res://assets/anim/ronin_anims.res"

func _init() -> void:
	var lib := AnimationLibrary.new()
	var ron := _load_abs("/data/ronins_edge/game/assets/char/Ronin.glb")
	var ron_sk := _find_sk(ron)
	print("Ronin skeleton bones: ", ron_sk.get_bone_count())
	var k_h := 1.0
	for src in ["anim/UAL1_Standard.glb", "anim/UAL2_Standard.glb"]:
		var scn := _load_abs(SRC + src)
		var sk := _find_sk(scn)
		var ap := _find_ap(scn)
		var kh := 1.0
		var pi_u := sk.find_bone("pelvis"); var pi_r := ron_sk.find_bone("pelvis")
		kh = ron_sk.get_bone_rest(pi_r).origin.y / sk.get_bone_rest(pi_u).origin.y
		print(src, ": ", ap.get_animation_list().size(), " clips, pelvis height ratio ", kh)
		for an in ap.get_animation_list():
			var a: Animation = ap.get_animation(an).duplicate()
			var name := String(an)
			if name.ends_with("_Loop"):
				name = name.trim_suffix("_Loop"); a.loop_mode = Animation.LOOP_LINEAR
			if lib.has_animation(name): continue
			var drop: Array = []
			for i in a.get_track_count():
				var p := String(a.track_get_path(i))
				var bone := p.substr(p.rfind(":") + 1)
				if ron_sk.find_bone(bone) < 0:
					drop.append(i); continue
				a.track_set_path(i, NodePath("Skeleton3D:" + bone))
				if bone == "pelvis" and a.track_get_type(i) == Animation.TYPE_POSITION_3D:
					for k in a.track_get_key_count(i):
						a.track_set_key_value(i, k, (a.track_get_key_value(i, k) as Vector3) * kh)
			drop.reverse()
			for i in drop: a.remove_track(i)
			lib.add_animation(name, a)
		scn.queue_free()
	print("library clips: ", lib.get_animation_list().size())
	var err := ResourceSaver.save(lib, OUT)
	print("saved ", OUT, " err=", err)
	quit()

func _load_abs(path: String) -> Node:
	var st := GLTFState.new(); var doc := GLTFDocument.new()
	var e := doc.append_from_file(path, st)
	if e != OK: push_error("cannot load " + path); quit(1)
	return doc.generate_scene(st)

func _find_sk(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var r := _find_sk(c)
		if r != null: return r
	return null

func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer: return n
	for c in n.get_children():
		var r := _find_ap(c)
		if r != null: return r
	return null
