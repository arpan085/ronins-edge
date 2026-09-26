extends Node
## Quest definitions and runtime tracking.

signal quest_started(id: String)
signal quest_updated(id: String)
signal quest_completed(id: String)
signal objective_toast(text: String)

const DEFS := {
	"ronin": {
		"title": "Path of the Ronin", "zone": "shrine",
		"desc": "Learn the way of the blade at the shrine.",
		"objectives": [
			{"id": "deflect", "text": "Land 3 perfect deflects", "type": "deflect", "target": "", "count": 3},
			{"id": "kill3", "text": "Defeat 3 enemies", "type": "kill", "target": "", "count": 3},
		],
		"reward": {"xp": 3, "text": "Unlock: Water stance mastery"}
	},
	"forest": {
		"title": "Clear the Forest", "zone": "forest",
		"desc": "Bandits hold the bamboo groves.",
		"objectives": [
			{"id": "kill5", "text": "Defeat 5 bandits in the forest", "type": "kill", "target": "forest", "count": 5},
			{"id": "reach", "text": "Reach the forest shrine marker", "type": "reach", "target": "forest_marker", "count": 1},
		],
		"reward": {"xp": 4, "text": "Reward: Wind stance scroll"}
	},
	"village": {
		"title": "Village Defense", "zone": "village",
		"desc": "Raiders are burning the village.",
		"objectives": [
			{"id": "kill4", "text": "Defeat 4 raiders", "type": "kill", "target": "village", "count": 4},
			{"id": "well", "text": "Inspect the village well", "type": "interact", "target": "well", "count": 1},
		],
		"reward": {"xp": 4, "text": "Reward: village supplies (heal)"}
	},
	"castle": {
		"title": "Storm the Castle", "zone": "castle",
		"desc": "Push through the ruined gate.",
		"objectives": [
			{"id": "gate", "text": "Reach the castle gate", "type": "reach", "target": "castle_gate", "count": 1},
			{"id": "kill6", "text": "Defeat 6 defenders", "type": "kill", "target": "castle", "count": 6},
		],
		"reward": {"xp": 5, "text": "Reward: Moon stance scroll"}
	},
	"mountain": {
		"title": "Mountain Crossing", "zone": "mountain",
		"desc": "Cross the pass before nightfall.",
		"objectives": [
			{"id": "reach", "text": "Reach the watchtower", "type": "reach", "target": "watchtower", "count": 1},
			{"id": "kill3", "text": "Defeat 3 archers on the pass", "type": "kill", "target": "mountain", "count": 3},
		],
		"reward": {"xp": 5, "text": "Reward: Spirit Blade technique"}
	},
	"duel": {
		"title": "The Final Duel", "zone": "castle",
		"desc": "The Captain of the ruins waits for you.",
		"objectives": [
			{"id": "boss", "text": "Break the Captain's posture and land the Deathblow", "type": "boss", "target": "captain", "count": 1},
		],
		"reward": {"xp": 10, "text": "Reward: Ronin's Edge complete"}
	},
}
const ORDER := ["ronin", "forest", "village", "castle", "mountain", "duel"]

var active := {}
var done := {}
var order_index := 0

func reset_all() -> void:
	active = {}; done = {}; order_index = 0

func serialize() -> Dictionary:
	return {"active": active, "done": done, "order": order_index}

func deserialize(d: Dictionary) -> void:
	active = d.get("active", {})
	done = d.get("done", {})
	order_index = int(d.get("order", 0))

func start(id: String) -> bool:
	if done.has(id) or active.has(id) or not DEFS.has(id): return false
	var def: Dictionary = DEFS[id]
	var objs := {}
	for o in def["objectives"]:
		objs[o["id"]] = 0
	active[id] = {"progress": objs}
	quest_started.emit(id)
	objective_toast.emit("Quest: %s" % def["title"])
	return true

func start_next() -> String:
	while order_index < ORDER.size():
		var id: String = ORDER[order_index]
		order_index += 1
		if not done.has(id):
			start(id)
			return id
	return ""

func current_id() -> String:
	for id in ORDER:
		if active.has(id): return id
	return ""

func current_title() -> String:
	var id := current_id()
	return DEFS[id]["title"] if id != "" else "Free roam"

func current_objective_text() -> String:
	var id := current_id()
	if id == "": return "Explore the land"
	var def: Dictionary = DEFS[id]
	var prog: Dictionary = active[id]["progress"]
	for o in def["objectives"]:
		if int(prog.get(o["id"], 0)) < int(o["count"]):
			return "%s  (%d/%d)" % [o["text"], int(prog.get(o["id"], 0)), int(o["count"])]
	return "Return to %s" % def["title"]

func objectives(id: String) -> Array:
	var out := []
	if not DEFS.has(id): return out
	var prog: Dictionary = active.get(id, {}).get("progress", {})
	for o in DEFS[id]["objectives"]:
		out.append({"text": o["text"], "done": int(prog.get(o["id"], 0)) >= int(o["count"]),
			"cur": int(prog.get(o["id"], 0)), "max": int(o["count"])})
	return out

## type: "kill" | "deflect" | "reach" | "interact" | "boss"; ctx: zone name or target id
func progress(type: String, ctx: String = "", amount: int = 1) -> void:
	for id in active.keys():
		var def: Dictionary = DEFS[id]
		var prog: Dictionary = active[id]["progress"]
		var changed := false
		for o in def["objectives"]:
			if o["type"] != type: continue
			var tgt: String = o["target"]
			if tgt != "" and tgt != ctx: continue
			if int(prog.get(o["id"], 0)) >= int(o["count"]): continue
			prog[o["id"]] = int(prog.get(o["id"], 0)) + amount
			changed = true
			objective_toast.emit(o["text"])
		if changed:
			quest_updated.emit(id)
			_check_complete(id)

func _check_complete(id: String) -> void:
	var def: Dictionary = DEFS[id]
	var prog: Dictionary = active[id]["progress"]
	for o in def["objectives"]:
		if int(prog.get(o["id"], 0)) < int(o["count"]): return
	active.erase(id)
	done[id] = true
	var reward: Dictionary = def["reward"]
	Game.add_xp(int(reward.get("xp", 1)))
	quest_completed.emit(id)
	objective_toast.emit("Complete: %s" % def["title"])
	Game.notice.emit("%s — %s" % [def["title"], String(reward.get("text", ""))], "quest")
