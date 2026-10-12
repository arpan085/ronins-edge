extends Node
## v0.16 techniques (技): the three skill paths from the design document, four
## techniques each, bought with mastery points. Mastery points were already
## earned (quests, shrines, hidden caches, hunting) but had nothing to buy; now
## kills and assassinations earn them too.
##
## Each path is a short trunk that forks: tier 0 -> tier 1 -> two tier-2
## techniques that both need tier 1. Every technique changes gameplay code
## (Player.gd, EnemyBase.gd, SpiritFox.gd, SmokeBomb.gd); none is cosmetic.

signal changed

const PATHS := ["bushido", "shinobi", "spirit"]
const PATH_INFO := {
	"bushido": {"name": "Bushido Path", "kanji": "武士道", "blurb": "The sword and the guard"},
	"shinobi": {"name": "Shinobi Arts", "kanji": "忍術", "blurb": "Unseen, unheard"},
	"spirit": {"name": "Spirit Bond", "kanji": "霊縁", "blurb": "Fox, blade and shadow"},
}
## slot: 0 = trunk top, 1 = trunk, 2 = left fork, 3 = right fork
const TREE := {
	"b_deflect": {"path": "bushido", "slot": 0, "cost": 1, "req": "", "name": "Steady Hand", "kanji": "心眼",
		"desc": "The perfect-deflect window is 20% longer."},
	"b_posture": {"path": "bushido", "slot": 1, "cost": 2, "req": "b_deflect", "name": "Unbroken", "kanji": "不動",
		"desc": "Your posture recovers 30% faster, and blocking costs 15% less posture."},
	"b_iai": {"path": "bushido", "slot": 2, "cost": 3, "req": "b_posture", "name": "Iaijutsu", "kanji": "居合",
		"desc": "A cut drawn straight from the sheath deals 1.8x damage and 2x posture."},
	"b_mikiri": {"path": "bushido", "slot": 3, "cost": 3, "req": "b_posture", "name": "Mikiri Counter", "kanji": "見切",
		"desc": "Dodge INTO a perilous thrust to pin the spear: a huge posture blow, then a riposte."},
	"s_silent": {"path": "shinobi", "slot": 0, "cost": 1, "req": "", "name": "Silent Step", "kanji": "忍足",
		"desc": "Enemies take 40% longer to notice you and hear you from half as far."},
	"s_assassin": {"path": "shinobi", "slot": 1, "cost": 2, "req": "s_silent", "name": "Assassination", "kanji": "暗殺",
		"desc": "Behind an enemy that has not seen you, or one blinded by smoke: interact to kill it in one stroke."},
	"s_smoke": {"path": "shinobi", "slot": 2, "cost": 3, "req": "s_assassin", "name": "Smoke Bomb", "kanji": "煙玉",
		"desc": "Throw smoke (3 per rest): enemies inside are blinded, the rest lose you."},
	"s_chain": {"path": "shinobi", "slot": 3, "cost": 3, "req": "s_assassin", "name": "Chain Assassination", "kanji": "連殺",
		"desc": "Right after an assassination, strike a second unaware enemy within 8 m."},
	"p_fox": {"path": "spirit", "slot": 0, "cost": 1, "req": "", "name": "Fox Spirit", "kanji": "霊狐",
		"desc": "A spirit fox joins your fights and every 16 s pounces on the enemy about to strike you."},
	"p_mend": {"path": "spirit", "slot": 1, "cost": 2, "req": "p_fox", "name": "Spirit Mending", "kanji": "癒魂",
		"desc": "Each perfect deflect heals 3 health and each kill heals 6."},
	"p_blade": {"path": "spirit", "slot": 2, "cost": 3, "req": "p_mend", "name": "Spirit Blade Mastery", "kanji": "霊刃",
		"desc": "Spirit Blade lasts 15 s, cuts through any guard and deals 50% more posture damage."},
	"p_step": {"path": "spirit", "slot": 3, "cost": 3, "req": "p_mend", "name": "Shadow Step", "kanji": "影歩",
		"desc": "Attack right after a perfect dodge to appear behind the attacker and strike (8 s cooldown)."},
}

var unlocked: Array[String] = []

func has(id: String) -> bool:
	return unlocked.has(id)

func ids_in(path: String) -> Array:
	var out := []
	for id in TREE.keys():
		if String(TREE[id]["path"]) == path: out.append(id)
	out.sort_custom(func(a, b): return int(TREE[a]["slot"]) < int(TREE[b]["slot"]))
	return out

## "owned" | "available" | "need_points" | "locked"
func state_of(id: String) -> String:
	if not TREE.has(id): return "locked"
	if has(id): return "owned"
	var req := String(TREE[id]["req"])
	if req != "" and not has(req): return "locked"
	if Game.mastery_points < int(TREE[id]["cost"]): return "need_points"
	return "available"

func can_unlock(id: String) -> bool:
	return state_of(id) == "available"

func unlock(id: String) -> bool:
	if not can_unlock(id): return false
	Game.mastery_points -= int(TREE[id]["cost"])
	unlocked.append(id)
	changed.emit()
	Game.emit_signal("state_changed")
	Game.notice.emit("Technique learned — %s" % String(TREE[id]["name"]), "quest")
	Audio.play_sfx("quest", null, 1.0, -2.0)
	return true

func total_cost() -> int:
	var n := 0
	for id in TREE.keys(): n += int(TREE[id]["cost"])
	return n

func serialize() -> Array:
	return unlocked.duplicate()

func deserialize(a) -> void:
	unlocked.clear()
	if typeof(a) != TYPE_ARRAY: return
	for v in a:
		var id := String(v)
		if TREE.has(id) and not unlocked.has(id): unlocked.append(id)
	# a save edited by hand (or from a future build) must not hold a technique
	# whose prerequisite is missing
	var again := true
	while again:
		again = false
		for id in unlocked.duplicate():
			var req := String(TREE[id]["req"])
			if req != "" and not unlocked.has(req):
				unlocked.erase(id); again = true
	changed.emit()

func reset() -> void:
	unlocked.clear()
	changed.emit()
