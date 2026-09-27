"""Synthesises the UI sound effects (no samples): a chunky stone-slab
"ba-DOOM" for buttons, in a few variants, plus a light stone tick for
checkboxes and drop-downs. Run: python3 tools/make_sfx.py"""
import numpy as np
from scipy.signal import butter, sosfilt
from scipy.io import wavfile
import os

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "sfx")

def t(n): return np.arange(n) / SR
def env(n, attack, decay):
    x = t(n)
    a = np.clip(x / max(attack, 1e-4), 0, 1)
    return a * np.exp(-np.maximum(x - attack, 0) / decay)
def band(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], btype="band", fs=SR, output="sos"), x)
def low(x, f, order=2):
    return sosfilt(butter(order, f, btype="low", fs=SR, output="sos"), x)
def place(buf, sig, at):
    i = int(at * SR)
    n = min(len(sig), len(buf) - i)
    buf[i:i + n] += sig[:n]

def slab(seed, pitch=1.0, dur=0.46):
    rng = np.random.default_rng(seed)
    N = int(dur * SR)
    out = np.zeros(N)
    noise = rng.standard_normal(N)
    # "ba": the slab catches — a short gritty knock
    n = int(0.07 * SR)
    knock = band(noise[:n], 500 * pitch, 2600 * pitch) * env(n, 0.002, 0.018) * 1.3
    knock += np.sin(2 * np.pi * 190 * pitch * t(n)) * env(n, 0.001, 0.03) * 0.8
    place(out, knock, 0.0)
    # the slide: stone grinding on stone, pitch of the grit falling
    n = int(0.17 * SR)
    grit = noise[int(0.1 * SR):int(0.1 * SR) + n].copy()
    crackle = (rng.random(n) < 0.012) * rng.standard_normal(n) * 6.0
    g = band(grit + crackle, 250 * pitch, 1500 * pitch)
    sweep = np.linspace(1.0, 0.35, n)
    g = low(g * sweep, 1400 * pitch)
    shape = np.sin(np.pi * np.clip(t(n) / (n / SR), 0, 1)) ** 0.8
    place(out, g * shape * 0.7, 0.03)
    # "DOOM": the slab settles — a heavy low thud with a stony body
    n = int(0.45 * SR)
    f = 90 * pitch * np.exp(-t(n) / 0.08) + 68 * pitch
    phase = 2 * np.pi * np.cumsum(f) / SR
    thud = (np.sin(phase) + 0.35 * np.sin(2 * phase)) * env(n, 0.004, 0.1) * 1.6
    thud += low(noise[:n], 260 * pitch, 4) * env(n, 0.003, 0.09) * 2.2
    for fr, amp, dec in [(233, 0.45, 0.06), (377, 0.3, 0.04), (611, 0.16, 0.03)]:
        thud += np.sin(2 * np.pi * fr * pitch * t(n) + rng.random() * 6) * env(n, 0.002, dec) * amp
    place(out, thud, 0.155)
    # a touch of grit on impact
    n = int(0.05 * SR)
    place(out, band(noise[-n:], 900, 3500) * env(n, 0.001, 0.012) * 0.6, 0.155)
    out = np.tanh(out * 1.4)                   # chunky saturation
    out = low(out, 5000)
    fade = int(0.03 * SR)
    out[-fade:] *= np.linspace(1, 0, fade)
    return out

def tick(seed):
    rng = np.random.default_rng(seed)
    N = int(0.14 * SR)
    noise = rng.standard_normal(N)
    s = band(noise, 700, 3000) * env(N, 0.001, 0.012) * 1.2
    s += np.sin(2 * np.pi * 150 * t(N)) * env(N, 0.002, 0.03) * 0.9
    s += low(noise, 300) * env(N, 0.002, 0.03) * 1.2
    return np.tanh(s * 1.3)

def save(name, x, peak_db=-3.0):
    x = x / np.max(np.abs(x)) * 10 ** (peak_db / 20)
    wavfile.write(os.path.join(OUT, name), SR, (x * 32767).astype(np.int16))

for i, (seed, p) in enumerate([(11, 1.0), (23, 0.94), (37, 1.06)]):
    save(f"stone_button_{i + 1}.wav", slab(seed, p))
save("stone_tick.wav", tick(5), -6.0)
print("ok")
