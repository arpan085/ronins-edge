class_name AnimLOD
extends Node
## Distance-based animation quality. The player character is never downgraded
## below MEDIUM; distant NPCs drop secondary motion and update less often.

enum Q {NEAR, MEDIUM, FAR, CULLED}

@export var near_dist := 12.0
@export var mid_dist := 26.0
@export var far_dist := 55.0
@export var is_player := false

var rig: AnimRig
var foot_ik: FootIK
var look: LookAtLayer
var level: int = Q.NEAR

var _t := 0.0
var _accum := 0.0
var _cam: Camera3D
var _host: Node3D

func setup(host: Node3D, r: AnimRig, ik: FootIK, lk: LookAtLayer) -> void:
	_host = host
	rig = r
	foot_ik = ik
	look = lk

func _process(delta: float) -> void:
	if _host == null or rig == null or rig.tree == null: return
	_t += delta
	if _t < 0.25: return
	_t = 0.0
	if _cam == null or not is_instance_valid(_cam):
		_cam = _host.get_viewport().get_camera_3d()
	var d := 0.0
	if _cam != null:
		d = _host.global_position.distance_to(_cam.global_position)
	var lv: int = Q.NEAR
	if d > far_dist: lv = Q.CULLED
	elif d > mid_dist: lv = Q.FAR
	elif d > near_dist: lv = Q.MEDIUM
	if is_player and lv > Q.MEDIUM: lv = Q.MEDIUM
	if lv == level: return
	level = lv
	_apply()

func _apply() -> void:
	match level:
		Q.NEAR:
			rig.tree.active = true
			rig.set_breathe(0.55)
			if foot_ik: foot_ik.influence = 1.0
			if look: look.influence = 1.0
		Q.MEDIUM:
			rig.tree.active = true
			rig.set_breathe(0.35)
			if foot_ik: foot_ik.influence = 0.55
			if look: look.influence = 0.7
		Q.FAR:
			rig.tree.active = true
			rig.set_breathe(0.0)
			if foot_ik: foot_ik.influence = 0.0
			if look: look.influence = 0.0
		Q.CULLED:
			rig.tree.active = false
			if foot_ik: foot_ik.influence = 0.0
			if look: look.influence = 0.0
