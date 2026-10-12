extends SceneTree
## Prints triangle counts per tree family / LOD (dev tool).
## godot --headless --path . -s tools/tree_tris.gd
func _init() -> void:
	for fam in ["pine", "cedar", "maple", "sakura", "bamboo", "young_tree", "dead_tree"]:
		var line: String = str(fam) + ":"
		for lod in 3:
			var m: ArrayMesh = MeshLib.tree(fam, lod, 5)
			var parts := []
			for s in m.get_surface_count():
				var a := m.surface_get_arrays(s)
				var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var n: int = idx.size() / 3 if idx.size() > 0 else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
				parts.append(n)
			line += "  L%d=%s" % [lod, str(parts)]
		print(line)
	quit()
