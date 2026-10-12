"""Quest 'reach'/'interact' targets were still at the old 480 m world's
coordinates (v6), so e.g. the village well objective pointed at empty
mountainside. Place real props for them inside the 1536 m world and print the
positions for World.gd. Idempotent: skips props already tagged 'quest'."""
import json, math, struct, sys
import numpy as np
ROOT = sys.argv[1] if len(sys.argv) > 1 else "/data/ronins_edge/game"
W = json.load(open(f"{ROOT}/assets/terrain/world.json"))
N, CELL, WL = W["n"], W["cell"], W["water_level"]
H = np.fromfile(f"{ROOT}/assets/terrain/heightmap.bin", dtype="<f4").reshape(N, N)

def h(x, z):
    gx, gz = x / CELL, z / CELL
    x0, z0 = int(gx), int(gz); fx, fz = gx - x0, gz - z0
    x0 = min(max(x0, 0), N - 2); z0 = min(max(z0, 0), N - 2)
    a = H[z0, x0] * (1 - fx) + H[z0, x0 + 1] * fx
    b = H[z0 + 1, x0] * (1 - fx) + H[z0 + 1, x0 + 1] * fx
    return float(a * (1 - fz) + b * fz)

def rough(x, z, r):
    hs = [h(x + dx, z + dz) for dx in (-r, 0, r) for dz in (-r, 0, r)]
    return max(hs) - min(hs)

BIG = {"house": 9.0, "stall": 6.0, "wall": 7.0, "fence": 4.0, "watchtower": 7.0, "castle_gate": 14.0,
       "castle_keep": 22.0, "shrine_hall": 14.0, "torii": 5.0, "bridge": 8.0, "well": 4.0, "lantern": 2.0}
def clear(x, z, pad):
    for p in W["props"] + W["landmarks"]:
        r = BIG.get(p["kind"], 1.2 if p["kind"] in ("rock",) else 0.0)
        if r and math.hypot(p["x"] - x, p["z"] - z) < r + pad: return False
    for t in W.get("trees", []):
        if math.hypot(t["x"] - x, t["z"] - z) < pad + 1.0: return False
    for pts in W.get("roads", {}).values():
        for q in pts:
            if math.hypot(q[0] - x, q[1] - z) < pad * 0.5 + 2.0: return False
    return True

def find(cx, cz, r0, r1, pad, max_rough):
    for r in range(r0, r1):
        for a in range(0, 360, 8):
            x = cx + r * math.cos(math.radians(a)); z = cz + r * math.sin(math.radians(a))
            if h(x, z) < WL + 0.8: continue
            if rough(x, z, 2.5) > max_rough: continue
            if clear(x, z, pad): return round(x, 1), round(z, 1)
    raise SystemExit(f"no spot near {cx},{cz}")

if any(p.get("quest") for p in W["props"]):
    print("already placed:", [(p["kind"], p["x"], p["z"]) for p in W["props"] if p.get("quest")]); sys.exit(0)
Z = {k: (v["x"], v["z"]) for k, v in W["zones"].items()}
out = {}
x, z = find(*Z["village"], 8, 40, 3.0, 0.6)
W["props"].append({"kind": "well", "x": x, "z": z, "y": round(h(x, z) - 0.05, 2), "rot": 0, "s": 1.0, "quest": "well"}); out["well"] = (x, z)
x, z = find(*Z["mountain"], 12, 70, 3.0, 1.4)
W["props"].append({"kind": "watchtower", "x": x, "z": z, "y": round(h(x, z) - 0.2, 2), "rot": 20, "s": 1.0, "quest": "watchtower"}); out["watchtower"] = (x, z)
x, z = find(*Z["forest"], 6, 40, 2.5, 0.9)
ang = math.atan2(Z["forest"][1] - z, Z["forest"][0] - x)
for side in (-1, 1):
    lx = x + math.cos(ang + math.pi / 2) * 1.8 * side; lz = z + math.sin(ang + math.pi / 2) * 1.8 * side
    W["props"].append({"kind": "lantern", "x": round(lx, 1), "z": round(lz, 1), "y": round(h(lx, lz) - 0.05, 2), "rot": math.degrees(-ang), "s": 1.0, "quest": "forest_marker"})
out["forest_marker"] = (x, z)
json.dump(W, open(f"{ROOT}/assets/terrain/world.json", "w"), separators=(",", ":"))
print(json.dumps(out))
