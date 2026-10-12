class_name PoseLayer
extends SkeletonModifier3D
## Upper-body override.  After the AnimationPlayer has posed the whole body, this
## modifier re-poses a masked set of bones from a second clip, so the legs can run
## while the arms hold the sword in guard (or ride, or brace behind a block).
##
## `influence` (built into SkeletonModifier3D) fades the whole layer in and out;
## per-bone weights shape the mask (a spine that only half follows, and so on).
## `offsets` are extra local rotations stacked on top afterwards (rider legs).

var clip: Animation
var clip_t := 0.0
var speed := 1.0
var loop := true
var hold_at := -1.0          ## >= 0: freeze the clip on this time
var _bones := PackedInt32Array()
var _weights := PackedFloat32Array()
var _tracks := PackedInt32Array()
var offsets := {}            ## bone index -> Quaternion, a model-space turn about the bone's head
                             ## applied after the layer, in insertion order (parents first)

## mask: {bone_name: weight}
func set_mask(sk: Skeleton3D, mask: Dictionary) -> void:
	_bones = PackedInt32Array(); _weights = PackedFloat32Array()
	for bn in mask:
		var b := sk.find_bone(bn)
		if b < 0: continue
		_bones.append(b); _weights.append(float(mask[bn]))
	_bind_tracks()

func set_clip(a: Animation, at := -1.0) -> void:
	if a == clip and at == hold_at: return
	clip = a
	hold_at = at
	if a != null and at >= 0.0: clip_t = at
	_bind_tracks()

func _bind_tracks() -> void:
	_tracks = PackedInt32Array()
	var sk := get_skeleton()
	for i in _bones.size():
		var ti := -1
		if clip != null and sk != null:
			ti = clip.find_track(NodePath("Skeleton3D:" + sk.get_bone_name(_bones[i])), Animation.TYPE_ROTATION_3D)
		_tracks.append(ti)

func advance(delta: float) -> void:
	if clip == null or hold_at >= 0.0: return
	clip_t += delta * speed
	if loop: clip_t = fposmod(clip_t, maxf(clip.length, 0.01))
	else: clip_t = minf(clip_t, clip.length)

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null: return
	if clip != null:
		if _tracks.size() != _bones.size(): _bind_tracks()
		var t := hold_at if hold_at >= 0.0 else clip_t
		for i in _bones.size():
			var ti := _tracks[i]
			if ti < 0: continue
			var q: Quaternion = clip.rotation_track_interpolate(ti, t)
			var w := _weights[i]
			if w < 0.999:
				q = sk.get_bone_pose_rotation(_bones[i]).slerp(q, w)
			sk.set_bone_pose_rotation(_bones[i], q)
	for b in offsets:
		var par := sk.get_bone_parent(b)
		var pg: Basis = sk.get_bone_global_pose(par).basis if par >= 0 else Basis.IDENTITY
		var g: Basis = sk.get_bone_global_pose(b).basis
		var nb: Basis = Basis(offsets[b] as Quaternion) * g
		sk.set_bone_pose_rotation(b, (pg.inverse() * nb).get_rotation_quaternion())
