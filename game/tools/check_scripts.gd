extends SceneTree
## Loads every GDScript in the project so parse / type errors surface in the log.
var _done := false

## Runs on the first frame: autoload singletons (Game, Audio...) only exist
## once the main loop has started, so checking from _init reports false errors.
func _process(_delta: float) -> bool:
	if _done: return true
	_done = true
	var bad := 0
	var n := 0
	for p in _walk("res://"):
		if p.begins_with("res://addons") or p.begins_with("res://.godot"): continue
		n += 1
		var s = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REUSE)
		if s == null or not (s is GDScript) or not s.can_instantiate():
			bad += 1
			print("SCRIPT_FAIL ", p)
	print("SCRIPTS_CHECKED %d failed %d" % [n, bad])
	quit(0 if bad == 0 else 1)
	return false

func _walk(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null: return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.begins_with("."):
			f = d.get_next(); continue
		var full := dir.path_join(f)
		if d.current_is_dir(): out.append_array(_walk(full))
		elif f.ends_with(".gd"): out.append(full)
		f = d.get_next()
	return out
