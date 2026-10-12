extends Node
## Collision audit. Boots the real Main scene, then measures:
##  1) terrain collision surface vs Terrain.sample_height() (the visual mesh),
##  2) how many solid bodies exist and what covers the authored props,
##  3) whether the player capsule rests at the right height.

var t := 0.0
var done := false
var world: Node = null
var terrain: Node = null

func _ready() -> void:
	process_priority = 900
	Perf.level = 0
	var ps: PackedScene = load("res://main/Main.tscn")
	var main: Node = ps.instantiate()
	main.name = "Main"
	add_child(main)
	await get_tree().create_timer(0.6).timeout
	if main.has_method("start_world"): main.start_world(false)

func _process(delta: float) -> void:
	t += delta
	if done or t < 8.0: return
	done = true
	_find()
	if terrain == null:
		print("AUDIT: no terrain"); get_tree().quit(); return
	_terrain_align()
	_body_census()
	_water_census()
	_prop_cover()
	await _stream_check()
	print("AUDIT: done")
	get_tree().quit()

func _find() -> void:
	for n in get_tree().get_nodes_in_group("world"):
		if n.get_class() == "Node3D" or n.has_method("warp_to"): world = n
	var st := [get_tree().root]
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n is Terrain: terrain = n
		for c in n.get_children(): st.append(c)

# ---------------------------------------------------------------- terrain
func _terrain_align() -> void:
	var space := get_viewport().world_3d.direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var n := 0
	var miss := 0
	var sum := 0.0
	var worst := 0.0
	var worst_p := Vector3.ZERO
	var steep_sum := 0.0
	var steep_n := 0
	var steep_worst := 0.0
	for i in 900:
		var x := rng.randf_range(20.0, terrain.size - 20.0)
		var z := rng.randf_range(20.0, terrain.size - 20.0)
		var hv: float = terrain.sample_height(x, z)
		var p := PhysicsRayQueryParameters3D.create(Vector3(x, hv + 60.0, z), Vector3(x, hv - 60.0, z))
		p.collision_mask = 1
		var r := space.intersect_ray(p)
		if r.is_empty():
			miss += 1
			continue
		n += 1
		var e: float = r["position"].y - hv
		sum += e
		if absf(e) > absf(worst):
			worst = e; worst_p = Vector3(x, hv, z)
		var sl: float = terrain.slope_at(x, z)
		if sl > 0.35:
			steep_n += 1
			steep_sum += e
			if absf(e) > absf(steep_worst): steep_worst = e
	print("TERRAIN rays=%d hits=%d miss=%d  mean_err=%+.3fm worst=%+.3fm at %v" % [900, n, miss, sum / maxf(1.0, float(n)), worst, worst_p])
	print("TERRAIN steep(slope>0.35) n=%d mean_err=%+.3fm worst=%+.3fm" % [steep_n, steep_sum / maxf(1.0, float(steep_n)), steep_worst])
	# lateral probe: walk a straight line and show the profile at 1m steps
	var line := ""
	for i in 24:
		var x := 300.0 + float(i) * 1.0
		var z := 300.0
		var hv: float = terrain.sample_height(x, z)
		var p := PhysicsRayQueryParameters3D.create(Vector3(x, hv + 40.0, z), Vector3(x, hv - 40.0, z))
		p.collision_mask = 1
		var r := space.intersect_ray(p)
		line += ("%+.2f " % (r["position"].y - hv)) if not r.is_empty() else "MISS "
	print("TERRAIN profile x=300..323 z=300 err: " + line)

# ---------------------------------------------------------------- bodies
func _body_census() -> void:
	var counts := {}
	var st := [get_tree().root]
	var total := 0
	while not st.is_empty():
		var nd: Node = st.pop_back()
		if nd is StaticBody3D or nd is CSGShape3D:
			total += 1
			var k: String = nd.get_parent().name if nd.get_parent() != null else "?"
			counts[k] = int(counts.get(k, 0)) + 1
		for c in nd.get_children(): st.append(c)
	print("BODIES static_total=%d" % total)
	var keys := counts.keys()
	keys.sort()
	var s := ""
	for k in keys: s += "%s=%d " % [k, counts[k]]
	print("BODIES by parent: " + s)

# ---------------------------------------------------------------- props
func _prop_cover() -> void:
	var f := FileAccess.open("res://assets/terrain/world.json", FileAccess.READ)
	if f == null: return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	var space := get_viewport().world_3d.direct_space_state
	var by_kind := {}
	for p in d.get("props", []):
		var k: String = p["kind"]
		if not by_kind.has(k): by_kind[k] = []
		if by_kind[k].size() < 8: by_kind[k].append(p)
	var keys := by_kind.keys()
	keys.sort()
	for k in keys:
		var solid := 0
		var tries := 0
		for p in by_kind[k]:
			tries += 1
			var x := float(p["x"]); var z := float(p["z"])
			var gy: float = terrain.sample_height(x, z)
			# shape query: a small sphere at chest height inside the prop
			var q := PhysicsShapeQueryParameters3D.new()
			var sp := SphereShape3D.new()
			sp.radius = 0.30
			q.shape = sp
			q.collision_mask = 1
			q.transform = Transform3D(Basis(), Vector3(x, gy + 1.0, z))
			if not space.intersect_shape(q, 4).is_empty(): solid += 1
		print("PROP %-12s samples=%d solid=%d" % [k, tries, solid])
	for lm in d.get("landmarks", []):
		var x := float(lm["x"]); var z := float(lm["z"])
		var gy: float = terrain.sample_height(x, z)
		var q := PhysicsShapeQueryParameters3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 0.30
		q.shape = sp
		q.collision_mask = 1
		q.transform = Transform3D(Basis(), Vector3(x, gy + 1.5, z))
		print("LANDMARK %-12s at %v solid=%s" % [lm["kind"], Vector2(x, z), not space.intersect_shape(q, 4).is_empty()])

# ---------------------------------------------------------------- streaming
func _stream_check() -> void:
	var solids = null
	var st := [get_tree().root]
	while not st.is_empty():
		var nd: Node = st.pop_back()
		if nd is SolidBodies: solids = nd
		for c in nd.get_children(): st.append(c)
	if solids == null:
		print("STREAM: SolidBodies missing"); return
	print("STREAM structures=%d streamed_items=%d" % [solids.structures, solids.streamed_items])
	# stop the live follower from re-streaming onto the player between our
	# prime() and our query
	solids.player = null
	var f := FileAccess.open("res://assets/terrain/world.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	var space := get_viewport().world_3d.direct_space_state
	var sets := {"tree": d.get("trees", []), "rock": []}
	for p in d.get("props", []):
		if String(p.get("kind", "")) == "rock" and sets["rock"].size() < 400: sets["rock"].append(p)
	for label in ["tree", "rock"]:
		var items: Array = sets[label]
		if items.is_empty(): continue
		var hit := 0
		var tries := 0
		var step: int = maxi(1, items.size() / 12)
		for i in range(0, items.size(), step):
			if tries >= 12: break
			var it: Dictionary = items[i]
			var x := float(it.get("x", 0.0)); var z := float(it.get("z", 0.0))
			# stream the region in, exactly like walking there would
			solids.prime(Vector3(x, 0.0, z))
			await get_tree().physics_frame
			tries += 1
			var gy: float = terrain.sample_height(x, z)
			var q := PhysicsShapeQueryParameters3D.new()
			var sp := SphereShape3D.new()
			sp.radius = 0.22
			q.shape = sp
			q.collision_mask = 1
			q.transform = Transform3D(Basis(), Vector3(x, gy + 1.0, z))
			if not space.intersect_shape(q, 4).is_empty(): hit += 1
		print("STREAM %-6s samples=%d solid=%d active=%d" % [label, tries, hit, solids.active])

func _water_census() -> void:
	var st: Array = [get_tree().root]
	while not st.is_empty():
		var nd: Node = st.pop_back()
		if nd is WaterSystem:
			print("WATER lake_quads=%d river_quads=%d falls=%d" % [nd.lake_quads, nd.river_quads, nd.falls])
			return
		for c in nd.get_children(): st.append(c)
	print("WATER: none")
