class_name MeshLib
extends RefCounted
## Procedural mesh library for world dressing.
##
## Everything here is generated once at load and shared by MultiMesh instances,
## so a family of assets costs one mesh regardless of how many are placed.
## Meshes are authored low-poly to match the existing character art, and each
## family exposes LOD variants (0 = near, 2 = cheapest) plus vertex colours:
##   COLOR.r = wind bend weight (0 at the root, 1 at the tip)
##   COLOR.g = ambient occlusion darkening toward the root
##   COLOR.b = seed-plume flag, so grass.gdshader can tint and whip the
##             feathery heads separately from the leaves

static func _push(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2, bend: float, ao: float, plume := 0.0) -> void:
	st.set_normal(n)
	st.set_uv(uv)
	st.set_color(Color(bend, ao, plume, 1.0))
	st.add_vertex(p)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ba: float, bb: float, bc: float, ao := 1.0) -> void:
	var n := (b - a).cross(c - a).normalized()
	_push(st, a, n, Vector2(0, 1), ba, ao * 0.65)
	_push(st, b, n, Vector2(1, 1), bb, ao * 0.65)
	_push(st, c, n, Vector2(0.5, 0), bc, ao)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, b0: float, b1: float, ao0 := 0.6, ao1 := 1.0, p0 := 0.0, p1 := 0.0) -> void:
	var n := (b - a).cross(d - a).normalized()
	_push(st, a, n, Vector2(0, 1), b0, ao0, p0)
	_push(st, b, n, Vector2(1, 1), b0, ao0, p0)
	_push(st, c, n, Vector2(1, 0), b1, ao1, p1)
	_push(st, a, n, Vector2(0, 1), b0, ao0, p0)
	_push(st, c, n, Vector2(1, 0), b1, ao1, p1)
	_push(st, d, n, Vector2(0, 0), b1, ao1, p1)

## Tapered, optionally curved cylinder — trunks, branches, bamboo culms.
static func _limb(st: SurfaceTool, base: Vector3, dir: Vector3, len_m: float, r0: float, r1: float, sides: int, segs := 2, curve := Vector3.ZERO) -> Vector3:
	var up := dir.normalized()
	var side := up.cross(Vector3(0.123, 0.987, 0.331)).normalized()
	if side.length() < 0.01: side = Vector3.RIGHT
	var fwd := up.cross(side).normalized()
	var prev := base
	var prev_r := r0
	var prev_up := up
	for s in range(1, segs + 1):
		var t := float(s) / float(segs)
		var cur_up := (up + curve * t).normalized()
		var nxt := prev + prev_up * (len_m / float(segs)) + curve * (len_m / float(segs)) * t * 0.5
		var r := lerpf(r0, r1, t)
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var o0 := (side * cos(a0) + fwd * sin(a0))
			var o1 := (side * cos(a1) + fwd * sin(a1))
			var p0 := prev + o0 * prev_r
			var p1 := prev + o1 * prev_r
			var p2 := nxt + o1 * r
			var p3 := nxt + o0 * r
			var bd0 := (float(s - 1) / float(segs))
			var bd1 := t
			_quad(st, p0, p1, p2, p3, bd0 * bd0, bd1 * bd1, 0.55 + 0.45 * bd0, 0.55 + 0.45 * bd1)
		prev = nxt; prev_r = r; prev_up = cur_up
	return prev

## Low-poly foliage blob (octahedron), the canopy building block.
## Canopy / bush blob.
## This used to emit a bare 8-face octahedron with flat per-face normals, which
## is why every canopy read as a faceted crystal and was lit from the inside
## (the geometric normal of those faces points inward). It now subdivides the
## octahedron `sub` times, projects onto an ellipsoid with a stable per-direction
## lump so shared vertices agree, flattens the underside into a dome, uses smooth
## outward normals and bakes vertical AO into the vertex colour.
const _OCTA := [Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(1, 0, 0),
	Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
const _OCTA_F := [[0, 2, 4], [0, 4, 3], [0, 3, 5], [0, 5, 2],
	[1, 4, 2], [1, 3, 4], [1, 5, 3], [1, 2, 5]]

static func _blob(st: SurfaceTool, c: Vector3, r: Vector3, bend: float, seed := 0,
		sub := 1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 991 + seed
	var jit := Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.1, 0.1),
		rng.randf_range(-0.12, 0.12)) * r.length() * 0.22
	var tris: Array = []
	for f in _OCTA_F:
		tris.append([_OCTA[f[0]], _OCTA[f[1]], _OCTA[f[2]]])
	for _s in maxi(sub, 0):
		var nt: Array = []
		for t in tris:
			var a: Vector3 = t[0]
			var b: Vector3 = t[1]
			var d: Vector3 = t[2]
			var ab: Vector3 = (a + b).normalized()
			var bd: Vector3 = (b + d).normalized()
			var da: Vector3 = (d + a).normalized()
			nt.append([a, ab, da]); nt.append([ab, b, bd])
			nt.append([da, bd, d]); nt.append([ab, bd, da])
		tris = nt
	var sf := float(seed)
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(0.5, 0)]
	for t in tris:
		for k in 3:
			var dir: Vector3 = (t[k] as Vector3).normalized()
			var lump: float = 1.0 \
				+ 0.17 * sin(dir.x * 5.3 + sf) * cos(dir.z * 4.7 - sf * 0.7) \
				+ 0.11 * sin(dir.y * 7.1 + sf * 1.3)
			var q := Vector3(dir.x * r.x, dir.y * r.y, dir.z * r.z) * lump
			if q.y < 0.0: q.y *= 0.62      # dome, not sphere
			var nrm := Vector3(dir.x / maxf(r.x, 0.001), dir.y / maxf(r.y, 0.001),
				dir.z / maxf(r.z, 0.001)).normalized()
			var ao := clampf(0.42 + 0.62 * (dir.y * 0.5 + 0.5), 0.0, 1.0)
			_push(st, c + jit + q, nrm, uvs[k], bend, ao)

## Canopy mass built from scattered foliage cards rather than one smooth hull.
##
## A flattened octahedron -- which is what _blob gives you -- has six silhouette
## vertices. Stack three of them on a pole and you do not get a pine, you get a
## signpost: hard-edged hexagonal discs with clean air between them. What makes
## a canopy read as foliage is a BROKEN outline, and that only comes from many
## small cards at many angles. Twenty-four two-triangle cards cost 48 triangles,
## which is less than one subdivided blob, and they silhouette correctly.
##
## flat  <1 squashes the cloud vertically (pine plate 0.30, round crown 0.75)
## droop how far the card tips fall below their anchor (pines droop, maples do
##       not much)
static func _canopy(st: SurfaceTool, c: Vector3, r: float, flat: float, cards: int,
		rng: RandomNumberGenerator, bend: float, droop := 0.35) -> void:
	for i in cards:
		# position inside an ellipsoid, biased outward so the rim is dense and
		# the interior does not waste triangles nobody can see
		var a := rng.randf() * TAU
		var q := sqrt(rng.randf_range(0.20, 1.0))
		var yy := rng.randf_range(-1.0, 1.0)
		var p := c + Vector3(cos(a) * q, yy * flat * sqrt(maxf(1.0 - q * q * 0.7, 0.05)),
			sin(a) * q) * r
		# each card points away from the centre and tips downward
		var out := (p - c)
		out.y *= 0.5
		if out.length() < 0.001: out = Vector3(cos(a), 0, sin(a))
		out = (out.normalized() + Vector3(0, -droop, 0)).normalized()
		var side := out.cross(Vector3.UP)
		if side.length() < 0.01: side = Vector3.RIGHT
		side = side.normalized() * r * rng.randf_range(0.16, 0.30)
		var len_m := r * rng.randf_range(0.38, 0.72)
		var tip := p + out * len_m
		var mid := p + out * len_m * 0.5
		# spray: wide at the base, tapering to a point, with a kink at mid so
		# the two halves catch light differently
		var lift := Vector3(0, r * flat * rng.randf_range(-0.10, 0.14), 0)
		# (v0.13 trees) COLOR.r did double duty in the old tree shader: wind weight AND the
		# bark/leaf selector (below about 0.55 a vertex is painted bark). A
		# card must therefore never drop into the bark band, however little
		# the branch it hangs from is meant to move.
		var b0 := 0.62 + 0.20 * bend
		var b1 := 0.78 + 0.22 * bend
		_quad(st, p - side, p + side, mid + side * 0.75 + lift, mid - side * 0.75 + lift,
			b0, b1)
		_tri(st, mid + side * 0.75 + lift, mid - side * 0.75 + lift, tip + lift * 1.6,
			b1, b1, minf(b1 + 0.12, 1.0))

static func _commit(st: SurfaceTool) -> ArrayMesh:
	st.generate_tangents()
	return st.commit()

# =================================================================== grass
## Grass clump. One instance draws several blades so instance counts stay low.
## kind: short | medium | tall | wild | dry | undergrowth | bamboo_ground
static func grass(kind: String, lod := 0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# h    blade length in metres (arc length, not height: an arched blade
	#      stands lower than it is long)
	# w    blade width at the base
	# n    blades per clump
	# segs segments per blade -- this is what makes the arc smooth instead of
	#      a two-link shear when the wind lays the field over
	# arc  total lean of the blade from vertical, in radians
	# lean how far the root is pushed off the clump centre
	# plume fraction of blades carrying a susuki seed head
	var cfg: Dictionary = {
		# "short" is the ground-cover layer whose whole job is to hide soil, so
		# it is a splayed rosette -- many wide blades at a 60-degree arc -- not
		# a miniature of the tall clump. Seven thin upright blades over a 0.2 m
		# spread covered about two percent of the ground under them.
		"short":        {"h": 0.30, "w": 0.068, "n": 10, "segs": 3, "spread": 0.30, "arc": 1.10, "lean": 0.09, "plume": 0.0},
		# v0.14: everything shorter and far fewer seed heads. At 1.2 m with 60%
		# plumes the meadow was a wall of dark blades topped with yellow flags
		# that stood taller than the camera's lens.
		"medium":       {"h": 0.50, "w": 0.060, "n": 9, "segs": 4, "spread": 0.28, "arc": 0.85, "lean": 0.08, "plume": 0.0},
		"tall":         {"h": 0.75, "w": 0.064, "n": 8, "segs": 5, "spread": 0.30, "arc": 1.00, "lean": 0.09, "plume": 0.12},
		"wild":         {"h": 0.65, "w": 0.072, "n": 8, "segs": 5, "spread": 0.40, "arc": 1.20, "lean": 0.12, "plume": 0.05},
		"dry":          {"h": 0.60, "w": 0.050, "n": 8, "segs": 4, "spread": 0.34, "arc": 1.10, "lean": 0.10, "plume": 0.15},
		# v0.14: narrower - at 13 cm wide the forest floor read as paper strips
		"undergrowth":  {"h": 0.38, "w": 0.085, "n": 8, "segs": 3, "spread": 0.42, "arc": 1.00, "lean": 0.11, "plume": 0.0},
		"bamboo_ground":{"h": 0.70, "w": 0.100, "n": 6, "segs": 4, "spread": 0.30, "arc": 0.55, "lean": 0.06, "plume": 0.0},
	}.get(kind, {"h": 0.6, "w": 0.06, "n": 8, "segs": 4, "spread": 0.3, "arc": 0.8, "lean": 0.08, "plume": 0.0})
	var blades := int(cfg["n"])
	var segs := int(cfg["segs"])
	var plume_f := float(cfg["plume"])
	if lod == 1:
		blades = maxi(3, blades / 2); segs = maxi(2, segs / 2); plume_f *= 0.6
	elif lod >= 2:
		blades = maxi(2, blades / 3); segs = 1; plume_f = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) & 0x7fffffff
	for b in blades:
		var a := rng.randf() * TAU
		var dir := Vector3(cos(a), 0, sin(a))
		# Width runs across the blade, so it has to be perpendicular to the way
		# the blade arches. Building every blade with its width on +X, which is
		# what this did, made each clump a stack of parallel cards.
		var side := Vector3(-sin(a), 0, cos(a))
		var off := dir * rng.randf() * float(cfg["spread"])
		var blen := float(cfg["h"]) * rng.randf_range(0.78, 1.18)
		var wid := float(cfg["w"]) * rng.randf_range(0.8, 1.2)
		var arc := float(cfg["arc"]) * rng.randf_range(0.55, 1.35)
		var root := off + dir * float(cfg["lean"])
		# Circular arc of total turn `arc` over arc-length `blen`: the blade
		# curves over under its own weight and keeps its length while doing it.
		var radius := blen / maxf(arc, 0.001)
		var has_plume := rng.randf() < plume_f
		var prev_c := root
		var prev_w := wid * 0.5
		var tip := root
		var tip_dir := Vector3.UP
		for s in range(1, segs + 1):
			var t := float(s) / float(segs)
			var th := arc * t
			var ctr := root + dir * (radius * (1.0 - cos(th))) + Vector3(0, radius * sin(th), 0)
			# Widest low down, tapering to a point. The previous curve was
			# sin(PI * min(t*1.6, 1)), which reaches zero at t = 0.625 and
			# stays there: the top 37% of every blade was a zero-width strip
			# with a degenerate normal.
			var w2 := wid * 0.5 * pow(1.0 - t, 0.60) * (0.80 + 0.30 * sin(PI * t))
			var bend0 := ((float(s - 1) / float(segs)) ** 1.5)
			var bend1 := (t ** 1.5)
			_quad(st, prev_c - side * prev_w, prev_c + side * prev_w,
				ctr + side * w2, ctr - side * w2,
				bend0, bend1, 0.32 + 0.68 * bend0, 0.32 + 0.68 * bend1)
			prev_c = ctr
			prev_w = w2
			tip = ctr
			tip_dir = (dir * sin(th) + Vector3.UP * cos(th)).normalized()
		if has_plume:
			_plume(st, tip, tip_dir, side, blen * 0.34, rng, maxi(segs / 2, 2))
	return _commit(st)

## Susuki seed head: three thin feathery spikelets carried on past the blade
## tip. They are the pale part that catches a low sun, so they get COLOR.b = 1
## and the shader tints and whips them separately. One wide card, which this
## was, reads as a paper flag; a real seed head is fine enough that the sky
## shows through it, and that is the whole effect.
static func _plume(st: SurfaceTool, base: Vector3, dir: Vector3, side: Vector3,
		length_m: float, rng: RandomNumberGenerator, segs: int) -> void:
	var fan := [-0.26, 0.0, 0.26]
	for k in fan.size():
		var tilt: float = float(fan[k]) * rng.randf_range(0.6, 1.4)
		var d0 := (dir + side * tilt).normalized()
		var len_k := length_m * rng.randf_range(0.70, 1.0)
		var wid_k := 0.010 + 0.006 * rng.randf()
		var prev := base + side * (tilt * 0.02)
		var prev_w := wid_k * 0.3
		for s in range(1, segs + 1):
			var t := float(s) / float(segs)
			var d := (d0 + Vector3(0, -0.70 * t * t, 0)).normalized()
			var ctr := prev + d * (len_k / float(segs))
			var w := wid_k * sin(PI * minf(t * 1.3, 1.0)) + 0.002
			_quad(st, prev - side * prev_w, prev + side * prev_w,
				ctr + side * w, ctr - side * w,
				0.86, 0.94 + 0.06 * t, 1.0, 1.0, 1.0, 1.0)
			prev = ctr
			prev_w = w

# =================================================================== ground cover
static func fern(lod := 0) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fronds := 7 if lod == 0 else (4 if lod == 1 else 3)
	var rng := RandomNumberGenerator.new(); rng.seed = 4242
	for f in fronds:
		var a := TAU * float(f) / float(fronds) + rng.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(a), 1.5, sin(a)).normalized()
		var l := rng.randf_range(0.5, 0.85)
		var tip := dir * l + Vector3(0, 0, 0)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.10
		_quad(st, -side * 0.6, side * 0.6, tip + side * 0.25, tip - side * 0.25, 0.1, 1.0, 0.5, 1.0)
	return _commit(st)

static func shrub(lod := 0) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A bush is not a boulder. Five smooth spheres read as rock no matter what
	# colour they are, because the silhouette is closed and the shading is
	# smooth. What makes a shrub legible is a broken edge: dozens of small flat
	# leaves catching light at different angles, hung off woody stems that
	# splay out from one root. So: stems first, then leaf cards on the stems.
	var rng := RandomNumberGenerator.new(); rng.seed = 515
	var stems := 6 if lod == 0 else (4 if lod == 1 else 2)
	var leaves := 7 if lod == 0 else (4 if lod == 1 else 2)
	var lw := 0.055 if lod == 0 else (0.075 if lod == 1 else 0.11)
	for s in stems:
		# stems fan out from the root, leaning further over the further round
		# the circle we go, so the bush is lopsided rather than a neat dome
		var a := TAU * (float(s) + rng.randf_range(-0.22, 0.22)) / float(stems)
		var lean := rng.randf_range(0.42, 0.85)
		var dir := Vector3(cos(a) * lean, 1.0, sin(a) * lean).normalized()
		var slen := rng.randf_range(0.30, 0.52)
		var base := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.0, 0.06)
		if lod < 2:
			_limb(st, base, dir, slen, 0.020, 0.010, 3, 2, Vector3(0, -0.10, 0))
		var tip := base + dir * slen + Vector3(0, -0.05, 0)
		# leaf cards clustered around the last third of each stem
		for l in leaves:
			var t := rng.randf_range(0.45, 1.0)
			var at := base.lerp(tip, t)
			var la := rng.randf() * TAU
			var pitch := rng.randf_range(-0.55, 0.30)
			var out := Vector3(cos(la), pitch, sin(la)).normalized()
			var llen := rng.randf_range(0.10, 0.20) * (1.0 if lod == 0 else 1.5)
			var side := out.cross(Vector3.UP).normalized()
			if side.length() < 0.01: side = Vector3.RIGHT
			side *= lw * rng.randf_range(0.7, 1.3)
			var p0 := at + side
			var p1 := at - side
			var mid := at + out * llen * 0.55
			var end := at + out * llen + Vector3(0, -llen * 0.18, 0)
			# a leaf is a slim diamond: narrow at the stem, wide at mid, pointed
			_quad(st, p0, p1, mid - side * 1.25, mid + side * 1.25, 0.25, 0.65)
			_tri(st, mid + side * 1.25, mid - side * 1.25, end, 0.65, 0.65, 1.0)
	# a little dense mass at the heart so light does not read straight through
	if lod < 2:
		_blob(st, Vector3(0, 0.20, 0), Vector3(0.20, 0.16, 0.20), 0.10, 3, 0)
	return _commit(st)

static func flower(lod := 0) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new(); rng.seed = 77
	var stems := 4 if lod == 0 else 2
	for i in stems:
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * rng.randf() * 0.16
		var h := rng.randf_range(0.20, 0.38)
		_limb(st, base, Vector3.UP, h, 0.012, 0.008, 3, 1)
		var top := base + Vector3(0, h, 0)
		for p in 4:
			var pa := TAU * float(p) / 4.0
			var o := Vector3(cos(pa), 0.25, sin(pa)) * 0.055
			_tri(st, top, top + o, top + Vector3(-o.z, 0.02, o.x) * 0.9, 1.0, 1.0, 1.0)
	return _commit(st)

static func mushroom(lod := 0) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new(); rng.seed = 313
	for i in (3 if lod == 0 else 2):
		var base := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
		var h := rng.randf_range(0.07, 0.15)
		_limb(st, base, Vector3.UP, h, 0.016, 0.013, 4, 1)
		var cap_c := base + Vector3(0, h, 0)
		_blob(st, cap_c, Vector3(0.07, 0.035, 0.07) * rng.randf_range(0.8, 1.3), 0.0, i)
	return _commit(st)

# =================================================================== debris
static func stone(size := 1.0, seed := 0, lod := 0) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new(); rng.seed = 600 + seed
	var lumps := 3 if lod == 0 else 1
	for i in lumps:
		var c := Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.0, 0.18), rng.randf_range(-0.2, 0.2)) * size
		_blob(st, c, Vector3(rng.randf_range(0.28, 0.5), rng.randf_range(0.2, 0.36), rng.randf_range(0.28, 0.5)) * size, 0.0, seed * 7 + i)
	return _commit(st)

static func boulder(seed := 0, lod := 0) -> ArrayMesh:
	return stone(2.4, 90 + seed, lod)

static func branch(lod := 0) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var e := _limb(st, Vector3.ZERO, Vector3(1, 0.12, 0.2).normalized(), 1.1, 0.045, 0.02, 4, 2, Vector3(0, -0.08, 0))
	if lod == 0:
		_limb(st, e * 0.55, Vector3(0.7, 0.2, -0.6).normalized(), 0.4, 0.022, 0.01, 3, 1)
	return _commit(st)

static func log_mesh(lod := 0) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_limb(st, Vector3(0, 0.22, 0), Vector3(1, 0.02, 0.1).normalized(), 3.0, 0.24, 0.19, 7 if lod == 0 else 5, 2)
	if lod == 0:
		_limb(st, Vector3(1.4, 0.3, 0.1), Vector3(0.2, 0.9, 0.3).normalized(), 0.5, 0.05, 0.02, 4, 1)
	return _commit(st)

static func stump(lod := 0) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_limb(st, Vector3.ZERO, Vector3.UP, 0.55, 0.36, 0.30, 8 if lod == 0 else 5, 1)
	if lod == 0:
		for i in 4:
			var a := TAU * float(i) / 4.0 + 0.4
			_limb(st, Vector3(cos(a), 0.06, sin(a)) * 0.3, Vector3(cos(a), -0.25, sin(a)).normalized(), 0.5, 0.09, 0.03, 4, 2)
	return _commit(st)

static func root(lod := 0) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new(); rng.seed = 828
	for i in (3 if lod == 0 else 2):
		var a := rng.randf() * TAU
		_limb(st, Vector3.ZERO, Vector3(cos(a), 0.35, sin(a)).normalized(), rng.randf_range(0.6, 1.1), 0.07, 0.025, 4, 2, Vector3(0, -0.5, 0))
	return _commit(st)

# =================================================================== village props
static func crate(lod := 0) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := 0.34
	var c := Vector3(0, s, 0)
	var pts := []
	for i in 8:
		pts.append(c + Vector3((-1 if (i & 1) == 0 else 1) * s, (-1 if (i & 2) == 0 else 1) * s, (-1 if (i & 4) == 0 else 1) * s))
	var faces := [[0,1,3,2],[4,6,7,5],[0,4,5,1],[2,3,7,6],[0,2,6,4],[1,5,7,3]]
	for f in faces:
		_quad(st, pts[f[0]], pts[f[1]], pts[f[2]], pts[f[3]], 0.0, 0.0, 0.7, 1.0)
	return _commit(st)

static func barrel(lod := 0) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 9 if lod == 0 else 6
	_limb(st, Vector3.ZERO, Vector3.UP, 0.34, 0.24, 0.29, sides, 1)
	_limb(st, Vector3(0, 0.34, 0), Vector3.UP, 0.34, 0.29, 0.24, sides, 1)
	return _commit(st)

static func basket(lod := 0) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_limb(st, Vector3.ZERO, Vector3.UP, 0.30, 0.16, 0.24, 8 if lod == 0 else 5, 1)
	return _commit(st)

static func sign_post(lod := 0) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_limb(st, Vector3.ZERO, Vector3.UP, 1.5, 0.06, 0.05, 4, 1)
	_quad(st, Vector3(-0.42, 1.05, 0.02), Vector3(0.42, 1.05, 0.02), Vector3(0.42, 1.42, 0.02), Vector3(-0.42, 1.42, 0.02), 0.0, 0.0, 1.0, 1.0)
	_quad(st, Vector3(0.42, 1.05, -0.02), Vector3(-0.42, 1.05, -0.02), Vector3(-0.42, 1.42, -0.02), Vector3(0.42, 1.42, -0.02), 0.0, 0.0, 1.0, 1.0)
	return _commit(st)

# =================================================================== trees
## Tree families. Trunk motion is subtle (low bend weight), leaves move most.
## family: cedar | maple | pine | sakura | dead_tree | young_tree | bamboo
# =================================================================== trees (v0.14)
## Trees are two surfaces:
##   0 bark   - opaque tubes, UV.x = turns around the limb, UV.y = metres along it
##              (tree_bark.gdshader tiles the Poly Haven bark set by that)
##   1 leaves - alpha-scissored cluster cards from leaf_atlas.png (4 x 2 cells,
##              tools/make_foliage_atlas.py), tree_leaf.gdshader
## Vertex colour: r = wind bend (0 root .. 1 tip), g = ambient occlusion,
## b = 1 on leaf cards, a = per-card random (flutter phase, tint jitter).
## Leaf TANGENT.xyz carries the card's true facing so the shader can thin out
## cards seen edge-on (their normals are bent onto the crown and cannot).
##
## v0.13 trees were flat-coloured triangle sprays on six-sided poles: pines read
## as telephone poles and maples as confetti. A crown is now a cloud of textured
## cluster cards whose normals are bent onto the crown ellipsoid, so the whole
## crown shades like one soft volume (lit side, shadow side, dark interior)
## while each card still shows real leaves and a broken, see-through outline.
##
## Every family draws its skeleton (trunk, limbs, crown) from one RNG with the
## same number of calls at every LOD, and leaf cards from a second RNG, so LOD
## 0/1/2 of a tree share one silhouette and the swap at range does not pop.
const CELL_BROAD := 0
const CELL_MAPLE := 1
const CELL_SAKURA := 2
const CELL_PINE := 3
const CELL_CEDAR := 4
const CELL_BAMBOO := 5
const CELL_TWIG := 6
const CELL_MAPLE_GREEN := 7

static func _tv(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2, c: Color) -> void:
	st.set_normal(n)
	st.set_uv(uv)
	st.set_color(c)
	st.add_vertex(p)

static func _rnd3(rng: RandomNumberGenerator) -> Vector3:
	return Vector3(rng.randfn(), rng.randfn(), rng.randfn()) * 0.5

## Tapered bark tube along a gently curved path. Returns the end point; fills
## `path` (if given) with the ring centres so leaves can be hung on the limb.
## flare widens the base (root buttress) over the first half metre. With
## emit = false only the path is computed (skeleton kept identical across LODs).
static func _tube(st: SurfaceTool, base: Vector3, dir: Vector3, len_m: float, r0: float, r1: float,
		sides: int, segs: int, curve: Vector3, bend0: float, bend1: float, ao0: float, ao1: float,
		v0 := 0.0, flare := 0.0, path: Array = [], emit := true) -> Vector3:
	var d := dir.normalized()
	var ref := Vector3(0.123, 0.0, 0.993) if absf(d.y) > 0.7 else Vector3.UP
	var side := (ref - d * ref.dot(d)).normalized()
	var reps := maxf(1.0, roundf(TAU * r0 / 1.1))
	var ts: Array = []
	for k in segs + 1:
		var t := float(k) / float(segs)
		if flare > 0.0: t = pow(t, 1.35)
		ts.append(t)
	var centres: Array = []
	var heads: Array = []
	var c := base
	var prev_t := 0.0
	for k in segs + 1:
		var t: float = ts[k]
		var h := (d + curve * t).normalized()
		if k > 0:
			var hm := (d + curve * (t + prev_t) * 0.5).normalized()
			c += hm * len_m * (t - prev_t)
		centres.append(c)
		heads.append(h)
		prev_t = t
	path.append_array(centres)
	if not emit:
		return centres[segs]
	var rings: Array = []
	var dist := 0.0
	for k in segs + 1:
		var h: Vector3 = heads[k]
		side = (side - h * side.dot(h)).normalized()
		var fwd := h.cross(side).normalized()
		var t: float = ts[k]
		if k > 0: dist += (centres[k] as Vector3).distance_to(centres[k - 1])
		var r := lerpf(r0, r1, t) * (1.0 + flare * exp(-dist / 0.42))
		var ring: Array = []
		for i in sides + 1:
			var th := TAU * float(i) / float(sides)
			var o := side * cos(th) + fwd * sin(th)
			var bump := 1.0 + 0.07 * sin(th * 3.0 + float(k) * 1.7) * (1.0 if flare > 0.0 else 0.4)
			var p: Vector3 = (centres[k] as Vector3) + o * r * bump
			var n := (o + h * (r0 - r1) / maxf(len_m, 0.01)).normalized()
			ring.append([p, n, Vector2(reps * float(i) / float(sides), v0 + dist),
				Color(lerpf(bend0, bend1, t), lerpf(ao0, ao1, t), 0.0, 0.0)])
		rings.append(ring)
	for k in segs:
		var ra: Array = rings[k]
		var rb: Array = rings[k + 1]
		for i in sides:
			var va: Array = ra[i]
			var vb: Array = ra[i + 1]
			var vc: Array = rb[i + 1]
			var vd: Array = rb[i]
			# Godot front faces are clockwise: a -> d -> c, a -> c -> b
			for q in [va, vd, vc, va, vc, vb]:
				_tv(st, q[0], q[1], q[2], q[3])
	return centres[segs]

static func _path_at(path: Array, t: float) -> Vector3:
	if path.is_empty(): return Vector3.ZERO
	if path.size() == 1: return path[0]
	var f := clampf(t, 0.0, 1.0) * float(path.size() - 1)
	var i := mini(int(f), path.size() - 2)
	return (path[i] as Vector3).lerp(path[i + 1], f - float(i))

## One leaf card centred on p (or hanging from it when hang = true).
## n0 = facing, up_hint = which way the leaf tips point. Normals are bent onto
## the crown ellipsoid (gcc, gcr); the true facing goes into TANGENT.
static func _card(st: SurfaceTool, p: Vector3, n0: Vector3, up_hint: Vector3, size: float, cell: int,
		gcc: Vector3, gcr: Vector3, bend: float, rng: RandomNumberGenerator, fold := 0.0,
		hang := false) -> void:
	var n := n0.normalized()
	var up := up_hint - n * up_hint.dot(n)
	if up.length() < 0.05:
		up = n.cross(Vector3(0.3, 0.1, 0.9))
	up = up.normalized()
	var side := up.cross(n).normalized()
	var hw := size * 0.5
	var b := (p - up * size * 0.10) if hang else (p - up * size * 0.5)
	var t := b + up * size
	var cu := float(cell % 4) * 0.25
	var cv := floorf(float(cell) / 4.0) * 0.5
	var u0 := cu + 0.0015
	var u1 := cu + 0.25 - 0.0015
	if rng.randf() < 0.5:
		var tmp := u0
		u0 = u1
		u1 = tmp
	var v0 := cv + 0.003
	var v1 := cv + 0.5 - 0.003
	var rnd := rng.randf()
	var tb := minf(bend + 0.15, 1.0)
	var pts: Array = [b - side * hw, b + side * hw, t + side * hw, t - side * hw]
	var uvs: Array = [Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0), Vector2(u0, v0)]
	var bends: Array = [bend, bend, tb, tb]
	var order: Array = [0, 3, 2, 0, 2, 1]
	if fold > 0.0:
		# open-book fold along the card's spine: depth when seen edge-on
		pts.append(b + n * size * fold)
		pts.append(t + n * size * fold)
		var um := (u0 + u1) * 0.5
		uvs.append(Vector2(um, v1))
		uvs.append(Vector2(um, v0))
		bends.append(bend)
		bends.append(tb)
		order = [0, 3, 5, 0, 5, 4, 4, 5, 2, 4, 2, 1]
	var safe_r := Vector3(maxf(gcr.x, 0.3), maxf(gcr.y, 0.3), maxf(gcr.z, 0.3))
	var nrms: Array = []
	var cols: Array = []
	for i in pts.size():
		var v: Vector3 = pts[i]
		var q := (v - gcc) / safe_r
		var gn := (q / safe_r).normalized()
		if gn.length() < 0.01: gn = n
		var nn := n if n.dot(gn) >= 0.0 else -n
		nrms.append((nn * 0.30 + gn * 0.70).normalized())
		var ao := clampf(0.30 + 0.55 * minf(q.length(), 1.15) + 0.22 * clampf(q.y, -1.0, 1.0), 0.2, 1.0)
		cols.append(Color(bends[i], ao, 1.0, rnd))
	var tg := Plane(n, 1.0)
	for i in order:
		st.set_tangent(tg)
		_tv(st, pts[i], nrms[i], uvs[i], cols[i])

## Scatter `n` cards over an ellipsoidal clump (centre c, radii r), mostly
## near its surface and pulled inward by part of their own size, so the much
## larger cards of a distant LOD do not swell the silhouette. flat < 1 keeps
## cards toward the clump's rim (pine pads).
static func _cluster(st: SurfaceTool, c: Vector3, r: Vector3, n: int, size: float, cell: int,
		rng: RandomNumberGenerator, bend: float, gcc: Vector3, gcr: Vector3, up_bias := 0.5,
		fold := 0.0, droop := 0.0, shell := 0.55, flat := 1.0, ny := 0.6, jit := 0.7) -> void:
	for i in n:
		var d := Vector3(rng.randfn(), (rng.randfn() * 0.75 + 0.22) * flat, rng.randfn())
		if d.length() < 0.001: d = Vector3.UP
		d = d.normalized()
		var k := lerpf(shell, 1.0, sqrt(rng.randf()))
		var ln := Vector3(d.x / maxf(r.x, 0.05), d.y / maxf(r.y, 0.05), d.z / maxf(r.z, 0.05)).normalized()
		var sz := size * rng.randf_range(0.8, 1.2)
		var p := c + Vector3(d.x * r.x, d.y * r.y, d.z * r.z) * k - ln * sz * 0.28
		var gq := (p - gcc) / Vector3(maxf(gcr.x, 0.3), maxf(gcr.y, 0.3), maxf(gcr.z, 0.3))
		var gn := gq.normalized() if gq.length() > 0.01 else Vector3.UP
		var nn := ln * 0.5 + gn * 0.5
		nn.y *= ny
		nn = (nn.normalized() + _rnd3(rng) * jit).normalized()
		var uh := Vector3.UP * up_bias + ln * (1.0 - up_bias) + Vector3(0, -droop, 0) + _rnd3(rng) * jit
		_card(st, p, nn, uh, sz, cell, gcc, gcr, bend, rng, fold)

static func tree(family: String, lod := 0, seed := 0) -> ArrayMesh:
	var sb := SurfaceTool.new()
	sb.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sl := SurfaceTool.new()
	sl.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = (hash(family) + seed * 7919) & 0x7fffffff
	var rc := RandomNumberGenerator.new()
	rc.seed = (hash(family) * 31 + seed * 104729 + 17) & 0x7fffffff
	var q := {
		"lod": lod,
		"ts": 9 if lod == 0 else (6 if lod == 1 else 4),
		"bs": 5 if lod == 0 else (4 if lod == 1 else 3),
		"cmul": 1.0 if lod == 0 else (0.36 if lod == 1 else 0.20),
		"smul": 1.0 if lod == 0 else (1.62 if lod == 1 else 2.05),
		"fold": 0.0,   # v0.14: the open-book fold doubled leaf tris for little gain
	}
	match family:
		"pine": _tree_pine(sb, sl, rng, rc, q)
		"cedar": _tree_cedar(sb, sl, rng, rc, q)
		"maple":
			# v0.14: spring, with the cherries in bloom - two maples in three
			# are in fresh green leaf, the rest a deep red-leaf cultivar
			var cell := CELL_MAPLE if (seed % 3) == 2 else CELL_MAPLE_GREEN
			_tree_broad(sb, sl, rng, rc, q, cell, rng.randf_range(6.0, 9.5), 0.33, 0.95, 5, 150, 1.35, 0.62)
		"sakura":
			_tree_broad(sb, sl, rng, rc, q, CELL_SAKURA, rng.randf_range(5.5, 8.5), 0.28, 0.55, 5, 165, 1.40, 0.45)
		"bamboo": _tree_bamboo(sb, sl, rng, rc, q)
		"dead_tree": _tree_dead(sb, sl, rng, rc, q)
		_:
			_tree_broad(sb, sl, rng, rc, q, CELL_BROAD, rng.randf_range(2.6, 4.2), 0.42, 1.0, 3, 56, 0.95, 0.75)
	sb.index()
	sb.generate_tangents()
	var m := sb.commit()
	sl.index()
	sl.commit(m)
	return m

static func _n(q: Dictionary, base: float, lo := 2) -> int:
	return maxi(lo, int(round(base * float(q["cmul"]))))

## Japanese black pine: leaning, kinked trunk; long boughs ending in flat
## needle pads, widest near the top (the wind-pruned umbrella).
static func _tree_pine(sb: SurfaceTool, sl: SurfaceTool, rng: RandomNumberGenerator,
		rc: RandomNumberGenerator, q: Dictionary) -> void:
	var lod: int = q["lod"]
	var smul: float = q["smul"]
	var fold: float = q["fold"]
	var H := rng.randf_range(8.5, 13.0)
	var sweep := Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
	var r0 := 0.26 + H * 0.012
	var p1: Array = []
	var mid := _tube(sb, Vector3.ZERO, Vector3.UP, H * 0.60, r0, r0 * 0.62, q["ts"], 5 if lod == 0 else 2,
		sweep, 0.0, 0.08, 0.5, 0.85, 0.0, 0.35, p1)
	var kink := Vector3(-sweep.z, 0, sweep.x) * rng.randf_range(0.6, 1.3) + sweep * 0.5
	var p2: Array = []
	var top := _tube(sb, mid, (Vector3.UP * 3.0 + kink).normalized(), H * 0.40, r0 * 0.62, 0.05,
		maxi(int(q["ts"]) - 2, 3), 3 if lod == 0 else 1, kink * 0.4, 0.08, 0.30, 0.85, 0.85, H * 0.60,
		0.0, p2)
	var cc := mid.lerp(top, 0.45) + Vector3(0, 0.4, 0)
	var crad := Vector3(H * 0.36, H * 0.24, H * 0.36)
	var nb := 7
	var ga := rng.randf() * TAU
	for i in nb:
		var t := float(i) / float(nb - 1)
		var anchor: Vector3 = _path_at(p1, 0.55 + 0.45 * t / 0.6) if t < 0.6 else _path_at(p2, (t - 0.6) / 0.4 * 0.75)
		ga += 2.39996 + rng.randf_range(-0.3, 0.3)
		var reach := H * (0.34 - 0.18 * t) * rng.randf_range(0.8, 1.15)
		var dir := Vector3(cos(ga), rng.randf_range(0.06, 0.30), sin(ga)).normalized()
		# every LOD walks the same bough; only LOD 0/1 draw the wood
		var end := _tube(sb, anchor, dir, reach, r0 * (0.30 - 0.12 * t), 0.035, q["bs"],
			3 if lod == 0 else 1, Vector3(0, 0.35, 0), 0.20, 0.70, 0.65, 0.85, 0.0, 0.0, [], lod < 2)
		var pr := Vector3(1.0 + reach * 0.40, 0.42 + 0.06 * reach, 1.0 + reach * 0.40)
		# coarse LODs: big cards scattered at random angles read as stray X's,
		# so their pads are kept tidier
		var jit := 0.7 if lod == 0 else (0.5 if lod == 1 else 0.38)
		_cluster(sl, end + Vector3(0, 0.25, 0), pr, _n(q, 20.0), 1.30 * smul, CELL_PINE, rc,
			0.72 + 0.2 * t, cc, crad, 0.25, fold, 0.0, 0.35, 0.45, 1.0, jit)
	_cluster(sl, top + Vector3(0, -0.1, 0), Vector3(1.5, 0.8, 1.5), _n(q, 14.0), 1.25 * smul,
		CELL_PINE, rc, 1.0, cc, crad, 0.5, fold, 0.0, 0.4, 0.6, 1.0, 0.7 if lod == 0 else 0.45)

## Sugi (Japanese cedar): straight column trunk, dense narrow cone of fronds.
static func _tree_cedar(sb: SurfaceTool, sl: SurfaceTool, rng: RandomNumberGenerator,
		rc: RandomNumberGenerator, q: Dictionary) -> void:
	var lod: int = q["lod"]
	var smul: float = q["smul"]
	var fold: float = q["fold"]
	var H := rng.randf_range(12.0, 18.0)
	var r0 := 0.26 + H * 0.014
	var lean := Vector3(rng.randf_range(-0.06, 0.06), 0, rng.randf_range(-0.06, 0.06))
	var path: Array = []
	# the trunk stops just inside the spire, so no bare stick pokes out on top
	_tube(sb, Vector3.ZERO, Vector3.UP, H * 0.95, r0, 0.05, q["ts"], 6 if lod == 0 else 3, lean, 0.0, 0.30,
		0.5, 0.8, 0.0, 0.40, path)
	var y0 := H * rng.randf_range(0.22, 0.30)
	var rb := H * rng.randf_range(0.15, 0.18)
	var cc := Vector3(0, (y0 + H) * 0.5, 0)
	var crad := Vector3(rb, (H - y0) * 0.55, rb)
	for i in 12:
		var u := float(i) / 12.0 * 0.8
		var y := y0 + (H - y0) * u
		var ax := _path_at(path, y / H)
		var a := rng.randf() * TAU
		var R := rb * (1.0 - u)
		_tube(sb, ax, Vector3(cos(a), -0.25, sin(a)).normalized(), R * 0.85, 0.06, 0.02, 4, 1,
			Vector3.ZERO, 0.25, 0.6, 0.6, 0.75, 0.0, 0.0, [], lod == 0)
	var nc := _n(q, 230.0, 8)
	for i in nc:
		# uniform in height: the smaller cards higher up then cover the narrow
		# top as densely as the big ones cover the skirt
		# (stratified + golden-angle spiral, so a coarse LOD's few cards still
		# wrap the whole cone without gaps)
		var u := (float(i) + rc.randf()) / float(nc) * 0.975
		var y := y0 + (H - y0) * u
		var ax := _path_at(path, minf(y / (H * 0.95), 1.0))
		var a := float(i) * 2.39996 + rc.randf_range(-0.5, 0.5)
		var radial := Vector3(cos(a), 0, sin(a))
		var R := rb * pow(1.0 - u, 0.85) + 0.30
		# cards shrink toward the top, and the coarse LODs enlarge them less
		# there, so the cone keeps its point instead of ending in a cross
		var sm := lerpf(smul, 1.0 + (smul - 1.0) * 0.5, u)
		var sz := (0.80 + 1.00 * (1.0 - u)) * sm * rc.randf_range(0.85, 1.15)
		var p := ax + radial * maxf(R * rc.randf_range(0.55, 1.0) - sz * 0.25, 0.1) + Vector3(0, -sz * 0.15, 0)
		var cone_n := (radial * (H - y0) + Vector3.UP * rb).normalized()
		var nn := (cone_n + _rnd3(rc) * 0.5).normalized()
		var uh := radial * 0.85 + Vector3(0, -0.30, 0) + _rnd3(rc) * 0.4
		_card(sl, p, nn, uh, sz, CELL_CEDAR, cc, crad, 0.55 + 0.45 * u, rc, fold)
	# spire: a few small upright sprays closing the cone
	var tip := _path_at(path, 1.0)
	var ns := _n(q, 8.0, 2)
	var tsz := 0.75 * (1.0 + (smul - 1.0) * 0.45)
	for k in ns:
		var a := TAU * float(k) / float(ns) + rc.randf_range(-0.4, 0.4)
		var f := Vector3(cos(a), 0.0, sin(a))
		var yk := H - tsz * (0.45 + 0.9 * float(k) / float(ns))
		_card(sl, Vector3(tip.x, yk, tip.z) + f * 0.08, f, Vector3.UP + _rnd3(rc) * 0.15,
			tsz * rc.randf_range(0.9, 1.1), CELL_CEDAR, cc, crad, 1.0, rc, fold)

## Maple, sakura and young trees: short trunk forking into limbs, a broken
## dome crown built from clumps at the limb ends. The crown ellipsoid is
## measured from the limb tips, so foliage always sits on the wood.
static func _tree_broad(sb: SurfaceTool, sl: SurfaceTool, rng: RandomNumberGenerator,
		rc: RandomNumberGenerator, q: Dictionary, cell: int, H: float, fork_f: float, rise: float,
		nlimbs: int, cards: int, csize: float, dome: float) -> void:
	var lod: int = q["lod"]
	var smul: float = q["smul"]
	var fold: float = q["fold"]
	var r0 := 0.07 + H * 0.028
	var lean := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
	var hf := H * fork_f
	var fork := _tube(sb, Vector3.ZERO, Vector3.UP, hf, r0, r0 * 0.78, q["ts"], 3 if lod == 0 else 1,
		lean, 0.0, 0.06, 0.5, 0.75, 0.0, 0.45)
	var tips: Array = []
	var a0 := rng.randf() * TAU
	for i in nlimbs:
		var a := a0 + TAU * float(i) / float(nlimbs) + rng.randf_range(-0.35, 0.35)
		var dir := Vector3(cos(a) * 0.85, rise * rng.randf_range(0.75, 1.1), sin(a) * 0.85).normalized()
		var L := (H - hf) * rng.randf_range(0.55, 0.72) * (1.0 + (1.0 - rise) * 0.35)
		var lp: Array = []
		var draw_limb := lod < 2 or i < 3
		var e := _tube(sb, fork, dir, L, r0 * 0.56, maxf(r0 * 0.16, 0.025), q["bs"], 3 if lod == 0 else 1,
			Vector3(cos(a), -0.15, sin(a)) * 0.35, 0.06, 0.45, 0.72, 0.9, hf, 0.0, lp, draw_limb)
		tips.append(e)
		for j in 2:
			var sp := _path_at(lp, rng.randf_range(0.45, 0.8))
			var a2 := a + rng.randf_range(-1.1, 1.1)
			var d2 := Vector3(cos(a2), rng.randf_range(0.15, 0.6) * rise + 0.1, sin(a2)).normalized()
			var l2 := L * rng.randf_range(0.42, 0.58)
			tips.append(_tube(sb, sp, d2, l2, maxf(r0 * 0.16, 0.025), 0.02, 4, 2, Vector3(0, 0.25, 0),
				0.4, 0.7, 0.8, 0.95, 0.0, 0.0, [], lod == 0))
	# crown = bounding ellipsoid of the tips, lifted a little
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for tp in tips:
		lo = lo.min(tp)
		hi = hi.max(tp)
	var crad := ((hi - lo) * 0.5 + Vector3(0.9, 0.7, 0.9)).max(Vector3(1.0, 0.9, 1.0))
	# a dome, not a lily pad: enforce crown depth, hang it from the highest tips
	crad.y = maxf(crad.y, (crad.x + crad.z) * 0.5 * dome)
	var cc := Vector3((lo.x + hi.x) * 0.5, hi.y + 0.5 - crad.y * 0.30, (lo.z + hi.z) * 0.5)
	var total := _n(q, float(cards), 5)
	var in_clumps := 0.72 if lod == 0 else (0.55 if lod == 1 else 0.40)
	var nclump := int(round(float(total) * in_clumps))
	var rcl := Vector3(maxf(crad.x * 0.42, 0.8), maxf(crad.y * 0.50, 0.6), maxf(crad.z * 0.42, 0.8))
	for i in nclump:
		var tp: Vector3 = tips[i % tips.size()]
		var c2 := tp.lerp(cc, 0.15) + Vector3(0, 0.25, 0)
		_cluster(sl, c2, rcl, 1, csize * smul, cell, rc, 0.8, cc, crad, 0.45, fold, 0.0, 0.25)
	_cluster(sl, cc, crad * 0.92, total - nclump, csize * smul, cell, rc, 0.8, cc, crad, 0.45, fold, 0.0, 0.55)

## Bamboo clump: tall thin culms leaning gently out, leaf sprays on the upper half.
static func _tree_bamboo(sb: SurfaceTool, sl: SurfaceTool, rng: RandomNumberGenerator,
		rc: RandomNumberGenerator, q: Dictionary) -> void:
	var lod: int = q["lod"]
	var smul: float = q["smul"]
	var fold: float = q["fold"]
	var culms := 9
	var drawn := 9 if lod == 0 else (5 if lod == 1 else 3)
	var paths: Array = []
	var outs: Array = []
	for c in culms:
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.9)
		var h := rng.randf_range(7.0, 12.0)
		var out := Vector3(cos(a), 0, sin(a))
		var lean := out * rng.randf_range(0.05, 0.18)
		var r := rng.randf_range(0.040, 0.065)
		var path: Array = []
		_tube(sb, base, (Vector3.UP + lean * 0.25).normalized(), h, r, r * 0.55, maxi(int(q["ts"]) - 3, 3),
			5 if lod == 0 else 2, lean, 0.0, 1.0, 0.55, 0.95, 0.0, 0.0, path, c < drawn)
		paths.append(path)
		outs.append(a)
	var cc := Vector3(0, 7.5, 0)
	var crad := Vector3(2.4, 3.5, 2.4)
	var total := _n(q, 150.0, 6)
	for k in total:
		var ci := k % culms
		var path: Array = paths[ci]
		var t := rc.randf_range(0.45, 1.0)
		var p := _path_at(path, t)
		var la: float = float(outs[ci]) + rc.randf_range(-1.6, 1.6)
		var lo := Vector3(cos(la), rc.randf_range(-0.55, 0.05), sin(la)).normalized()
		var nn := (Vector3.UP * 0.5 + lo * 0.5 + _rnd3(rc) * 0.6).normalized()
		_card(sl, p + lo * 0.25 * smul, nn, lo, 1.35 * smul * rc.randf_range(0.85, 1.15), CELL_BAMBOO,
			cc, crad, 0.55 + 0.45 * t, rc, fold)

## Dead tree: bare trunk and branches with fine twig cards at the ends.
static func _tree_dead(sb: SurfaceTool, sl: SurfaceTool, rng: RandomNumberGenerator,
		rc: RandomNumberGenerator, q: Dictionary) -> void:
	var lod: int = q["lod"]
	var H := rng.randf_range(5.0, 8.5)
	var r0 := 0.20 + H * 0.02
	var path: Array = []
	var top := _tube(sb, Vector3.ZERO, Vector3.UP, H, r0, 0.07, q["ts"], 4 if lod == 0 else 2,
		Vector3(rng.randf_range(-0.45, 0.45), 0, rng.randf_range(-0.45, 0.45)), 0.0, 0.30, 0.5, 0.8,
		0.0, 0.40, path)
	var cc := Vector3(0, H * 0.72, 0)
	var crad := Vector3(2.6, 2.4, 2.6)
	var ends: Array = [[top, Vector3.UP]]
	for b in 6:
		var a := rng.randf() * TAU
		var bp := _path_at(path, rng.randf_range(0.42, 0.92))
		var dir := Vector3(cos(a) * 0.9, rng.randf_range(0.3, 0.9), sin(a) * 0.9).normalized()
		var L := rng.randf_range(1.5, 3.2)
		var e := _tube(sb, bp, dir, L, r0 * 0.34, 0.025, q["bs"], 2, Vector3(0, 0.3, 0), 0.3, 0.8, 0.7, 0.9,
			0.0, 0.0, [], lod == 0 or b < (3 if lod == 1 else 2))
		ends.append([e, dir])
		for j in 2:
			var sp := bp.lerp(e, rng.randf_range(0.4, 0.75))
			var a2 := a + rng.randf_range(-1.0, 1.0)
			var d2 := Vector3(cos(a2), rng.randf_range(0.3, 0.9), sin(a2)).normalized()
			var e2 := _tube(sb, sp, d2, L * 0.5, r0 * 0.14, 0.015, 3, 1, Vector3.ZERO, 0.5, 0.85, 0.8, 0.95,
				0.0, 0.0, [], lod == 0)
			ends.append([e2, d2])
	var per := 2 if lod == 0 else 1
	var step := 1 if lod == 0 else (2 if lod == 1 else 3)
	var idx := 0
	for en in ends:
		idx += 1
		if idx % step != 0 and idx > 1: continue
		var p: Vector3 = en[0]
		var dd: Vector3 = en[1]
		for k in per:
			var nn := (Vector3(dd.z, 0.2, -dd.x) + _rnd3(rc) * 0.8).normalized()
			_card(sl, p - dd * 0.25, nn, dd + _rnd3(rc) * 0.4, 1.35 * (1.0 if lod == 0 else 1.5),
				CELL_TWIG, cc, crad, 0.85, rc, 0.0, true)
