#!/usr/bin/env python3
"""v0.15 sound sets (wildlife, hunting, map, night) from CC0 freesound previews
fetched by tools/fetch_sfx.py into /tmp/fs. Same treatment as build_audio.py:
trim, fade, peak-normalise, OGG; multi-call recordings are split into calls.
Writes game/assets/audio/sfx/<set>_<n>.ogg and prints the credit lines."""
import subprocess, numpy as np, os, json, glob
SR = 44100
OUT = "/data/ronins_edge/game/assets/audio/sfx"
FS = "/tmp/fs"
meta = json.load(open(FS + "/meta.json"))
info = {}
for cat, lst in meta.items():
    for g in lst: info[g["id"]] = (cat, g)

def path_of(i):
    for p in glob.glob("%s/*/%s.mp3" % (FS, i)): return p
    raise SystemExit("missing %s" % i)
def load(path, rate=1.0):
    af = [] if rate == 1.0 else ["-af", "asetrate=%d,aresample=%d" % (int(SR * rate), SR)]
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path] + af + ["-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
                         capture_output=True).stdout
    return np.frombuffer(raw, np.float32).copy()
def save(a, path, q=4):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ac", "1", "-ar", str(SR), "-i", "-",
                    "-c:a", "libvorbis", "-q:a", str(q), path], input=np.ascontiguousarray(a, np.float32).tobytes(), check=True)
def env(a, win=0.01):
    w = max(1, int(win * SR))
    return np.convolve(np.abs(a), np.ones(w) / w, "same")
def trim(a, thr=0.03, pre=0.006, post=0.06):
    e = env(a, 0.004)
    idx = np.where(e > thr * e.max())[0]
    if len(idx) == 0: return a
    return a[max(0, idx[0] - int(pre * SR)): min(len(a), idx[-1] + int(post * SR))]
def fade(a, fin=0.004, fout=0.08):
    a = a.copy(); n = len(a)
    i = min(n, int(fin * SR)); o = min(n, int(fout * SR))
    a[:i] *= np.linspace(0, 1, i); a[n - o:] *= np.linspace(1, 0, o)
    return a
def peak(a, db=-1.0):
    m = np.abs(a).max()
    return a * (10 ** (db / 20) / m) if m > 0 else a
def highpass(a, fc=60.0):
    k = np.exp(-2 * np.pi * fc / SR)
    y = np.empty_like(a); prev_x = 0.0; prev_y = 0.0
    for i in range(len(a)):
        prev_y = k * (prev_y + a[i] - prev_x); prev_x = a[i]; y[i] = prev_y
    return y
def calls(a, thr=0.08, gap=0.10, min_len=0.12):
    """split a recording of several calls at the quiet gaps between them"""
    e = env(a, 0.01); on = e > thr * e.max()
    segs = []; i = 0; n = len(a)
    while i < n:
        if not on[i]: i += 1; continue
        s = i; quiet = 0
        while i < n and quiet < int(gap * SR):
            quiet = quiet + 1 if not on[i] else 0
            i += 1
        e_ = i - quiet
        if e_ - s > min_len * SR: segs.append(a[max(0, s - int(0.01 * SR)): min(n, e_ + int(0.05 * SR))])
    return segs
used = []
def make(name, items, maxlen=None, db=-1.0, fout=0.08, split=False, max_n=6):
    for f in glob.glob("%s/%s_*.ogg*" % (OUT, name)): os.remove(f)
    n = 0
    for it in items:
        t = list(it) if isinstance(it, tuple) else [it]
        t += [None] * (4 - len(t))
        i, rate, s0, s1 = t[0], (t[1] or 1.0), t[2], t[3]
        a = load(path_of(i), rate)
        if s0 is not None: a = a[int(s0 * SR): int(s1 * SR)]
        a = highpass(a, 50.0)
        parts = calls(a) if split else [trim(a)]
        for p in parts:
            if n >= max_n: break
            if maxlen: p = p[: int(maxlen * SR)]
            p = peak(fade(trim(p), 0.004, fout), db)
            n += 1
            save(p, "%s/%s_%d.ogg" % (OUT, name, n))
        if i not in used: used.append(i)
    print("set %-12s %d variants" % (name, n))

make("deer_alarm", ["696776", ("696776", 0.9)], maxlen=1.2)
make("fox_bark", ["173208", ("173208", 1.08)], split=True, max_n=4, maxlen=0.9)
make("boar_grunt", [("442907", 0.85), ("233183", 0.82), ("233182", 0.85), ("233181", 0.8, 0.0, 1.7)], maxlen=1.7)
make("boar_squeal", [("233177", 0.88), ("233176", 0.88), ("233175", 0.9)], maxlen=1.6)
make("wolf_howl", ["398430", "378334", "753896"], maxlen=8.0, fout=0.8, db=-1.5)
make("wolf_growl", [("342204", 1.0, 0.0, 1.9), "13789"], maxlen=1.9, fout=0.15)
make("wolf_yelp", [("735365", 0.82), ("735365", 0.92)], maxlen=0.9)
make("harvest", [("472501", 1.0, 0.0, 1.5), "429225"], maxlen=1.3, db=-2.0)
make("map_open", ["447931", "211246"], maxlen=1.3, db=-2.0)
make("owl", ["465697", "398734", "558396", "558397", "558398"], maxlen=5.0, fout=0.4, db=-2.0)
print("CREDITS")
for i in used:
    cat, g = info[i]
    print("- \"%s\" by %s — freesound.org/s/%s (CC0)" % (g["title"], g["user"], i))
