class_name Horse
extends CharacterBody3D
## Kaito's horse (CC0 Quaternius "Animals" horse, with a procedural saddle).
##
## Riding: camera-relative steering like the ronin on foot.  Hold forward to
## canter, hold Sprint to gallop, Walk toggles a walk, Move back brakes and then
## backs up, Jump clears fences and streams.  Turn rate falls with speed so a
## gallop carves wide arcs; acceleration and braking are eased so the horse has
## weight.  Called with the whistle key it runs to you from wherever it is (or
## from just out of sight when it is far away).

const MODEL := "res://assets/horse/HorseHQ.glb"      ## tools/horse_hq.py (smoothed, coat + hair cards)
const MODEL_FALLBACK := "res://assets/horse/Horse.gltf"
const SCALE := 0.45
const WALK := 1.6
const TROT := 3.6
const CANTER := 6.8
const GALLOP := 12.5
## measured ground speed of each clip at speed_scale 1 (hoof stance velocity x SCALE):
## the old mapping played the gallop at 0.65x while cantering, so the horse skated
const WALK_NAT := 1.2
const TROT_NAT := 1.35
const GALLOP_NAT := 3.9
## hoof touchdown phases (0..1 of the cycle), measured from the leg IK targets
const STEPS := {
	"Walk": [["BL", 0.13], ["FL", 0.43], ["BR", 0.65], ["FR", 0.0]],
	"Trot": [["BL", 0.13], ["FR", 0.17], ["BR", 0.65], ["FL", 0.60]],
	"Gallop": [["BR", 0.38], ["BL", 0.55], ["FR", 0.67], ["FL", 0.83]],
}
const HOOF_OFS := {"FL": Vector3(0.15, 0, 0.67), "FR": Vector3(-0.15, 0, 0.67), "BL": Vector3(0.2, 0, -0.8), "BR": Vector3(-0.2, 0, -0.8)}
const REVERSE := 1.5
const GRAVITY := 22.0
const JUMP_V := 6.4
const SEAT_POINT := Vector3(0.0, 3.46, 0.02)   ## on the saddle, horse model units
## Horse stamina: a gallop lasts ~15 s, then it drops to a canter, blowing hard,
## until it has its wind back (40%).
const STAMINA_DRAIN := 6.5
const STAMINA_REGEN := 8.0

enum H {IDLE, CALLED, RIDDEN}

var mode: int = H.IDLE
var rider: Node3D = null
var world: Node = null
var camera: Node = null
var model: Node3D
var anim: AnimationPlayer
var skel: Skeleton3D
var _seat_bone := -1
var _seat_local := Vector3.ZERO
var _speed := 0.0            ## signed forward speed
var _turn := 0.0
var _call_target := Vector3.ZERO
var _call_t := 0.0
var _stuck_t := 0.0
var _jumping := false
var _air_t := 0.0
var _pitch := 0.0
var _step_t := 0.0
var _idle_t := 0.0
var _cur := ""
var _lean := 0.0
var _phase_prev := 0.0
var _snort_t := 9.0
var _neigh_t := 0.0
var _bob := 0.0
var stamina := 100.0
var max_stamina := 100.0
var winded := false
var _st_idle := 0.0
var _blow_t := 0.0

## v0.23 the tail on springs (anim/HorseTail.gd); dust, breathing and steaming
## nostrils (fx/HorseFX.gd)
var tail: HorseTail
var fx: HorseFX

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 8   # world + map bounds
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.6
	floor_constant_speed = true
	safe_margin = 0.03
	add_to_group("horse")
	_build()

func _build() -> void:
	var ps = load(MODEL) if ResourceLoader.exists(MODEL) else load(MODEL_FALLBACK)
	if ps == null:
		push_error("Horse: cannot load " + MODEL)
		return
	model = ps.instantiate()
	model.name = "Model"
	model.scale = Vector3.ONE * SCALE
	add_child(model)
	skel = model.find_children("*", "Skeleton3D", true, false)[0]
	anim = model.find_children("*", "AnimationPlayer", true, false)[0]
	for a in ["Idle", "Idle_2", "Idle_Headlow", "Walk", "Gallop", "Eating"]:
		if anim.has_animation(a): anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_make_trot()
	_polish_materials()
	anim.playback_default_blend_time = 0.25
	_seat_bone = skel.find_bone("Torso2")
	if _seat_bone >= 0:
		_seat_local = skel.get_bone_global_rest(_seat_bone).affine_inverse() * SEAT_POINT
	_build_saddle()
	_build_bridle()
	tail = HorseTail.new()
	tail.name = "HorseTail"
	if tail.setup(skel):
		tail.horse = self
		skel.add_child(tail)
	else:
		tail = null
	fx = HorseFX.attach(self, skel)
	# body: a standing capsule for the floor contact and a lying one for the barrel
	var legs := CollisionShape3D.new()
	var c1 := CapsuleShape3D.new()
	c1.radius = 0.36; c1.height = 1.5
	legs.shape = c1
	legs.position = Vector3(0, 0.75, 0.1)
	add_child(legs)
	var barrel := CollisionShape3D.new()
	var c2 := CapsuleShape3D.new()
	c2.radius = 0.34; c2.height = 2.1
	barrel.shape = c2
	barrel.rotation = Vector3(PI * 0.5, 0, 0)
	barrel.position = Vector3(0, 1.22, 0.15)
	add_child(barrel)
	_play("Idle", 0.0)

## A trot is the walk with the diagonal pairs moving together: shift the front
## legs a sixth of a cycle later so each front hoof lands with the opposite hind.
func _make_trot() -> void:
	if anim == null or not anim.has_animation("Walk") or anim.has_animation("Trot"): return
	var walk: Animation = anim.get_animation("Walk")
	var trot: Animation = walk.duplicate(true)
	var L := trot.length
	var shift := 0.17 * L
	for t in trot.get_track_count():
		var bone := String(trot.track_get_path(t).get_concatenated_subnames())
		if not (bone.begins_with("Front") or bone.begins_with("IKFront") or bone.begins_with("FF.") or bone.begins_with("PoleTarget.")):
			continue
		var n := trot.track_get_key_count(t)
		var keys := []
		for k in n: keys.append([fposmod(trot.track_get_key_time(t, k) + shift, L), trot.track_get_key_value(t, k)])
		for k in range(n - 1, -1, -1): trot.track_remove_key(t, k)
		for kv in keys: trot.track_insert_key(t, kv[0], kv[1])
	trot.loop_mode = Animation.LOOP_LINEAR
	var lib: AnimationLibrary = anim.get_animation_library("")
	if lib != null: lib.add_animation("Trot", trot)

## Imported glTF materials are plain PBR: give the coat a soft sheen and the
## hair cards alpha scissor + two sides (they are single quads).
func _polish_materials() -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s) as StandardMaterial3D
			if mat == null: continue
			mat = mat.duplicate() as StandardMaterial3D
			match mat.resource_name:
				"Coat", "Main", "Main_Dark", "Main_Light", "Muzzle":
					mat.roughness = 0.72
					mat.metallic_specular = 0.38
					mat.rim_enabled = true
					mat.rim = 0.28
					mat.rim_tint = 0.65
					mat.normal_scale = 0.8
				"Hoof", "Hooves":
					mat.roughness = 0.46
					mat.metallic_specular = 0.45
				"ManeHair":
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					mat.alpha_scissor_threshold = 0.38
					mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
					mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					mat.roughness = 0.5
					mat.metallic_specular = 0.55
					mat.rim_enabled = true
					mat.rim = 0.35
					mat.rim_tint = 0.3
				"ManeCore", "Hair":
					mat.roughness = 0.62
				"Eye", "Eye_Black", "Eye_White":
					mat.roughness = 0.04
					mat.metallic_specular = 0.9
					mat.clearcoat_enabled = true
					mat.clearcoat = 1.0
			m.set_surface_override_material(s, mat)

func _build_saddle() -> void:
	if _seat_bone < 0: return
	var ba := BoneAttachment3D.new()
	ba.name = "SaddleMount"
	ba.bone_name = "Torso2"
	skel.add_child(ba)
	var rest := skel.get_bone_global_rest(_seat_bone)
	var holder := Node3D.new()
	holder.transform = rest.affine_inverse()      # back to horse model space
	ba.add_child(holder)
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.23, 0.12, 0.06)
	leather.roughness = 0.62
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.46, 0.06, 0.07)
	cloth.roughness = 0.9
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.72, 0.56, 0.20)
	trim.metallic = 0.8
	trim.roughness = 0.35
	# saddle blanket draped over the barrel
	var blanket := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.28, 0.05, 1.25)
	blanket.mesh = bm
	blanket.material_override = cloth
	blanket.position = SEAT_POINT + Vector3(0, -0.10, 0.0)
	holder.add_child(blanket)
	for sd in [-1.0, 1.0]:
		var flap := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.05, 0.62, 1.2)
		flap.mesh = fm
		flap.material_override = cloth
		flap.position = SEAT_POINT + Vector3(sd * 0.62, -0.40, 0.0)
		flap.rotation = Vector3(0, 0, sd * 0.18)
		holder.add_child(flap)
		# stirrup
		var st := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.22, 0.06, 0.3)
		st.mesh = sm
		st.material_override = trim
		st.position = SEAT_POINT + Vector3(sd * 0.82, -1.45, 0.08)
		holder.add_child(st)
		var strap := MeshInstance3D.new()
		var stm := BoxMesh.new()
		stm.size = Vector3(0.03, 1.0, 0.07)
		strap.mesh = stm
		strap.material_override = leather
		strap.position = SEAT_POINT + Vector3(sd * 0.76, -0.95, 0.08)
		strap.rotation = Vector3(0, 0, sd * 0.1)
		holder.add_child(strap)
	# the saddle itself: seat, raised pommel and cantle
	var seat := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.72, 0.14, 0.95)
	seat.mesh = sb
	seat.material_override = leather
	seat.position = SEAT_POINT + Vector3(0, -0.02, 0.0)
	holder.add_child(seat)
	for z in [0.52, -0.52]:
		var arch := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.62, 0.34, 0.14)
		arch.mesh = am
		arch.material_override = leather
		arch.position = SEAT_POINT + Vector3(0, 0.12, z)
		holder.add_child(arch)
		var cap := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.64, 0.05, 0.16)
		cap.mesh = cm
		cap.material_override = trim
		cap.position = SEAT_POINT + Vector3(0, 0.30, z)
		holder.add_child(cap)

# ------------------------------------------------------------------ bridle + reins
## v0.15: a headstall (crownpiece and throatlatch, browband, cheekpieces,
## noseband) and bit rings ride on the Head bone; the reins are a sagging
## leather strap redrawn every frame from the bit rings to the rider's fists,
## or draped along the neck to the pommel when nobody is riding.
const REIN_LEN := 1.5            ## metres, bit to hand
const REIN_W := 0.024
var _bit := []                   ## [left, right] markers on the head
var _rest := []                  ## [left, right] markers at the pommel
var _reins: MeshInstance3D
var _rein_mesh: ImmediateMesh
var _rein_mat: StandardMaterial3D

static func _box(st: SurfaceTool, xf: Transform3D) -> void:
	# unit box (-0.5..0.5) through xf; normals from the basis axes
	var ax: Array = [xf.basis.x, xf.basis.y, xf.basis.z]
	for a in 3:
		for sgn in [-1.0, 1.0]:
			var n: Vector3 = (ax[a] as Vector3).normalized() * sgn
			var u: Vector3 = ax[(a + 1) % 3]
			var v: Vector3 = ax[(a + 2) % 3]
			var c: Vector3 = xf.origin + (ax[a] as Vector3) * 0.5 * sgn
			var q := [c - u * 0.5 - v * 0.5, c + u * 0.5 - v * 0.5, c + u * 0.5 + v * 0.5, c - u * 0.5 + v * 0.5]
			var order := [0, 1, 2, 0, 2, 3] if sgn > 0.0 else [0, 2, 1, 0, 3, 2]
			for i in order:
				st.set_normal(n)
				st.add_vertex(q[i])

## a flat strap from a to b: `w` wide, `t` thick along `out` (the surface normal)
static func _strap(st: SurfaceTool, a: Vector3, b: Vector3, w: float, t: float, out: Vector3) -> void:
	var dv := b - a
	var l := dv.length()
	if l < 0.0001: return
	var z := dv / l
	var n := (out - z * out.dot(z))
	if n.length() < 0.001: n = z.cross(Vector3.RIGHT)
	n = n.normalized()
	var x := z.cross(n).normalized()
	_box(st, Transform3D(Basis(x * w, n * t, z * (l + w * 0.4)), (a + b) * 0.5))

## an elliptical loop of straps round centre c in the plane spanned by u, v
static func _loop(st: SurfaceTool, c: Vector3, u: Vector3, v: Vector3, w: float, t: float, seg: int,
		from := 0.0, to := TAU) -> void:
	for i in seg:
		var a0 := lerpf(from, to, float(i) / float(seg))
		var a1 := lerpf(from, to, float(i + 1) / float(seg))
		var p0 := c + u * cos(a0) + v * sin(a0)
		var p1 := c + u * cos(a1) + v * sin(a1)
		var mid := (p0 + p1) * 0.5
		_strap(st, p0, p1, w, t, mid - c)

func _build_bridle() -> void:
	var hb := skel.find_bone("Head")
	if hb < 0: return
	var ba := BoneAttachment3D.new()
	ba.name = "BridleMount"
	ba.bone_name = "Head"
	skel.add_child(ba)
	var holder := Node3D.new()
	holder.transform = skel.get_bone_global_rest(hb).affine_inverse()   # horse model space
	ba.add_child(holder)
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.16, 0.085, 0.045)
	leather.roughness = 0.55
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.70, 0.62, 0.45)
	metal.metallic = 0.85
	metal.roughness = 0.32
	# model units (x0.45 = metres); the head points down +Z, measured from the mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.075
	var t := 0.022
	# noseband round the face, tilted back with the nasal line
	var nb_c := Vector3(0.0, 3.79, 3.06)
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(-22.0))
	_loop(st, nb_c, tilt * Vector3(0.205, 0.0, 0.0), tilt * Vector3(0.0, 0.365, 0.0), w, t, 14)
	# crownpiece over the poll behind the ears, closing as the throatlatch
	var cr_c := Vector3(0.0, 4.08, 2.44)
	var ctilt := Basis(Vector3.RIGHT, deg_to_rad(12.0))
	_loop(st, cr_c, ctilt * Vector3(0.315, 0.0, 0.0), ctilt * Vector3(0.0, 0.50, 0.0), w, t, 16)
	# browband across the forehead in front of the ears
	_strap(st, Vector3(0.29, 4.30, 2.50), Vector3(0.0, 4.43, 2.66), w * 0.8, t, Vector3(0.6, 0.3, 0.6))
	_strap(st, Vector3(0.0, 4.43, 2.66), Vector3(-0.29, 4.30, 2.50), w * 0.8, t, Vector3(-0.6, 0.3, 0.6))
	# cheekpieces down to the bit
	for sx in [1.0, -1.0]:
		_strap(st, Vector3(sx * 0.315, 4.05, 2.46), Vector3(sx * 0.215, 3.66, 3.10), w, t, Vector3(sx, 0.0, 0.0))
	var m := st.commit()
	m.surface_set_material(0, leather)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sx in [1.0, -1.0]:
		var bc := Vector3(sx * 0.215, 3.60, 3.14)
		_loop(st2, bc, Vector3(0.0, 0.07, 0.0), Vector3(0.0, 0.0, 0.07), 0.026, 0.026, 10)
	# the mouthpiece between the rings
	_strap(st2, Vector3(0.215, 3.60, 3.14), Vector3(-0.215, 3.60, 3.14), 0.03, 0.03, Vector3.UP)
	st2.commit(m)
	m.surface_set_material(1, metal)
	var mi := MeshInstance3D.new()
	mi.name = "Bridle"
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	_bit.clear()
	for sx in [1.0, -1.0]:
		var mk := Node3D.new()
		mk.position = Vector3(sx * 0.225, 3.56, 3.12)
		holder.add_child(mk)
		_bit.append(mk)
	# where the reins rest when nobody holds them: just ahead of the pommel
	var sm := skel.get_node_or_null("SaddleMount")
	if sm != null and sm.get_child_count() > 0:
		var sh: Node3D = sm.get_child(0)
		_rest.clear()
		for sx in [1.0, -1.0]:
			var mk := Node3D.new()
			mk.position = SEAT_POINT + Vector3(sx * 0.16, 0.26, 0.66)
			sh.add_child(mk)
			_rest.append(mk)
	_rein_mesh = ImmediateMesh.new()
	_rein_mat = StandardMaterial3D.new()
	_rein_mat.albedo_color = Color(0.15, 0.08, 0.04)
	_rein_mat.roughness = 0.6
	_rein_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_reins = MeshInstance3D.new()
	_reins.name = "Reins"
	_reins.top_level = true
	_reins.mesh = _rein_mesh
	_reins.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_reins)
	process_priority = 20

func _process(_delta: float) -> void:
	_update_reins()

func _update_reins() -> void:
	if _reins == null or _bit.size() < 2: return
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.global_position.distance_to(global_position) > 70.0:
		_reins.visible = false
		return
	_reins.visible = true
	_reins.global_transform = Transform3D.IDENTITY
	if _rest.size() < 2: return
	var ends := PackedVector3Array([(_rest[0] as Node3D).global_position, (_rest[1] as Node3D).global_position])
	var held := [false, false]
	if rider != null and is_instance_valid(rider) and rider.has_method("rein_grip_points"):
		var g: PackedVector3Array = rider.rein_grip_points()
		if g.size() == 2:
			# one hand on the reins (sword out): both reins run to the left fist
			if g[0] != Vector3.INF and g[1] == Vector3.INF: g[1] = g[0] - global_transform.basis.x.normalized() * 0.025
			for k in 2:
				if g[k] != Vector3.INF:
					ends[k] = g[k]
					held[k] = true
	var side := global_transform.basis.x.normalized()
	var up := Vector3.UP
	_rein_mesh.clear_surfaces()
	for k in 2:
		var a: Vector3 = (_bit[k] as Node3D).global_position
		var b: Vector3 = ends[k]
		var sx := 1.0 if k == 0 else -1.0
		var d := a.distance_to(b)
		var sag := clampf(REIN_LEN - d, 0.0, 0.8) * 0.45 + 0.03
		var c := (a + b) * 0.5 - up * sag + side * sx * (0.10 if held[k] else 0.16)
		_rein_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _rein_mat)
		var n := 12
		for i in n + 1:
			var f := float(i) / float(n)
			var p := a.lerp(c, f).lerp(c.lerp(b, f), f)
			var tg := (2.0 * (1.0 - f) * (c - a) + 2.0 * f * (b - c)).normalized()
			var wv := tg.cross(up)
			if wv.length() < 0.01: wv = side
			wv = wv.normalized() * REIN_W * 0.5
			var nn := wv.cross(tg).normalized()
			if nn.y < 0.0: nn = -nn
			_rein_mesh.surface_set_normal(nn)
			_rein_mesh.surface_add_vertex(p - wv)
			_rein_mesh.surface_set_normal(nn)
			_rein_mesh.surface_add_vertex(p + wv)
		_rein_mesh.surface_end()

## World transform of the saddle top: the rider's pelvis goes here.
func seat_transform() -> Transform3D:
	var yaw := Basis(Vector3.UP, rotation.y)
	var pitch := Basis(Vector3.RIGHT, _pitch * 0.6)
	var p := global_position + yaw * Vector3(0, SEAT_POINT.y * SCALE, SEAT_POINT.z * SCALE)
	if _seat_bone >= 0 and skel != null and skel.is_inside_tree():
		p = skel.global_transform * (skel.get_bone_global_pose(_seat_bone) * _seat_local)
	return Transform3D(yaw * pitch, p)

func set_rider(r: Node3D) -> void:
	rider = r
	mode = H.RIDDEN if r != null else H.IDLE
	_idle_t = 0.0
	if r != null and randf() < 0.4: _neigh_t = 0.35

func is_ridden() -> bool:
	return rider != null

# ---------------------------------------------------------------- calling
func call_to(player: Node3D) -> void:
	if rider != null: return
	var pp := player.global_position
	var d := global_position.distance_to(pp)
	if d > 70.0 and world != null:
		# appear just out of sight behind the player and run in
		var yaw: float = camera.get_yaw() if camera != null and camera.has_method("get_yaw") else player.rotation.y
		var back := Vector3(sin(yaw), 0.0, cos(yaw))
		var spot := pp + back * 32.0
		if world.has_method("_free_spot"): spot = world._free_spot(spot)
		if world.terrain != null and world.terrain.loaded:
			spot.y = world.terrain.sample_height(spot.x, spot.z) + 0.2
		global_position = spot
		velocity = Vector3.ZERO
	mode = H.CALLED
	_neigh_t = 0.7          # answers the whistle a moment later
	_call_target = pp
	_call_t = 0.0
	_stuck_t = 0.0

# ---------------------------------------------------------------- loop
func _physics_process(delta: float) -> void:
	if model == null: return
	match mode:
		H.RIDDEN: _ridden(delta)
		H.CALLED: _called(delta)
		_: _idle(delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
		_air_t += delta
	else:
		if _jumping and _air_t > 0.1:
			_jumping = false
			_play("Jump_toIdle" if absf(_speed) < 3.0 else "Gallop", 0.12)
			Audio.play_sfx("land", global_position, 0.8, 2.0)
			Audio.play_sfx("hoof_dirt", global_position, 0.95, 0.0)
		_air_t = 0.0
		if velocity.y < 0.0: velocity.y = -1.0
	move_and_slide()
	# stop dead against walls/trees instead of grinding
	if is_on_wall() and absf(_speed) > 2.0:
		var n := get_wall_normal()
		var fwd := global_transform.basis.z
		if fwd.dot(n) < -0.6:
			_speed *= 0.4
	_align_to_ground(delta)
	_hooves(delta)
	_update_stamina(delta)

func _fwd() -> Vector3:
	return global_transform.basis.z

func _drive(want_speed: float, want_yaw: float, has_dir: bool, delta: float) -> void:
	# ease the speed: canter pickup ~2 s, gallop ~2 s more, braking faster
	var acc := 4.2 if want_speed > _speed else 8.5
	if want_speed > CANTER and _speed > CANTER - 1.0: acc = 3.4
	_speed = move_toward(_speed, want_speed, acc * delta)
	if has_dir:
		var diff := wrapf(want_yaw - rotation.y, -PI, PI)
		var rate := lerpf(2.8, 1.25, clampf(absf(_speed) / GALLOP, 0.0, 1.0))
		if absf(_speed) < 1.0: rate = 2.2
		var step := clampf(diff, -rate * delta, rate * delta)
		rotation.y = wrapf(rotation.y + step, -PI, PI)
		_turn = lerpf(_turn, step / maxf(delta, 0.001), clampf(delta * 6.0, 0.0, 1.0))
	else:
		_turn = lerpf(_turn, 0.0, clampf(delta * 4.0, 0.0, 1.0))
	_water_check(delta)
	var hv := _fwd() * _speed
	velocity.x = hv.x
	velocity.z = hv.z
	_anim_for_speed()

## Water: a ford slows the horse to a wade; deep water it will not enter
## (it stops at the edge with a snort instead of walking along the lake bed).
var _refuse_t := 0.0
func _water_check(delta: float) -> void:
	_refuse_t = maxf(0.0, _refuse_t - delta)
	if world == null or world.terrain == null or absf(_speed) < 0.05: return
	var t = world.terrain
	var ahead := global_position + _fwd() * signf(_speed) * 2.4
	if t.water_depth_at(ahead.x, ahead.z) > 1.15:
		_speed = move_toward(_speed, 0.0, 16.0 * delta)
		if _refuse_t <= 0.0:
			_refuse_t = 2.5
			Audio.play_sfx("horse_snort", global_position + _fwd() * 1.2 + Vector3.UP * 1.5, 0.95, -2.0)
		return
	var here: float = t.water_depth_at(global_position.x, global_position.z)
	if here > 0.2:
		var cap := lerpf(CANTER, WALK * 1.3, clampf((here - 0.2) / 0.7, 0.0, 1.0))
		if absf(_speed) > cap: _speed = move_toward(_speed, signf(_speed) * cap, 9.0 * delta)

## Gait by speed, and each clip played at the rate its hooves actually move
## (a little slide is allowed at a full gallop, where the clip's stride is short).
func _anim_for_speed() -> void:
	if _jumping: return
	var s := absf(_speed)
	if s < 0.25:
		_play("Idle", 0.35)
		anim.speed_scale = 1.0
	elif s < 2.5:
		_play("Walk", 0.3)
		anim.speed_scale = clampf(s / WALK_NAT, 0.55, 2.0) * (1.0 if _speed >= 0.0 else -1.0)
	elif s < 5.0 and anim.has_animation("Trot"):
		_play("Trot", 0.25)
		anim.speed_scale = clampf(s / TROT_NAT, 1.6, 3.2)
	else:
		_play("Gallop", 0.25)
		anim.speed_scale = clampf(s / GALLOP_NAT, 1.15, 2.35)

# ---------------------------------------------------------------- v0.23 autopilot
## Cinematic autopilot (the prologue ride): follow auto_path at auto_speed with
## pure-pursuit steering, then brake smoothly to a stop on its last point.
var auto_path := PackedVector3Array()
var auto_speed := GALLOP
var auto_done := false
var _auto_i := 0

func start_auto(path: PackedVector3Array, speed: float) -> void:
	auto_path = path
	auto_speed = speed
	auto_done = false
	_auto_i = 0

func stop_auto() -> void:
	auto_path = PackedVector3Array()

func auto_active() -> bool:
	return not auto_path.is_empty()

func _autopilot(delta: float) -> void:
	var n := auto_path.size()
	var here := global_position
	# advance the segment index while the horse is past the segment's end
	while _auto_i < n - 2:
		var a := auto_path[_auto_i + 1]
		var b := auto_path[_auto_i + 2]
		var seg := Vector2(b.x - a.x, b.z - a.z)
		if seg.dot(Vector2(here.x - a.x, here.z - a.z)) > 0.0 or Vector2(a.x - here.x, a.z - here.z).length() < 2.0:
			_auto_i += 1
		else:
			break
	# remaining path length (for braking) and a look-ahead target
	var nxt := auto_path[mini(_auto_i + 1, n - 1)]
	var rem := Vector2(nxt.x - here.x, nxt.z - here.z).length()
	for i in range(_auto_i + 1, n - 1):
		rem += Vector2(auto_path[i + 1].x - auto_path[i].x, auto_path[i + 1].z - auto_path[i].z).length()
	var look := clampf(absf(_speed) * 0.9, 4.0, 11.0)
	var tgt := nxt
	var left := look - Vector2(nxt.x - here.x, nxt.z - here.z).length()
	var j := _auto_i + 1
	while left > 0.0 and j < n - 1:
		var sl := Vector2(auto_path[j + 1].x - auto_path[j].x, auto_path[j + 1].z - auto_path[j].z).length()
		if sl >= left:
			tgt = auto_path[j].lerp(auto_path[j + 1], left / maxf(sl, 0.001))
			left = 0.0
		else:
			left -= sl
			tgt = auto_path[j + 1]
		j += 1
	var to := Vector2(tgt.x - here.x, tgt.z - here.z)
	var want_yaw := atan2(to.x, to.y) if to.length() > 0.3 else rotation.y
	# v = sqrt(2 a d): a steady 4.5 m/s^2 rein-in onto the final point
	var want := minf(auto_speed, sqrt(2.0 * 4.5 * maxf(rem - 0.6, 0.0)))
	if rem < 1.2 and absf(_speed) < 0.7:
		want = 0.0
		auto_done = true
	_drive(want, want_yaw, rem > 1.0, delta)

func _ridden(delta: float) -> void:
	if not auto_path.is_empty():
		_autopilot(delta)
		return
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back") + Game.touch_move
	if v.length() > 1.0: v = v.normalized()
	var sprint := (Input.is_action_pressed("sprint") or Game.touch_sprint) and not winded
	var walk: bool = rider != null and bool(rider.get("walk_mode"))
	var want_speed := 0.0
	var want_yaw := rotation.y
	var has_dir := false
	if v.y > 0.6 and absf(v.x) < 0.45:
		# back: brake, then back up slowly
		want_speed = -REVERSE if _speed < 0.8 else 0.0
	elif v.length() > 0.12:
		var yaw: float = camera.get_yaw() if camera != null else rotation.y + PI
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		var dir := right * v.x - fwd * v.y
		want_yaw = atan2(dir.x, dir.z)
		has_dir = true
		want_speed = GALLOP if sprint else (WALK if walk else CANTER)
		want_speed *= clampf(v.length() * 1.3, 0.3, 1.0)
		# sharp turns at speed: slow down into them
		var off := absf(wrapf(want_yaw - rotation.y, -PI, PI))
		if off > 1.4: want_speed = minf(want_speed, 3.0)
	_drive(want_speed, want_yaw, has_dir, delta)
	if Input.is_action_just_pressed("jump") and is_on_floor() and not _jumping and _speed > 1.5:
		velocity.y = JUMP_V
		_jumping = true
		_air_t = 0.0
		_play("Gallop_Jump", 0.08)
		anim.speed_scale = 1.25
		Audio.play_sfx("horse_snort", global_position + _fwd() * 1.2 + Vector3.UP * 1.5, 1.05, -4.0)
	# trample: a galloping horse bowls enemies over
	if absf(_speed) > 9.0 and world != null:
		for e in world.enemies:
			if not is_instance_valid(e) or e.is_dead: continue
			var to: Vector3 = e.global_position - global_position
			to.y = 0.0
			if to.length() < 1.6 and _fwd().dot(to.normalized()) > 0.3:
				if e.has_method("take_hit"):
					e.take_hit({"damage": 8.0, "posture": 45.0, "heavy": true, "source": rider if rider != null else self})
				if e.has_method("knock_down"): e.knock_down()
				_speed *= 0.8

## Gallop drains the horse; anything slower lets it recover (faster at a walk).
func _update_stamina(delta: float) -> void:
	var s := absf(_speed)
	if s > CANTER + 0.6 and mode == H.RIDDEN:
		stamina = maxf(0.0, stamina - STAMINA_DRAIN * delta)
		_st_idle = 0.0
		if stamina <= 0.0 and not winded:
			winded = true
			Audio.play_sfx("horse_snort", global_position + _fwd() * 1.2 + Vector3.UP * 1.5, 0.9, 2.0)
			if mode == H.RIDDEN: Game.notice.emit("Your horse is winded", "warn")
	else:
		_st_idle += delta
		if _st_idle > 1.0 and stamina < max_stamina:
			stamina = minf(max_stamina, stamina + STAMINA_REGEN * (1.6 if s < 2.5 else 1.0) * delta)
		if winded and stamina >= max_stamina * 0.4: winded = false
	# blowing hard when tired
	if stamina < 30.0 and s > 1.0:
		_blow_t -= delta
		if _blow_t <= 0.0:
			_blow_t = randf_range(2.2, 3.6)
			Audio.play_sfx("horse_snort", global_position + _fwd() * 1.2 + Vector3.UP * 1.5, randf_range(0.85, 0.95), -3.0)

func stamina_ratio() -> float:
	return stamina / maxf(max_stamina, 1.0)

func _called(delta: float) -> void:
	var p: Node3D = Game.player_ref
	if p != null and is_instance_valid(p): _call_target = p.global_position
	var to := _call_target - global_position
	to.y = 0.0
	var d := to.length()
	_call_t += delta
	if d < 3.2:
		_drive(0.0, rotation.y, false, delta)
		if absf(_speed) < 0.3:
			mode = H.IDLE
			_idle_t = 0.0
		return
	var want := GALLOP * 0.8 if d > 25.0 else clampf(d * 0.8, 2.0, CANTER)
	_drive(want, atan2(to.x, to.z), true, delta)
	if Vector3(velocity.x, 0, velocity.z).length() < 0.8 and _call_t > 1.0: _stuck_t += delta
	else: _stuck_t = 0.0
	if _stuck_t > 1.5 or _call_t > 25.0:
		# boxed in: pop out next to the player
		var spot := _call_target + (global_position - _call_target).normalized() * 4.0
		if world != null and world.has_method("_free_spot"): spot = world._free_spot(spot)
		global_position = spot
		_stuck_t = 0.0

func _idle(delta: float) -> void:
	_drive(0.0, rotation.y, false, delta)
	_idle_t += delta
	if absf(_speed) < 0.2 and _idle_t > 7.0 and _cur == "Idle":
		_play("Eating", 0.5)
	if _cur == "Eating" and _idle_t > 13.0:
		_idle_t = 0.0
		_play("Idle", 0.5)

func _play(clip: String, blend: float) -> void:
	if anim == null or not anim.has_animation(clip): return
	if clip == _cur and anim.is_playing(): return
	_cur = clip
	anim.play(clip, blend)

## Pitch the body to the slope under the front and back hooves, and bank a
## touch into turns.
func _align_to_ground(delta: float) -> void:
	var want := 0.0
	if world != null and world.terrain != null and world.terrain.loaded and is_on_floor():
		var f := global_position + _fwd() * 1.05
		var b := global_position - _fwd() * 1.05
		var hf: float = world.terrain.sample_height(f.x, f.z)
		var hb: float = world.terrain.sample_height(b.x, b.z)
		want = clampf(atan2(hb - hf, 2.1), -0.45, 0.45)
	_pitch = lerpf(_pitch, want, clampf(delta * 6.0, 0.0, 1.0))
	_lean = lerpf(_lean, clampf(-_turn * 0.05 * clampf(absf(_speed) / 8.0, 0.0, 1.0), -0.16, 0.16), clampf(delta * 4.0, 0.0, 1.0))
	model.rotation = Vector3(_pitch, 0.0, _lean)

## One hoof sound per touchdown, read off the clip's own phase so the rhythm is
## the gait's (4-beat walk, 2-beat trot, gallop with its suspension gap). The
## old version fired a pitched-down footstep on a timer: at a gallop that was
## 15 loud clicks a second, which sounded like gunfire.
func _hooves(delta: float) -> void:
	_neigh_t -= delta
	if _neigh_t < 0.0 and _neigh_t > -1.0:
		_neigh_t = -2.0
		Audio.play_sfx("horse_neigh", global_position + _fwd() * 1.2 + Vector3.UP * 1.7, 1.0, 0.0)
	var s := absf(_speed)
	_snort_t -= delta
	if _snort_t <= 0.0:
		_snort_t = randf_range(9.0, 22.0)
		if s < 2.0: Audio.play_sfx("horse_snort", global_position + _fwd() * 1.2 + Vector3.UP * 1.5, 1.0, -2.0)
	if anim == null or not STEPS.has(_cur) or not anim.is_playing():
		_phase_prev = 0.0
		return
	var a := anim.get_animation(_cur)
	if a == null or a.length <= 0.0: return
	var ph := fposmod(anim.current_animation_position / a.length, 1.0)
	if not is_on_floor() or s < 0.3:
		_phase_prev = ph
		return
	var surf := "dirt"
	if world != null and world.has_method("surface_at"): surf = String(world.surface_at(global_position.x, global_position.z))
	var set_name := "hoof_hard" if surf in ["rock", "road", "stone", "wood"] else ("footstep_water" if surf == "water" else "hoof_dirt")
	var vol := -9.0 + clampf(s / GALLOP, 0.0, 1.0) * 7.0
	if surf == "grass": vol -= 3.0
	if surf == "mud": vol -= 2.0
	var fwd_d := fposmod(ph - _phase_prev, 1.0)
	var back := fwd_d > 0.5          # reverse walk: the phase runs down
	for st in STEPS[_cur]:
		var p: float = st[1]
		var crossed := false
		if not back:
			var dp := fposmod(p - _phase_prev, 1.0)
			crossed = dp > 0.0 and dp <= fwd_d
		else:
			crossed = fposmod(_phase_prev - p, 1.0) < 1.0 - fwd_d
		if crossed:
			var ofs: Vector3 = HOOF_OFS[st[0]]
			var pos := global_transform * ofs
			var pitch := randf_range(0.92, 1.06) * (0.9 if surf == "grass" else 1.0)
			Audio.play_sfx(set_name, pos, pitch, vol)
	_phase_prev = ph
