extends SceneTree
## Prints Atmosphere.LUM: the cosine-weighted luminance of the clear upper
## hemisphere for each sun elevation in Atmosphere.LUM_EL, integrated densely
## with the CPU twin of the sky shader. Re-run after changing the model:
##   godot --headless --path . -s tools/sky_table.gd

func _init() -> void:
	var out := []
	var nz := 18
	var na := 48
	for el in Atmosphere.LUM_EL:
		var er := deg_to_rad(float(el))
		var sd := Vector3(0.0, sin(er), -cos(er))
		var acc := 0.0
		var wsum := 0.0
		for iz in nz:
			# uniform in elevation; weight = solid angle (cos el) * cosine (sin el)
			var e := (float(iz) + 0.5) / float(nz) * PI * 0.5
			var w := cos(e) * sin(e)
			for ia in na:
				var a := (float(ia) + 0.5) / float(na) * TAU
				var d := Vector3(cos(e) * sin(a), sin(e), -cos(e) * cos(a))
				var c := Atmosphere.inscatter(d, sd, 1.4, 12)
				acc += (c.x * 0.2126 + c.y * 0.7152 + c.z * 0.0722) * w
				wsum += w
		out.append(acc / wsum)
	print("LUM_TABLE ", out)
	quit()
