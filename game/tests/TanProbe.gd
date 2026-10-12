extends Node
## Does the imported character mesh have tangents?
##
## glTF stores TANGENT as an optional attribute and the Blender exporter only
## writes it in some configurations; without it a normal map is a no-op no
## matter how good the texture is. Guessing is not evidence.

func _ready() -> void:
	for path: String in ["res://assets/models/Kaito_Ronin.glb",
			"res://assets/props/farmhouse.glb"]:
		if not ResourceLoader.exists(path):
			print("TAN missing ", path)
			continue
		var scn: PackedScene = load(path)
		var root: Node = scn.instantiate()
		for mi: MeshInstance3D in _meshes(root):
			var mesh: Mesh = mi.mesh
			if mesh == null: continue
			for i: int in mesh.get_surface_count():
				var fmt: int = mesh.surface_get_format(i)
				var tan: bool = (fmt & Mesh.ARRAY_FORMAT_TANGENT) != 0
				var uv: bool = (fmt & Mesh.ARRAY_FORMAT_TEX_UV) != 0
				var m := mesh.surface_get_material(i)
				var nm := "?"
				var has_n := false
				if m is StandardMaterial3D:
					nm = m.resource_name
					has_n = (m as StandardMaterial3D).normal_texture != null
				print("TAN %s surf=%d tangent=%s uv=%s mat=%s normal_tex=%s"
					% [path.get_file(), i, tan, uv, nm, has_n])
		root.free()
	print("TAN_DONE")
	get_tree().quit()

func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D: out.append(n)
	for c: Node in n.get_children(): out.append_array(_meshes(c))
	return out
