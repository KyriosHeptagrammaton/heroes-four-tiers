"""Synthesises a short crowd cheer ("HEY!" shouts from a dozen voices over a
roar, a few claps, a little room echo) for critical hits. No samples used.
Run: python3 tools/make_cheer.py   -> sfx/cheer_1..3.ogg"""
import os, subprocess, tempfile
import numpy as np
from scipy.signal import butter, sosfilt, lfilter
from scipy.io import wavfile

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "sfx")

def band(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], btype="band", fs=SR, output="sos"), x)

def formant(x, f, bw):
    """two-pole resonator"""
    r = np.exp(-np.pi * bw / SR)
    th = 2 * np.pi * f / SR
    return lfilter([1 - r], [1, -2 * r * np.cos(th), r * r], x)

def voice(rng, dur, f0, vowel):
    n = int(dur * SR)
    t = np.arange(n) / SR
    # shout contour: quick rise, hold, fall; a little vibrato and jitter
    rise = np.clip(t / 0.08, 0, 1)
    contour = f0 * (0.85 + 0.35 * rise - 0.25 * np.clip((t - dur * 0.55) / (dur * 0.45), 0, 1))
    contour *= 1 + 0.02 * np.sin(2 * np.pi * rng.uniform(4, 7) * t) + 0.01 * rng.standard_normal(n).cumsum() / np.sqrt(n)
    phase = np.cumsum(contour) / SR
    src = 2 * (phase % 1.0) - 1                      # sawtooth glottal source
    src = src + 0.12 * rng.standard_normal(n)        # a little breath
    y = np.zeros(n)
    for f, bw, g in vowel:
        y += formant(src, f * rng.uniform(0.93, 1.07), bw) * g
    env = np.clip(t / 0.03, 0, 1) * np.clip((dur - t) / 0.18, 0, 1)
    return y * env

VOWELS = {   # formant frequency, bandwidth, gain
    "ey": [(620, 90, 1.0), (1850, 120, 0.6), (2600, 160, 0.3)],
    "ah": [(780, 100, 1.0), (1250, 110, 0.7), (2550, 170, 0.25)],
    "oh": [(520, 90, 1.0), (900, 100, 0.6), (2450, 160, 0.2)],
}

def cheer(seed, length=1.5):
    rng = np.random.default_rng(seed)
    N = int(length * SR)
    out = np.zeros(N)
    # a dozen shouting voices, mostly together, some late
    for v in range(12):
        f0 = rng.choice([rng.uniform(120, 190), rng.uniform(200, 290)], p=[0.65, 0.35])
        dur = rng.uniform(0.45, 0.95)
        at = rng.uniform(0.0, 0.12) if v < 9 else rng.uniform(0.25, 0.5)
        vw = VOWELS[rng.choice(["ey", "ah", "ah", "oh"])]
        s = voice(rng, dur, f0, vw) * rng.uniform(0.5, 1.0)
        i = int(at * SR)
        out[i:i + len(s)] += s[:N - i]
    out /= np.max(np.abs(out)) + 1e-9
    # crowd roar underneath
    t = np.arange(N) / SR
    roar = band(rng.standard_normal(N), 350, 2800, 2)
    roar *= np.clip(t / 0.06, 0, 1) * np.exp(-np.maximum(t - 0.3, 0) / 0.45)
    out += roar / (np.max(np.abs(roar)) + 1e-9) * 0.18
    # a few claps
    for k in range(rng.integers(5, 9)):
        at = rng.uniform(0.15, length * 0.7)
        n = int(0.03 * SR)
        clap = band(rng.standard_normal(n), 900, 4000) * np.exp(-np.arange(n) / SR / 0.006)
        i = int(at * SR)
        out[i:i + n] += clap / (np.max(np.abs(clap)) + 1e-9) * rng.uniform(0.15, 0.3)
    # small room: a few decaying echoes
    wet = np.zeros(N)
    for d, g in [(0.023, 0.35), (0.041, 0.25), (0.067, 0.18), (0.11, 0.1)]:
        k = int(d * SR)
        wet[k:] += out[:N - k] * g
    out = out + wet
    out = np.tanh(out * 1.1)
    fade = int(0.25 * SR)
    out[-fade:] *= np.linspace(1, 0, fade)
    return out / np.max(np.abs(out)) * 10 ** (-3 / 20)

for i, seed in enumerate([7, 19, 42]):
    x = cheer(seed)
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        wavfile.write(tmp.name, SR, (x * 32767).astype(np.int16))
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp.name, "-c:a", "libvorbis", "-q:a", "5",
                        os.path.join(OUT, f"cheer_{i + 1}.ogg")], check=True)
print("ok")
