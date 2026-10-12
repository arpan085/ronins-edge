#!/usr/bin/env python3
"""Ronin's Edge audio build: CC0 recordings (freesound previews, Kenney packs,
OpenGameArt music) -> trimmed, normalised OGG in game/assets/audio/.
Inputs: /tmp/fs (tools/fetch_sfx.py), /tmp/kn (Kenney zips), /tmp/oga (music)."""
import subprocess, numpy as np, os, json, glob, shutil
SR = 44100
OUT = "/data/ronins_edge/game/assets/audio"
FS, KN, OGA = "/tmp/fs", "/tmp/kn", "/tmp/oga"
os.makedirs(OUT + "/sfx", exist_ok=True); os.makedirs(OUT + "/amb", exist_ok=True); os.makedirs(OUT + "/music", exist_ok=True)
credits = []
def fsf(cat, i): return "%s/%s/%s.mp3" % (FS, cat, i)
def kn(pat): return sorted(glob.glob(KN + "/**/" + pat, recursive=True))
def load(path, ch=1):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", str(ch), "-ar", str(SR), "-"], capture_output=True).stdout
    a = np.frombuffer(raw, np.float32).copy()
    return a if ch == 1 else a.reshape(-1, ch)
def save(a, path, q=4):
    ch = 1 if a.ndim == 1 else a.shape[1]
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ac", str(ch), "-ar", str(SR), "-i", "-",
                    "-c:a", "libvorbis", "-q:a", str(q), path], input=np.ascontiguousarray(a, np.float32).tobytes(), check=True)
def trim(a, thr=0.02, pre=0.004, post=0.03):
    m = np.abs(a) if a.ndim == 1 else np.abs(a).max(1)
    idx = np.where(m > thr * m.max())[0]
    if len(idx) == 0: return a
    s = max(0, idx[0] - int(pre * SR)); e = min(len(a), idx[-1] + int(post * SR))
    return a[s:e]
def fade(a, fin=0.003, fout=0.04):
    a = a.copy(); n = len(a)
    i = min(n, int(fin * SR)); o = min(n, int(fout * SR))
    ramp_in = np.linspace(0, 1, i); ramp_out = np.linspace(1, 0, o)
    if a.ndim == 1: a[:i] *= ramp_in; a[n - o:] *= ramp_out
    else: a[:i] *= ramp_in[:, None]; a[n - o:] *= ramp_out[:, None]
    return a
def peak(a, db=-1.0):
    m = np.abs(a).max()
    return a * (10 ** (db / 20) / m) if m > 0 else a
def lowpass(a, fc):
    # one-pole, twice
    k = np.exp(-2 * np.pi * fc / SR); y = a.copy()
    for _ in range(2):
        out = np.empty_like(y); acc = 0.0
        for i in range(len(y)):
            acc = (1 - k) * y[i] + k * acc; out[i] = acc
        y = out
    return y
def sfx(name, sources, cut=None, maxlen=None, db=-1.0, fout=0.05, thr=0.02):
    n = 0
    for src in sources:
        if isinstance(src, tuple): path, s0, s1 = src
        else: path, s0, s1 = src, None, None
        if not os.path.exists(path): print("  missing", path); continue
        a = load(path)
        if s0 is not None: a = a[int(s0 * SR): int(s1 * SR)]
        a = trim(a, thr)
        if maxlen: a = a[: int(maxlen * SR)]
        a = peak(fade(a, 0.002, fout), db)
        n += 1
        save(a, "%s/sfx/%s_%d.ogg" % (OUT, name, n))
        credits.append((name, path))
    print("sfx", name, n)
# ---------------------------------------------------------------- onset cutter (hooves)
def hits(paths, name, want=8, seg=0.16, gap=0.06, lp=None, db=-2.0):
    cands = []
    for path in paths:
        a = load(path)
        if lp: a = lowpass(a, lp)
        w = int(0.003 * SR)
        env = np.convolve(np.abs(a), np.ones(w) / w, 'same')
        top = np.percentile(env, 99.7)
        i = int(0.02 * SR)
        while i < len(env) - int(seg * SR):
            if env[i] > 0.35 * top and env[i] >= env[max(0, i - int(0.03 * SR)): i + int(0.03 * SR)].max():
                s = max(0, i - int(0.012 * SR))
                seg_a = a[s: s + int(seg * SR)]
                # isolation: nothing as loud in the tail
                tail = env[i + int(gap * SR): s + int(seg * SR)]
                iso = tail.max() / env[i] if len(tail) else 0
                if iso < 0.55 and env[i] < 0.99 * np.abs(a).max() + 1:
                    cands.append((iso, env[i], seg_a, path))
                i += int(gap * SR)
            else:
                i += 1
    cands.sort(key=lambda c: c[0])
    got = cands[:want]
    for k, (_, _, seg_a, path) in enumerate(got):
        save(peak(fade(seg_a, 0.001, seg * 0.45), db), "%s/sfx/%s_%d.ogg" % (OUT, name, k + 1))
        credits.append((name, path))
    print("hits", name, len(got), "of", len(cands))
# ---------------------------------------------------------------- seamless loops
def loop(name, path, start, length, xf=2.0, q=3, gain_db=-1.0):
    a = load(path, 2)
    a = a[int(start * SR): int((start + length + xf) * SR)]
    n = int(xf * SR); body = a[: len(a) - n].copy(); tail = a[len(a) - n:]
    r = np.linspace(0, 1, n)[:, None]
    body[:n] = body[:n] * r + tail * (1 - r)
    save(peak(body, gain_db), "%s/amb/%s.ogg" % (OUT, name), q)
    credits.append((name, path)); print("loop", name, round(len(body) / SR, 1))
# ---------------------------------------------------------------- music (loudness matched)
def lufs(path):
    r = subprocess.run(["ffmpeg", "-hide_banner", "-i", path, "-af", "ebur128", "-f", "null", "-"], capture_output=True, text=True).stderr
    import re
    m = re.findall(r"I:\s+(-?[\d.]+) LUFS", r)
    return float(m[-1]) if m else -18.0
def music(name, path, target=-19.0, q=3):
    L = lufs(path); g = target - L
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path, "-af", "volume=%.2fdB,alimiter=limit=0.95" % g, "-ac", "2", "-ar", str(SR),
                    "-c:a", "libvorbis", "-q:a", str(q), "%s/music/%s.ogg" % (OUT, name)], check=True)
    credits.append(("music_" + name, path)); print("music", name, "LUFS %.1f gain %+.1f" % (L, g))
# ---------------------------------------------------------------- synthesized (no recording needed)
def synth_bell(name, f0=880.0, dur=1.6):
    t = np.arange(int(dur * SR)) / SR; a = np.zeros_like(t)
    for ratio, amp, dec in ((1.0, 1.0, 1.4), (2.76, 0.5, 2.2), (5.4, 0.25, 3.5), (8.93, 0.12, 5.0), (1.5, 0.3, 1.8)):
        a += amp * np.sin(2 * np.pi * f0 * ratio * t) * np.exp(-dec * t)
    a *= np.minimum(1, t / 0.004)
    save(peak(a, -3.0), "%s/sfx/%s_1.ogg" % (OUT, name))
def synth_koto(name, notes, step=0.16, dur=2.4):
    """Karplus-Strong plucked-string arpeggio (koto-like), pentatonic"""
    out = np.zeros(int((dur + step * len(notes)) * SR))
    for k, f in enumerate(notes):
        N = int(SR / f); buf = np.random.uniform(-1, 1, N); y = np.zeros(int(dur * SR))
        for i in range(len(y)):
            y[i] = buf[i % N]; buf[i % N] = 0.996 * 0.5 * (buf[i % N] + buf[(i + 1) % N])
        s = int(k * step * SR); out[s: s + len(y)] += y * (0.9 ** k)
    save(peak(fade(out, 0.001, 0.4), -2.0), "%s/sfx/%s_1.ogg" % (OUT, name))
def synth_taiko(name, f0=62.0, dur=1.2):
    t = np.arange(int(dur * SR)) / SR
    f = f0 * (1 + 1.2 * np.exp(-t * 30))
    ph = 2 * np.pi * np.cumsum(f) / SR
    a = np.sin(ph) * np.exp(-t * 4.0) + 0.25 * np.random.randn(len(t)) * np.exp(-t * 60)
    save(peak(a, -1.0), "%s/sfx/%s_1.ogg" % (OUT, name))
def synth_whistle(name):
    """two-tone call whistle: rising then falling glide with breath noise"""
    parts = []
    for f0, f1, d in ((1500, 2350, 0.34), (2350, 1700, 0.42)):
        t = np.arange(int(d * SR)) / SR
        f = f0 + (f1 - f0) * (t / d) ** 0.7 + 18 * np.sin(2 * np.pi * 6 * t)
        ph = 2 * np.pi * np.cumsum(f) / SR
        env = np.minimum(1, t / 0.04) * np.minimum(1, (d - t) / 0.08)
        parts.append((np.sin(ph) + 0.06 * np.random.randn(len(t))) * env)
        parts.append(np.zeros(int(0.05 * SR)))
    save(peak(np.concatenate(parts), -3.0), "%s/sfx/%s_1.ogg" % (OUT, name))
if __name__ == "__main__":
    for d in ("sfx", "amb", "music"):
        for f in glob.glob("%s/%s/*.ogg" % (OUT, d)): os.remove(f)
    sfx("swing_light", [fsf("swoosh", 60024), fsf("swoosh", 507466), fsf("swoosh", 192055), fsf("swoosh", 161098)], maxlen=0.6, fout=0.12)
    sfx("swing_heavy", [fsf("swoosh", 19312), fsf("swoosh", 240640), (fsf("swoosh", 507466), 0, 0.9)], maxlen=0.9, fout=0.2)
    sfx("draw", [fsf("sword_draw", 107589), fsf("sword_draw", 471147), (fsf("sword_draw", 320521), 0, 1.3)], maxlen=1.4, fout=0.25)
    sfx("sheathe", [fsf("sword_sheathe", 56264), fsf("sword_draw", 471148), fsf("sword_sheathe", 449552)], maxlen=1.3, fout=0.2)
    sfx("clash", [fsf("clash", 275159), fsf("clash", 334169), fsf("clash", 326868), (fsf("clash", 471095), 0, 1.6)], maxlen=1.4, fout=0.35)
    sfx("hit_blade", [fsf("slash_hit", 395373), fsf("punch", 276600), fsf("punch", 517744)], maxlen=0.7, fout=0.15)
    sfx("hit_blunt", kn("impactPunch_heavy_00[0-4].ogg") + [fsf("punch", 321810)], maxlen=0.5, fout=0.1)
    sfx("block", kn("impactPlate_heavy_00[0-3].ogg") + kn("impactMetal_heavy_00[0-1].ogg"), maxlen=0.8, fout=0.25)
    sfx("posture_break", [fsf("gong", 535594), (fsf("clash", 471095), 0, 2.2)], maxlen=2.2, fout=0.6)
    sfx("deathblow", [fsf("gong", 541029)], maxlen=1.9, fout=0.6)
    sfx("bodyfall", [fsf("bodyfall", 504626), fsf("bodyfall", 346695), fsf("bodyfall", 395331)], maxlen=1.2, fout=0.25)
    sfx("footstep_grass", kn("footstep_grass_00[0-4].ogg"), maxlen=0.5)
    sfx("footstep_dirt", kn("footstep0[0-9].ogg"), maxlen=0.5)
    sfx("footstep_rock", kn("footstep_concrete_00[0-4].ogg"), maxlen=0.5)
    sfx("footstep_wood", kn("footstep_wood_00[0-4].ogg"), maxlen=0.5)
    sfx("footstep_mud", kn("footstep_snow_00[0-4].ogg"), maxlen=0.5)
    sfx("footstep_water", [(fsf("splash", 393494), 0, 1.0)], maxlen=0.6, fout=0.2)
    sfx("cloth", kn("cloth[1-4].ogg") + kn("clothBelt*.ogg"), maxlen=0.6)
    sfx("land", kn("impactSoft_heavy_00[0-3].ogg"), maxlen=0.5)
    sfx("horse_neigh", [fsf("horse_neigh", 269571), fsf("horse_neigh", 826753), fsf("horse_neigh", 521246)], maxlen=2.6, fout=0.4)
    sfx("horse_snort", [fsf("horse_snort", 475483), fsf("horse_snort", 397236), (fsf("horse_walk", 538697), 0, 3.0)], maxlen=2.4, fout=0.4)
    sfx("ui_click", kn("click_00[1-3].ogg"), maxlen=0.3)
    sfx("ui_select", kn("select_00[1-2].ogg"), maxlen=0.4)
    sfx("ui_confirm", kn("confirmation_00[1-2].ogg"), maxlen=0.8)
    sfx("ui_back", kn("back_00[1-2].ogg"), maxlen=0.5)
    sfx("quest", [fsf("gong", 369428)], maxlen=4.5, fout=1.5)
    sfx("taiko", [fsf("taiko2", 486140), fsf("taiko2", 486141)], maxlen=1.8, fout=0.5)
    sfx("bow", [fsf("bow", 394180), fsf("bow", 536068)], maxlen=0.8)
    sfx("arrow_hit", [(fsf("bow", 179996), 0.35, 1.2)], maxlen=0.6)
    sfx("telegraph", [fsf("sword_draw", 724716)], maxlen=0.5, fout=0.2)
    synth_bell("heal", 1046.5); synth_koto("discover", [293.7, 349.2, 392.0, 440.0, 587.3]); synth_taiko("drum"); synth_whistle("whistle")
    hits([fsf("horse_gallop", 675420), fsf("horse_gallop", 684446), fsf("horse_gallop", 479703)], "hoof_dirt", 10, seg=0.14, gap=0.05)
    hits([fsf("horse_trot", 182504), fsf("horse_trot", 581834)], "hoof_hard", 10, seg=0.16, gap=0.06)
    loop("wind", fsf("wind", 139337), 20, 50)
    loop("wind_strong", fsf("wind", 167684), 30, 50)
    loop("birds", fsf("birds", 288899), 10, 60)
    loop("night", fsf("crickets", 333221), 20, 60)
    loop("stream", fsf("stream", 433589), 5, 50)
    loop("rain", fsf("rain", 167034), 1, 22, xf=1.5)
    loop("fire", fsf("fire", 204348), 10, 40)
    for n, f in (("menu", "the-last-samurai.mp3"), ("shrine", "koto-booth.ogg"), ("forest", "lapsy-koto.ogg"),
                 ("bamboo", "sugimai.ogg"), ("village", "hot-springs-town.ogg"), ("farmland", "orient-peace-valley.ogg"),
                 ("grassland", "asianoriental2.ogg"), ("lake", "oriental-somber.ogg"), ("ruins", "orient-5.ogg"),
                 ("castle", "ninja-theme.ogg"), ("mountain", "tyhosiasian.ogg"), ("combat", "bosskoto.mp3"),
                 ("combat2", "prepare-your-swords.ogg"), ("boss", "great-boss.ogg")):
        music(n, OGA + "/" + f)
    json.dump(credits, open("/tmp/audio_credits.json", "w"), indent=0)
    print("DONE")
