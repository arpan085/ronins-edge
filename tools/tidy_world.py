"""v0.14: clean up what the world generator scattered in the wrong places.

  * trees growing through buildings, walls, the castle gate, torii, lanterns
  * trees standing on the road centre lines
  * a forest inside the castle walls (150 trees, logs, rocks and branches in
    the bailey): keep a few ornamental pines and cherries, clear the rest
  * rocks, logs and branches inside buildings or lying on the roads

Only removes entries from assets/terrain/world.json, so it is safe to run
again. Nothing in the game refers to trees or props by index.
"""
import json, math, sys
import numpy as np

PATH = "/data/ronins_edge/game/assets/terrain/world.json"
if len(sys.argv) > 1: PATH = sys.argv[1]
d = json.load(open(PATH))

# footprint radius (m, before the prop's own scale) of each structure kind
RAD = {"house": 4.6, "stall": 2.6, "watchtower": 3.2, "shrine_hall": 7.0, "castle_gate": 6.5,
       "torii": 4.0, "well": 1.5, "bridge": 6.0, "wall": 2.4, "fence": 1.8, "lantern": 0.8,
       "castle_keep": 16.0}
DEBRIS = ("rock", "log", "branch", "stone_small", "stump", "mushroom", "flower")
structs = [(float(p["x"]), float(p["z"]), RAD[p["kind"]] * float(p.get("s", 1.0)))
           for p in d["props"] + d["landmarks"] if p["kind"] in RAD]
SX = np.array([s[0] for s in structs]); SZ = np.array([s[1] for s in structs]); SR = np.array([s[2] for s in structs])

segs = []
for pl in d.get("roads", {}).values():
    for a, b in zip(pl[:-1], pl[1:]): segs.append((a, b))
A = np.array([s[0] for s in segs], float); B = np.array([s[1] for s in segs], float)
AB = B - A; L2 = np.maximum((AB * AB).sum(1), 1e-6)

def road_dist(x, z):
    p = np.array([x, z]); t = np.clip(((p - A) * AB).sum(1) / L2, 0, 1)
    q = A + AB * t[:, None]
    return float(np.min(np.linalg.norm(q - p, axis=1)))

def in_struct(x, z, pad):
    return bool(np.any(np.hypot(SX - x, SZ - z) < SR + pad))

cz = d["zones"]["castle"]
CX, CZ = float(cz["x"]), float(cz["z"])
BAILEY = 72.0

trees_out, removed = [], {"struct": 0, "road": 0, "bailey": 0}
for t in d["trees"]:
    x, z = float(t["x"]), float(t["z"])
    if in_struct(x, z, 1.5): removed["struct"] += 1; continue
    if road_dist(x, z) < 3.2: removed["road"] += 1; continue
    r = math.hypot(x - CX, z - CZ)
    if r < BAILEY:
        k = t.get("kind", "")
        # one in three, chosen by position so a second run keeps the same ones
        ok = r > 30.0 and k in ("pine", "sakura") and int(abs(x * 7.0 + z * 13.0)) % 3 == 0
        if not ok: removed["bailey"] += 1; continue
    trees_out.append(t)

# the keep, the shrine hall and the first torii were listed both as props
# and as landmarks: two copies of each, and the prop copy never switched LOD,
# so at range the two meshes z-fought
lm_at = [(l["kind"], float(l["x"]), float(l["z"])) for l in d["landmarks"]]
props_out, prem = [], {"struct": 0, "road": 0, "bailey": 0, "dup": 0}
for p in d["props"]:
    if any(k == p["kind"] and abs(x - float(p["x"])) < 1.0 and abs(z - float(p["z"])) < 1.0 for k, x, z in lm_at):
        prem["dup"] += 1; continue
    if p["kind"] in DEBRIS:
        x, z = float(p["x"]), float(p["z"])
        if in_struct(x, z, 0.5): prem["struct"] += 1; continue
        if road_dist(x, z) < 2.2: prem["road"] += 1; continue
        if math.hypot(x - CX, z - CZ) < BAILEY: prem["bailey"] += 1; continue
    props_out.append(p)

print("trees", len(d["trees"]), "->", len(trees_out), removed)
print("props", len(d["props"]), "->", len(props_out), prem)
d["trees"] = trees_out
d["props"] = props_out
d["tidy"] = 1
json.dump(d, open(PATH, "w"), separators=(",", ":"))
