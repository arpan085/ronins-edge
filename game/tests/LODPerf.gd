extends Node3D
## v0.19: what the soldier LOD buys on the CPU. Spawns a camp's worth of
## soldiers at 6-90 m from a camera, ticks them like EnemyBase does and times
## whole frames with the LOD off, then on (twice). Prints LODPERF lines.
##   godot --headless --path . res://tests/LODPerf.tscn -- --n 36 --frames 240
var drivers := []
var cam: Camera3D
func _ready() -> void:
	var args := {}
	var ua := OS.get_cmdline_user_args()
	for i in range(0, ua.size() - 1):
		if ua[i].begins_with("--"): args[ua[i].substr(2)] = ua[i + 1]
	var n := int(args.get("n", 36))
	var frames := int(args.get("frames", 240))
	cam = Camera3D.new(); add_child(cam); cam.current = true
	var kinds := ["ashigaru", "archer", "captain"]
	var t0 := Time.get_ticks_msec()
	for k in n:
		var host := Node3D.new()
		var d0 := lerpf(6.0, 90.0, float(k) / maxf(1.0, n - 1.0))
		var a := k * 2.39996
		host.position = Vector3(sin(a) * d0, 0, -cos(a) * d0)
		add_child(host)
		var d := UBCDriver.new()
		host.add_child(d)
		if d.build(host, "", kinds[k % 3], false): drivers.append(d)
	print("LODPERF built %d soldiers in %d ms" % [drivers.size(), Time.get_ticks_msec() - t0])
	for mode in [false, true, false, true]:
		UBCDriver.lod_enabled = mode
		await _run(30)  # settle
		var r := await _run(frames)
		var lv := [0, 0, 0, 0]
		for d in drivers: lv[d.lod_level] += 1
		print("LODPERF lod=%s  %.3f ms/frame (tick %.3f ms)  levels %s" % [str(mode), r[0], r[1], str(lv)])
	UBCDriver.lod_enabled = true
	get_tree().quit()

func _run(frames: int) -> Array:
	var tick_us := 0
	var start := Time.get_ticks_usec()
	for f in frames:
		var t := Time.get_ticks_usec()
		var dt := 1.0 / 60.0
		for i in drivers.size():
			var d: UBCDriver = drivers[i]
			# half of them walk in place, like a patrol
			var v := Vector3(0, 0, 1.4) if i % 2 == 0 else Vector3.ZERO
			d.tick(dt, v, 0.0, i % 2 == 0)
		tick_us += Time.get_ticks_usec() - t
		await get_tree().process_frame
	var tot := Time.get_ticks_usec() - start
	return [tot / 1000.0 / frames, tick_us / 1000.0 / frames]
