class_name SwordCarry
extends SkeletonModifier3D
## Carries the katana in its saya when it is not drawn.
##
## The katana is skinned to a single bone, weapon.R, which is a child of
## hand.R, so it goes wherever the hand goes. That meant the sword was
## permanently drawn and the lacquered saya at the hip was permanently empty --
## in every idle, every walk, every cutscene. Splitting the mesh out of the GLB
## would mean rebuilding the character; overriding one bone does not.
##
## When sheathed, weapon.R's pose is rewritten so its GLOBAL transform matches
## the scabbard bone's (times a fixed offset that seats the blade in the
## mouth of the saya). The hand animates freely underneath and the sword stays
## at the hip. Drawing is the same override fading from 1 to 0 across the
## Unsheathe clip, so the blade travels out of the saya and into the grip.

## 0 = blade in the hand, 1 = blade in the saya. Starts drawn; whoever owns
## the character decides when it is put away.
var blend := 0.0
## Where the hilt sits relative to the scabbard bone.
##
## Measured, not guessed. In weapon.R's bone space the katana runs from a
## pommel at y -0.082 to a tip at (y 0.907, z -0.408): an axis 24 degrees off
## +Y, which is the extra_rot the build applies when it mounts the sword in
## the hand. In the scabbard bone's space the saya is a straight tube on +Y
## from -0.10 (mouth, at the front of the hip) to +0.70 (tip, sweeping back).
## So the seating rotation is exactly +24 degrees about X, which lands the
## blade on the saya's axis, and the translation puts the tsuba at the mouth.
## The blade is 0.908 m and the saya 0.80 m, so the last 0.06 m of tip sits
## past the kojiri -- closer than any offset I could have eyeballed.
@export var offset_pos := Vector3(0.0, -0.25, 0.0)
@export var offset_rot_deg := Vector3(24.0, 0.0, 0.0)

var _w := -1
var _s := -1
var _parent := -1
var _offset := Transform3D.IDENTITY
var _ok := false

func _ready() -> void:
	var skel := get_skeleton()
	if skel == null: return
	_w = skel.find_bone("weapon.R")
	_s = skel.find_bone("scabbard")
	if _w < 0 or _s < 0: return
	_parent = skel.get_bone_parent(_w)
	if _parent < 0: return
	_rebuild_offset()
	_ok = true

func _rebuild_offset() -> void:
	var b := Basis.from_euler(Vector3(deg_to_rad(offset_rot_deg.x),
		deg_to_rad(offset_rot_deg.y), deg_to_rad(offset_rot_deg.z)))
	_offset = Transform3D(b, offset_pos)

func set_offset(pos: Vector3, rot_deg: Vector3) -> void:
	offset_pos = pos
	offset_rot_deg = rot_deg
	_rebuild_offset()

func _process_modification() -> void:
	if not _ok or blend <= 0.001: return
	var skel := get_skeleton()
	if skel == null: return
	var want: Transform3D = skel.get_bone_global_pose(_s) * _offset
	var local: Transform3D = skel.get_bone_global_pose(_parent).affine_inverse() * want
	var k: float = clampf(blend, 0.0, 1.0)
	skel.set_bone_pose_position(_w, skel.get_bone_pose_position(_w).lerp(local.origin, k))
	skel.set_bone_pose_rotation(_w, skel.get_bone_pose_rotation(_w).slerp(
		local.basis.get_rotation_quaternion(), k))
