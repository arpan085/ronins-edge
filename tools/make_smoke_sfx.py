#!/usr/bin/env python3
"""v0.16: synthesise the smoke-bomb sound (own work, CC0): a dull pop, then a
hissing bloom of filtered noise. Writes game/assets/audio/sfx/smoke_<n>.ogg
(two variants) via ffmpeg/libvorbis."""
import numpy as np, subprocess, wave, os, sys
SR = 44100
out_dir = sys.argv[1] if len(sys.argv) > 1 else "game/assets/audio/sfx"

def lowpass(x, a):
    y = np.empty_like(x); acc = 0.0
    for i in range(len(x)):
        acc += a * (x[i] - acc); y[i] = acc
    return y

def make(seed, dur=1.9, pop_hz=72.0, hiss_lp=0.16):
    rng = np.random.default_rng(seed)
    n = int(SR * dur)
    t = np.arange(n) / SR
    # pop: a decaying sine sweep with a click
    f = pop_hz * (1.0 + 1.8 * np.exp(-t * 40.0))
    phase = 2 * np.pi * np.cumsum(f) / SR
    pop = np.sin(phase) * np.exp(-t * 18.0)
    click = rng.standard_normal(n) * np.exp(-t * 260.0) * 0.6
    # hiss: noise, band-limited, swelling in then dying away
    noise = rng.standard_normal(n)
    hiss = lowpass(noise, hiss_lp) - lowpass(noise, 0.012)
    env = (1.0 - np.exp(-t * 30.0)) * np.exp(-t * 2.1)
    env *= 1.0 + 0.25 * np.sin(2 * np.pi * 3.1 * t + seed)
    hiss *= env * 3.2
    sig = pop * 0.9 + click + hiss
    fade = np.minimum(1.0, (dur - t) / 0.25)
    sig *= fade
    sig /= np.max(np.abs(sig)) + 1e-9
    return (sig * 0.89 * 32767).astype(np.int16)

os.makedirs(out_dir, exist_ok=True)
for i, (seed, hz, lp) in enumerate([(11, 72.0, 0.16), (29, 64.0, 0.13)], start=1):
    pcm = make(seed, pop_hz=hz, hiss_lp=lp)
    wav = f"/tmp/smoke_{i}.wav"
    with wave.open(wav, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    ogg = os.path.join(out_dir, f"smoke_{i}.ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "4", ogg], check=True)
    print(ogg, os.path.getsize(ogg))
