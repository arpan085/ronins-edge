class_name UBCDriver
extends AnimDriver
## v0.18: enemies on the same realistic body as the player.
##
## The old enemies were low-poly procedural meshes on their own 38-bone rig.
## This driver puts every soldier on Ronin.glb (Universal Base Character,
## 65 bones) with the player's Universal Animation Library, dressed per type
## by CharDress, while keeping AnimDriver's public API so EnemyBase and the AI
## do not change. The old per-enemy clip names ("Attack", "Hit_L", "Death_B",
## "Knocked" ...) are mapped onto library clips by UBCRig below.

const CHAR_PATH := "res://assets/char/Ronin.glb"
const LIB_PATH := "res://assets/anim/ronin_anims.res"
const WEAPON_PATH := "res://assets/weapons/weapons.glb"

## ground speed (m/s) each gait clip was authored at (same table as Player)
const CLIP_SPEED := {"Walk": 1.03, "Jog_Fwd": 5.7, "Sprint": 8.8, "K_Strafe_L": 3.2,
	"K_Strafe_R": 3.2, "K_Walk_Back": 1.35}

## enemy clip -> [library clip, playback speed, start (s), end (s, 0 = clip end)]
const COMMON := {
	"Alert": ["Hit_Head", 0.55, 0.0, 0.0],
	"Block": ["K_Block", 1.0, 0.0, 0.0],
	"BackStep": ["K_Dodge_B", 1.0, 0.0, 0.0],
	"Hit_F": ["Hit_Chest", 1.0, 0.0, 0.0],
	"Hit_B": ["K_Hit_B", 1.0, 0.0, 0.0],
	"Hit_L": ["Hit_Head", 1.0, 0.0, 0.0],
	"Hit_R": ["K_Hit_A", 1.0, 0.0, 0.0],
	"HitHeavy_F": ["K_Hit_B", 0.9, 0.0, 0.0],
	"HitHeavy_B": ["K_Hit_B", 0.9, 0.0, 0.0],
	"HitHeavy_L": ["K_Hit_A", 0.85, 0.0, 0.0],
	"HitHeavy_R": ["K_Hit_A", 0.85, 0.0, 0.0],
	"Flinch": ["K_Hit_A", 1.2, 0.0, 0.0],
	"Stagger_A": ["K_Hit_B", 0.55, 0.0, 0.0],
	"Stagger_B": ["K_Hit_A", 0.45, 0.0, 0.0],
	"Intimidate": ["K_2H_Spin", 0.8, 0.0, 0.0],
	"EnterCombat": ["Sword_Block", 0.8, 0.0, 0.0],
	"PhaseTransition": ["K_2H_Spin", 0.7, 0.0, 0.0],
}
## looping / held states for travel()
const STATES := {
	"Move": "", "Investigate": "Walk", "IdleBoss": "Idle_FoldArms",
	"HoldDraw": "Idle", "DeathA": "Death01", "DeathB": "K_Death_A",
	"Knocked": "Hit_Knockback", "GetUp": "LayToIdle", "Defeat": "Fixing_Kneeling",
}
## Attacks: [library clip, from, hold, impact, end, recovery clip] in clip
## seconds. The wind-up (from -> hold) is stretched to the soldier's windup
## time so the tell reads; the strike itself (hold -> impact) runs at authored
## speed, so the blade visibly lands on the frame the hit is scored.
const ATTACKS := {
	"ashigaru": {"Attack": ["K_2H_Stab", 0.10, 0.24, 0.34, 1.05, ""],
		"Sweep": ["K_2H_Spin", 0.30, 0.56, 0.66, 1.90, ""]},
	"captain": {"Attack1": ["Sword_Regular_A", 0.0, 0.12, 0.21, 0.43, "Sword_Regular_A_Rec"],
		"Attack2": ["K_1H_Stab", 0.10, 0.26, 0.36, 0.95, ""],
		"Attack3": ["K_2H_Spin", 0.30, 0.56, 0.66, 1.90, ""]},
}
const STRIKE_RATE := 1.15

## per-type extras: attack clips, combat idle, weapon, hand
const KINDS := {
	"ashigaru": {"Attack": ["K_2H_Stab", 1.0, 0.0, 0.0], "Sweep": ["K_2H_Slice", 1.0, 0.0, 0.0],
		"_idle_combat": "K_2H_Idle", "_weapon": "Yari"},
	"archer": {"Shoot": ["Idle", 1.0, 0.0, 0.0], "Nock": ["Idle", 1.0, 0.0, 0.0],
		"AimIn": ["Idle", 1.0, 0.0, 0.0], "_idle_combat": "Idle", "_weapon": "bow"},
	"captain": {"Attack1": ["Sword_Regular_A", 1.0, 0.0, 0.0], "Attack2": ["Sword_Regular_B", 1.0, 0.0, 0.0],
		"Attack3": ["K_2H_Slice", 1.0, 0.0, 0.0], "Block": ["Sword_Block", 1.0, 0.0, 0.0],
		"Defeat": ["Fixing_Kneeling", 1.0, 0.0, 0.0], "_idle_combat": "Sword_Idle", "_weapon": "Katana",
		"_idle_boss": "Idle_FoldArms"},
}

## weapon space -> hand_r (same grip as the player's rig)
const GRIP_BASIS := Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))
const GRIP_POS := Vector3(-0.035, 0.085, 0.0)

var ubc: UBCRig
var anatomy: Anatomy
var weapon_node: Node3D
var _gait := 0
var _bow_hand: BoneAttachment3D
var _bow_back: BoneAttachment3D
var _bow_back_xf := Transform3D()
var _bow_in_hand := false
var _loco := ""

func build(host: Node3D, glb: String, character: String, is_player := false) -> bool:
	_host = host
	kind = character
	var ps: PackedScene = load(CHAR_PATH)
	if ps == null: return false
	model_root = Node3D.new()
	model_root.name = "Model"
	host.add_child(model_root)
	var m: Node3D = ps.instantiate()
	m.name = "Body"
	CharDress.dress(m, character)
	model_root.add_child(m)
	_vary(m, character)
	if not vary_enabled and beard_force != "": _beard(m, character, null)
	skeleton = _find(m, "Skeleton3D") as Skeleton3D
	if skeleton == null: return false
	anim_player = AnimationPlayer.new()
	anim_player.name = "Anim"
	m.add_child(anim_player)
	var lib: AnimationLibrary = load(LIB_PATH)
	GroundFix.apply(lib, skeleton)    # v0.22: UAL clips stood 17 cm low
	anim_player.add_animation_library("", lib)
	anim_player.root_node = anim_player.get_path_to(skeleton.get_parent())
	anim_player.playback_default_blend_time = 0.0
	ubc = UBCRig.new()
	ubc.name = "UBCRig"
	add_child(ubc)
	ubc.init(anim_player, skeleton, character, _merged_map(character))
	rig = ubc
	anatomy = Anatomy.new()
	anatomy.name = "Anatomy"
	skeleton.add_child(anatomy)
	look = LookAtLayer.new()
	look.name = "LookAt"
	skeleton.add_child(look)
	breath = BreathFX.attach(skeleton, anatomy, self)
	# v0.22: feet planted on slopes; footfalls heard up close
	foot_ik = FootIK.new()
	foot_ik.name = "FootIK"
	skeleton.add_child(foot_ik)
	foot_ik.footfall.connect(_on_footfall)
	if gear_enabled:
		_attach_weapon(character)
		_attach_gear(character)
	if character == "archer": _archer_build()
	if anatomy != null:
		var wn: String = _kind_opt("_weapon", "")
		anatomy.grip_r = 1.0 if wn == "Yari" or wn == "Katana" else 0.0
		anatomy.grip_l = 1.0 if wn == "bow" else 0.0
	speed_walk = 1.4
	speed_jog = 3.6
	speed_sprint = 6.0
	speed_back_walk = 1.2
	speed_back_jog = 2.0
	speed_side = 1.6
	speed_side_fast = 2.6
	ubc.play_loop("Idle", 0.0, 1.0)
	_lod_setup()
	return true

func _merged_map(character: String) -> Dictionary:
	var mp := COMMON.duplicate()
	var k: Dictionary = KINDS.get(character, {})
	for key in k:
		if not String(key).begins_with("_"): mp[key] = k[key]
	return mp

func _kind_opt(key: String, def = "") -> Variant:
	return (KINDS.get(kind, {}) as Dictionary).get(key, def)

func _attach_weapon(character: String) -> void:
	var wname: String = _kind_opt("_weapon", "")
	if wname == "": return
	var hand_i := skeleton.find_bone("hand_l" if wname == "bow" else "hand_r")
	if hand_i < 0: return
	var sock := BoneAttachment3D.new()
	sock.name = "HandSock"
	sock.bone_name = skeleton.get_bone_name(hand_i)
	skeleton.add_child(sock)
	if wname == "bow":
		# carried slung across the back; it moves to the left fist to shoot
		weapon_node = EnemyGear.make_bow()
		_bow_hand = sock
		var bi := skeleton.find_bone("spine_03")
		_bow_back = BoneAttachment3D.new()
		_bow_back.name = "BowBack"
		_bow_back.bone_name = "spine_03"
		skeleton.add_child(_bow_back)
		var y := Vector3(0.45, 1.0, 0.0).normalized()
		var z := Vector3(0, 0, -1)
		var mxf := Transform3D(Basis(y.cross(z), y, z), skeleton.get_bone_global_rest(bi).origin + Vector3(-0.08, -0.30, -0.19))
		_bow_back_xf = skeleton.get_bone_global_rest(bi).affine_inverse() * mxf
		_bow_back.add_child(weapon_node)
		weapon_node.transform = _bow_back_xf
		return
	var ws: PackedScene = load(WEAPON_PATH)
	if ws == null: return
	var all: Node = ws.instantiate()
	var w: Node3D = all.get_node_or_null(wname)
	if w == null:
		all.free()
		return
	all.remove_child(w)
	all.free()
	w.name = "Weapon" + wname
	sock.add_child(w)
	w.transform = Transform3D(GRIP_BASIS, GRIP_POS)
	weapon_node = w
	_hand_sock = sock
	_build_carry(wname)
	_set_drawn(false)

## rigid kit placed in bind-pose model space, then parented to its bone
func _prop(bone: String, node: Node3D, model_xf: Transform3D) -> void:
	var i := skeleton.find_bone(bone)
	if i < 0: return
	var sock := BoneAttachment3D.new()
	sock.name = "Sock_" + bone
	sock.bone_name = bone
	skeleton.add_child(sock)
	sock.add_child(node)
	node.transform = skeleton.get_bone_global_rest(i).affine_inverse() * model_xf

func _head_top() -> Vector3:
	var i := skeleton.find_bone("Head")
	return skeleton.get_bone_global_rest(i).origin if i >= 0 else Vector3(0, 1.6, 0)

func _attach_gear(character: String) -> void:
	var h := _head_top()
	match character:
		"ashigaru":
			_prop("Head", EnemyGear.make_jingasa(), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-6.0)), h + Vector3(0, 0.155, 0.005)))
			var b := skeleton.get_bone_global_rest(skeleton.find_bone("spine_03")).origin if skeleton.find_bone("spine_03") >= 0 else Vector3(0, 1.3, 0)
			_prop("spine_03", EnemyGear.make_sashimono(), Transform3D(Basis(), b + Vector3(0, -0.18, -0.27)))
		"archer":
			var p := skeleton.get_bone_global_rest(skeleton.find_bone("pelvis")).origin if skeleton.find_bone("pelvis") >= 0 else Vector3(0, 0.95, 0)
			_prop("pelvis", EnemyGear.make_quiver(), Transform3D(Basis(Vector3.FORWARD, deg_to_rad(-12.0)), p + Vector3(-0.2, -0.02, -0.06)))
		"captain":
			_prop("Head", EnemyGear.make_kabuto(), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-4.0)), h + Vector3(0, 0.135, -0.012)))

func ok() -> bool:
	return ubc != null

## Gait selection from the actual ground velocity with the player's hysteresis
## and stride-matched playback rate, so feet do not skate.
func tick(delta: float, vel: Vector3, want_yaw: float, has_input: bool,
		grounded := true, blocking := false, allow_loco := true) -> float:
	if not ok(): return want_yaw
	_lod_tick(delta)
	_grounded = grounded
	var exert := 0.0
	var hv := Vector3(vel.x, 0, vel.z)
	var sp := hv.length()
	_step_speed = sp
	if foot_ik != null:
		foot_ik.set_grounded(grounded)
		var ik_on := lod_level < 1 and _alive_pose()
		if foot_ik.active != ik_on: foot_ik.active = ik_on
	if sp > 3.0: exert = 0.6
	if anatomy != null:
		var k := 0.5 if exert > anatomy.exertion else 0.07
		anatomy.exertion = move_toward(anatomy.exertion, exert, delta * k)
	ubc.tick(delta)
	if _bow_hand != null:
		var aim: bool = ubc.loco_state() == "HoldDraw" or _shoot_t >= 0.0
		if aim != _bow_in_hand:
			_bow_in_hand = aim
			weapon_node.get_parent().remove_child(weapon_node)
			if aim:
				_bow_hand.add_child(weapon_node)
				weapon_node.transform = EnemyGear.BOW_GRIP
			else:
				_bow_back.add_child(weapon_node)
				weapon_node.transform = _bow_back_xf
	if _arch_ok: _archer_tick(delta, sp)
	if not allow_loco or ubc.busy(): return want_yaw
	var combat: bool = _host != null and _host.get("in_combat") == true
	if combat != _drawn and not ubc.busy(): _set_drawn(combat)
	var fwd := Vector3(sin(_host.rotation.y), 0, cos(_host.rotation.y))
	var right := Vector3(-fwd.z, 0, fwd.x)
	var f := hv.dot(fwd)
	var s := hv.dot(right)
	if sp > 0.35 and f < -0.45 * sp:
		ubc.play_loop("K_Walk_Back", 0.25, clampf(sp / 1.35, 0.6, 1.6))
		_gait = 1
		return want_yaw
	if sp > 0.35 and absf(s) > 0.7 * sp and combat:
		var c := "K_Strafe_R" if s > 0.0 else "K_Strafe_L"
		ubc.play_loop(c, 0.25, clampf(sp / 3.2, 0.5, 1.5))
		_gait = 1
		return want_yaw
	match _gait:
		0: if sp > 0.35: _gait = 1
		1:
			if sp < 0.18: _gait = 0
			elif sp > 2.7: _gait = 2
		2:
			if sp < 2.3: _gait = 1
			elif sp > 6.7: _gait = 3
		3: if sp < 6.2: _gait = 2
	match _gait:
		0:
			var idle: String = ubc.state_clip() if ubc.state_clip() != "" else (String(_kind_opt("_idle_combat", "Idle")) if combat else "Idle")
			ubc.play_loop(idle, 0.3, 1.0)
		1: ubc.play_loop("Walk", 0.25, clampf(sp / 1.03, 0.75, 1.8))
		2: ubc.play_loop("Jog_Fwd", 0.22, clampf(sp / 5.7, 0.62, 1.2))
		3: ubc.play_loop("Sprint", 0.22, clampf(sp / 8.8, 0.8, 1.2))
	return want_yaw

func turning() -> bool:
	return false

func action(clip: String, speed := 1.0, xfade := 0.07) -> bool:
	if not ok(): return false
	if _arch_ok and clip == "Shoot":
		_shoot_t = 0.0
		_shoot_wu = 0.6
		if _host != null and _host.get("windup") != null:
			var mult = _host.get("_windup_mult")
			_shoot_wu = maxf(0.25, float(_host.get("windup")) * (float(mult) if mult != null else 1.0))
		return true
	var at: Dictionary = ATTACKS.get(kind, {})
	if at.has(clip):
		_set_drawn(true)
		var e: Array = at[clip]
		var wu := 0.5
		if _host != null and _host.get("windup") != null:
			var mult = _host.get("_windup_mult")
			wu = float(_host.get("windup")) * (float(mult) if mult != null else 1.0)
		var t_strike: float = (float(e[3]) - float(e[2])) / STRIKE_RATE
		var r1: float = clampf((float(e[2]) - float(e[1])) / maxf(wu - t_strike, 0.08), 0.25, 2.5)
		return ubc.play_attack(clip, String(e[0]), float(e[1]), float(e[2]), r1, STRIKE_RATE, float(e[4]), String(e[5]), xfade)
	return ubc.play_action(clip, xfade, speed)

## clip-time of the scored hit for an attack (tests / tuning)
func impact_time(clip: String) -> float:
	var at: Dictionary = ATTACKS.get(kind, {})
	return float((at[clip] as Array)[3]) if at.has(clip) else -1.0

# ---------------------------------------------------------------- carry
## Out of a fight the captain's katana is in its saya on the left hip and the
## ashigaru's yari rides across his back; both come to hand when he engages.
var _drawn := true
var _carry_sock: BoneAttachment3D
var _carry_xf := Transform3D()
var _hand_sock: BoneAttachment3D

func _set_drawn(v: bool) -> void:
	if v == _drawn or weapon_node == null or _carry_sock == null or _hand_sock == null: return
	_drawn = v
	if anatomy != null: anatomy.grip_r = 1.0 if v else 0.0
	weapon_node.get_parent().remove_child(weapon_node)
	if v:
		_hand_sock.add_child(weapon_node)
		weapon_node.transform = Transform3D(GRIP_BASIS, GRIP_POS)
	else:
		_carry_sock.add_child(weapon_node)
		weapon_node.transform = _carry_xf

func _build_carry(wname: String) -> void:
	var bone := "pelvis" if wname == "Katana" else "spine_03"
	var bi := skeleton.find_bone(bone)
	if bi < 0: return
	_carry_sock = BoneAttachment3D.new()
	_carry_sock.name = "CarrySock"
	_carry_sock.bone_name = bone
	skeleton.add_child(_carry_sock)
	var mxf: Transform3D
	if wname == "Katana":
		mxf = Transform3D(PlayerRig.weapon_basis(Vector3(0.20, -0.36, -0.91).normalized(), Vector3.UP), Vector3(0.102, 1.032, 0.241))
	else:
		mxf = Transform3D(PlayerRig.weapon_basis(Vector3(-0.36, 0.93, -0.07), Vector3(0, 0, -1)), Vector3(-0.22, 1.56, -0.23))
	_carry_xf = skeleton.get_bone_global_rest(bi).affine_inverse() * mxf
	if wname == "Katana":
		var ws: PackedScene = load(WEAPON_PATH)
		var all: Node = ws.instantiate()
		var saya: Node3D = all.get_node_or_null("KatanaSaya")
		if saya != null:
			all.remove_child(saya)
			_carry_sock.add_child(saya)
			saya.transform = _carry_xf
		all.free()

func death(variant := -1) -> void:
	if not ok(): return
	if breath != null: breath.stop()
	if foot_ik != null: foot_ik.active = false
	var v: int = variant if variant >= 0 else (0 if randf() < 0.5 else 1)
	ubc.abort_action()
	ubc.abort_reaction()
	ubc.travel("DeathA" if v == 0 else "DeathB")

func consume_root_motion(warp := 1.0) -> Vector3:
	return Vector3.ZERO

func authored_distance(clip: String) -> float:
	return 0.0

# ===================================================================== variety
## v0.18: no two soldiers alike. Each body gets its own height (+-4.5 %,
## captains a little taller), skin tone, and a different dye lot for the robe
## (value +-10 %, hue +-0.02). Seeded per instance; set variety_seed for a
## repeatable look (EnemyLab uses it for side-by-side renders).
var variety_seed := 0
var height_scale := 1.0
static var vary_enabled := true      ## false: every soldier at the base look
static var vary_seed_base := 0       ## non-zero: repeatable variety (EnemyLab)
static var _vary_n := 0

func _vary(body: Node3D, character: String) -> void:
	if not vary_enabled: return
	var rng := RandomNumberGenerator.new()
	if variety_seed != 0: rng.seed = variety_seed
	elif vary_seed_base != 0:
		rng.seed = vary_seed_base + _vary_n * 7919
		_vary_n += 1
	else: rng.randomize()
	height_scale = rng.randf_range(1.0, 1.06) if character == "captain" else rng.randf_range(0.955, 1.045)
	model_root.scale = Vector3.ONE * height_scale
	var tone := rng.randf_range(-1.0, 1.0)
	var lum := rng.randf_range(0.9, 1.05)
	var skin := Color(lum * (1.0 + 0.045 * tone), lum * (1.0 + 0.01 * tone), lum * (1.0 - 0.04 * tone))
	var dye_v := rng.randf_range(0.9, 1.1)
	var dye_s := rng.randf_range(0.88, 1.1)
	var dye_h := rng.randf_range(-0.02, 0.02)
	var made := {}
	for mi in _meshes(body):
		for si in mi.get_surface_override_material_count():
			var mat := mi.get_surface_override_material(si)
			if mat == null or not (mat is StandardMaterial3D): continue
			if not made.has(mat):
				var nm := String(mat.resource_name)
				var src := mat as StandardMaterial3D
				var c: Color = CharWet.dry_albedo(src)
				if nm.find("Peasant") >= 0:
					c = Color.from_hsv(fposmod(c.h + dye_h, 1.0), clampf(c.s * dye_s, 0.0, 1.0),
						clampf(c.v * dye_v, 0.0, 1.0), c.a)
				elif nm.find("Male") >= 0:
					c = Color(c.r * skin.r, c.g * skin.g, c.b * skin.b, c.a)
				else:
					made[mat] = mat
					continue
				var d: StandardMaterial3D = CharWet.dry_copy(src)
				d.albedo_color = c
				made[mat] = d
				CharWet.track(d, "cloth" if nm.find("Peasant") >= 0 else "skin")
			if made[mat] != mat: mi.set_surface_override_material(si, made[mat])
	_beard(body, character, rng)

## v0.19 facial hair: [style, chance] per soldier type (see FacialHair.gd)
const BEARDS := {
	"ashigaru": [["none", 0.3], ["stubble", 0.3], ["moustache", 0.15], ["droop", 0.1], ["goatee", 0.1], ["beard", 0.05]],
	"archer": [["none", 0.35], ["stubble", 0.3], ["moustache", 0.15], ["goatee", 0.1], ["beard", 0.1]],
	"captain": [["droop", 0.3], ["beard", 0.3], ["goatee", 0.25], ["moustache", 0.15]],
}
## lab override: every soldier gets this style ("" = random per soldier)
static var beard_force := ""
## lab switch: no weapon, hat or banner (face close-ups)
static var gear_enabled := true
## perf test switch (tests/LODPerf): false keeps every soldier at full detail
static var lod_enabled := true
var beard_style := "none"
var breath: BreathFX            ## v0.21: visible breath in the cold
var _step_speed := 0.0

func _beard(body: Node3D, character: String, rng: RandomNumberGenerator) -> void:
	var style := beard_force
	var col := Color(0.075, 0.062, 0.055)
	if style == "":
		if rng == null: return
		var r := rng.randf()
		style = "none"
		for e in BEARDS.get(character, BEARDS["ashigaru"]):
			r -= float(e[1])
			if r <= 0.0:
				style = String(e[0]); break
		col = Color(0.06, 0.05, 0.045).lerp(Color(0.14, 0.11, 0.085), rng.randf())
		# some captains have gone grey
		if character == "captain" and rng.randf() < 0.35: col = col.lerp(Color(0.44, 0.42, 0.40), 0.55)
	beard_style = style
	FacialHair.grow(body, style, col)

static func _meshes(n: Node, out: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	if n is MeshInstance3D: out.append(n)
	for ch in n.get_children(): _meshes(ch, out)
	return out

# ========================================================================= LOD
## v0.18: distance LOD for the full-body soldiers. A UBC enemy costs an
## AnimationPlayer over a 121-clip library, two skeleton modifiers (Anatomy,
## LookAt) and a dressed body of ~20 skinned surfaces plus gear. Near: all of
## it every frame. Mid (>15 m): unchanged motion, the tiniest parts (eyes,
## brows, rivets, cords) are gone (visibility ranges, below). Far (>32 m):
## the animation steps at 12 Hz, Anatomy and LookAt are off. Distant (>55 m)
## or off screen: 5 Hz, small parts stop casting shadows. Combat hits are
## scored from the host transform, never from bones, so LOD cannot change a
## fight; only what you see.
const LOD_DIST := [15.0, 32.0, 55.0]
const LOD_STEP := [0.0, 0.0, 1.0 / 12.0, 1.0 / 5.0]
var lod_level := -1
var _lod_t := 0.0
var _anim_acc := 0.0
var _lod_cam: Camera3D
var _lod_notifier: VisibleOnScreenNotifier3D
var _lod_parts: Array = []      ## [mesh, size, cast_shadow]
var _lod_headless := false

func _lod_setup() -> void:
	_lod_headless = DisplayServer.get_name() == "headless"
	_lod_notifier = VisibleOnScreenNotifier3D.new()
	_lod_notifier.name = "LODNotifier"
	_lod_notifier.aabb = AABB(Vector3(-1.0, -0.1, -1.0), Vector3(2.0, 2.6, 2.0))
	model_root.add_child(_lod_notifier)
	_lod_notifier.screen_entered.connect(func(): _lod_t = 0.0)
	for mi in _meshes(model_root):
		if mi.mesh == null: continue
		var sz: Vector3 = mi.mesh.get_aabb().size * mi.transform.basis.get_scale()
		var big := maxf(sz.x, maxf(sz.y, sz.z))
		if big < 0.10:
			mi.visibility_range_end = 20.0
			mi.visibility_range_end_margin = 2.0
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif big < 0.30:
			mi.visibility_range_end = 40.0
			mi.visibility_range_end_margin = 3.0
		_lod_parts.append([mi, big, mi.cast_shadow])
	_lod_apply(0)

func _lod_tick(delta: float) -> void:
	if not lod_enabled:
		if lod_level != 0: _lod_apply(0)
		return
	_lod_t -= delta
	if _lod_t <= 0.0:
		_lod_t = 0.25
		var lv := _lod_eval()
		if lv != lod_level: _lod_apply(lv)
	if lod_level >= 2 and anim_player != null:
		_anim_acc += delta
		if _anim_acc >= LOD_STEP[lod_level]:
			anim_player.advance(_anim_acc)
			_anim_acc = 0.0

func _lod_eval() -> int:
	if _host == null or not _host.is_inside_tree(): return 0
	if _lod_cam == null or not is_instance_valid(_lod_cam):
		_lod_cam = _host.get_viewport().get_camera_3d()
	if _lod_cam == null: return 0
	var d := _host.global_position.distance_to(_lod_cam.global_position)
	var lv := 0
	for i in LOD_DIST.size():
		if d > LOD_DIST[i]: lv = i + 1
	if not _lod_headless and _lod_notifier != null and not _lod_notifier.is_on_screen():
		lv = 3
	return lv

func _lod_apply(lv: int) -> void:
	lod_level = lv
	if anim_player != null:
		if lv >= 2:
			anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		elif anim_player.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
			if _anim_acc > 0.0: anim_player.advance(_anim_acc)
			_anim_acc = 0.0
			anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	if anatomy != null: anatomy.active = lv < 2
	if look != null: look.active = lv < 2
	for p in _lod_parts:
		var mi: MeshInstance3D = p[0]
		if not is_instance_valid(mi): continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if (lv >= 3 and p[1] < 0.6) else p[2]

# ====================================================================== archer
## v0.18: a real draw instead of a borrowed spell clip. Side-on stance (left
## shoulder to the target), bow arm straight with the thumb up so the yumi
## stands vertical, the string drawn to the jaw by an arm IK, the arrow nocked
## along the line of sight; release snaps the string and the hand flies back.
var _arch_ok := false
var _ik_l: SkeletonIK3D
var _ik_r: SkeletonIK3D
var _tg_l: Node3D
var _tg_r: Node3D
var _arrow: Node3D
var _str_a: MeshInstance3D
var _str_b: MeshInstance3D
var _aim_w := 0.0
var _draw := 0.0
var _shoot_t := -1.0
var _shoot_wu := 0.6
var _look_p := Vector3.ZERO
var _looking := false
const AIM_TURN := -72.0      ## body yaw (deg) when side-on

func look_at_point(p: Vector3) -> void:
	_look_p = p
	_looking = true
	super.look_at_point(p)

func look_clear() -> void:
	_looking = false
	super.look_clear()

func _arm_ik(root_b: String, tip_b: String, tgt: Node3D) -> SkeletonIK3D:
	var ik := SkeletonIK3D.new()
	ik.name = "IK_" + tip_b
	ik.root_bone = root_b
	ik.tip_bone = tip_b
	skeleton.add_child(ik)
	ik.use_magnet = true
	ik.max_iterations = 10
	ik.target_node = ik.get_path_to(tgt)
	ik.influence = 0.0
	ik.start()
	return ik

func _archer_build() -> void:
	if skeleton.find_bone("upperarm_l") < 0 or weapon_node == null: return
	_tg_l = Node3D.new(); _tg_l.name = "BowHandTarget"; _tg_l.top_level = true; add_child(_tg_l)
	_tg_r = Node3D.new(); _tg_r.name = "DrawHandTarget"; _tg_r.top_level = true; add_child(_tg_r)
	_ik_l = _arm_ik("upperarm_l", "hand_l", _tg_l)
	_ik_l.override_tip_basis = true
	_ik_r = _arm_ik("upperarm_r", "hand_r", _tg_r)
	_ik_r.override_tip_basis = false
	_arrow = EnemyGear.make_arrow()
	_arrow.top_level = true
	_arrow.visible = false
	add_child(_arrow)
	var smat: Material = EnemyGear.cloth("hessian_380", Color(0.85, 0.82, 0.74), 0.02)
	_str_a = EnemyGear.make_rod(0.0018, smat); _str_a.top_level = true; _str_a.visible = false; add_child(_str_a)
	_str_b = EnemyGear.make_rod(0.0018, smat); _str_b.top_level = true; _str_b.visible = false; add_child(_str_b)
	_arch_ok = true

func _bone_w(b: String) -> Vector3:
	var i := skeleton.find_bone(b)
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin if i >= 0 else _host.global_position

func _archer_tick(delta: float, speed := 0.0) -> void:
	# a drawn bow is held standing; on the move he carries it low and faces his way
	var aiming: bool = (ubc.loco_state() == "HoldDraw" and speed < 0.7) or _shoot_t >= 0.0
	if not _alive_pose(): aiming = false
	_aim_w = move_toward(_aim_w, 1.0 if aiming else 0.0, delta * 3.5)
	var w := smoothstep(0.0, 1.0, _aim_w)
	model_root.rotation.y = deg_to_rad(AIM_TURN) * w
	# draw / release timeline
	var follow := 0.0
	if _shoot_t >= 0.0:
		_shoot_t += delta
		if _shoot_t < _shoot_wu:
			_draw = smoothstep(0.0, maxf(_shoot_wu - 0.12, 0.1), _shoot_t)
		else:
			var after := _shoot_t - _shoot_wu
			_draw = 0.0
			follow = clampf(1.0 - after / 0.45, 0.0, 1.0)
			if after > 0.9: _shoot_t = -1.0
	else:
		_draw = move_toward(_draw, 0.35 if aiming else 0.0, delta * 1.5)
	var released := _shoot_t >= _shoot_wu
	_ik_l.influence = w
	_ik_r.influence = w
	if w <= 0.001:
		_arrow.visible = false
		_str_a.visible = false
		_str_b.visible = false
		var st: Node3D = weapon_node.get_node_or_null("String")
		if st != null: st.visible = true
		return
	var fwd: Vector3 = _host.global_transform.basis.z.normalized()
	var aim := fwd
	if _looking:
		var to := _look_p - _bone_w("Head")
		if to.length() > 0.5: aim = to.normalized()
	var up := Vector3.UP
	var side := aim.cross(up).normalized()      # the face's right when looking down the arrow
	var head := _bone_w("Head")
	var anchor := head + side * 0.075 - up * 0.075 - aim * 0.02
	var grip := anchor + aim * 0.66
	var sh_l := _bone_w("upperarm_l")
	if grip.distance_to(sh_l) > 0.64: grip = sh_l + (grip - sh_l).normalized() * 0.64
	var lb := Basis(side, aim, side.cross(aim)).orthonormalized()
	_tg_l.global_transform = Transform3D(lb, grip)
	var nock := grip - aim * 0.08
	var hand_r := nock.lerp(anchor, _draw)
	if released: hand_r = anchor - aim * 0.13 * follow + side * 0.06 * follow
	_tg_r.global_position = hand_r
	var inv := skeleton.global_transform.affine_inverse()
	_ik_l.magnet = inv * (sh_l - up * 0.4 + side * 0.1)
	_ik_r.magnet = inv * (_bone_w("upperarm_r") - aim * 0.45 + up * 0.15)
	# string runs tip -> fingers -> tip while drawn; straight again once loosed
	var st2: Node3D = weapon_node.get_node_or_null("String")
	var bt: Transform3D = weapon_node.global_transform
	var top: Vector3 = bt * EnemyGear.BOW_TOP
	var bot: Vector3 = bt * EnemyGear.BOW_BOTTOM
	var pull := _bone_w("index_01_r") if not released else (top + bot) * 0.5
	var drawn := not released and _draw > 0.02
	if st2 != null: st2.visible = not drawn
	_str_a.visible = drawn
	_str_b.visible = drawn
	if drawn:
		EnemyGear.span(_str_a, top, pull)
		EnemyGear.span(_str_b, pull, bot)
	_arrow.visible = not released and _draw > 0.02
	if _arrow.visible:
		var tip := grip + aim * 0.06
		var nk := pull
		var d := tip - nk
		if d.length() > 0.05:
			var y := d.normalized()
			var x := y.cross(Vector3.UP).normalized()
			_arrow.global_transform = Transform3D(Basis(x, y, x.cross(y)), nk)

func _alive_pose() -> bool:
	var st := ubc.loco_state()
	return not (st.begins_with("Death") or st == "Knocked" or st == "Defeat")

# ====================================================================== rig
## AnimRig's API on a plain AnimationPlayer: one looping base clip, one-shot
## actions and reactions crossfaded over it, and held states (death, knocked,
## kneeling) that own the body until something else is asked for.
class UBCRig extends AnimRig:
	var ap: AnimationPlayer
	var sk: Skeleton3D
	var map := {}
	var _loop := ""
	var _loop_speed := 1.0
	var _shot := ""           # current one-shot (enemy clip name)
	var _shot_kind := ""      # "action" / "reaction"
	var _shot_end := 0.0
	var _state := "Move"
	var _state_clip := ""
	var _hold := false

	func init(a: AnimationPlayer, s: Skeleton3D, character: String, m: Dictionary) -> void:
		ap = a
		sk = s
		map = m

	func ok() -> bool:
		return ap != null

	func _lib(c: String) -> String:
		if map.has(c): return String((map[c] as Array)[0])
		if ap.has_animation(c): return c
		return ""

	func has_clip(c: String) -> bool:
		return _lib(c) != "" or UBCDriver.STATES.has(c) and UBCDriver.STATES[c] != "" and ap.has_animation(UBCDriver.STATES[c])

	func clip_len(c: String) -> float:
		var l := _lib(c)
		if l == "": return 0.0
		var e: Array = map.get(c, [l, 1.0, 0.0, 0.0])
		var a := ap.get_animation(l)
		var end: float = float(e[3]) if float(e[3]) > 0.0 else a.length
		return maxf(0.0, end - float(e[2])) / maxf(float(e[1]), 0.05)

	func play_loop(clip: String, xfade: float, speed: float) -> void:
		if not ap.has_animation(clip): return
		_loop_speed = speed
		if _loop == clip and ap.current_animation == clip:
			ap.speed_scale = speed
			return
		_loop = clip
		if _shot != "" or _hold: return
		var a := ap.get_animation(clip)
		a.loop_mode = Animation.LOOP_LINEAR
		ap.play(clip, xfade, 1.0)
		ap.speed_scale = speed

	func _one_shot(c: String, xfade: float, speed: float, kind_s: String) -> bool:
		var l := _lib(c)
		if l == "": return false
		var e: Array = map.get(c, [l, 1.0, 0.0, 0.0])
		var a := ap.get_animation(l)
		_hold_t = -1.0
		_rec = ""
		_shot = c
		_shot_kind = kind_s
		var sp: float = float(e[1]) * speed
		var st: float = float(e[2])
		var end: float = float(e[3]) if float(e[3]) > 0.0 else a.length
		_shot_end = end
		ap.play(l, xfade, 1.0)
		ap.speed_scale = sp
		if st > 0.0: ap.seek(st, false)
		return true

	var _hold_t := -1.0
	var _rate2 := 1.0
	var _rec := ""

	func play_attack(c: String, lib: String, from: float, hold: float, r1: float, r2: float,
			end: float, rec: String, xfade: float) -> bool:
		if _hold or not ap.has_animation(lib): return false
		_shot = c
		_shot_kind = "action"
		_shot_end = end
		_hold_t = hold
		_rate2 = r2
		_rec = rec
		ap.get_animation(lib).loop_mode = Animation.LOOP_NONE
		ap.play(lib, maxf(xfade, 0.08), 1.0)
		ap.seek(from, true)
		ap.speed_scale = r1
		return true

	func play_action(clip: String, xfade := 0.07, speed := 1.0) -> bool:
		if _hold: return false
		return _one_shot(clip, maxf(xfade, 0.08), speed, "action")

	func play_reaction(clip: String, xfade := 0.04) -> bool:
		if _hold: return false
		return _one_shot(clip, maxf(xfade, 0.06), 1.0, "reaction")

	func set_action_speed(s: float) -> void:
		if _shot != "": ap.speed_scale *= s

	func action_active() -> bool:
		return _shot != "" and _shot_kind == "action"

	func abort_action(fade := true) -> void:
		if _shot_kind == "action":
			_rec = ""
			_end_shot(0.15 if fade else 0.0)

	func abort_reaction() -> void:
		if _shot_kind == "reaction": _end_shot(0.12)

	func busy() -> bool:
		return _shot != "" or _hold

	func state_clip() -> String:
		return _state_clip

	func _end_shot(xfade: float) -> void:
		_hold_t = -1.0
		if _rec != "" and _shot_kind == "action" and ap.has_animation(_rec) and not _hold:
			var r := _rec
			_rec = ""
			_shot = "Recover"
			_shot_end = ap.get_animation(r).length
			ap.get_animation(r).loop_mode = Animation.LOOP_NONE
			ap.play(r, 0.06, 1.0)
			ap.speed_scale = 1.1
			return
		_rec = ""
		_shot = ""
		_shot_kind = ""
		if _hold: return
		if _loop != "" and ap.has_animation(_loop):
			ap.play(_loop, xfade, 1.0)
			ap.speed_scale = _loop_speed

	func tick(_delta: float) -> void:
		if _shot != "":
			var pos := ap.current_animation_position
			if _hold_t >= 0.0 and pos >= _hold_t:
				_hold_t = -1.0
				ap.speed_scale = _rate2
			if not ap.is_playing() or pos >= _shot_end - 0.02:
				_end_shot(0.2)

	func travel(state: String) -> void:
		_state = state
		match state:
			"Move":
				_state_clip = ""
				if _hold:
					_hold = false
					_end_shot(0.3)
			"Investigate", "IdleBoss", "HoldDraw":
				_state_clip = String(UBCDriver.STATES[state]) if state != "Investigate" else ""
				if _hold:
					_hold = false
					_end_shot(0.3)
			"DeathA", "DeathB", "Knocked", "Defeat":
				var c := String(UBCDriver.STATES[state])
				if not ap.has_animation(c): return
				_shot = ""
				_shot_kind = ""
				_hold_t = -1.0
				_rec = ""
				_hold = true
				ap.get_animation(c).loop_mode = Animation.LOOP_NONE
				ap.play(c, 0.12, 1.0)
				ap.speed_scale = 1.0
			"GetUp":
				_hold = false
				_get_up()
			_:
				pass

	func _get_up() -> void:
		var c := String(UBCDriver.STATES["GetUp"])
		if not ap.has_animation(c): return
		_shot = "GetUp"
		_shot_kind = "reaction"
		_shot_end = ap.get_animation(c).length
		ap.play(c, 0.2, 1.0)
		ap.speed_scale = 1.0

	func loco_state() -> String:
		return _state

	func clip_meta(_clip: String) -> Dictionary:
		return {}

	func root_motion() -> Vector3:
		return Vector3.ZERO

## v0.22: a soldier's step is heard when his foot lands (near soldiers only)
func _on_footfall(_side: String, pos: Vector3) -> void:
	if lod_level > 0 or _host == null or _step_speed < 0.7: return
	if _host.get("is_dead") == true: return
	var surf := "dirt"
	var w = _host.get("world")
	if w != null and is_instance_valid(w) and w.has_method("surface_at"): surf = w.surface_at(pos.x, pos.z)
	var lvl := -20.0 + clampf(_step_speed, 0.0, 6.0) * 1.3
	Audio.play_sfx("footstep_" + surf, pos, randf_range(0.9, 1.04), lvl)
