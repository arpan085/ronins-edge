extends Node3D
var d: AnimDriver
var n := 0
var prev := Vector3.ZERO
func _ready() -> void:
	d = AnimDriver.new()
	add_child(d)
	d.build(self, "res://assets/models/Kaito_Ronin.glb", "kaito", true)
	d.lod.set_process(false)
	d.foot_ik.active = false
	d.look.active = false
	d.rig.travel("Move")
	d.rig.set_locomotion(0.0, 2.0, true)
	d.rig.set_breathe(0.0)
	print("jogF meta speed=", d.rig.clip_ground_speed("Jog_F"), " targets=", d._row_target)
func _physics_process(dt: float) -> void:
	d.rig.update(dt)
	d.rig.set_loco_speed(2.42 / d.rig.clip_ground_speed("Jog_F"))
	n += 1
	var l := d.ankle_world("L")
	if n > 30 and n <= 75:
		print("%d z=%.4f dz/dt=%.3f y=%.3f" % [n, l.z, (l.z - prev.z) / dt, l.y])
	prev = l
	if n > 75:
		print("PROBE_DONE"); get_tree().quit()
