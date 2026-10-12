class_name WaterSystem
extends Node3D
## Lake, rivers and waterfalls.
##
## Surfaces are built from the terrain data: the lake from cells below the water
## plane, rivers from the generator's river mask following the real downhill
## flow direction, and waterfalls where the channel drops sharply. Depth is
## baked into vertex colour so the shader can foam the shoreline without
## sampling a depth texture (keeps it usable on the mobile renderer).

var terrain: Terrain
var _mat: ShaderMaterial
var _river_mat: ShaderMaterial      ## v0.13 main river ribbon (flow_mode 1)
var _sheet_mat: ShaderMaterial      ## waterfall sheets
var _pool_mat: ShaderMaterial       ## plunge-pool foam discs
var _noise: Texture2D
var _mist_tex: Texture2D
var river_quads := 0
var lake_quads := 0
var main_quads := 0
var falls := 0
## world positions of every waterfall's plunge (for audio / tests)
var fall_points: Array[Vector3] = []

func setup(t: Terrain) -> void:
	terrain = t

func build(data: Dictionary) -> void:
	if terrain == null or not terrain.loaded: return
	_noise = load("res://assets/textures/water_noise.png")
	_mat = _make_mat(false)
	_river_mat = _make_mat(false)
	_river_mat.set_shader_parameter("flow_mode", 1)
	_river_mat.set_shader_parameter("flow_speed", 0.95)
	_sheet_mat = _make_sheet_mat(0)
	_pool_mat = _make_sheet_mat(1)
	_build_lake()
	_build_rivers()
	_build_main_river(data.get("river_main", {}))
	_build_falls(data.get("waterfalls", []))

func _make_sheet_mat(mode: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/waterfall.gdshader")
	m.set_shader_parameter("foam_noise", _noise)
	m.set_shader_parameter("ripple_n", load("res://assets/textures/water_n.png"))
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("opacity", 0.86 if mode == 0 else 0.9)
	m.render_priority = 2
	return m

func _make_mat(fall: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water.gdshader")
	# metal_n.png was standing in here: a brushed-metal normal map on a
	# water surface, which is why the lake had no ripple structure at all
	# and read as a sheet of plastic. water_n.png is generated as tiling,
	# wind-stretched capillary ripples.
	m.set_shader_parameter("ripple_n", load("res://assets/textures/water_n.png"))
	m.set_shader_parameter("shallow_col", Color(0.30, 0.46, 0.44))
	m.set_shader_parameter("deep_col", Color(0.055, 0.14, 0.19))
	m.set_shader_parameter("flow_speed", 1.9 if fall else 0.55)
	m.set_shader_parameter("foam_amount", 1.5 if fall else 0.85)
	# A waterfall is a thin sheet of churn: no refraction, no mirror, and it
	# goes opaque almost immediately.
	m.set_shader_parameter("refract_strength", 0.0 if fall else 0.045)
	m.set_shader_parameter("clarity", 0.25 if fall else 2.60)
	m.set_shader_parameter("ssr_steps", 0)
	m.set_shader_parameter("foam_noise", _noise)
	m.render_priority = 1
	return m

## Reflection and refraction are the expensive parts of the water shader, so
## the quality tier owns them rather than the material.
func set_sky_color(horizon: Color, zenith: Color) -> void:
	for m in [_mat, _river_mat]:
		if m == null: continue
		(m as ShaderMaterial).set_shader_parameter("sky_col", horizon)
		(m as ShaderMaterial).set_shader_parameter("sky_top_col", zenith)

func set_quality(level: int) -> void:
	var steps: int = [0, 0, 12, 20][clampi(level, 0, 3)]
	var refr: float = [0.0, 0.035, 0.045, 0.055][clampi(level, 0, 3)]
	for m in [_mat, _river_mat]:
		if m == null: continue
		(m as ShaderMaterial).set_shader_parameter("ssr_steps", steps)
		(m as ShaderMaterial).set_shader_parameter("refract_strength", refr)

## A smooth 0..1 "how much channel is here" field over the whole river mask.
##
## The mask stores rivers as one-pixel lines, and plenty of them run diagonally.
## Drawing one square per marked pixel therefore produced a chain of squares
## that touch only at their corners -- the disconnected white rhomboids that
## survived every previous water fix, because the problem was never the shader.
## A plus-shaped dilation reconnects the diagonal, and a box blur gives the
## bank a gradient for the shader to foam and fade against.
var _field := PackedFloat32Array()
var _wet := PackedByteArray()
var _fw := 0
var _fh := 0

## Turn the raw drainage mask into a river network that can be drawn.
##
## The mask is a flow trace, not a river. Measured on the shipped 769x769
## image: the alpha channel lights 14,172 pixels but they form 5,009 separate
## fragments, 3,788 of which are a single pixel, and most runs are one pixel
## wide and diagonal. Emitting one axis-aligned quad per lit pixel therefore
## produces squares that meet only at their corners -- the "stepping stones"
## the first pass rendered -- and scatters puddles across dry meadows.
##
## The R channel is NOT a separate damp mask (an earlier comment here claimed
## it covered 10% of the map; it covers 0.95%, and every R pixel is also an
## alpha pixel). It marks the high-accumulation stems: the trunk of each
## drainage tree. That makes it a free river-order signal.
##
## Three passes:
##   1. plus-shaped dilation makes every run 4-connected and about three
##      cells wide, so neighbouring quads share whole edges. 896 components.
##   2. drop any component holding fewer than MIN_TRUNK trunk pixels. 146
##      real river systems survive and every isolated speck is gone.
##   3. a 3x3 box blur of what survives becomes the cross-section weight, so
##      a channel is deep in the middle and shelves out at the banks.
const MIN_TRUNK := 8
## Metres of depth packed into the 8-bit vertex-colour channel. Must match
## water.gdshader's depth_range uniform.
const DEPTH_RANGE := 4.0

func _build_field(img: Image) -> void:
	_fw = img.get_width()
	_fh = img.get_height()
	var n := _fw * _fh
	var trunk := PackedByteArray(); trunk.resize(n)
	for z in _fh:
		for x in _fw:
			var i := z * _fw + x
			trunk[i] = 1 if img.get_pixel(x, z).r > 0.5 else 0

	# 1. plus-shaped dilation OF THE TRUNK CHANNEL.
	#
	# Measured: every channel in river.png is exactly one pixel wide (p95 of
	# the distance transform is 1.00 cell), so something has to widen them or
	# the rivers are 2 m ditches. But dilating the whole ALPHA mask widened
	# 914 hairline drainage lines along with the 147 real watercourses and
	# took the map from 2.40% water to 7.05% -- 12.9% of the ground in the
	# reference grassland shot, which rendered as a pale sheet lying across
	# the field with the grass suppressed underneath it.
	#
	# The R channel marks main stems and is a strict subset of alpha. Widening
	# only that gives 147 systems over 2.43% of the map, the tributaries stay
	# dry gullies where they belong, and the grassland goes back to grass.
	var dil := PackedByteArray(); dil.resize(n)
	for z in _fh:
		for x in _fw:
			var i := z * _fw + x
			var v: int = trunk[i]
			if v == 0:
				if x > 0 and trunk[i - 1] == 1: v = 1
				elif x < _fw - 1 and trunk[i + 1] == 1: v = 1
				elif z > 0 and trunk[i - _fw] == 1: v = 1
				elif z < _fh - 1 and trunk[i + _fw] == 1: v = 1
			dil[i] = v

	# 2. keep only components that reach a trunk
	var keep := PackedByteArray(); keep.resize(n)
	var seen := PackedByteArray(); seen.resize(n)
	var stack := PackedInt32Array()
	var cells := PackedInt32Array()
	for s in n:
		if dil[s] == 0 or seen[s] == 1: continue
		stack.clear(); cells.clear()
		stack.push_back(s); seen[s] = 1
		var tr := 0
		while not stack.is_empty():
			var i: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			cells.push_back(i)
			tr += trunk[i]
			var x := i % _fw
			@warning_ignore("integer_division")
			var z: int = i / _fw
			if x > 0 and dil[i - 1] == 1 and seen[i - 1] == 0:
				seen[i - 1] = 1; stack.push_back(i - 1)
			if x < _fw - 1 and dil[i + 1] == 1 and seen[i + 1] == 0:
				seen[i + 1] = 1; stack.push_back(i + 1)
			if z > 0 and dil[i - _fw] == 1 and seen[i - _fw] == 0:
				seen[i - _fw] = 1; stack.push_back(i - _fw)
			if z < _fh - 1 and dil[i + _fw] == 1 and seen[i + _fw] == 0:
				seen[i + _fw] = 1; stack.push_back(i + _fw)
		if tr >= MIN_TRUNK:
			for i in cells: keep[i] = 1
	_wet = keep

	# 3. cross-section weight
	var a := PackedFloat32Array(); a.resize(n)
	var b := PackedFloat32Array(); b.resize(n)
	for i in n: b[i] = float(keep[i])
	for z in _fh:
		for x in _fw:
			var i := z * _fw + x
			var l := b[i - 1] if x > 0 else b[i]
			var r := b[i + 1] if x < _fw - 1 else b[i]
			a[i] = (l + b[i] + r) / 3.0
	for z in _fh:
		for x in _fw:
			var i := z * _fw + x
			var u := a[i - _fw] if z > 0 else a[i]
			var d := a[i + _fw] if z < _fh - 1 else a[i]
			b[i] = (u + a[i] + d) / 3.0
	_field = b

func _is_wet(x: int, z: int) -> bool:
	if _wet.is_empty(): return false
	return _wet[clampi(z, 0, _fh - 1) * _fw + clampi(x, 0, _fw - 1)] == 1

func _chan_w(x: int, z: int) -> float:
	if _field.is_empty(): return 0.0
	return _field[clampi(z, 0, _fh - 1) * _fw + clampi(x, 0, _fw - 1)]

## Weight at a cell *corner*, which is where the depths are baked. Averaging
## the four cells that meet there is what lets the outermost wet cell see the
## dry ground beyond it; sampling the cell alone never reads below the band
## edge, so the channel came out with vertical walls and no shoreline.
func _corner_w(x: int, z: int) -> float:
	return (_chan_w(x - 1, z - 1) + _chan_w(x, z - 1)
		+ _chan_w(x - 1, z) + _chan_w(x, z)) * 0.25

func _px_flow(x: float, z: float) -> Vector2:
	if terrain.river_img == null: return Vector2(0, 1)
	var img := terrain.river_img
	var xi := clampi(int(x / terrain.size * float(img.get_width())), 0, img.get_width() - 1)
	var zi := clampi(int(z / terrain.size * float(img.get_height())), 0, img.get_height() - 1)
	var c := img.get_pixel(xi, zi)
	return Vector2(c.g * 2.0 - 1.0, c.b * 2.0 - 1.0)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		depth: Array, flow: Vector2) -> void:
	var n := Vector3.UP
	var pts := [a, b, c, d]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	# a,b,c,d run counter-clockwise in XZ seen from above. Godot's front face is
	# the one the (v1-v0) x (v2-v0) cross product points AWAY from, so an
	# up-facing surface needs a -Y cross: 0,1,2 / 0,2,3. The old 0,2,1 / 0,3,2
	# order gave +Y and would have been back-face culled; it only ever drew
	# because water.gdshader is cull_disabled.
	var order := [0, 1, 2, 0, 2, 3]
	for i in order:
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.set_uv2(flow)                       # flow direction for the shader
		# Depth is baked in metres but the colour channel is 8-bit unorm, so it
		# is packed over a 0..DEPTH_RANGE metre span. water.gdshader multiplies
		# by the same constant and then works in metres throughout; the two
		# used to disagree, which made a 0.4 m bank read as 0.1 and put every
		# stream at the top of the foam ramp -- solid white.
		st.set_color(Color(clampf(float(depth[i]) / DEPTH_RANGE, 0.0, 1.0), 0, 0, 1))
		st.add_vertex(pts[i])

## Lake / standing water: one mesh from the cells under the water plane.
func _build_lake() -> void:
	# 4 m blocks, not 8 m: the lake surface is a flat plane at water level, so
	# every block that is only partly submerged hangs over dry land by up to
	# one block. Halving the block halves that overhang.
	var step := 2
	var g := terrain.grid
	var cell := terrain.cell
	var wl := terrain.water_level
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z := 0
	while z < g - step:
		var x := 0
		while x < g - step:
			var hs := [
				terrain.heights[z * g + x],
				terrain.heights[z * g + mini(x + step, g - 1)],
				terrain.heights[mini(z + step, g - 1) * g + mini(x + step, g - 1)],
				terrain.heights[mini(z + step, g - 1) * g + x],
			]
			var below := 0
			for h in hs:
				if h < wl: below += 1
			# Draw a block only once most of it is actually under water.
			# `below > 0` let a single submerged corner paint a full flat tile
			# across three corners of dry hillside, which is what produced the
			# pale sheets floating above the shoreline.
			if below >= 3:
				var x0 := float(x) * cell
				var z0 := float(z) * cell
				var x1 := float(x + step) * cell
				var z1 := float(z + step) * cell
				_quad(st,
					Vector3(x0, wl, z0), Vector3(x1, wl, z0),
					Vector3(x1, wl, z1), Vector3(x0, wl, z1),
					[wl - hs[0], wl - hs[1], wl - hs[2], wl - hs[3]], Vector2(0.15, 0.1))
				lake_quads += 1
			x += step
		z += step
	if lake_quads == 0: return
	var mi := MeshInstance3D.new()
	mi.name = "Lake"
	mi.mesh = st.commit()
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## Rivers: ribbon quads along the channel, sitting just above the carved bed.
func _build_rivers() -> void:
	if terrain.river_img == null: return
	var img := terrain.river_img
	var iw := img.get_width()
	var ih := img.get_height()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 1, not 2: a channel quad only conforms to the terrain at its corners, so
	# a 4 m cell on a 1:3 slope could sit 0.66 m above the ground in the
	# middle. 2 m cells halve that, and the channel stops hovering.
	_build_field(img)
	var step := 1
	var scale_x := terrain.size / float(iw)
	var wl := terrain.water_level
	var z := 0
	while z < ih - step:
		var x := 0
		while x < iw - step:
			var c := img.get_pixel(x, z)
			if _is_wet(x, z):
				var cx := (float(x) + 0.5) * scale_x
				var cz := (float(z) + 0.5) * scale_x
				# Slope: every corner is sampled on the terrain now, so a
				# channel running downhill conforms to the bed instead of
				# hovering. Only cliff-like cells are dropped.
				if terrain.slope_at(cx, cz) > 0.30:
					x += step
					continue

				# One quad per cell, exactly covering the cell, with every
				# corner sampled on the terrain, so adjacent cells share corner
				# heights exactly and the channel is one continuous surface.
				var x0 := float(x) * scale_x
				var z0 := float(z) * scale_x
				var x1 := float(x + step) * scale_x
				var z1 := float(z + step) * scale_x
				var rise := 0.09
				# Depth per corner, in metres, from the blurred cross-section.
				# The bank floor of 0.06 is what gives the shader a genuine
				# shoreline to foam and fade against; a flat-bottomed channel
				# rendered as a hard blue strip laid on the grass.
				var dep := 1.60
				var d00 := dep * lerpf(0.06, 1.0, smoothstep(0.42, 0.95, _corner_w(x, z)))
				var d10 := dep * lerpf(0.06, 1.0, smoothstep(0.42, 0.95, _corner_w(x + step, z)))
				var d11 := dep * lerpf(0.06, 1.0, smoothstep(0.42, 0.95, _corner_w(x + step, z + step)))
				var d01 := dep * lerpf(0.06, 1.0, smoothstep(0.42, 0.95, _corner_w(x, z + step)))
				var fl := Vector2(c.g * 2.0 - 1.0, c.b * 2.0 - 1.0)
				_quad(st,
					Vector3(x0, _surf(x0, z0, rise, wl), z0),
					Vector3(x1, _surf(x1, z0, rise, wl), z0),
					Vector3(x1, _surf(x1, z1, rise, wl), z1),
					Vector3(x0, _surf(x0, z1, rise, wl), z1),
					[d00, d10, d11, d01], fl)
				river_quads += 1
			x += step
		z += step
	if river_quads == 0: return
	var mi := MeshInstance3D.new()
	mi.name = "Rivers"
	mi.mesh = st.commit()
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## Water surface height at a channel corner: the carved bed plus a little, but
## never below the standing water plane.
func _surf(x: float, z: float, rise: float, wl: float) -> float:
	return maxf(wl, terrain.sample_height(x, z) + rise)

## Old stream waterfalls from the generator: a lip position, its height and
## the drop. v0.13 aims each one down the real slope (they all used to face
## +Z whatever the stream did) and gives it the same sheet, pool and mist as
## the main river's falls.
func _build_falls(list: Array) -> void:
	for w in list:
		var x := float(w.get("x", 0.0))
		var z := float(w.get("z", 0.0))
		var drop: float = maxf(float(w.get("drop", 6.0)), 3.0)
		# v0.14: falls the generator found on the border wall (Terrain._relax_edges
		# removes that wall) would now pour into flat ground
		var em := 24.0
		if x < em or z < em or x > terrain.size - em or z > terrain.size - em: continue
		var g := Vector2(terrain.sample_height(x + 3.0, z) - terrain.sample_height(x - 3.0, z),
			terrain.sample_height(x, z + 3.0) - terrain.sample_height(x, z - 3.0))
		var dir := -g.normalized() if g.length() > 0.05 else Vector2(0, 1)
		var top := terrain.sample_height(x, z) + 0.12
		# landing: the lowest ground along the fall line within 14 m
		var land := 2.0
		var low := top
		var d := 1.0
		while d <= 14.0:
			var hh := terrain.sample_height(x + dir.x * d, z + dir.y * d)
			if hh < low - 0.05:
				low = hh
				land = d
			if hh < top - drop * 0.9: break
			d += 0.5
		var bottom := low + 0.12
		if top - bottom < 2.0: bottom = top - drop
		_fall(Vector3(x, top, z), dir, 4.2, bottom, 1.6, false)

## One waterfall: two curved sheets on a ballistic arc from the lip, a foam
## disc and mist where it lands, and a positional roar.
func _fall(lip: Vector3, dir: Vector2, width: float, bottom: float, v0: float, lake: bool) -> void:
	dir = dir.normalized()
	var drop := maxf(0.5, lip.y - bottom)
	var fwd := Vector3(dir.x, 0.0, dir.y)
	var side := Vector3(-dir.y, 0.0, dir.x)
	var t_fall := sqrt(2.0 * drop / 9.8)
	var rows := 14
	# arc samples (centre line), lifted clear of the rock wherever the cliff
	# is less than vertical so the sheet slides over it instead of through it
	var arc := PackedVector3Array()
	arc.append(lip - fwd * 0.5 + Vector3(0, 0.02, 0))
	for r in rows:
		var t := t_fall * float(r) / float(rows - 1)
		var p := lip + fwd * (v0 * t) + Vector3(0.0, -4.9 * t * t, 0.0)
		var gmax := -INF
		for o in [-0.4, 0.0, 0.4]:
			var q := p + side * (width * float(o))
			gmax = maxf(gmax, terrain.sample_height(q.x, q.z))
		p.y = maxf(p.y, gmax + 0.14)
		if r == rows - 1: p.y = bottom - 0.3
		arc.append(p)
	var arc_len := 0.0
	for i in range(1, arc.size()): arc_len += arc[i].distance_to(arc[i - 1])
	for layer in 2:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var cols := 7
		var wl := width * (0.94 if layer == 0 else 0.78)
		var acc := 0.0
		for i in arc.size():
			if i > 0: acc += arc[i].distance_to(arc[i - 1])
			var v := acc / maxf(arc_len, 0.01)
			var tan := (arc[mini(i + 1, arc.size() - 1)] - arc[maxi(i - 1, 0)]).normalized()
			var nrm := side.cross(tan).normalized()
			if nrm.dot(fwd + Vector3.UP) < 0.0: nrm = -nrm
			var spread := 1.0 + 0.12 * v
			for c in cols:
				var u := float(c) / float(cols - 1)
				var a := (u - 0.5) * wl * spread
				var bulge := 0.16 * (1.0 - pow(2.0 * u - 1.0, 2.0)) + (0.13 if layer == 1 else 0.0)
				var pos := arc[i] + side * a + nrm * bulge
				st.set_normal(nrm)
				st.set_uv(Vector2(u, v))
				st.set_uv2(Vector2(wl * spread, arc_len))
				st.set_color(Color(0.5 * float(layer), 0, 0, 1))
				st.add_vertex(pos)
		for i in arc.size() - 1:
			for c in cols - 1:
				var a0 := i * cols + c
				var b0 := a0 + cols
				st.add_index(a0); st.add_index(b0); st.add_index(a0 + 1)
				st.add_index(a0 + 1); st.add_index(b0); st.add_index(b0 + 1)
		st.generate_tangents()
		var mi := MeshInstance3D.new()
		mi.name = "Fall"
		mi.mesh = st.commit()
		mi.material_override = _sheet_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	var foot := arc[arc.size() - 1]
	var pool_y := bottom + 0.035
	if lake: pool_y = terrain.water_level + 0.035
	_pool(Vector3(foot.x, pool_y, foot.z) + fwd * 0.6, width * (1.1 if lake else 0.8) + drop * 0.12)
	_mist(Vector3(foot.x, pool_y, foot.z), fwd, width, drop)
	_roar(Vector3(foot.x, pool_y + 1.0, foot.z), drop, width)
	fall_points.append(Vector3(foot.x, pool_y, foot.z))
	falls += 1

func _pool(c: Vector3, radius: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 20
	var phase := Color(randf(), 0, 0, 1)
	st.set_normal(Vector3.UP); st.set_uv(Vector2(0.5, 0.5)); st.set_uv2(Vector2(radius * 2.0, radius * 2.0))
	st.set_color(phase)
	st.add_vertex(c)
	for i in seg + 1:
		var a := TAU * float(i) / float(seg)
		var d := Vector2(cos(a), sin(a))
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.5, 0.5) + d * 0.5)
		st.set_uv2(Vector2(radius * 2.0, radius * 2.0))
		st.set_color(phase)
		st.add_vertex(c + Vector3(d.x * radius, 0.0, d.y * radius))
	for i in seg:
		st.add_index(0); st.add_index(i + 1); st.add_index(i + 2)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "PlungeFoam"
	mi.mesh = st.commit()
	mi.material_override = _pool_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _mist(at: Vector3, fwd: Vector3, width: float, drop: float) -> void:
	if _mist_tex == null:
		var gt := GradientTexture2D.new()
		gt.width = 64; gt.height = 64
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(1.0, 0.5)
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 1)); gr.set_color(1, Color(1, 1, 1, 0))
		gr.add_point(0.45, Color(1, 1, 1, 0.45))
		gt.gradient = gr
		_mist_tex = gt
	var ps := GPUParticles3D.new()
	ps.name = "Mist"
	var q := clampf(float(Perf.preset().get("particles", 1.0)), 0.3, 2.0)
	ps.amount = int(clampf((18.0 + drop * 3.0 + width * 1.5) * q, 10.0, 90.0))
	ps.lifetime = 2.8
	ps.local_coords = false
	ps.visibility_aabb = AABB(Vector3(-width - 6.0, -2.0, -width - 6.0), Vector3(width * 2.0 + 12.0, drop + 10.0, width * 2.0 + 12.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(width * 0.45, 0.3, width * 0.45)
	pm.direction = (Vector3.UP * 1.4 + fwd).normalized()
	pm.spread = 38.0
	pm.initial_velocity_min = 0.6 + drop * 0.08
	pm.initial_velocity_max = 1.6 + drop * 0.22
	pm.gravity = Vector3(0, -0.35, 0)
	pm.damping_min = 0.4; pm.damping_max = 0.9
	pm.scale_min = 1.6; pm.scale_max = 3.2 + drop * 0.18
	pm.angle_min = -180.0; pm.angle_max = 180.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.9, 0.94, 0.96, 0.0))
	ramp.set_color(1, Color(0.9, 0.94, 0.96, 0.0))
	ramp.add_point(0.18, Color(0.9, 0.94, 0.96, 0.16 + minf(drop, 12.0) * 0.008))
	var rt := GradientTexture1D.new(); rt.gradient = ramp
	pm.color_ramp = rt
	var grow := Curve.new(); grow.add_point(Vector2(0, 0.45)); grow.add_point(Vector2(1, 1.0))
	var ct := CurveTexture.new(); ct.curve = grow
	pm.scale_curve = ct
	ps.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _mist_tex
	m.backlight_enabled = true
	m.backlight = Color(0.55, 0.58, 0.6)
	m.disable_receive_shadows = true
	m.roughness = 1.0
	quad.material = m
	ps.draw_pass_1 = quad
	ps.position = at
	add_child(ps)

## Positional waterfall roar: the stream loop pitched down, louder and
## carrying further for a bigger drop. Falls within 12 m share one voice.
func _roar(at: Vector3, drop: float, width: float) -> void:
	for p in fall_points:
		if p.distance_to(at) < 12.0: return
	var s = load("res://assets/audio/amb/stream.ogg")
	if s == null: return
	if s is AudioStreamOggVorbis: (s as AudioStreamOggVorbis).loop = true
	var ap := AudioStreamPlayer3D.new()
	ap.name = "Roar"
	ap.stream = s
	ap.bus = "Ambience"
	ap.pitch_scale = clampf(0.86 - drop * 0.02, 0.62, 0.84)
	ap.volume_db = clampf(-6.0 + drop * 0.7 + width * 0.25, -6.0, 5.0)
	ap.unit_size = 5.0 + drop * 0.8
	ap.max_distance = 60.0 + drop * 5.0
	ap.attenuation_filter_cutoff_hz = 5000.0
	ap.position = at
	ap.autoplay = true
	add_child(ap)

# ------------------------------------------------------------ main river
## The v0.13 river (tools/make_river.py): a ribbon along the carved channel,
## split at every fall. UV is (metres downstream, metres across) for the
## flow_mode-1 shader path; COLOR is depth / rapids / plunge churn. Each
## cross-section is flat at the surface height and reaches just past where
## the ground rises through it, so the banks, not the mesh, draw the edge.
const MAIN_COLS := [0.0, 0.28, 0.55, 0.8, 0.93]

func _build_main_river(rm: Dictionary) -> void:
	var pts: Array = rm.get("points", [])
	var n := pts.size()
	if n < 4: return
	var P := PackedVector3Array()
	var W := PackedFloat32Array()
	var F := PackedFloat32Array()
	for q in pts:
		P.append(Vector3(float(q[0]), float(q[1]), float(q[2])))
		W.append(float(q[3]))
		F.append(clampf(float(q[5]), 0.0, 1.0))
	var S := PackedFloat32Array()
	S.resize(n)
	for i in range(1, n):
		S[i] = S[i - 1] + Vector2(P[i].x - P[i - 1].x, P[i].z - P[i - 1].z).length()
	var fl: Array = rm.get("falls", [])
	var cut := {}
	for f in fl: cut[int(f.get("k", -1))] = f
	# the data un-narrows the lip point itself; smooth width and rapids so
	# the ribbon does not pinch or flash white there
	var Ws := W.duplicate(); var Fs := F.duplicate()
	for i in n:
		var a := maxi(0, i - 2); var b := mini(n - 1, i + 2)
		var sw := 0.0; var sf := 0.0
		for j in range(a, b + 1):
			sw += W[j]; sf += F[j]
		Ws[i] = sw / float(b - a + 1); Fs[i] = sf / float(b - a + 1)
	# plunge churn fades over ~12 m below each fall
	var C := PackedFloat32Array()
	C.resize(n)
	for f in fl:
		if bool(f.get("lake", false)): continue
		var k := int(f.get("k", 0))
		var strength := clampf(float(f.get("top", 0.0)) - float(f.get("bottom", 0.0)), 1.0, 5.0) / 5.0
		for i in range(k + 1, n):
			var ds := S[i] - S[mini(k + 1, n - 1)]
			if ds > 12.0: break
			C[i] = maxf(C[i], pow(1.0 - ds / 12.0, 1.4) * lerpf(0.55, 1.0, strength))
	# runs between falls
	var runs := []
	var start := 0
	for i in n:
		if cut.has(i) or i == n - 1:
			if i - start >= 1: runs.append([start, i])
			start = i + 1
	for rr in runs:
		_main_run(P, Ws, Fs, C, S, int(rr[0]), int(rr[1]))
	for f in fl:
		var k := int(f.get("k", 0))
		if k < 0 or k >= n: continue
		var lip := Vector3(float(f.get("x", P[k].x)), float(f.get("top", P[k].y)), float(f.get("z", P[k].z)))
		var dir := Vector2(float(f.get("dx", 0.0)), float(f.get("dz", 1.0)))
		var lake := bool(f.get("lake", false))
		_fall(lip, dir, Ws[k] * 0.9, float(f.get("bottom", lip.y - 3.0)), 2.1 if lake else 1.8, lake)

func _bank_reach(c: Vector3, dir: Vector3, lim: float) -> float:
	## distance from the centre line to where the ground rises through the
	## surface, or -1 if it never does within `lim`
	var d := 0.5
	while d <= lim:
		var p := c + dir * d
		if terrain.sample_height(p.x, p.z) >= c.y + 0.02: return d
		d += 0.25
	return -1.0

func _main_run(P: PackedVector3Array, W: PackedFloat32Array, F: PackedFloat32Array,
		C: PackedFloat32Array, S: PackedFloat32Array, a: int, b: int) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := P.size()
	var cols := MAIN_COLS.size() * 2 + 1          # edge..centre..edge incl. tuck
	var rows := 0
	for i in range(a, b + 1):
		var t := Vector3(P[mini(i + 1, n - 1)].x - P[maxi(i - 1, 0)].x, 0.0,
			P[mini(i + 1, n - 1)].z - P[maxi(i - 1, 0)].z).normalized()
		var left := Vector3(-t.z, 0.0, t.x)
		var half := W[i] * 0.5
		var lim := half + 6.0
		var reach := []
		for sgn in [-1.0, 1.0]:
			var r := _bank_reach(P[i], left * sgn, lim)
			# never found: the ground is lower than the water here; stop at the
			# nominal edge and let the depth fade take it to nothing
			reach.append(r if r > 0.0 else half + 0.4)
		var fade_in := clampf(float(i) / 3.0, 0.0, 1.0)
		var offs := []
		for k in range(MAIN_COLS.size() - 1, -1, -1):
			offs.append(-float(reach[0]) * float(MAIN_COLS[k]))
		offs.push_front(-(float(reach[0]) + 0.6))
		for k in range(1, MAIN_COLS.size()):
			offs.append(float(reach[1]) * float(MAIN_COLS[k]))
		offs.append(float(reach[1]) + 0.6)
		for o in offs:
			var p: Vector3 = P[i] + left * float(o)
			var dep := maxf(0.0, P[i].y - terrain.sample_height(p.x, p.z)) * fade_in
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(S[i], float(o)))
			st.set_uv2(Vector2(t.x, t.z))
			st.set_color(Color(clampf(dep / DEPTH_RANGE, 0.0, 1.0), F[i], C[i], 1.0))
			st.add_vertex(Vector3(p.x, P[i].y, p.z))
		rows += 1
	if rows < 2: return
	for r in rows - 1:
		for c in cols - 1:
			var i0 := r * cols + c
			var i1 := i0 + cols
			st.add_index(i0); st.add_index(i0 + 1); st.add_index(i1)
			st.add_index(i0 + 1); st.add_index(i1 + 1); st.add_index(i1)
			main_quads += 1
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "MainRiver"
	mi.mesh = st.commit()
	mi.material_override = _river_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func stats() -> Dictionary:
	return {"lake_quads": lake_quads, "river_quads": river_quads, "main_quads": main_quads, "waterfalls": falls}
