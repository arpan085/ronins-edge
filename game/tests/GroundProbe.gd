extends Node3D
## v0.22 probe: a soldier standing across a slope. Prints each sole's gap to the
## ground with the foot IK on and off, and counts footfalls while walking.
##   godot --headless --path . res://tests/GroundProbe.tscn -- --slope 20
var falls := 0
var _post := {}
func _arg(k: String, d: String) -> String:
	var ua := OS.get_cmdline_user_args()
	var i := ua.find("--" + k)
	return ua[i + 1] if i >= 0 and i + 1 < ua.size() else d

func _ready() -> void:
	var th := deg_to_rad(float(_arg("slope", "20")))
	var sb := StaticBody3D.new(); add_child(sb)
	var cs := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(20, 1, 20)
	cs.shape = bx; sb.add_child(cs)
	sb.rotation = Vector3(0, 0, th)
	sb.position = Vector3(0.5 * sin(th), -0.5 * cos(th), 0)
	var host := Node3D.new(); add_child(host)
	var drv := UBCDriver.new(); host.add_child(drv)
	if not drv.build(host, "", "ashigaru", false):
		print("GROUND build failed"); get_tree().quit(1); return
	drv.foot_ik.footfall.connect(func(_s, _p): falls += 1)
	drv.foot_ik.modification_processed.connect(func(): _post = drv.ankle_gaps())
	await get_tree().create_timer(1.5).timeout
	var on: Dictionary = _post
	print("GROUND animated (pre-IK) gap L=%.3f R=%.3f" % [drv.ankle_gaps().get("L", 9), drv.ankle_gaps().get("R", 9)])
	var fk: FootIK = drv.foot_ik
	print("GROUND dbg lift=", fk._lift, " pel=", fk._pelvis_off, " ah=", fk.ankle_height, " infl=", fk.influence, " act=", fk.active, " grounded=", fk._grounded, " ankleL=", fk.ankle_world("L"), " ankleR=", fk.ankle_world("R"), " host=", host.global_position, " skel=", drv.skeleton.global_transform.origin, " gapL=", fk.sole_gap("L"))
	drv.foot_ik.active = false
	await get_tree().create_timer(0.4).timeout
	var off: Dictionary = drv.ankle_gaps()
	for c in ["Idle", "Walk", "Jog_Fwd", "Sprint"]:
		drv.ubc.play_loop(c, 0.0, 1.0)
		await get_tree().create_timer(0.5).timeout
		var lo := 9.0
		for i in 12:
			await get_tree().create_timer(0.05).timeout
			var gg: Dictionary = drv.ankle_gaps()
			lo = minf(lo, minf(gg.get("L", 9), gg.get("R", 9)))
		print("GROUND clip %s lowest animated sole gap on 20deg slope=%.3f" % [c, lo])
	print("GROUND slope=%.0f IK on  L=%.3f R=%.3f" % [rad_to_deg(th), on.get("L", 9), on.get("R", 9)])
	print("GROUND slope=%.0f IK off L=%.3f R=%.3f" % [rad_to_deg(th), off.get("L", 9), off.get("R", 9)])
	drv.foot_ik.active = true
	drv.ubc.play_loop("Walk", 0.2, 1.0)
	await get_tree().create_timer(0.6).timeout
	falls = 0
	var mx := -9.0
	var mn := 9.0
	for i in 60:
		await get_tree().create_timer(0.05).timeout
		var g: Dictionary = _post
		mn = minf(mn, minf(g.get("L", 9), g.get("R", 9)))
		mx = maxf(mx, maxf(g.get("L", -9), g.get("R", -9)))
	print("GROUND walk 3 s: footfalls=%d  sole gap min=%.3f max=%.3f  live=%d" % [falls, mn, mx, drv.foot_ik.live_frames])
	get_tree().quit()
