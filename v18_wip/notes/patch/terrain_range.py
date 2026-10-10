p='/data/ronins_edge/game/world/Terrain.gd'
s=open(p).read()
a=s.index('func _build_distant_range() -> void:')
b=s.index('## One ridge span')
new='''func _build_distant_range() -> void:
	# v0.14: a real heightfield ring of hills and mountains around the map
	# (v0.13 stood flat ridge cut-outs on a circle). The polar grid starts
	# exactly on the playable square's edge at the terrain's own edge height,
	# so there is no gap or cliff at the border.
	# v0.17: ~4x the resolution (1024 bearings x ~60 rings, written straight
	# into an ArrayMesh instead of through SurfaceTool) and real mountain
	# shapes: domain-warped ridged noise with weighted octaves - sharp crests,
	# smoother valley floors - under a massif envelope, forested foothills
	# near the border and a high rocky range 2.5-4.7 km out, with crags on
	# the crests. Layered ridgelines instead of one smooth pale wall;
	# distant_land.gdshader adds the small relief, rock, snow and cloud
	# shadows, and the depth fog hazes each ridge a little more than the last.
	var cx := size * 0.5
	var cz := size * 0.5
	var half := size * 0.5
	var na := 1024
	var offs := PackedFloat32Array([-1.0])
	var od := 20.0
	while od < 4700.0:
		offs.append(od)
		od += clampf(od * 0.09, 20.0, 150.0)
	offs.append(4700.0)
	var nr := offs.size()
	var mass := FastNoiseLite.new()
	mass.seed = 4127
	mass.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mass.fractal_type = FastNoiseLite.FRACTAL_FBM
	mass.fractal_octaves = 3
	mass.frequency = 1.0 / 3400.0
	var ridge := FastNoiseLite.new()
	ridge.seed = 7731
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 6
	ridge.fractal_lacunarity = 2.05
	ridge.fractal_weighted_strength = 0.55
	ridge.frequency = 1.0 / 1500.0
	ridge.domain_warp_enabled = true
	ridge.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	ridge.domain_warp_amplitude = 260.0
	ridge.domain_warp_frequency = 1.0 / 1900.0
	ridge.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_PROGRESSIVE
	ridge.domain_warp_fractal_octaves = 2
	var hills := FastNoiseLite.new()
	hills.seed = 911
	hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	hills.fractal_octaves = 5
	hills.frequency = 1.0 / 520.0
	var crag := FastNoiseLite.new()
	crag.seed = 5519
	crag.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	crag.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	crag.fractal_octaves = 3
	crag.frequency = 1.0 / 230.0
	var nv := na * nr
	var pos := PackedVector3Array()
	pos.resize(nv)
	var uvs := PackedVector2Array()
	uvs.resize(nv)
	for ia in na:
		var th := TAU * float(ia) / float(na)
		var dx := cos(th)
		var dz := sin(th)
		var rin := half / maxf(absf(dx), absf(dz))
		var eh := sample_height(cx + dx * (rin - 2.0), cz + dz * (rin - 2.0))
		for ir in nr:
			var d: float = offs[ir]
			var r := rin + d
			var x := cx + dx * r
			var z := cz + dz * r
			var h := eh - 0.8
			if ir > 0:
				var hl := hills.get_noise_2d(x, z) * 0.5 + 0.5
				var rr := clampf((ridge.get_noise_2d(x, z) * 0.5 + 0.5 - 0.38) / 0.55, 0.0, 1.0)
				var ms := mass.get_noise_2d(x, z) * 0.5 + 0.5
				var foot := 30.0 + 170.0 * hl + 80.0 * rr * rr
				var hi := 150.0 + (600.0 + 800.0 * ms) * pow(rr, 1.6) + 90.0 * hl
				var far := smoothstep(300.0, 2500.0, d)
				var mh := lerpf(foot, hi, far)
				mh += (crag.get_noise_2d(x, z) * 0.5 + 0.5) * 75.0 * far * smoothstep(0.30, 0.75, rr)
				h = lerpf(eh, eh * 0.55 + mh, smoothstep(0.0, 520.0, d))
			pos[ia * nr + ir] = Vector3(x, h, z)
			uvs[ia * nr + ir] = Vector2(maxf(d, 0.0), 0.0)
	var nrm := PackedVector3Array()
	nrm.resize(nv)
	for ia in na:
		var ja := ((ia + 1) % na) * nr
		var jb := ((ia - 1 + na) % na) * nr
		var i0 := ia * nr
		for ir in nr:
			var n := (pos[i0 + mini(ir + 1, nr - 1)] - pos[i0 + maxi(ir - 1, 0)]).cross(
				pos[ja + ir] - pos[jb + ir]).normalized()
			if n.y < 0.0: n = -n
			nrm[i0 + ir] = n
	var idx := PackedInt32Array()
	idx.resize(na * (nr - 1) * 6)
	var k := 0
	for ia in na:
		var a0 := ia * nr
		var b0 := ((ia + 1) % na) * nr
		for ir in nr - 1:
			# clockwise seen from above: A -> D -> C, A -> C -> B
			idx[k] = a0 + ir; idx[k + 1] = a0 + ir + 1; idx[k + 2] = b0 + ir + 1
			idx[k + 3] = a0 + ir; idx[k + 4] = b0 + ir + 1; idx[k + 5] = b0 + ir
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "DistantRange"
	mi.mesh = am
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/distant_land.gdshader")
	if _mat != null:
		m.set_shader_parameter("albedo_arr", _mat.get_shader_parameter("albedo_arr"))
		m.set_shader_parameter("macro_tex", _mat.get_shader_parameter("macro_tex"))
	mi.material_override = m
	mi.extra_cull_margin = 64.0
	add_child(mi)

'''
s=s[:a]+new+s[b:]
open(p,'w').write(s)
print("terrain ok")
