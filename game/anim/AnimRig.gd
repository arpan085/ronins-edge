class_name AnimRig
extends Node
## Runtime animation system: a locomotion state machine with a 2D blend space,
## an additive breathing layer, and two one-shot layers for actions and reactions.
## Gameplay code never hard-switches clips; it sets parameters and fires shots.

## Blend grid rows: y = signed speed tier, x = strafe. Clips are repeated across
## a row so the triangulation is always well formed (auto-triangulation fails on
## collinear points and silently produces a frozen pose).
const LOCO_ROWS := [
	{"y": -2.0, "c": ["Jog_L",  "Jog_B",    "Jog_R"]},
	{"y": -1.0, "c": ["Walk_L", "Walk_B",   "Walk_R"]},
	{"y":  0.0, "c": ["Walk_L", "Idle_Loco", "Walk_R"]},
	{"y":  1.0, "c": ["Walk_L", "Walk_F",   "Walk_R"]},
	{"y":  2.0, "c": ["Jog_L",  "Jog_F",    "Jog_R"]},
	{"y":  3.0, "c": ["Jog_L",  "Sprint_F", "Jog_R"]},
]
const LOCO_X := [-1.0, 0.0, 1.0]

# loco states that hold or loop; everything else runs through the one-shot layers
const HOLD_STATES := {
	"Move": "", "IdleB": "Idle_B", "IdleC": "Idle_C",
	"StartRun": "Start_Run", "StopRun": "Stop_Run", "StopWalk": "Stop_Walk",
	"TurnL45": "Turn_L45", "TurnR45": "Turn_R45",
	"TurnL90": "Turn_L90", "TurnR90": "Turn_R90",
	"TurnL180": "Turn_L180", "TurnR180": "Turn_R180",
	"JumpUp": "Jump_Up", "JumpAir": "Jump_Air", "JumpLand": "Jump_Land",
	"BlockIn": "Block_In", "BlockIdle": "Block_Idle",
	"Knocked": "Knockdown_B", "GetUp": "GetUp_A",
	"DeathA": "Death_A", "DeathB": "Death_B",
	"Investigate": "Investigate", "Shuffle": "Shuffle", "HoldDraw": "HoldDraw",
	"IdleBoss": "Idle_Boss",
}

const ACTION_CLIPS := [
	"Light1", "Light2", "Light3", "Heavy", "Deflect", "Block_Impact", "Deathblow",
	"Dodge_F", "Dodge_B", "Dodge_L", "Dodge_R", "Roll_F", "Sheathe", "Unsheathe",
	"Cine_Arrive", "Cine_Discover", "Cine_Bow",
	"Attack", "Sweep", "Block", "Nock", "AimIn", "Shoot", "BackStep",
	"Attack1", "Attack2", "Attack3", "Intimidate", "EnterCombat",
	"PhaseTransition", "Defeat", "Alert",
]
const REACT_CLIPS := [
	"Hit_F", "Hit_B", "Hit_L", "Hit_R", "HitHeavy_F", "HitHeavy_B",
	"Stagger_A", "Stagger_B", "Flinch",
]

var tree: AnimationTree
var player: AnimationPlayer
var skel: Skeleton3D
var kind := ""
var available := {}          # clip name -> true
var meta := {}               # per-clip metadata from the Blender build
var _sm: AnimationNodeStateMachinePlayback
var _actions: Array[String] = []
var _reacts: Array[String] = []
var _cur_action := ""
var _cur_react := ""
var _loco := Vector2.ZERO
var _loco_target := Vector2.ZERO
var _ready_ok := false
var blend_points := 0
var loops_applied := 0
var blend_triangles := 0

func setup(ap: AnimationPlayer, sk: Skeleton3D, character: String, anim_meta: Dictionary) -> bool:
	player = ap
	skel = sk
	kind = character
	meta = anim_meta.get("clips", {})
	if player == null:
		push_warning("AnimRig: no AnimationPlayer")
		return false
	for n in player.get_animation_list():
		available[_short(n)] = n
	# glTF carries no loop flag, so every clip imports as play-once and freezes
	# on its last frame. Restore the authored loop mode from the build metadata.
	_apply_loop_modes()
	var bt := AnimationNodeBlendTree.new()
	var loco := _build_loco()
	bt.add_node("loco", loco, Vector2(0, 0))
	bt.add_node("ts_loco", AnimationNodeTimeScale.new(), Vector2(260, 0))
	bt.connect_node("ts_loco", 0, "loco")
	var add := AnimationNodeAdd2.new()
	bt.add_node("add_breathe", add, Vector2(460, 0))
	bt.connect_node("add_breathe", 0, "ts_loco")
	if available.has("Breathe_Add"):
		var br := AnimationNodeAnimation.new()
		br.animation = available["Breathe_Add"]
		bt.add_node("breathe", br, Vector2(260, 160))
		bt.connect_node("add_breathe", 1, "breathe")
	var act := _build_transition(ACTION_CLIPS, _actions)
	bt.add_node("act", act, Vector2(260, 320))
	bt.add_node("ts_act", AnimationNodeTimeScale.new(), Vector2(460, 320))
	bt.connect_node("ts_act", 0, "act")
	var os_act := AnimationNodeOneShot.new()
	os_act.fadein_time = 0.06
	os_act.fadeout_time = 0.14
	os_act.break_loop_at_end = true
	bt.add_node("os_act", os_act, Vector2(660, 0))
	bt.connect_node("os_act", 0, "add_breathe")
	bt.connect_node("os_act", 1, "ts_act")
	var rea := _build_transition(REACT_CLIPS, _reacts)
	bt.add_node("react", rea, Vector2(460, 520))
	var os_re := AnimationNodeOneShot.new()
	os_re.fadein_time = 0.04
	os_re.fadeout_time = 0.16
	os_re.break_loop_at_end = true
	bt.add_node("os_react", os_re, Vector2(860, 0))
	bt.connect_node("os_react", 0, "os_act")
	bt.connect_node("os_react", 1, "react")
	bt.connect_node("output", 0, "os_react")

	tree = AnimationTree.new()
	tree.name = "AnimTree"
	tree.tree_root = bt
	tree.anim_player = tree.get_path_to(player)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	tree.active = true
	player.get_parent().add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	if skel != null:
		skel.set_modifier_callback_mode_process(Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS)
		var idx := skel.find_bone("root")
		if idx >= 0:
			tree.root_motion_track = NodePath("%s:root" % [tree.get_path_to(skel)])
	_sm = tree.get("parameters/loco/playback")
	_ready_ok = _sm != null
	if _ready_ok:
		_sm.start("Move")
	set_breathe(0.55)
	return _ready_ok

func _short(n: String) -> String:
	var s := n
	var i := s.rfind("/")
	if i >= 0: s = s.substr(i + 1)
	return s

func _anim_node(clip: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = available[clip]
	return a

func _apply_loop_modes() -> void:
	var looped := 0
	for short in available.keys():
		var a: Animation = player.get_animation(available[short])
		if a == null: continue
		var m: Dictionary = meta.get(short, {})
		if bool(m.get("loop", false)):
			a.loop_mode = Animation.LOOP_LINEAR
			looped += 1
		else:
			a.loop_mode = Animation.LOOP_NONE
	loops_applied = looped

func _build_loco() -> AnimationNodeStateMachine:
	var sm := AnimationNodeStateMachine.new()
	var bs := AnimationNodeBlendSpace2D.new()
	bs.auto_triangles = false
	bs.min_space = Vector2(-1.0, -2.0)
	bs.max_space = Vector2(1.0, 3.0)
	bs.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	var grid := []
	var added := 0
	for row in LOCO_ROWS:
		var idxs := []
		for ci in range(3):
			var clip: String = row["c"][ci]
			if not available.has(clip):
				clip = "Idle_A" if available.has("Idle_A") else ""
			if clip == "":
				idxs.append(-1); continue
			bs.add_blend_point(_anim_node(clip), Vector2(LOCO_X[ci], row["y"]))
			idxs.append(added)
			added += 1
		grid.append(idxs)
	for r in range(grid.size() - 1):
		for c in range(2):
			var a: int = grid[r][c]
			var b: int = grid[r][c + 1]
			var d: int = grid[r + 1][c]
			var e: int = grid[r + 1][c + 1]
			if a < 0 or b < 0 or d < 0 or e < 0: continue
			bs.add_triangle(a, b, d)
			bs.add_triangle(b, e, d)
	blend_points = added
	blend_triangles = bs.get_triangle_count()
	sm.add_node("Move", bs, Vector2(300, 100))
	var made := ["Move"]
	for st in HOLD_STATES.keys():
		if st == "Move": continue
		var clip: String = HOLD_STATES[st]
		if not available.has(clip): continue
		sm.add_node(st, _anim_node(clip), Vector2(600, 100 + made.size() * 60))
		made.append(st)
	# hub-and-spoke: every state blends out of and back into Move
	var fades := {
		"IdleB": 0.55, "IdleC": 0.55, "StartRun": 0.10, "StopRun": 0.10,
		"StopWalk": 0.14, "TurnL45": 0.14, "TurnR45": 0.14, "TurnL90": 0.12,
		"TurnR90": 0.12, "TurnL180": 0.12, "TurnR180": 0.12,
		"JumpUp": 0.08, "JumpAir": 0.10, "JumpLand": 0.08,
		"BlockIn": 0.09, "BlockIdle": 0.12, "Knocked": 0.06, "GetUp": 0.10,
		"DeathA": 0.10, "DeathB": 0.10, "Investigate": 0.35, "Shuffle": 0.30,
		"HoldDraw": 0.18, "IdleBoss": 0.45,
	}
	var auto_back := {
		"StartRun": true, "StopRun": true, "StopWalk": true,
		"TurnL45": true, "TurnR45": true, "TurnL90": true, "TurnR90": true,
		"TurnL180": true, "TurnR180": true, "JumpLand": true, "GetUp": true,
	}
	for st in made:
		if st == "Move": continue
		var f: float = fades.get(st, 0.15)
		_link(sm, "Move", st, f, false)
		var back_auto: bool = auto_back.get(st, false)
		if st in ["DeathA", "DeathB", "Knocked"]:
			continue
		_link(sm, st, "Move", f, back_auto)
	# chained sequences
	if sm.has_node("JumpUp") and sm.has_node("JumpAir"):
		_link(sm, "JumpUp", "JumpAir", 0.10, true)
	if sm.has_node("JumpAir") and sm.has_node("JumpLand"):
		_link(sm, "JumpAir", "JumpLand", 0.08, false)
	if sm.has_node("BlockIn") and sm.has_node("BlockIdle"):
		_link(sm, "BlockIn", "BlockIdle", 0.10, true)
	if sm.has_node("Knocked") and sm.has_node("GetUp"):
		_link(sm, "Knocked", "GetUp", 0.14, false)
	if sm.has_node("StartRun"):
		_link(sm, "StartRun", "Move", 0.12, true)
	return sm

func _link(sm: AnimationNodeStateMachine, a: String, b: String, xf: float, auto: bool) -> void:
	if not sm.has_node(a) or not sm.has_node(b): return
	if sm.has_transition(a, b): return
	var t := AnimationNodeStateMachineTransition.new()
	t.xfade_time = xf
	t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
	t.advance_mode = (AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO if auto
		else AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED)
	t.reset = false
	sm.add_transition(a, b, t)

func _build_transition(clips: Array, out_names: Array[String]) -> AnimationNodeTransition:
	var tn := AnimationNodeTransition.new()
	tn.xfade_time = 0.07
	tn.allow_transition_to_self = true
	var n := 0
	for c in clips:
		if not available.has(c): continue
		out_names.append(c)
		n += 1
	tn.input_count = max(n, 1)
	for i in range(out_names.size()):
		tn.set("input_%d/name" % i, out_names[i])
		tn.set("input_%d/break_loop_at_end" % i, true)
	return tn

# ------------------------------------------------------------------ driving
func ok() -> bool:
	return _ready_ok

func has_clip(c: String) -> bool:
	return available.has(c)

func set_locomotion(strafe: float, fwd: float, snap := false) -> void:
	if not _ready_ok: return
	_loco_target = Vector2(strafe, fwd)
	if snap: _loco = _loco_target

func update(dt: float) -> void:
	if not _ready_ok: return
	# damp the blend position so speed changes never pop
	var rate := 9.0
	_loco = _loco.lerp(_loco_target, clamp(rate * dt, 0.0, 1.0))
	tree.set("parameters/loco/Move/blend_position", _loco)

func set_breathe(a: float) -> void:
	if tree == null: return
	tree.set("parameters/add_breathe/add_amount", clamp(a, 0.0, 1.0))

func set_loco_speed(s: float) -> void:
	if tree == null: return
	tree.set("parameters/ts_loco/scale", clamp(s, 0.1, 3.0))

func set_action_speed(s: float) -> void:
	if tree == null: return
	tree.set("parameters/ts_act/scale", clamp(s, 0.1, 3.0))

func has_state(state: String) -> bool:
	if not _ready_ok: return false
	var sm := tree.tree_root.get_node("loco") as AnimationNodeStateMachine
	return sm != null and sm.has_node(state)

func travel(state: String) -> void:
	if not _ready_ok: return
	if _sm.get_current_node() == state: return
	if not has_state(state): return
	_sm.travel(state)

func force_state(state: String) -> void:
	if not _ready_ok: return
	_sm.start(state)

func loco_state() -> String:
	if not _ready_ok: return ""
	return _sm.get_current_node()

func play_action(clip: String, xfade := 0.07, speed := 1.0) -> bool:
	if not _ready_ok or not clip in _actions: return false
	tree.set("parameters/act/xfade_time", xfade)
	tree.set("parameters/act/transition_request", clip)
	tree.set("parameters/ts_act/scale", clamp(speed, 0.1, 3.0))
	tree.set("parameters/os_act/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_cur_action = clip
	return true

func play_reaction(clip: String, xfade := 0.04) -> bool:
	if not _ready_ok or not clip in _reacts: return false
	tree.set("parameters/react/xfade_time", xfade)
	tree.set("parameters/react/transition_request", clip)
	tree.set("parameters/os_react/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_cur_react = clip
	return true

func abort_action(fade := true) -> void:
	if not _ready_ok: return
	tree.set("parameters/os_act/request", (AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT
		if fade else AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT))
	_cur_action = ""

func abort_reaction() -> void:
	if not _ready_ok: return
	tree.set("parameters/os_react/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	_cur_react = ""

func action_active() -> bool:
	if not _ready_ok: return false
	return bool(tree.get("parameters/os_act/active"))

func reaction_active() -> bool:
	if not _ready_ok: return false
	return bool(tree.get("parameters/os_react/active"))

func current_action() -> String:
	return _cur_action

func clip_len(clip: String) -> float:
	if not available.has(clip): return 0.0
	var a := player.get_animation(available[clip])
	return 0.0 if a == null else a.length

func clip_meta(clip: String) -> Dictionary:
	return meta.get(clip, {})

## Speed at which a locomotion clip's planted foot matches the ground, in m/s.
## Runtime snapshot used by the QA harness to explain a bad pose.
func debug_state() -> Dictionary:
	if tree == null: return {}
	var pb = tree.get("parameters/loco/playback")
	var st := ""
	var travelling := false
	if pb != null:
		st = String(pb.get_current_node())
		travelling = pb.is_playing() and pb.get_travel_path().size() > 0
	return {
		"state": st,
		"pos": float(tree.get("parameters/loco/current_position")) if pb != null else 0.0,
		"blend": _loco,
		"ts": float(tree.get("parameters/ts_loco/scale")),
		"act": int(tree.get("parameters/os_act/active") == true),
		"react": int(tree.get("parameters/os_react/active") == true),
		"active": int(tree.active),
		"travel": int(travelling),
	}

func clip_ground_speed(clip: String) -> float:
	var m: Dictionary = meta.get(clip, {})
	return float(m.get("speed_mps", 0.0))

## Ground velocity the clip's planted foot implies, as (lateral, forward) m/s.
func clip_ground_vel(clip: String) -> Vector2:
	var m: Dictionary = meta.get(clip, {})
	var fv: Array = m.get("foot_vel", [])
	if fv.size() < 2: return Vector2.ZERO
	return Vector2(float(fv[0]), float(fv[1]))

func root_motion() -> Vector3:
	if tree == null: return Vector3.ZERO
	return tree.get_root_motion_position()
