class_name PlayerRig
extends Node3D
## The visible ronin: model, animation library, weapon sockets.
##
## Everything visual about the player lives here so Player.gd can stay a plain
## state machine.  The rig owns
##   * the Ronin.glb skinned model (Universal Base Character skeleton),
##   * one AnimationPlayer holding ronin_anims.res (Universal Animation Library),
##   * three bone sockets: right hand (drawn weapon), left hip (katana saya) and
##     upper back (long weapons), and
##   * the weapon meshes from weapons.glb, moved between those sockets.
##
## Coordinates: the rig faces +Z like the rest of the game.

const CHAR_PATH := "res://assets/char/Ronin.glb"
const ANIM_PATH := "res://assets/anim/ronin_anims.res"
const WEAPON_PATH := "res://assets/weapons/weapons.glb"

## Weapon space -> hand_r bone space.  Weapon +Y is the blade, +Z the cutting
## edge.  In the hand bone's frame the fingers run along +Y and the thumb sits
## on +Z, so a fist round the grip sends the blade out of the thumb side with
## the edge facing the way the fingers point.
const GRIP_BASIS := Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))
var grip_pos := Vector3(-0.035, 0.085, 0.0)

var model: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var hand_sock: BoneAttachment3D
var hip_sock: BoneAttachment3D
var back_sock: BoneAttachment3D
var ok := false
var layer: PoseLayer          ## upper-body override (guard while running, rider arms)
var legs: PoseLayer           ## model-space leg offsets (rider straddle)
var ik: SkeletonIK3D          ## right-hand reach for draw / sheathe
var foot_ik: FootIK           ## v0.22: feet planted on slopes and steps
var ik_target: Node3D

var weapon := "katana"
var drawn := false
var _nodes := {}          # weapon scene node name -> Node3D
var _mount := {}          # "hip"/"back"/"hip2" -> Transform3D relative to the socket bone
var _cur := ""

func _ready() -> void:
	if not ok: build()

func build() -> bool:
	if ok: return true
	var ps = load(CHAR_PATH)
	if ps == null:
		push_error("PlayerRig: cannot load " + CHAR_PATH)
		return false
	model = ps.instantiate()
	model.name = "Model"
	CharDress.dress(model)
	add_child(model)
	skeleton = _find_skeleton(model)
	if skeleton == null:
		push_error("PlayerRig: no skeleton in Ronin.glb")
		return false
	# Godot 4.3 redraws a paused skeleton without its modifiers, so the guard
	# layer, rider legs and hand IK vanished behind the pause menu. Keep the
	# skeleton (not the AnimationPlayer) processing so the pose holds.
	skeleton.process_mode = Node.PROCESS_MODE_ALWAYS
	anim = AnimationPlayer.new()
	anim.name = "Anim"
	model.add_child(anim)
	var lib: AnimationLibrary = load(ANIM_PATH)
	GroundFix.apply(lib, skeleton)    # v0.22: UAL clips stood 17 cm low
	anim.add_animation_library("", lib)
	anim.root_node = anim.get_path_to(skeleton.get_parent())
	anim.playback_default_blend_time = 0.0
	_build_sockets()
	_load_weapons()
	_build_layers()
	anatomy = Anatomy.new()
	anatomy.name = "Anatomy"
	skeleton.add_child(anatomy)
	BreathFX.attach(skeleton, anatomy, null)
	_build_saya_ik()
	ok = true
	set_weapon("katana", false)
	play("Idle", 0.0)
	return true

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null: return r
	return null

# ---------------------------------------------------------------- layers
const UPPER_MASK := {
	"spine_02": 0.35, "spine_03": 0.6, "neck_01": 0.3,
	"clavicle_r": 1.0, "upperarm_r": 1.0, "lowerarm_r": 1.0, "hand_r": 1.0,
	"clavicle_l": 1.0, "upperarm_l": 1.0, "lowerarm_l": 1.0, "hand_l": 1.0,
}
const RIGHT_ARM := ["clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"]

func _build_layers() -> void:
	layer = PoseLayer.new()
	layer.name = "UpperLayer"
	skeleton.add_child(layer)
	var m := UPPER_MASK.duplicate()
	for i in skeleton.get_bone_count():
		var bn := skeleton.get_bone_name(i)
		for f in ["index", "middle", "ring", "pinky", "thumb"]:
			if bn.begins_with(f + "_"): m[bn] = 1.0
	layer.set_mask(skeleton, m)
	layer.influence = 0.0
	legs = PoseLayer.new()
	legs.name = "LegOffsets"
	skeleton.add_child(legs)
	legs.influence = 0.0
	# v0.22: ground contact after the leg offsets, before the hand IK, so the
	# pelvis drop on a slope does not pull the reaching hand off its target
	foot_ik = FootIK.new()
	foot_ik.name = "FootIK"
	foot_ik.influence = 0.0
	skeleton.add_child(foot_ik)
	ik_target = Node3D.new()
	ik_target.name = "ReachTarget"
	ik_target.top_level = true
	add_child(ik_target)
	ik = SkeletonIK3D.new()
	ik.name = "ReachIK"
	# bones before add_child: SkeletonIK3D rebuilds its chain on every setter
	# once it is under a skeleton and complains about the half-set pair
	ik.root_bone = "upperarm_r"
	ik.tip_bone = "hand_r"
	skeleton.add_child(ik)
	ik.override_tip_basis = true
	ik.use_magnet = true
	ik.magnet = Vector3(-0.6, 1.0, -0.4)
	ik.max_iterations = 12
	ik.target_node = ik.get_path_to(ik_target)
	ik.influence = 0.0
	ik.start()
	_build_rein_ik()

# ---------------------------------------------------------------- rider fit
var rider_pelvis := Vector3(0.0, 0.62, 0.0)   ## pelvis joint in rig space, seated clip
var _rider_ready := false

# ---------------------------------------------------------------- saya hand
## v0.18: with the sword sheathed a samurai walks with his left hand on the
## scabbard just behind the guard, so the saya does not swing and the free arm
## never passes through it. An arm IK puts the wrist there; the hand keeps the
## clip's wrist angle, so the fingers lie along the saya.
var saya_ik: SkeletonIK3D
var saya_target: Node3D
## wrist target in the katana's mount frame (+Y along the blade toward the tip,
## +Z the edge side, which is up when worn, +X outward). The saya mouth is at
## y 0.082, so the palm lands just behind it with the thumb at the guard.
var saya_grip := Vector3(0.045, 0.11, 0.055)

func _build_saya_ik() -> void:
	saya_target = Node3D.new()
	saya_target.name = "SayaTarget"
	saya_target.top_level = true
	add_child(saya_target)
	saya_ik = SkeletonIK3D.new()
	saya_ik.name = "SayaIK"
	saya_ik.root_bone = "upperarm_l"
	saya_ik.tip_bone = "hand_l"
	skeleton.add_child(saya_ik)
	saya_ik.override_tip_basis = false
	saya_ik.use_magnet = true
	# elbow out to the side and a little back, like a hand resting on a hilt
	saya_ik.magnet = Vector3(0.55, 1.05, -0.25)
	saya_ik.max_iterations = 10
	saya_ik.target_node = saya_ik.get_path_to(saya_target)
	saya_ik.influence = 0.0
	saya_ik.start()

## Fade the left hand onto (or off) the katana's saya. Call every frame.
func update_saya_hand(delta: float, want: bool) -> void:
	if saya_ik == null: return
	var nd: Node3D = _nodes.get("KatanaSaya")
	if nd == null or not nd.is_inside_tree() or not nd.visible or nd.get_parent() != hip_sock:
		want = false
	saya_ik.influence = move_toward(saya_ik.influence, 1.0 if want else 0.0, delta * (3.5 if want else 6.0))
	if saya_ik.influence <= 0.0: return
	# run after LocoPolish / foot IK, which are added to the skeleton later
	if saya_ik.get_index() != skeleton.get_child_count() - 1:
		skeleton.move_child(saya_ik, -1)
	saya_target.global_transform = Transform3D(Basis(), nd.global_transform * saya_grip)

var anatomy: Anatomy

## v0.18: breathing follows exertion (fast to rise, ~15 s to recover); the left
## hand closes around the saya while it holds it.
func update_anatomy(delta: float, exert_target: float) -> void:
	if anatomy == null: return
	var t := clampf(exert_target, 0.0, 1.0)
	var k := 0.5 if t > anatomy.exertion else 0.07
	anatomy.exertion = move_toward(anatomy.exertion, t, delta * k)
	anatomy.grip_l = saya_hand_weight()

func saya_hand_weight() -> float:
	return 0.0 if saya_ik == null else saya_ik.influence

# ---------------------------------------------------------------- reins
## v0.15: the seated clip is a car driver's ("Driving"): hands up on a wheel,
## which on horseback read as steering an invisible wheel. While riding, two
## arm IKs bring the fists down together above the pommel where a rider holds
## the reins; the hands keep the clip's closed grip and orientation.
var rein_ik := {}                 ## "l"/"r" -> SkeletonIK3D
var rein_target := {}             ## "l"/"r" -> Node3D (top level)
var _rein_hand := {}              ## "l"/"r" -> hand transform in rig space, seated clip
## fist centres in rig space (+X is the character's left), relative to the seat
const REIN_GRIP := {"l": Vector3(0.095, 0.69, 0.07), "r": Vector3(-0.095, 0.69, 0.07)}
## fist centre in hand-bone space (+Y runs toward the fingers)
const FIST := Vector3(0.0, 0.07, 0.02)

func _build_rein_ik() -> void:
	for side in ["l", "r"]:
		var t := Node3D.new()
		t.name = "ReinTarget_" + side
		t.top_level = true
		add_child(t)
		var k := SkeletonIK3D.new()
		k.name = "ReinIK_" + side
		k.root_bone = "upperarm_" + side
		k.tip_bone = "hand_" + side
		skeleton.add_child(k)
		k.override_tip_basis = true
		k.use_magnet = true
		# elbows at the rider's sides, a little back and down
		k.magnet = Vector3(0.42 if side == "l" else -0.42, 0.62, -0.32)
		k.max_iterations = 10
		k.target_node = k.get_path_to(t)
		k.influence = 0.0
		k.start()
		rein_ik[side] = k
		rein_target[side] = t

## Place both rein fists for this frame. `hold_l` / `hold_r`: whether that hand
## is on the reins (a drawn sword takes the right, a two-handed cut both).
## `give` moves the hands with the horse's head at speed (metres, rig space).
func update_reins(delta: float, hold_l: bool, hold_r: bool, give: Vector3) -> void:
	if saya_ik != null: saya_ik.influence = 0.0
	if _rein_hand.is_empty(): return
	for side in ["l", "r"]:
		var k: SkeletonIK3D = rein_ik.get(side)
		if k == null: continue
		var want := 1.0 if (hold_l if side == "l" else hold_r) else 0.0
		k.influence = move_toward(k.influence, want, delta * 5.0)
		var hand: Transform3D = _rein_hand[side]
		var p: Vector3 = REIN_GRIP[side] + give
		(rein_target[side] as Node3D).global_transform = global_transform * Transform3D(hand.basis, p - hand.basis * FIST)

func release_reins() -> void:
	for k in rein_ik.values():
		(k as SkeletonIK3D).influence = 0.0

## World positions of the two fists (where the reins end); a hand that has
## let go returns INF and its rein drops onto the horse's neck. The grip
## points are the IK targets themselves: bone poses read outside
## Skeleton3D.skeleton_updated do not include the IK yet.
func rein_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for side in ["l", "r"]:
		var k: SkeletonIK3D = rein_ik.get(side)
		if k != null and k.influence > 0.6:
			out.append(global_transform * (REIN_GRIP[side] as Vector3))
		else:
			out.append(Vector3.INF)
	return out

func reins_held(side: String) -> bool:
	var k: SkeletonIK3D = rein_ik.get(side)
	return k != null and k.influence > 0.5

## Evaluate a clip's first frame for a chain of bones without touching the live
## skeleton: rig-space transforms, keyed by bone index.
func _eval_clip(clip: String, bones: Array) -> Dictionary:
	var a: Animation = anim.get_animation(clip)
	var out := {}
	var skel_xf := global_transform.affine_inverse() * skeleton.global_transform if is_inside_tree() else Transform3D()
	for bn in bones:
		var b := skeleton.find_bone(String(bn))
		if b < 0: continue
		var chain: Array = []
		var c := b
		while c >= 0:
			chain.push_front(c)
			c = skeleton.get_bone_parent(c)
		var g := Transform3D()
		for i in chain:
			var rest := skeleton.get_bone_rest(i)
			var pos := rest.origin
			var rot := rest.basis.get_rotation_quaternion()
			var sc := rest.basis.get_scale()
			var path := NodePath("Skeleton3D:" + skeleton.get_bone_name(i))
			var tp := a.find_track(path, Animation.TYPE_POSITION_3D)
			var tr := a.find_track(path, Animation.TYPE_ROTATION_3D)
			if tp >= 0: pos = a.position_track_interpolate(tp, 0.0)
			if tr >= 0: rot = a.rotation_track_interpolate(tr, 0.0)
			g = g * Transform3D(Basis(rot).scaled(sc), pos)
		out[b] = skel_xf * g
	return out

## Straddle: turn the seated clip's thighs down and out around the barrel and
## send the shins to the stirrups, as model-space offsets on the leg layer.
## Also records where the pelvis sits so the player can be placed on the saddle.
func fit_rider(clip := "Driving") -> void:
	if _rider_ready or not has_clip(clip): return
	_rider_ready = true
	var names := ["pelvis", "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r",
		"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"]
	var ev := _eval_clip(clip, names)
	for side in ["l", "r"]:
		var hb := skeleton.find_bone("hand_" + side)
		if hb >= 0 and ev.has(hb): _rein_hand[side] = ev[hb]
	var pel := skeleton.find_bone("pelvis")
	if ev.has(pel): rider_pelvis = (ev[pel] as Transform3D).origin
	var skel_basis: Basis = (global_transform.affine_inverse() * skeleton.global_transform).basis if is_inside_tree() else Basis()
	var to_skel := skel_basis.inverse()
	var offs := {}
	for side in ["l", "r"]:
		var th := skeleton.find_bone("thigh_" + side)
		var ca := skeleton.find_bone("calf_" + side)
		var fo := skeleton.find_bone("foot_" + side)
		var ba := skeleton.find_bone("ball_" + side)
		if th < 0 or ca < 0 or fo < 0 or not ev.has(th) or not ev.has(ca) or not ev.has(fo): continue
		var H: Vector3 = (ev[th] as Transform3D).origin
		var K: Vector3 = (ev[ca] as Transform3D).origin
		var F: Vector3 = (ev[fo] as Transform3D).origin
		var s := 1.0 if H.x > 0.0 else -1.0          # +X is the character's left
		var l1 := H.distance_to(K)
		var l2 := K.distance_to(F)
		# knee forward-down-out round the barrel, foot back under it in the stirrup
		var want_k := H + Vector3(s * 0.23, -0.33, 0.27).normalized() * l1
		var want_f := Vector3(s * 0.36, rider_pelvis.y - 0.74, rider_pelvis.z + 0.06)
		var d1 := (K - H).normalized()
		var q1 := Quaternion(d1, (want_k - H).normalized())
		var K1 := H + (q1 * (K - H))
		var F1 := H + (q1 * (F - H))
		var d2 := (F1 - K1).normalized()
		var q2 := Quaternion(d2, (want_f - K1).normalized())
		offs[th] = Quaternion(to_skel * Basis(q1) * skel_basis)
		offs[ca] = Quaternion(to_skel * Basis(q2) * skel_basis)
		if ba >= 0 and ev.has(ba):
			# level the foot: toes forward and a touch down
			var B: Vector3 = (ev[ba] as Transform3D).origin
			var toe := (q2 * (q1 * (B - F))).normalized()
			var want_toe := Vector3(s * 0.25, -0.25, 1.0).normalized()
			offs[fo] = Quaternion(to_skel * Basis(Quaternion(toe, want_toe)) * skel_basis)
	legs.offsets = offs

## Arm mask for the upper layer: both arms, or only the sword arm (so the free
## arm keeps swinging with the run).
func set_layer_arms(both: bool) -> void:
	var m := {}
	for k in UPPER_MASK: m[k] = UPPER_MASK[k]
	if not both:
		for k in ["clavicle_l", "upperarm_l", "lowerarm_l", "hand_l"]: m.erase(k)
		m["spine_03"] = 0.25; m["spine_02"] = 0.1
	for i in skeleton.get_bone_count():
		var bn := skeleton.get_bone_name(i)
		for f in ["index", "middle", "ring", "pinky", "thumb"]:
			if bn.begins_with(f + "_") and (both or bn.ends_with("_r")): m[bn] = 1.0
	layer.set_mask(skeleton, m)

## Pose the upper layer from a library clip, frozen on `at` (or looping when at < 0).
func set_layer_clip(clip: String, at := -1.0, spd := 1.0) -> void:
	if not has_clip(clip): return
	layer.set_clip(anim.get_animation(clip), at)
	layer.speed = spd

## Place the right hand so the given weapon, currently parked somewhere on the
## body, would sit in the fist exactly as it does when drawn.
func reach_for(weapon_name: String) -> void:
	var nd: Node3D = _nodes.get(weapon_name)
	if nd == null: return
	ik_target.global_transform = nd.global_transform * Transform3D(GRIP_BASIS, grip_pos).affine_inverse()

## Where the hand has to be for the weapon to sit in its sheath/back mount.
func reach_for_mount(weapon_name: String) -> void:
	var sock_name := "hip"
	var sock: Node3D = hip_sock
	if weapon_name == "Nodachi": sock_name = "back"; sock = back_sock
	elif weapon_name == "Yari": sock_name = "back_pole"; sock = back_sock
	var xf: Transform3D = sock.global_transform * (_mount[sock_name] as Transform3D)
	ik_target.global_transform = xf * Transform3D(GRIP_BASIS, grip_pos).affine_inverse()

func weapon_mesh_name(id: String) -> String:
	match id:
		"katana": return "Katana"
		"nodachi": return "Nodachi"
		"yari": return "Yari"
	return ""

# ---------------------------------------------------------------- sockets
func _sock(bone: String) -> BoneAttachment3D:
	var b := BoneAttachment3D.new()
	b.name = "Sock_" + bone
	b.bone_name = bone
	skeleton.add_child(b)
	return b

func _to_bone(bone: String, model_xf: Transform3D) -> Transform3D:
	return skeleton.get_bone_global_rest(skeleton.find_bone(bone)).affine_inverse() * model_xf

## Basis whose +Y runs along `blade` and whose +Z (the edge) leans toward `edge`.
static func weapon_basis(blade: Vector3, edge: Vector3) -> Basis:
	var b := blade.normalized()
	var e := (edge - b * edge.dot(b)).normalized()
	return Basis(b.cross(e), b, e)

func _build_sockets() -> void:
	hand_sock = _sock("hand_r")
	hip_sock = _sock("pelvis")
	back_sock = _sock("spine_03")
	# Katana worn edge-up through the obi on the left hip, hilt forward, saya
	# trailing behind and a little down.  (Character faces +Z, so left is +X.)
	# v0.18: worn the way a samurai wore it (otoshi-zashi): the guard just in
	# front of the obi at the left of the belly, the hilt angled forward and in,
	# the saya passing out past the left hip and dropping ~21 deg behind. The
	# old mount sat 0.3 m in front of the outer hip, pointing straight back, so
	# the hilt jutted half a metre ahead and the swinging left arm passed
	# through the saya on every step.
	_mount["hip"] = _to_bone("pelvis", Transform3D(
		weapon_basis(Vector3(0.20, -0.36, -0.91).normalized(), Vector3.UP), Vector3(0.102, 1.032, 0.241)))
	# Short sword: nearer the centre and flatter, crossing behind the katana.
	_mount["hip2"] = _to_bone("pelvis", Transform3D(
		weapon_basis(Vector3(0.26, -0.26, -0.93).normalized(), Vector3.UP), Vector3(0.053, 1.034, 0.202)))
	# Long weapons ride diagonally across the back with the grip just over the
	# right shoulder, where the drawing hand reaches.  Positions are model space
	# (feet at 0, shoulders ~1.46 m); weapon origins are their grip points.
	# Nodachi: hilt above the right shoulder, saya tip behind the left knee.
	_mount["back"] = _to_bone("spine_03", Transform3D(
		weapon_basis(Vector3(0.50, -0.86, -0.07), Vector3(0, 0, -1)), Vector3(-0.22, 1.58, -0.24)))
	# Yari: butt behind the left hip, head up past the right shoulder.
	_mount["back_pole"] = _to_bone("spine_03", Transform3D(
		weapon_basis(Vector3(-0.36, 0.93, -0.07), Vector3(0, 0, -1)), Vector3(-0.22, 1.56, -0.23)))

func _load_weapons() -> void:
	var ps = load(WEAPON_PATH)
	if ps == null:
		push_error("PlayerRig: cannot load " + WEAPON_PATH)
		return
	var scn: Node = ps.instantiate()
	for c in scn.get_children():
		_nodes[String(c.name)] = c
	for k in _nodes:
		scn.remove_child(_nodes[k])
		# clear the scene owner first, or every weapon logs an
		# "owner 'weapons' inconsistent" warning as it moves to the socket
		_nodes[k].owner = null
		_nodes[k].visible = false
		hip_sock.add_child(_nodes[k])
	scn.queue_free()

# ---------------------------------------------------------------- weapons
func weapon_node(n: String) -> Node3D:
	return _nodes.get(n)

func _park(n: String, sock: Node, xf: Transform3D, show := true) -> void:
	var nd: Node3D = _nodes.get(n)
	if nd == null: return
	if nd.get_parent() != sock:
		nd.get_parent().remove_child(nd)
		sock.add_child(nd)
	nd.transform = xf
	nd.visible = show

func set_weapon(id: String, is_drawn := false) -> void:
	weapon = id
	drawn = is_drawn
	refresh_weapons()

func set_drawn(v: bool) -> void:
	drawn = v
	refresh_weapons()

## Put every weapon mesh where the current weapon/drawn state says it goes.
func refresh_weapons() -> void:
	for k in _nodes: _nodes[k].visible = false
	var hand_xf := Transform3D(GRIP_BASIS, grip_pos)
	# The wakizashi is part of the dress: always in the belt unless the katana is out on its own.
	_park("Wakizashi", hip_sock, _mount["hip2"])
	_park("WakizashiSaya", hip_sock, _mount["hip2"])
	match weapon:
		"katana":
			_park("KatanaSaya", hip_sock, _mount["hip"])
			if drawn: _park("Katana", hand_sock, hand_xf)
			else: _park("Katana", hip_sock, _mount["hip"])
		"nodachi":
			_park("KatanaSaya", hip_sock, _mount["hip"], false)
			_park("NodachiSaya", back_sock, _mount["back"])
			if drawn: _park("Nodachi", hand_sock, hand_xf)
			else: _park("Nodachi", back_sock, _mount["back"])
		"yari":
			if drawn: _park("Yari", hand_sock, Transform3D(GRIP_BASIS, Vector3(-0.035, 0.085, 0.0)))
			else: _park("Yari", back_sock, _mount["back_pole"])
			_park("KatanaSaya", hip_sock, _mount["hip"])
			_park("Katana", hip_sock, _mount["hip"])
		_:
			# Bare hands: the katana stays sheathed at the hip.
			_park("KatanaSaya", hip_sock, _mount["hip"])
			_park("Katana", hip_sock, _mount["hip"])

## Point in the world where the blade tip of the drawn weapon is (for trails).
func blade_node() -> Node3D:
	match weapon:
		"katana": return _nodes.get("Katana")
		"nodachi": return _nodes.get("Nodachi")
		"yari": return _nodes.get("Yari")
	return null

## Blade length of the current weapon mesh along its +Y axis.
func blade_length() -> float:
	var nd := blade_node()
	if nd == null: return 0.0
	var best := 0.0
	for c in nd.find_children("*", "MeshInstance3D", true, false) + ([nd] if nd is MeshInstance3D else []):
		var mi := c as MeshInstance3D
		var ab := mi.get_aabb()
		best = maxf(best, (mi.transform * ab.end).y if mi != nd else ab.end.y)
	return best

# ---------------------------------------------------------------- animation
func has_clip(c: String) -> bool:
	return anim != null and anim.has_animation(c)

func clip_len(c: String) -> float:
	return anim.get_animation(c).length if has_clip(c) else 0.0

func current() -> String:
	return _cur

## Cross-fade to a clip.  Re-requesting the running clip only updates its speed.
func play(clip: String, blend := 0.2, speed := 1.0, from := 0.0, restart := false) -> void:
	if not has_clip(clip):
		push_warning("PlayerRig: missing clip " + clip)
		return
	anim.speed_scale = speed
	if clip == _cur and not restart:
		return
	_cur = clip
	anim.play(clip, blend, 1.0)
	if from > 0.0: anim.seek(from, true)

func set_speed(speed: float) -> void:
	if anim != null: anim.speed_scale = speed

func position_in_clip() -> float:
	return anim.current_animation_position if anim != null and anim.is_playing() else 0.0

func finished() -> bool:
	return anim == null or not anim.is_playing()

## v0.22: ground contact. grounded = on foot and standing on the floor (not in
## the air, rolling, swimming, riding or dead); the IK fades in over ~0.15 s.
func update_ground(dt: float, grounded: bool) -> void:
	if foot_ik == null: return
	foot_ik.set_grounded(grounded)
	foot_ik.influence = move_toward(foot_ik.influence, 1.0 if grounded else 0.0, dt * 7.0)
