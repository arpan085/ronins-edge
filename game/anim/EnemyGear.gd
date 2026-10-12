class_name EnemyGear
extends RefCounted
## v0.18: the soldier-specific kit built in code (no UV-less props): jingasa
## (ashigaru's lacquered conical hat), kabuto (captain's helmet with neck guard
## and crest), sashimono (back banner), yumi (asymmetric longbow) and quiver.
## Every piece is a rigid prop on a bone, placed in bind-pose model space.

const TEX := "res://assets/char/tex/"
## bow in the left fist: stave along the thumb axis, grip a third up the bow
const BOW_GRIP := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(0.035, 0.085, 0.0))

static var _mats := {}

static func lacquer(col: Color, gloss := 0.8) -> StandardMaterial3D:
	var key := "lq" + col.to_html() + str(gloss)
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.35
	m.clearcoat_enabled = true
	m.clearcoat = gloss
	m.clearcoat_roughness = 0.15
	m.rim_enabled = true
	m.rim = 0.05
	_mats[key] = m
	CharWet.track(m, "lacquer")
	return m

static func metal(col: Color, rough := 0.35) -> StandardMaterial3D:
	var key := "mt" + col.to_html() + str(rough)
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 1.0
	m.roughness = rough
	_mats[key] = m
	CharWet.track(m, "metal")
	return m

static func cloth(id: String, col: Color, tile := 0.2, two_sided := false) -> StandardMaterial3D:
	var key := "cl" + id + col.to_html() + str(two_sided)
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new()
	var t = load(TEX + id + "_diff_1k.jpg")
	if t != null:
		m.albedo_texture = t
		m.albedo_color = Color(col.r * 2.0, col.g * 2.0, col.b * 2.0)
		m.normal_enabled = true
		m.normal_texture = load(TEX + id + "_nor_1k.jpg")
		m.uv1_scale = Vector3(1.0 / tile, 1.0 / tile, 1.0)
	else:
		m.albedo_color = col
	m.roughness = 0.95
	if two_sided: m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	CharWet.track(m, "cloth")
	return m

## surface of revolution around +Y: profile = [Vector2(radius, y)], from
## angle a0 to a1 (radians, 0 = +Z front); smooth normals, UV = (angle, length)
static func lathe(st: SurfaceTool, prof: Array, segs: int, a0 := 0.0, a1 := TAU, xf := Transform3D()) -> void:
	var rows := []
	for i in segs + 1:
		var a := lerpf(a0, a1, float(i) / segs)
		var row := []
		for p in prof:
			var v: Vector2 = p
			row.append(Vector3(sin(a) * v.x, v.y, cos(a) * v.x))
		rows.append(row)
	for i in segs:
		for j in prof.size() - 1:
			var q := [rows[i][j], rows[i + 1][j], rows[i + 1][j + 1], rows[i][j + 1]]
			var uv := [Vector2(float(i) / segs, float(j)), Vector2(float(i + 1) / segs, float(j)),
				Vector2(float(i + 1) / segs, float(j + 1)), Vector2(float(i) / segs, float(j + 1))]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_uv(uv[k])
				st.add_vertex(xf * (q[k] as Vector3))

## Fukigaeshi (吹返): a curved sheet hinged on the front edge of the top two
## shikoro lames (62 deg off the face line), sweeping out and back (24 -> 46
## deg of turn) so it faces forward, 9 cm wide, rounded at the outer end.
## Two-sided lacquer with explicit normals; triangle winding is matched to
## the normal so both faces light correctly. A gilt mon sits on the front.
static func _fukigaeshi(root: Node3D, sgn: float, col: Color, mon_col: Color) -> void:
	var nu := 8
	var nv := 4
	var w := 0.09
	var a_e := sgn * deg_to_rad(62.0)
	var offs := [Vector3.ZERO]
	var o := Vector3.ZERO
	for i in nu:
		var u := (float(i) + 0.5) / nu
		var a := a_e + sgn * deg_to_rad(24.0 + 22.0 * u * u)
		o += Vector3(sin(a), 0.0, cos(a)) * (w / nu)
		offs.append(o)
	var grid := []
	for i in nu + 1:
		var u := float(i) / nu
		var shrink := 1.0
		if u > 0.6: shrink = 0.3 + 0.7 * sqrt(maxf(0.0, 1.0 - pow((u - 0.6) / 0.4, 2.0)))
		var row := []
		for j in nv + 1:
			var v := 0.5 + (float(j) / nv - 0.5) * shrink
			var r := lerpf(0.136, 0.172, v)
			var e := Vector3(sin(a_e) * r, lerpf(-0.002, -0.072, v), cos(a_e) * r)
			row.append(e + offs[i] + Vector3(0, 0.012 * sin(PI * u) * (1.0 - v), 0))
		grid.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nrm := func(i: int, j: int) -> Vector3:
		var du: Vector3 = grid[mini(i + 1, nu)][j] - grid[maxi(i - 1, 0)][j]
		var dv: Vector3 = grid[i][mini(j + 1, nv)] - grid[i][maxi(j - 1, 0)]
		var n := du.cross(dv).normalized()
		return n if n.z >= 0.0 else -n
	for i in nu:
		for j in nv:
			var q := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
			for tri in [[0, 1, 2], [0, 2, 3]]:
				var ids: Array = [q[tri[0]], q[tri[1]], q[tri[2]]]
				var p0: Vector3 = grid[ids[0][0]][ids[0][1]]
				var p1: Vector3 = grid[ids[1][0]][ids[1][1]]
				var p2: Vector3 = grid[ids[2][0]][ids[2][1]]
				var want: Vector3 = nrm.call(ids[0][0], ids[0][1])
				if (p0 - p2).cross(p0 - p1).dot(want) < 0.0:
					ids = [ids[0], ids[2], ids[1]]
				for k in 3:
					st.set_normal(nrm.call(ids[k][0], ids[k][1]))
					st.set_uv(Vector2(float(ids[k][0]) / nu, float(ids[k][1]) / nv))
					st.add_vertex(grid[ids[k][0]][ids[k][1]])
	var mat: StandardMaterial3D = lacquer(col, 0.7).duplicate()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.name = "Fukigaeshi"
	root.add_child(mi)
	var c: Vector3 = grid[nu / 2][nv / 2]
	var n: Vector3 = nrm.call(nu / 2, nv / 2)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.017
	cm.bottom_radius = 0.017
	cm.height = 0.003
	cm.radial_segments = 16
	cm.rings = 1
	disc.mesh = cm
	disc.material_override = metal(mon_col, 0.3)
	disc.transform = Transform3D(Basis(Quaternion(Vector3.UP, n)), c + n * 0.003)
	root.add_child(disc)

static func _mesh(st: SurfaceTool, mat: Material) -> MeshInstance3D:
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi

static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

## Jingasa: a shallow lacquered cone, 46 cm across, with the clan mon in gold.
static func make_jingasa(col := Color(0.09, 0.07, 0.06), mon := Color(0.75, 0.58, 0.22)) -> Node3D:
	var root := Node3D.new()
	root.name = "Jingasa"
	var st := _st()
	# outer shell (top), then the underside so it reads from below
	lathe(st, [Vector2(0.0, 0.105), Vector2(0.05, 0.088), Vector2(0.14, 0.04), Vector2(0.23, 0.0), Vector2(0.235, -0.008)], 28)
	lathe(st, [Vector2(0.232, -0.012), Vector2(0.14, 0.028), Vector2(0.05, 0.075), Vector2(0.0, 0.09)], 28)
	root.add_child(_mesh(st, lacquer(col, 0.6)))
	var st2 := _st()
	lathe(st2, [Vector2(0.0, 0.1065), Vector2(0.038, 0.094)], 20)
	var m := _mesh(st2, metal(mon, 0.3))
	root.add_child(m)
	# chin cord ring under the brim
	var st3 := _st()
	lathe(st3, [Vector2(0.085, 0.0), Vector2(0.09, -0.01), Vector2(0.085, -0.02)], 16)
	root.add_child(_mesh(st3, cloth("hessian_380", Color(0.55, 0.48, 0.38), 0.04)))
	return root

## Kabuto: riveted bowl, flared five-lame shikoro, turn-backs and a gilt crest.
static func make_kabuto(bowl := Color(0.06, 0.055, 0.05), lace := Color(0.62, 0.36, 0.10)) -> Node3D:
	var root := Node3D.new()
	root.name = "Kabuto"
	var st := _st()
	var prof := []
	for i in 9:
		var a := deg_to_rad(90.0 - i * 11.0)
		prof.append(Vector2(cos(a) * 0.128, sin(a) * 0.118 + 0.0))
	prof.append(Vector2(0.131, -0.006))
	lathe(st, prof, 32)
	root.add_child(_mesh(st, lacquer(bowl, 0.85)))
	# suji ridges: thin raised ribs from the crown
	var rib := _st()
	for k in 16:
		var a := TAU * k / 16.0
		var xf := Transform3D(Basis(Vector3.UP, a), Vector3.ZERO)
		var pr := []
		for i in 8:
			var e := deg_to_rad(84.0 - i * 11.0)
			pr.append(Vector2(cos(e) * 0.1305, sin(e) * 0.1205))
		lathe(rib, pr, 1, -0.012, 0.012, xf)
	root.add_child(_mesh(rib, metal(Color(0.30, 0.26, 0.20), 0.45)))
	# shikoro: five stepped lames round the back and sides
	var sh := _st()
	for l in 5:
		var y0 := -0.004 - l * 0.034
		var r0 := 0.134 + l * 0.021
		lathe(sh, [Vector2(r0, y0), Vector2(r0 + 0.02, y0 - 0.036)], 24, deg_to_rad(62.0), deg_to_rad(298.0))
	root.add_child(_mesh(sh, lacquer(bowl.lightened(0.05), 0.6)))
	# lacing rows on the lames
	var lc := _st()
	for l in 5:
		var y0 := -0.012 - l * 0.034
		var r0 := 0.1375 + l * 0.021
		lathe(lc, [Vector2(r0, y0), Vector2(r0 + 0.012, y0 - 0.02)], 24, deg_to_rad(64.0), deg_to_rad(296.0))
	root.add_child(_mesh(lc, cloth("poly_wool_herringbone", lace, 0.03)))
	# fukigaeshi: the top two lames run forward past the temples and turn
	# back on themselves, a lacquered wing either side of the face with the mon
	for sgn in [-1.0, 1.0]:
		_fukigaeshi(root, sgn, bowl, Color(0.83, 0.64, 0.25))
	# maedate: a gilt crescent (mikazuki), horns up, its middle seated in a
	# socket (haraidate) on the front of the bowl above the peak
	var cr := _st()
	var pts := []
	var cc := Vector3(0.0, 0.125, 0.0)
	for i in 13:
		var a := deg_to_rad(-78.0 + i * 13.0)
		pts.append(cc + Vector3(sin(a) * 0.16, -cos(a) * 0.125, 0.0))
	for i in 12:
		var a0: Vector3 = pts[i]
		var a1: Vector3 = pts[i + 1]
		var w0 := 0.02 * sin(PI * float(i) / 12.0) + 0.003
		var w1 := 0.02 * sin(PI * float(i + 1) / 12.0) + 0.003
		var n0 := (a0 - cc).normalized() * w0
		var n1 := (a1 - cc).normalized() * w1
		for v in [a0 - n0, a1 - n1, a1 + n1, a0 - n0, a1 + n1, a0 + n0]:
			cr.add_vertex(v)
		for v in [a0 - n0, a1 + n1, a1 - n1, a0 - n0, a0 + n0, a1 + n1]:
			cr.add_vertex(v + Vector3(0, 0, -0.004))
	var crest := _mesh(cr, metal(Color(0.83, 0.64, 0.25), 0.25))
	crest.material_override = crest.material_override.duplicate()
	(crest.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	crest.position = Vector3(0, 0.03, 0.132)
	crest.rotation.x = deg_to_rad(-14.0)
	crest.name = "Maedate"
	root.add_child(crest)
	var sock := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.026, 0.04, 0.008)
	sock.mesh = bm
	sock.material_override = metal(Color(0.62, 0.48, 0.2), 0.35)
	sock.position = Vector3(0, 0.03, 0.127)
	sock.rotation.x = deg_to_rad(-14.0)
	root.add_child(sock)
	# peak (mabizashi)
	var pk := _st()
	lathe(pk, [Vector2(0.125, 0.012), Vector2(0.165, -0.012)], 8, deg_to_rad(-55.0), deg_to_rad(55.0))
	root.add_child(_mesh(pk, lacquer(bowl, 0.85)))
	return root

## Sashimono: a banner on a pole in a socket between the shoulder blades.
static func make_sashimono(flag := Color(0.85, 0.82, 0.74), mon := Color(0.55, 0.10, 0.08)) -> Node3D:
	var root := Node3D.new()
	root.name = "Sashimono"
	var pole := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.009
	cy.bottom_radius = 0.011
	cy.height = 1.25
	cy.radial_segments = 8
	pole.mesh = cy
	pole.position = Vector3(0, 0.62, 0)
	pole.material_override = lacquer(Color(0.08, 0.06, 0.05), 0.4)
	root.add_child(pole)
	var bar := MeshInstance3D.new()
	var cb := CylinderMesh.new()
	cb.top_radius = 0.007
	cb.bottom_radius = 0.007
	cb.height = 0.30
	cb.radial_segments = 6
	bar.mesh = cb
	bar.rotation.z = PI * 0.5
	bar.position = Vector3(0.14, 1.22, 0)
	bar.material_override = pole.material_override
	root.add_child(bar)
	var fl := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.28, 0.62)
	fl.mesh = q
	fl.position = Vector3(0.15, 0.92, 0.0)
	fl.rotation.y = PI * 0.5
	fl.material_override = cloth("rough_linen", flag, 0.12, true)
	root.add_child(fl)
	for sd in [-1.0, 1.0]:
		var dot := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.07
		cm.bottom_radius = 0.07
		cm.height = 0.002
		cm.radial_segments = 20
		dot.mesh = cm
		dot.rotation.z = PI * 0.5
		dot.position = Vector3(0.15 + sd * 0.002, 1.02, 0.0)
		dot.material_override = cloth("rough_linen", mon, 0.12)
		root.add_child(dot)
	return root

## Yumi: 1.9 m asymmetric longbow (grip a third of the way up) with string.
static func make_bow() -> Node3D:
	var root := Node3D.new()
	root.name = "Yumi"
	var st := _st()
	var top := 1.25
	var bot := -0.62
	var n := 24
	var pts := []
	for i in n + 1:
		var t := float(i) / n
		var y := lerpf(bot, top, t)
		var u: float = (float(y) - bot) / (top - bot)
		var bend := 0.11 * sin(PI * u) - 0.05 * pow(absf(u - 0.5) * 2.0, 3.0)
		pts.append(Vector3(0, y, bend))
	for i in n:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var w := 0.014
		var d := 0.011
		var quads := [[Vector3(-w, 0, -d), Vector3(w, 0, -d)], [Vector3(w, 0, -d), Vector3(w, 0, d)],
			[Vector3(w, 0, d), Vector3(-w, 0, d)], [Vector3(-w, 0, d), Vector3(-w, 0, -d)]]
		for qd in quads:
			var p0: Vector3 = a + qd[0]
			var p1: Vector3 = a + qd[1]
			var p2: Vector3 = b + qd[1]
			var p3: Vector3 = b + qd[0]
			for v in [p0, p1, p2, p0, p2, p3]:
				st.add_vertex(v)
	root.add_child(_mesh(st, lacquer(Color(0.10, 0.06, 0.04), 0.5)))
	# rattan binding bands and the grip wrap
	for y: float in [-0.20, 0.0, 0.08, 0.45, 0.85]:
		var b := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.017
		cm.bottom_radius = 0.017
		cm.height = 0.03 if y != 0.0 else 0.11
		cm.radial_segments = 8
		b.mesh = cm
		var u: float = (float(y) - bot) / (top - bot)
		b.position = Vector3(0, y, 0.11 * sin(PI * u) - 0.05 * pow(absf(u - 0.5) * 2.0, 3.0))
		b.material_override = cloth("hessian_380", Color(0.42, 0.30, 0.20), 0.03)
		root.add_child(b)
	var s := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = 0.0018
	sc.bottom_radius = 0.0018
	sc.height = top - bot - 0.02
	sc.radial_segments = 4
	s.mesh = sc
	s.position = Vector3(0, (top + bot) * 0.5, -0.06)
	s.material_override = cloth("hessian_380", Color(0.85, 0.82, 0.74), 0.02)
	s.name = "String"
	root.add_child(s)
	return root

## bow tips in bow space (where the string is tied)
const BOW_TOP := Vector3(0, 1.24, -0.05)
const BOW_BOTTOM := Vector3(0, -0.61, -0.05)

## a unit-length thin cylinder along +Y from the origin, for strings/arrows
static func make_rod(radius: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 1.0
	cm.radial_segments = 4
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	return mi

## orient a unit rod (from make_rod) to span a -> b in world space
static func span(rod: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001: return
	var y := d / l
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	rod.global_transform = Transform3D(Basis(x, y * l, z), (a + b) * 0.5)

## nocked arrow: shaft along +Y from the nock (origin) to the head
static func make_arrow() -> Node3D:
	var root := Node3D.new()
	root.name = "Arrow"
	var sh := make_rod(0.004, cloth("hessian_380", Color(0.55, 0.45, 0.30), 0.03))
	sh.scale = Vector3(1, 0.86, 1)
	sh.position = Vector3(0, 0.43, 0)
	root.add_child(sh)
	var hd := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.0
	pm.bottom_radius = 0.008
	pm.height = 0.05
	pm.radial_segments = 4
	hd.mesh = pm
	hd.position = Vector3(0, 0.885, 0)
	hd.material_override = metal(Color(0.55, 0.56, 0.58), 0.3)
	root.add_child(hd)
	for k in 2:
		var f := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.03, 0.12)
		f.mesh = q
		f.position = Vector3(0, 0.08, 0)
		f.rotation.y = k * PI * 0.5
		f.material_override = cloth("rough_linen", Color(0.88, 0.86, 0.80), 0.05, true)
		root.add_child(f)
	return root

## Ebira-style quiver worn on the right hip, arrows fletched white.
static func make_quiver() -> Node3D:
	var root := Node3D.new()
	root.name = "Quiver"
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.11, 0.42, 0.07)
	box.mesh = bm
	box.material_override = lacquer(Color(0.12, 0.08, 0.05), 0.4)
	root.add_child(box)
	for i in 7:
		var a := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.004
		cm.bottom_radius = 0.004
		cm.height = 0.62
		cm.radial_segments = 4
		a.mesh = cm
		var x := -0.04 + 0.013 * i
		a.position = Vector3(x, 0.28, 0.01 * (i % 2))
		a.rotation.z = (i - 3) * 0.035
		a.material_override = cloth("hessian_380", Color(0.55, 0.45, 0.30), 0.03)
		root.add_child(a)
		var f := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.018, 0.11)
		f.mesh = q
		f.position = a.position + Vector3(0, 0.27, 0)
		f.material_override = cloth("rough_linen", Color(0.88, 0.86, 0.80), 0.05, true)
		root.add_child(f)
	return root
