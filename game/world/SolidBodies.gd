class_name SolidBodies
extends Node3D
## Collision for props, landmarks and trees.
##
## Everything in the world except the terrain and one castle keep was drawn with
## MultiMesh, which carries no collision at all, so the player walked straight
## through every house, wall, torii, boulder and tree in the game.
##
## Two strategies, because the counts are wildly different:
##  * Structures (houses, walls, gates, towers, bridges: ~150 items) get
##    permanent shapes. They are few and always matter.
##  * Boulders and trees (~15 000 items) stream. A fixed pool of shapes is
##    recycled onto whatever is near the player, refreshed when the player
##    moves far enough. Collision is never reduced by the quality preset --
##    walking through a tree is a bug, not a graphics setting.
##
## All shapes of a strategy hang off a single StaticBody3D. Godot's broadphase
## indexes bodies per shape, so one body with many shapes is cheaper than many
## bodies and keeps the scene tree small.

const BUCKET := 48.0        # spatial hash cell for streamed items
const RADIUS := 46.0        # stream in anything this close to the player
const POOL := 320          # recycled shape slots
const REFRESH := 6.0        # re-stream after the player moves this far

## kind -> list of shapes. `box` uses size, `cyl` uses radius/height, `o` is the
## local offset from the prop origin (before the prop's own Y rotation).
## Sizes come from the real GLB bounds, measured not guessed. Torii and the
## castle gate are deliberately split into flanks so you can still walk through
## the opening.
const STRUCTURES := {
	# Rebuilt minka: 5.6 x 4.4 walls on a 0.26 pad, 2.55 m to the eave, roof
	# ridge at 4.86. The body box stops at the eave so the roof overhang stays
	# walk-under, and a second box covers the veranda deck.
	"house": [
		{"t": "box", "s": Vector3(5.8, 2.85, 4.6), "o": Vector3(0, 1.43, 0)},
		{"t": "box", "s": Vector3(5.9, 0.50, 1.2), "o": Vector3(0, 0.30, 2.75)},
	],
	"wall": [{"t": "box", "s": Vector3(4.1, 2.5, 0.9), "o": Vector3(0, 1.25, 0)}],
	"fence": [{"t": "box", "s": Vector3(3.2, 1.3, 0.3), "o": Vector3(0, 0.65, 0)}],
	"stall": [{"t": "box", "s": Vector3(3.6, 2.4, 2.9), "o": Vector3(0, 1.20, 0)}],
	"watchtower": [{"t": "box", "s": Vector3(4.2, 7.6, 4.2), "o": Vector3(0, 3.80, 0)}],
	"shrine_hall": [{"t": "box", "s": Vector3(10.4, 6.1, 8.2), "o": Vector3(0, 3.05, 0)}],
	"castle_keep": [{"t": "box", "s": Vector3(15.0, 18.0, 13.0), "o": Vector3(0, 9.0, 0)}],
	"well": [{"t": "cyl", "r": 1.25, "h": 1.1, "o": Vector3(0, 0.55, 0)}],
	"lantern": [{"t": "cyl", "r": 0.30, "h": 1.4, "o": Vector3(0, 0.70, 0)}],
	# Small stuff you can walk into. A crate you can walk through is as
	# obviously wrong as a house you can walk through; there are only a
	# couple of dozen of these, so they get permanent shapes.
	"crate": [{"t": "box", "s": Vector3(0.80, 0.80, 0.80), "o": Vector3(0, 0.40, 0)}],
	"barrel": [{"t": "cyl", "r": 0.36, "h": 0.90, "o": Vector3(0, 0.45, 0)}],
	"basket": [{"t": "cyl", "r": 0.32, "h": 0.46, "o": Vector3(0, 0.23, 0)}],
	# Rebuilt torii: pillars at +/-2.90 at the base, leaning 1.9 degrees in,
	# 6.2 m tall. The opening between them stays walkable.
	"torii": [
		{"t": "cyl", "r": 0.34, "h": 6.2, "o": Vector3(-2.80, 3.10, 0)},
		{"t": "cyl", "r": 0.34, "h": 6.2, "o": Vector3(2.80, 3.10, 0)},
	],
	"castle_gate": [
		{"t": "box", "s": Vector3(3.6, 7.2, 4.4), "o": Vector3(-3.70, 3.60, 0)},
		{"t": "box", "s": Vector3(3.6, 7.2, 4.4), "o": Vector3(3.70, 3.60, 0)},
	],
	"bridge": [
		{"t": "box", "s": Vector3(10.0, 0.4, 3.2), "o": Vector3(0, 0.30, 0)},
		{"t": "box", "s": Vector3(10.0, 0.9, 0.2), "o": Vector3(0, 0.95, -1.55)},
		{"t": "box", "s": Vector3(10.0, 0.9, 0.2), "o": Vector3(0, 0.95, 1.55)},
	],
}

## Trunk radius per tree family. Crowns stay walk-through on purpose: clipping a
## branch reads as foliage, clipping a trunk reads as a bug.
const TRUNK := {
	"pine": 0.30, "cedar": 0.36, "sakura": 0.28, "maple": 0.28,
	"oak": 0.26, "bamboo": 0.11, "birch": 0.24,
}
const TRUNK_H := 3.4

var terrain: Terrain
var player: Node3D

var structures := 0
var streamed_items := 0
var active := 0

var _static_body: StaticBody3D
var _stream_body: StaticBody3D
var _pool: Array[CollisionShape3D] = []
var _grid := {}
var _last := Vector3(1.0e9, 0.0, 0.0)
var _primed := false

func setup(t: Terrain) -> void:
	terrain = t
	_static_body = StaticBody3D.new()
	_static_body.name = "Structures"
	_static_body.collision_layer = 1
	_static_body.collision_mask = 0
	add_child(_static_body)
	_stream_body = StaticBody3D.new()
	_stream_body.name = "Streamed"
	_stream_body.collision_layer = 1
	_stream_body.collision_mask = 0
	add_child(_stream_body)
	for i in POOL:
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.3
		cyl.height = 1.0
		cs.shape = cyl
		cs.disabled = true
		_stream_body.add_child(cs)
		_pool.append(cs)

# ------------------------------------------------------------- structures
func add_structures(props: Array, landmarks: Array) -> void:
	for p in props: _structure(String(p.get("kind", "")), p)
	for lm in landmarks: _structure(String(lm.get("kind", "")), lm)

func _structure(kind: String, p: Dictionary) -> void:
	if not STRUCTURES.has(kind): return
	var x := float(p.get("x", 0.0))
	var z := float(p.get("z", 0.0))
	var y := float(p.get("y", 0.0))
	if terrain != null and terrain.loaded: y = terrain.sample_height(x, z)
	var s := float(p.get("s", 1.0))
	var basis := Basis(Vector3.UP, deg_to_rad(float(p.get("rot", 0.0))))
	for d in STRUCTURES[kind]:
		var cs := CollisionShape3D.new()
		if String(d["t"]) == "box":
			var b := BoxShape3D.new()
			b.size = (d["s"] as Vector3) * s
			cs.shape = b
		else:
			var c := CylinderShape3D.new()
			c.radius = float(d["r"]) * s
			c.height = float(d["h"]) * s
			cs.shape = c
		var off: Vector3 = basis * ((d["o"] as Vector3) * s)
		cs.transform = Transform3D(basis, Vector3(x, y, z) + off)
		_static_body.add_child(cs)
		structures += 1

# ---------------------------------------------------------------- streamed
func add_trees(trees: Array) -> void:
	for tr in trees:
		var fam := String(tr.get("kind", "pine"))
		var r: float = float(TRUNK.get(fam, 0.28))
		var s := float(tr.get("s", 1.0))
		_insert(Vector3(float(tr.get("x", 0.0)), 0.0, float(tr.get("z", 0.0))),
			r * s, TRUNK_H * s, TRUNK_H * s * 0.5)

## Ground debris. Sizes are taken from the generators in MeshLib, not guessed:
## stone() reaches 0.50 m out and 0.36 m up, log_mesh() is a 3 m trunk of
## radius 0.24 lying on its side at y 0.22, stump() is a 0.55 m bole of radius
## 0.36. Branches, ferns, flowers and mushrooms stay walk-through -- being
## stopped by a twig is worse than clipping one.
const DEBRIS := {
	"rock":        {"r": 0.85, "h": 1.30, "y": 0.50},
	"stone_small": {"r": 0.46, "h": 0.42, "y": 0.18},
	"log":         {"r": 0.30, "h": 0.52, "y": 0.24},
	"stump":       {"r": 0.38, "h": 0.60, "y": 0.28},
}

func add_boulders(props: Array) -> void:
	for p in props:
		var k := String(p.get("kind", ""))
		if not DEBRIS.has(k): continue
		var d: Dictionary = DEBRIS[k]
		var s := float(p.get("s", 1.0))
		_insert(Vector3(float(p.get("x", 0.0)), 0.0, float(p.get("z", 0.0))),
			float(d["r"]) * s, float(d["h"]) * s, float(d["y"]) * s)

func _insert(pos: Vector3, r: float, h: float, yoff: float) -> void:
	var key := Vector2i(int(floor(pos.x / BUCKET)), int(floor(pos.z / BUCKET)))
	if not _grid.has(key): _grid[key] = []
	_grid[key].append({"p": pos, "r": r, "h": h, "y": yoff})
	streamed_items += 1

# ------------------------------------------------------------------ stream
func _physics_process(_delta: float) -> void:
	if player == null or _grid.is_empty(): return
	var p: Vector3 = player.global_position
	if _primed and p.distance_to(_last) < REFRESH: return
	_last = p
	_primed = true
	_restream(p)

## Fill the pool with the nearest items. Nearest, not first-found: if a bamboo
## grove overflows the pool we want the ones you are about to touch, not an
## arbitrary slice of the bucket.
func _restream(p: Vector3) -> void:
	var near: Array = []
	var bx := int(floor(p.x / BUCKET))
	var bz := int(floor(p.z / BUCKET))
	var r2 := RADIUS * RADIUS
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var list = _grid.get(Vector2i(bx + dx, bz + dz), null)
			if list == null: continue
			for it in list:
				var d := Vector2(it["p"].x - p.x, it["p"].z - p.z).length_squared()
				if d <= r2: near.append([d, it])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var n: int = mini(near.size(), POOL)
	for i in n:
		var it: Dictionary = near[i][1]
		var cs: CollisionShape3D = _pool[i]
		var cyl: CylinderShape3D = cs.shape
		cyl.radius = float(it["r"])
		cyl.height = float(it["h"])
		var gy: float = terrain.sample_height(it["p"].x, it["p"].z) if terrain != null and terrain.loaded else 0.0
		cs.position = Vector3(it["p"].x, gy + float(it["y"]), it["p"].z)
		cs.disabled = false
	for i in range(n, POOL):
		if not _pool[i].disabled: _pool[i].disabled = true
	active = n

## Force a refresh, e.g. right after a warp, so the player never lands a frame
## before the nearby trunks exist.
func prime(p: Vector3) -> void:
	_last = p
	_primed = true
	_restream(p)
