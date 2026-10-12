class_name LocoPolish
extends SkeletonModifier3D
## Secondary body motion for locomotion.
##
## The authored clips move the legs and arms properly, but measured over one
## stride the torso barely participates: chest and spine rotate 2 deg at walk
## and 8 deg at sprint, and the head is rigidly parented to the chest. That is
## what makes running read as stiff and cheap. This layer adds the counter
## motion a real body has, on top of whatever the blend tree produced:
##
##   * pelvis yaw and roll with the stride,
##   * spine and chest counter-rotation against the arm swing,
##   * a shoulder line that leans into turns,
##   * head stabilisation so the gaze stops bobbing with the chest,
##   * a vertical bob at twice stride frequency (lowest at full leg spread),
##   * forward lean from speed and acceleration, bank from turn rate,
##   * a little extra arm swing at high speed.
##
## v0.14: every amplitude roughly two thirds of v0.13 - players read the old
## values (plus the whole-body bank in Player) as cartoonish.
##
## Stride phase is read back from the thigh bones instead of integrated from a
## clock, so it stays locked to the clips through every blend, time-scale change
## and state transition -- there is nothing to drift out of sync.

@export var enabled := true
@export var pelvis_yaw_deg := 4.0
@export var pelvis_roll_deg := 2.5
@export var spine_yaw_deg := 5.0
@export var chest_yaw_deg := 4.0
@export var chest_roll_deg := 2.0
@export var shoulder_drop_deg := 2.5
@export var head_stab := 0.70
@export var bob_m := 0.022
@export var lean_deg := 5.5
@export var accel_lean_deg := 3.0
@export var bank_deg := 3.5
@export var arm_gain := 0.15
@export var smooth := 9.0

const UP := Vector3(0.0, 1.0, 0.0)
const RIGHT := Vector3(1.0, 0.0, 0.0)
const FWD := Vector3(0.0, 0.0, 1.0)

var _skel: Skeleton3D
var _b := {}
var _rest := {}
var _ok := false

var _speed01 := 0.0
var _accel := 0.0
var _turn := 0.0
var _grounded := true
var _lean := 0.0
var _bank := 0.0
var _swing := 0.0

const BONES := ["hips", "spine", "chest", "upperchest", "neck", "head",
	"shoulder.L", "shoulder.R", "upperarm.L", "upperarm.R",
	"thigh.L", "thigh.R"]

func _ready() -> void:
	_skel = get_skeleton()
	if _skel == null: return
	for n in BONES:
		var i := _skel.find_bone(n)
		_b[n] = i
		if i >= 0: _rest[n] = _skel.get_bone_rest(i).basis.get_rotation_quaternion()
	# hips, spine and both thighs are the minimum this layer needs
	_ok = _b.get("hips", -1) >= 0 and _b.get("spine", -1) >= 0 \
		and _b.get("thigh.L", -1) >= 0 and _b.get("thigh.R", -1) >= 0

## Called every frame by AnimDriver.
##  speed01  0..1 fraction of sprint speed
##  accel    -1..1 normalised change in speed
##  turn     -1..1 normalised yaw rate
func set_motion(speed01: float, accel: float, turn: float, grounded: bool) -> void:
	_speed01 = clampf(speed01, 0.0, 1.4)
	_accel = clampf(accel, -1.0, 1.0)
	_turn = clampf(turn, -1.0, 1.0)
	_grounded = grounded

func _process_modification() -> void:
	if not _ok or not enabled or influence <= 0.001: return
	var dt := get_process_delta_time()
	if dt <= 0.0: dt = 1.0 / 60.0
	var k: float = clampf(smooth * dt, 0.0, 1.0)

	# Stride phase straight from the pose: how far apart the thighs are swung.
	# Positive when the left leg leads.
	var raw := _leg_pitch("thigh.L") - _leg_pitch("thigh.R")
	_swing = lerpf(_swing, clampf(raw / 0.85, -1.0, 1.0), clampf(k * 2.4, 0.0, 1.0))

	var target_lean := lean_deg * _speed01 + accel_lean_deg * _accel
	if not _grounded: target_lean *= 0.35
	_lean = lerpf(_lean, target_lean, k)
	_bank = lerpf(_bank, bank_deg * _turn * clampf(_speed01 * 1.6, 0.0, 1.0), k)

	# Secondary motion fades out when standing still: the idle clips are
	# authored with their own sway and do not want a stride layer on top.
	# Ramps in quickly off idle, then keeps growing to 1.3x at full sprint --
	# a sprint carries far more thoracic rotation than a walk.
	var amp: float = influence * clampf(_speed01 * 2.4, 0.0, 1.0) \
		* (0.85 + 0.45 * clampf(_speed01, 0.0, 1.0))
	if amp <= 0.002 and absf(_lean) < 0.05 and absf(_bank) < 0.05: return
	var sw := _swing

	var spine_yaw := deg_to_rad(spine_yaw_deg) * -sw * amp
	var chest_yaw := deg_to_rad(chest_yaw_deg) * -sw * amp

	_rot("hips", UP, deg_to_rad(pelvis_yaw_deg) * sw * amp)
	_rot("hips", FWD, deg_to_rad(pelvis_roll_deg) * sw * amp)
	_rot("spine", UP, spine_yaw)
	_rot("spine", RIGHT, deg_to_rad(_lean) * 0.55 * influence)
	_rot("spine", FWD, deg_to_rad(_bank) * 0.6 * influence)
	_rot("chest", UP, chest_yaw)
	_rot("chest", FWD, deg_to_rad(chest_roll_deg) * -sw * amp + deg_to_rad(_bank) * 0.4 * influence)
	_rot("chest", RIGHT, deg_to_rad(_lean) * 0.45 * influence)
	_rot("upperchest", FWD, deg_to_rad(shoulder_drop_deg) * -sw * amp)
	# Keep the head roughly world-stable instead of welded to the chest.
	_rot("neck", UP, -(spine_yaw + chest_yaw) * head_stab)
	_rot("neck", RIGHT, deg_to_rad(-_lean) * 0.5 * influence)
	_rot("head", UP, -(spine_yaw + chest_yaw) * head_stab * 0.45)
	_rot("head", FWD, deg_to_rad(_bank) * -0.35 * influence)
	# Shoulders follow the counter-rotating chest a touch late.
	_rot("shoulder.L", UP, chest_yaw * 0.45)
	_rot("shoulder.R", UP, chest_yaw * 0.45)
	# Extra arm swing once the legs are really moving.
	var extra: float = deg_to_rad(18.0) * arm_gain * amp * clampf(_speed01, 0.0, 1.2)
	_rot("upperarm.L", RIGHT, -extra * sw)
	_rot("upperarm.R", RIGHT, extra * sw)

	# Bob: the body is lowest at full leg spread, highest as the legs pass.
	var hips: int = _b["hips"]
	var lift: float = bob_m * (0.45 - absf(sw)) * 2.0 * amp
	var pg := _parent_basis(hips)
	_skel.set_bone_pose_position(hips,
		_skel.get_bone_pose_position(hips) + (pg.inverse() * Vector3(0.0, lift, 0.0)))

# ---------------------------------------------------------------- helpers
## Forward pitch of a thigh relative to its rest pose, in radians.
func _leg_pitch(name: String) -> float:
	var i: int = _b.get(name, -1)
	if i < 0: return 0.0
	var d: Quaternion = (_rest[name].inverse() * _skel.get_bone_pose_rotation(i)).normalized()
	return d.get_euler().x

## Rotate a bone about an axis expressed in its parent's space, which keeps the
## axis meaning ("yaw", "lean", "roll") stable no matter how the rig's bone
## local axes happen to be oriented.
func _rot(name: String, axis: Vector3, ang: float) -> void:
	if absf(ang) < 0.0002: return
	var i: int = _b.get(name, -1)
	if i < 0: return
	var local: Vector3 = _parent_basis(i).inverse() * axis
	if local.length_squared() < 0.000001: return
	var d := Quaternion(local.normalized(), ang)
	_skel.set_bone_pose_rotation(i, (d * _skel.get_bone_pose_rotation(i)).normalized())

func _parent_basis(i: int) -> Basis:
	var p: int = _skel.get_bone_parent(i)
	if p < 0: return Basis.IDENTITY
	return _skel.get_bone_global_pose(p).basis.orthonormalized()
