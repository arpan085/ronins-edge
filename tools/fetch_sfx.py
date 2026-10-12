#!/usr/bin/env python3
"""Fetch CC0 sound candidates from freesound.org search pages (no API key: the
public HQ mp3 previews). Writes /tmp/fs/<cat>/<id>.mp3 and /tmp/fs/meta.json."""
import re, json, os, subprocess, sys, urllib.parse, html
UA = "Mozilla/5.0"
CATS = {
 # cat: (query, n, min_dur, max_dur)
 "horse_gallop":  ("horse gallop dirt", 4, 3, 60),
 "horse_trot":    ("horse trot", 4, 3, 60),
 "horse_walk":    ("horse walking hooves", 4, 3, 60),
 "horse_neigh":   ("horse neigh", 5, 0.8, 6),
 "horse_snort":   ("horse snort", 5, 0.4, 4),
 "sword_draw":    ("sword unsheathe", 5, 0.3, 3),
 "sword_sheathe": ("sword sheathe", 4, 0.3, 3),
 "swoosh":        ("sword swoosh", 6, 0.15, 1.5),
 "clash":         ("sword clash", 6, 0.2, 3),
 "slash_hit":     ("sword stab flesh", 5, 0.15, 2),
 "birds":         ("birds forest morning", 3, 20, 240),
 "crickets":      ("crickets night", 3, 20, 240),
 "stream":        ("river stream water flowing", 3, 20, 240),
 "wind":          ("wind grass field", 3, 20, 240),
 "gong":          ("gong hit", 3, 1.5, 12),
 "taiko":         ("taiko drum hit", 4, 0.3, 4),
 "grunt":         ("male grunt effort", 6, 0.2, 1.5),
 "splash":        ("water splash footstep", 4, 0.2, 2),
 "bodyfall":      ("body fall ground", 4, 0.2, 2),
 "flesh":         ("sword slash flesh", 5, 0.1, 2),
 "punch":         ("punch body hit", 5, 0.1, 1.5),
 "taiko2":        ("taiko", 5, 0.3, 8),
 "kiai":          ("martial arts shout", 5, 0.2, 2),
 "rain":          ("rain loop", 2, 20, 200),
 "fire":          ("campfire crackling", 2, 15, 200),
 "arrow":         ("arrow hit wood", 3, 0.1, 1.5),
 "bow":           ("bow release arrow", 3, 0.2, 2),
 # v0.15 wildlife, hunting, map and night
 "deer_alarm":    ("deer bark", 6, 0.2, 6),
 "fox_bark":      ("fox bark", 6, 0.2, 6),
 "boar_grunt":    ("wild boar grunt", 6, 0.3, 8),
 "wolf_howl":     ("wolf howl", 6, 2, 25),
 "wolf_growl":    ("wolf growl", 6, 0.4, 6),
 "wolf_yelp":     ("dog yelp", 6, 0.15, 3),
 "harvest":       ("knife cutting meat", 5, 0.3, 6),
 "map_open":      ("paper map unfold", 5, 0.3, 4),
 "owl":           ("owl hoot", 6, 0.5, 12),
 "deer_call":     ("deer call", 6, 0.2, 6),
 "muntjac":       ("muntjac bark", 4, 0.2, 6),
 "roe_deer":      ("roe deer", 6, 0.2, 8),
 "fox_call":      ("fox call", 6, 0.2, 6),
 "red_fox":       ("red fox", 6, 0.2, 8),
 "pig_grunt":     ("pig grunt", 6, 0.3, 6),
 "hog":           ("pig snort", 6, 0.3, 6),
 "boar":          ("boar", 6, 0.3, 8),
 "dog_growl":     ("dog growl", 6, 0.4, 6),
 "snarl":         ("growl snarl", 6, 0.4, 6),
 "dog_whimper":   ("dog yelp pain", 6, 0.15, 3),
 "wolves":        ("wolves howling", 6, 3, 30),
 "paper":         ("paper rustle", 4, 0.3, 3),
}
def get(url):
    return subprocess.run(["curl", "-s", "-L", "--max-time", "30", "-A", UA, url], capture_output=True).stdout.decode("utf-8", "ignore")
meta = json.load(open("/tmp/fs/meta.json")) if os.path.exists("/tmp/fs/meta.json") else {}
only = sys.argv[1:]
for cat, (q, n, lo, hi) in CATS.items():
    if only and cat not in only: continue
    url = "https://freesound.org/search/?q=%s&f=%s&s=%s" % (urllib.parse.quote_plus(q),
          urllib.parse.quote('license:"Creative Commons 0"'), urllib.parse.quote_plus("Downloads (most first)"))
    s = get(url)
    res = []
    for blk in s.split('class="bw-search__result"')[1:]:
        m = re.search(r'data-sound-id="(\d+)"', blk); u = re.search(r'data-username="([^"]+)"', blk)
        mp3 = re.search(r'data-mp3="([^"]+)"', blk); d = re.search(r'data-duration="([\d.]+)"', blk)
        t = re.search(r'aria-label="Sound (.*?) by ', blk)
        if not (m and mp3 and d): continue
        res.append(dict(id=m.group(1), user=u.group(1) if u else "?", title=html.unescape(t.group(1)) if t else "?",
                        dur=float(d.group(1)), url=mp3.group(1).replace("-lq.mp3", "-hq.mp3")))
    os.makedirs("/tmp/fs/" + cat, exist_ok=True)
    got = []
    for r in res:
        if not (lo <= r["dur"] <= hi): continue
        out = "/tmp/fs/%s/%s.mp3" % (cat, r["id"])
        subprocess.run(["curl", "-s", "-L", "--max-time", "60", "-A", UA, "-o", out, r["url"]])
        if os.path.exists(out) and os.path.getsize(out) > 2000:
            got.append(r)
        if len(got) >= n: break
    meta[cat] = got
    print(cat, len(res), "results ->", [(g["id"], g["title"][:28], round(g["dur"], 1)) for g in got], flush=True)
json.dump(meta, open("/tmp/fs/meta.json", "w"), indent=1)
