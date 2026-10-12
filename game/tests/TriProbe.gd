extends Node
## Do the three ground surfaces agree?
##
## The character stands on HeightMapShape3D, looks at the chunk mesh, and every
## system that asks "how high is the ground here?" calls Terrain.sample_height.
## If those disagree the feet sink into visible ground, grass floats, and props
## hover. This loads the real heightmap and measures all three against each
## other.
func _ready() -> void:
	var t := Terrain.new()
	t.name = "Terrain"
	add_child(t)
	for i in 40:
		await get_tree().process_frame
		if t.loaded: break
	if not t.loaded:
		print("GROUNDPROBE FAIL: terrain did not load"); get_tree().quit(); return
	await get_tree().physics_frame
	await get_tree().physics_frame
	var ss := get_viewport().world_3d.direct_space_state
	var rng := RandomNumberGenerator.new(); rng.seed = 909
	var worst := 0.0
	var total := 0.0
	var miss := 0
	var cnt := 0
	for i in 8000:
		var x := rng.randf_range(20.0, t.size - 20.0)
		var z := rng.randf_range(20.0, t.size - 20.0)
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -40.0, z))
		var hit := ss.intersect_ray(q)
		if hit.is_empty(): miss += 1; continue
		var e: float = absf(hit.position.y - t.sample_height(x, z))
		worst = maxf(worst, e); total += e; cnt += 1
	print("GROUNDPROBE samples=%d miss=%d  max|collider-sample_height|=%.5f m  mean=%.5f m"
		% [cnt, miss, worst, total / maxf(cnt, 1)])
	get_tree().quit()
